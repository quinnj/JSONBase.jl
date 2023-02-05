@enum Error InvalidJSON UnexpectedEOF ExpectedOpeningObjectChar ExpectedOpeningQuoteChar ExpectedOpeningArrayChar ExpectedClosingArrayChar ExpectedComma ExpectedColon ExpectedNewline InvalidChar InvalidNumber

@noinline invalid(error, buf, pos, T) = throw(ArgumentError("""
invalid JSON at byte position $pos while parsing type $T: $error
$(Base.String(buf[max(1, pos-25):min(end, pos+25)]))
"""))

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

function tostring(x::PtrString)
    if x.escaped
        str = Base.StringVector(x.len)
        len = GC.@preserve str unsafe_unescape_to_buffer(x.ptr, x.len, pointer(str))
        resize!(str, len)
        return String(str)
    else
        return _unsafe_string(x.ptr, x.len)
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
