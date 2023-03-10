macro constfield(ex) esc(VERSION >= v"1.8-" ? Expr(:const, ex) : ex) end

@enum Error InvalidJSON UnexpectedEOF ExpectedOpeningObjectChar ExpectedOpeningQuoteChar ExpectedOpeningArrayChar ExpectedClosingArrayChar ExpectedComma ExpectedColon ExpectedNewline InvalidChar InvalidNumber

@noinline invalid(error, buf, pos, T) = throw(ArgumentError("""
invalid JSON at byte position $pos while parsing type $T: $error
$(Base.String(buf[max(1, pos-25):min(end, pos+25)]))
"""))

# helper struct we pack lazy-specific keyword args into
# held by LazyValue for access
Base.@kwdef struct Options
    float64::Bool = false
    jsonlines::Bool = false
end

withopts(opts; kw...) = Options(;
    float64 = opts.float64,
    jsonlines = opts.jsonlines,
    kw...
)

const OPTIONS = Options()

# scoped enum
module JSONTypes
    primitive type T 8 end
    T(x::UInt8) = Base.bitcast(T, x)
    Base.UInt8(x::T) = Base.bitcast(UInt8, x)
    const OBJECT = T(0x00)
    const ARRAY = T(0x01)
    const STRING = T(0x02)
    const INT = T(0x03)
    const FLOAT = T(0x04)
    const FALSE = T(0x05)
    const TRUE = T(0x06)
    const NULL = T(0x07)
    const NUMBER = T(0x08) # only used by LazyValue, BinaryValue uses INT or FLOAT
    const names = Dict(
        OBJECT => "OBJECT",
        ARRAY => "ARRAY",
        STRING => "STRING",
        INT => "INT",
        FALSE => "FALSE",
        TRUE => "TRUE",
        FLOAT => "FLOAT",
        NULL => "NULL",
        NUMBER => "NUMBER",
    )
    Base.show(io::IO, x::T) = print(io, "JSONTypes.", names[x])
    Base.isless(x::T, y::T) = UInt8(x) < UInt8(y)
end

getlength(buf::AbstractVector{UInt8}) = length(buf)
getlength(buf::AbstractString) = sizeof(buf)

function getbyte(buf::AbstractVector{UInt8}, pos)
    @inbounds b = buf[pos]
    return b
end

function getbyte(buf::AbstractString, pos)
    @inbounds b = codeunit(buf, pos)
    return b
end

# helper macro to get the next byte and if checkwh=true
# to keep going until we get a non-whitespace byte
macro nextbyte(checkwh=true)
    esc(quote
        if pos > len
            error = UnexpectedEOF
            @goto invalid
        end
        b = getbyte(buf, pos)
        if $checkwh
            while b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')
                pos += 1
                if pos > len
                    error = UnexpectedEOF
                    @goto invalid
                end
                b = getbyte(buf, pos)
            end
        end
    end)
end

function reverseescapechar(b)
    b == UInt8('"')  && return UInt8('"')
    b == UInt8('\\') && return UInt8('\\')
    b == UInt8('/')  && return UInt8('/')
    b == UInt8('b')  && return UInt8('\b')
    b == UInt8('f')  && return UInt8('\f')
    b == UInt8('n')  && return UInt8('\n')
    b == UInt8('r')  && return UInt8('\r')
    b == UInt8('t')  && return UInt8('\t')
    return 0x00
end

utf16_is_surrogate(c::UInt16) = (c & 0xf800) == 0xd800
utf16_get_supplementary(lead::UInt16, trail::UInt16) = Char(UInt32(lead-0xd7f7)<<10 + trail)

charvalue(b) = (UInt8('0') <= b <= UInt8('9')) ? b - UInt8('0') :
               (UInt8('a') <= b <= UInt8('f')) ? b - (UInt8('a') - 0x0a) :
               (UInt8('A') <= b <= UInt8('F')) ? b - (UInt8('A') - 0x0a) :
               throw(ArgumentError("JSON invalid unicode hex value"))

@noinline invalid_escape(src, n) = throw(ArgumentError("encountered invalid escape character in json string: \"$(unsafe_string(src, n))\""))
@noinline unescaped_control(b) = throw(ArgumentError("encountered unescaped control character in json: '$(escape_string(Base.string(Char(b))))'"))

