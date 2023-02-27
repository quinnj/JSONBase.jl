sizeguess(::Union{Nothing, Missing}) = 4
sizeguess(x::Bool) = 5
sizeguess(x::Integer) = 20
sizeguess(x::AbstractFloat) = 20
sizeguess(x::Base.IEEEFloat) = Base.Ryu.neededdigits(typeof(x))
sizeguess(x::AbstractString) = 2 + sizeof(x)
sizeguess(_) = 512

"""
    JSONBase.json(x) -> String
    JSONBase.json(io, x)
    JSONBase.json(file_name, x)
    JSONBase.json!(buf, pos, x[, allow_inf]) -> pos

Serialize `x` to JSON format. The 1st method takes just the object and returns a `String`.
In the 2nd method, `io` is an `IO` object, and the JSON output will be written to it.
For the 3rd method, `file_name` is a `String`, a file will be opened and the JSON output will be written to it.
For the 4th method, a `buf` as a `Vector{UInt8}` is provided, along with an integer `pos` for the position where
JSON output should start to be written. If the `buf` isn't large enough, it will be `resize!`ed to be large enough.

All methods except the 4th accept `allow_inf::Bool=false` as a keyword argument.
The 4th method optionally accepts `allow_inf` as a 4th positional argument.
If `allow_inf` is `true`, allow `Inf`, `-Inf`, and `NaN` in the output.
If `allow_inf` is `false`, throw an error if `Inf`, `-Inf`, or `NaN` is encountered.
`allow_inf` is `false` by default.

By default, `x` must be a JSON-serializable object. Supported types include:
  * `AbstractString`
  * `Bool`
  * `Nothing`/`Missing`
  * `Number`
  * `AbstractArray`/`Tuple`/`AbstractSet`
  * `AbstractDict`/`NamedTuple`/structs

If an object is not JSON-serializable, an override for [`JSONBase.lower`](@ref) can
be defined to convert it to a JSON-serializable object. Some default `lower` defintions
are defined in JSONBase itself, like:
  * `lower(::Missing) = nothing`
  * `lower(x::Symbol) = String(x)`
  * `lower(x::Union{Enum, AbstractChar, VersionNumber, Cstring, Cwstring, UUID, Dates.TimeType}) = string(x)`
  * `lower(x::Regex) = x.pattern`

These allow common Base/stdlib types to be serialized in an expected format.
"""
function json end

function json(io::IO, x::T; allow_inf::Bool=false) where {T}
    buf = Vector{UInt8}(undef, sizeguess(x))
    pos = json!(buf, 1, lower(x), allow_inf, nothing)
    return write(io, resize!(buf, pos - 1))
end

function json(x::T; allow_inf::Bool=false) where {T}
    buf = Base.StringVector(sizeguess(x))
    pos = json!(buf, 1, lower(x), allow_inf, nothing)
    return String(resize!(buf, pos - 1))
end

function json(fname::String, obj::T; kw...) where {T}
    open(fname, "w") do io
        json(io, obj; kw...)
    end
    return fname
end

macro checkn(n)
    esc(quote
        if (pos + $n - 1) > length(buf)
            #TODO: this resize strategy is probably bad for really big/nested objects/arrays
            resize!(buf, ceil(Int, (pos + $n) * 1.25))
        end
    end)
end

struct WriteClosure{arraylike, T} # T is the type of the parent object/array being written
    buf::Vector{UInt8}
    pos::Ptr{Int}
    allow_inf::Bool
    objids::Base.IdSet{Any} # to track circular references
end

@inline function (f::WriteClosure{arraylike, T})(key, val) where {arraylike, T}
    pos = unsafe_load(f.pos)
    buf = f.buf
    if !arraylike
        pos = _string(buf, pos, key)
        @checkn 1
        buf[pos] = UInt8(':')
        pos += 1
    end
    #TODO: should we be checking the lowered value here?
    if val in f.objids
        pos = _null(buf, pos)
    else
        pos = json!(buf, pos, lower(T, key, val), f.allow_inf, f.objids)
    end
    @checkn 1
    buf[pos] = UInt8(',')
    pos += 1
    unsafe_store!(f.pos, pos)
    return Continue()