_unsafe_string(p, len) = ccall(:jl_pchar_to_string, Ref{Base.String}, (Ptr{UInt8}, Int), p, len)

struct PtrString
    ptr::Ptr{UInt8}
    len::Int
    escaped::Bool
end

"""
    JSONBase.tostring(T, x::JSONBase.PtrString)

Convert a `PtrString` to a string of type `T`.
Happens earlier in the materialization process than `lift`.
A utility that string types can overload if they have a more efficient
conversion method that can avoid the `String` intermediate + allocation.
"""
function tostring end

@inline function tostring(::Type{String}, x::PtrString)
    if x.escaped
        str = Base.StringVector(x.len)
        len = GC.@preserve str unsafe_unescape_to_buffer(x.ptr, x.len, pointer(str))
        resize!(str, len)
        return String(str)
    else
        return _unsafe_string(x.ptr, x.len)
    end
end

# generic fallbacks
tostring(::Type{T}, x::PtrString) where {T} = tostring(String, x)

"""
    JSONBase.tostring(x)

Overloadable function that allows non-`Integer` `Number` types
to convert themselves to a `String` that is then written directly (unquoted)
when serializing `x` to JSON.

An example overload would look something like:
```julia
JSONBase.tostring(x::MyDecimal) = string(x)
```
"""
tostring(x) = string(x)

_symbol(ptr, len) = ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), ptr, len)

tostring(::Type{Symbol}, x::PtrString) = x.escaped ? Symbol(tostring(String, x)) : _symbol(x.ptr, x.len)

function tostring(::Type{T}, x::PtrString) where {T <: Enum}
    sym = tostring(Symbol, x)
    for (k, v) in Base.Enums.namemap(T)
        v === sym && return T(k)
    end
    throw(ArgumentError("invalid `$T` string value: \"$sym\""))
end

function streq(x::PtrString, y::AbstractString)
    if x.escaped
        return isequal(tostring(String, x), y)
    else
        return x.len == sizeof(y) && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), x.ptr, pointer(y), x.len) == 0
    end
end

# unsafe because we're not checking that src or dst are valid pointers
# NOR are we checking that up to `n` bytes after dst are also valid to write to
function unsafe_unescape_to_buffer(src::Ptr{UInt8}, n::Int, dst::Ptr{UInt8})
    len = 1
    i = 1
    @inbounds begin
        while i <= n
            b = unsafe_load(src, i)
            if b == UInt8('\\')
                i += 1
                i > n && invalid_escape(src, n)
                b = unsafe_load(src, i)
                if b == UInt8('u')
                    c = 0x0000
                    i += 1
                    i > n && invalid_escape(src, n)
                    b = unsafe_load(src, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(src, n)
                    b = unsafe_load(src, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(src, n)
                    b = unsafe_load(src, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(src, n)
                    b = unsafe_load(src, i)
                    c = (c << 4) + charvalue(b)
                    if utf16_is_surrogate(c)
                        i += 3
                        i > n && invalid_escape(src, n)
                        c2 = 0x0000
                        b = unsafe_load(src, i)
                        c2 = (c2 << 4) + charvalue(b)
                        i += 1
                        i > n && invalid_escape(src, n)
                        b = unsafe_load(src, i)
                        c2 = (c2 << 4) + charvalue(b)
                        i += 1
                        i > n && invalid_escape(src, n)
                        b = unsafe_load(src, i)
                        c2 = (c2 << 4) + charvalue(b)
                        i += 1
                        i > n && invalid_escape(src, n)
                        b = unsafe_load(src, i)
                        c2 = (c2 << 4) + charvalue(b)
                        ch = utf16_get_supplementary(c, c2)
                    else
                        ch = Char(c)
                    end
                    st = codeunits(Base.string(ch))
                    for j = 1:length(st)-1
                        unsafe_store!(dst, st[j], len)
                        len += 1
                    end
                    b = st[end]
                else
                    b = reverseescapechar(b)
                    b == 0x00 && invalid_escape(src, n)
                end
            end
            unsafe_store!(dst, b, len)
            len += 1
            i += 1
        end
    end
    return len-1
end