end

# assume x is lowered value
function json!(buf, pos, x, allow_inf=false, objids::Union{Nothing, Base.IdSet{Any}}=nothing)
    # string
    if x isa AbstractString
        return _string(buf, pos, x)
    # bool; check before Number since Bool <: Number
    elseif x isa Bool
        if x
            @checkn 4
            @inbounds buf[pos] = 't'
            @inbounds buf[pos + 1] = 'r'
            @inbounds buf[pos + 2] = 'u'
            @inbounds buf[pos + 3] = 'e'
            return pos + 4
        else
            @checkn 5
            @inbounds buf[pos] = 'f'
            @inbounds buf[pos + 1] = 'a'
            @inbounds buf[pos + 2] = 'l'
            @inbounds buf[pos + 3] = 's'
            @inbounds buf[pos + 4] = 'e'
            return pos + 5
        end
    # number
    elseif x isa Number
        return _number(buf, pos, x, allow_inf)
    # null
    elseif x === nothing
        return _null(buf, pos)
    # special-case no-field objects (singletons, primitive types)
    # if we didn't, they'd just be written as empty objects
    elseif !arraylike(x) && nfields(x) == 0
        return _string(buf, pos, x)
    # object or array
    else
        # it's notable that we're in an `else` block here; and that
        # we don't actually call `objectlike` at all, but just assume
        # anything else is an object/array
        # this allows us to have a `json` that "doesn't throw", which can
        # be a good property for production systems
        # but, it also means objects might be written in ways that weren't
        # intended; in those cases, it should be determined whether an
        # appropriate `lower` method should be defined (preferred) or perhaps
        # a custom `API.foreach` override to provide key-value pairs (more rare)
        al = arraylike(x)
        @checkn 1
        @inbounds buf[pos] = al ? UInt8('[') : UInt8('{')
        pos += 1
        pre_pos = pos
        ref = Ref(pos)
        # use an IdSet to keep track of circular references
        objids = objids === nothing ? Base.IdSet{Any}() : objids
        push!(objids, x)
        c = WriteClosure{al, typeof(x)}(buf, Base.unsafe_convert(Ptr{Int}, ref), allow_inf, objids)
        GC.@preserve ref API.foreach(c, x)
        # get updated pos
        pos = unsafe_load(c.pos)
        # in WriteClosure, we eagerly write a comma after each element
        # so for non-empty object/arrays, we can just overwrite the last comma with the closechar
        if pos > pre_pos
            pos -= 1
        else
            # but if the object/array was empty, we need to do the check manually
            @checkn 1
        end
        @inbounds buf[pos] = al ? UInt8(']') : UInt8('}')
        return pos + 1
    end
end

@inline function _null(buf, pos)
    @checkn 4
    @inbounds buf[pos] = 'n'
    @inbounds buf[pos + 1] = 'u'
    @inbounds buf[pos + 2] = 'l'
    @inbounds buf[pos + 3] = 'l'
    return pos + 4
end

const NEEDESCAPE = Set(map(UInt8, ('"', '\\', '\b', '\f', '\n', '\r', '\t')))

function escapechar(b)
    b == UInt8('"')  && return UInt8('"')
    b == UInt8('\\') && return UInt8('\\')
    b == UInt8('\b') && return UInt8('b')
    b == UInt8('\f') && return UInt8('f')
    b == UInt8('\n') && return UInt8('n')
    b == UInt8('\r') && return UInt8('r')
    b == UInt8('\t') && return UInt8('t')
    return 0x00
end

iscntrl(c::Char) = c <= '\x1f' || '\x7f' <= c <= '\u9f'
function escaped(b)
    if b == UInt8('/')
        return [UInt8('/')]
    elseif b >= 0x80
        return [b]
    elseif b in NEEDESCAPE
        return [UInt8('\\'), escapechar(b)]
    elseif iscntrl(Char(b))
        return UInt8[UInt8('\\'), UInt8('u'), Base.string(b, base=16, pad=4)...]
    else
        return [b]
    end
end

const ESCAPECHARS = [escaped(b) for b = 0x00:0xff]
const ESCAPELENS = [length(x) for x in ESCAPECHARS]

function escapelength(str)
    x = 0
    @simd for i = 1:ncodeunits(str)
        @inbounds len = ESCAPELENS[codeunit(str, i) + 1]
        x += len
    end
    return x
end

# this definition is really for object keys that may not be AbstractSTring
@inline _string(buf, pos, x) = _string(buf, pos, string(x))

@inline function _string(buf, pos, x::AbstractString)
    sz = ncodeunits(x)
    el = escapelength(x)
    @checkn (el + 2)
    @inbounds buf[pos] = UInt8('"')
    pos += 1
    if el > sz
        for i = 1:sz
            @inbounds escbytes = ESCAPECHARS[codeunit(x, i) + 1]
            for j = 1:length(escbytes)
                @inbounds buf[pos] = escbytes[j]
                pos += 1
            end
        end
    else
        @simd for i = 1:sz
            @inbounds buf[pos] = codeunit(x, i)
            pos += 1
        end
    end
    @inbounds buf[pos] = UInt8('"')
    return pos + 1
end

_split_sign(x) = Base.split_sign(x)
_split_sign(x::BigInt) = (abs(x), x < 0)

@noinline infcheck(x, allow_inf) = isfinite(x) || allow_inf || throw(ArgumentError("$x not allowed to be written in JSON spec; pass `allow_inf=true` to allow anyway"))

_number(buf, pos, x, allow_inf) = _number(buf, pos, convert(Float64, x), allow_inf)

@inline function _number(buf, pos, x::Union{Integer, AbstractFloat}, allow_inf)
    if x isa Integer
        y, neg = _split_sign(x)
        n = i = ndigits(y, base=10, pad=1)
        @checkn (i + neg)
        if neg
            @inbounds buf[pos] = UInt8('-')
            pos += 1
        end
        while i > 0
            @inbounds buf[pos + i - 1] = 48 + rem(y, 10)
            y = oftype(y, div(y, 10))
            i -= 1
        end
        return pos + n
    elseif x isa AbstractFloat
        infcheck(x, allow_inf)
        if x isa Base.IEEEFloat
            if isinf(x)
                # Although this is non-standard JSON, "Infinity" is commonly used.
                # See https://docs.python.org/3/library/json.html#infinite-and-nan-number-values.
                neg = sign(x) == -1
                @checkn (8 + neg)
                if neg
                    @inbounds buf[pos] = UInt8('-')
                    pos += 1
                end
                @inbounds buf[pos] = UInt8('I')
                @inbounds buf[pos + 1] = UInt8('n')
                @inbounds buf[pos + 2] = UInt8('f')
                @inbounds buf[pos + 3] = UInt8('i')
                @inbounds buf[pos + 4] = UInt8('n')
                @inbounds buf[pos + 5] = UInt8('i')
                @inbounds buf[pos + 6] = UInt8('t')
                @inbounds buf[pos + 7] = UInt8('y')
                return pos + 8
            end
            @checkn Base.Ryu.neededdigits(typeof(x))
            return Base.Ryu.writeshortest(buf, pos, x)
        else
            bytes = codeunits(Base.string(x))
            sz = sizeof(bytes)
            @checkn sz
            for i = 1:sz
                @inbounds buf[pos + i - 1] = bytes[i]
            end
            return pos + sz
        end
    end
end
