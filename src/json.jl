sizeguess(::Nothing) = 4
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
    JSONBase.json!(buf, pos, x[, style, allownan]) -> pos

Serialize `x` to JSON format. The 1st method takes just the object and returns a `String`.
In the 2nd method, `io` is an `IO` object, and the JSON output will be written to it.
For the 3rd method, `file_name` is a `String`, a file will be opened and the JSON output will be written to it.
For the 4th method, a `buf` as a `Vector{UInt8}` is provided, along with an integer `pos` for the position where
JSON output should start to be written. If the `buf` isn't large enough, it will be `resize!`ed to be large enough.

All methods except the 4th accept `style::JSONStyle` as a keyword argument.
The 4th method optionally accepts `style` as a 4th positional argument, defaulting to `JSONBase.DefaultStyle()`.
Passing a custom style will result in `lower(style, x)` being called, where custom lowerings can be defined
for a custom style.

All methods except the 4th also accept `allownan::Bool=false` as a keyword argument.
The 4th method optionally accepts `allownan` as a 5th positional argument.
If `allownan` is `true`, allow `Inf`, `-Inf`, and `NaN` in the output.
If `allownan` is `false`, throw an error if `Inf`, `-Inf`, or `NaN` is encountered.
`allownan` is `false` by default.

Pretty printing of the JSON output is controlled via the `pretty` keyword argument. If `pretty` is `true`,
the output will be pretty-printed with 4 spaces of indentation. If `pretty` is an integer, it will be used
as the number of spaces of indentation. If `pretty` is `false` or `0`, the output will be compact (default behavior).

By default, `x` must be a JSON-serializable object. Supported types include:
  * `AbstractString` => JSON string: types must support the `AbstractString` interface, specifically with support for
    `ncodeunits` and `codeunit(x, i)`.
  * `Bool` => JSON boolean: must be `true` or `false`
  * `Nothing` => JSON null: must be the `nothing` singleton value
  * `Number` => JSON number: `Integer` or `Base.IEEEFloat` subtypes have default implementations
    for other `Number` types, [`JSONBase.tostring`](@ref) is first called to convert
    the value to a `String` before being written directly to JSON output
  * `AbstractArray`/`Tuple`/`AbstractSet` => JSON array: objects for which `JSONBase.arraylike` returns `true`
     are output as JSON arrays. `arraylike` is defined by default for
    `AbstractArray`, `AbstractSet`, `Tuple`, and `Base.Generator`. For other types that define,
    they must also properly implement [`JSONBase.applyeach`](@ref) to iterate over the index => elements pairs.
  * `AbstractDict`/`NamedTuple`/structs => JSON object: if a value doesn't fall into any of the above categories,
    it is output as a JSON object. [`JSONBase.applyeach`](@ref) is called, which has appropriate implementations
    for `AbstractDict`, `NamedTuple`, and structs, where field names => values are iterated over. Field names can
    be output using alternative JSON keys via [`JSONBase.fields`](@ref) overload. Typically, types shouldn't
    need to overload `applyeach`, however, since `JSONBase.lower` is much simpler (see below).

If an object is not JSON-serializable, an override for [`JSONBase.lower`](@ref) can
be defined to convert it to a JSON-serializable object. Some default `lower` defintions
are defined in JSONBase itself, like:
  * `lower(::Missing) = nothing`
  * `lower(x::Symbol) = String(x)`
  * `lower(x::Union{Enum, AbstractChar, VersionNumber, Cstring, Cwstring, UUID, Dates.TimeType}) = string(x)`
  * `lower(x::Regex) = x.pattern`

These allow common Base/stdlib types to be serialized in an expected format.

*NOTE*: `JSONBase.json` should _not_ be overloaded directly by custom
types as this isn't robust for various output options (IO, String, etc.)
and isn't conducive to recursive situations. Types should define an appropriate
[`JSONBase.lower`](@ref) definition instead.
"""
function json end

function json(io::IO, x::T; style::JSONStyle=DefaultStyle(), allownan::Bool=false, pretty::Union{Integer,Bool}=false) where {T}
    y = lower(style, x)
    buf = Vector{UInt8}(undef, sizeguess(y))
    pos = json!(buf, 1, y, style, allownan, nothing, pretty === true ? 4 : Int(pretty))
    return write(io, resize!(buf, pos - 1))
end

function json(x; style::JSONStyle=DefaultStyle(), allownan::Bool=false, pretty::Union{Integer,Bool}=false)
    y = lower(style, x)
    buf = Base.StringVector(sizeguess(y))
    pos = json!(buf, 1, y, style, allownan, nothing, pretty === true ? 4 : Int(pretty))
    return String(resize!(buf, pos - 1))
end

function json(fname::String, obj; kw...)
    open(fname, "w") do io
        json(io, obj; kw...)
    end
    return fname
end

# we use the same growth strategy as Base julia does for array growing
# which starts with small N at ~5x and approaches 1.125x as N grows
# ref: https://github.com/JuliaLang/julia/pull/40453
newlen(n₀) = ceil(Int, n₀ + 4*n₀^(7 / 8) + n₀ / 8)

macro checkn(n)
    esc(quote
        if (pos + $n - 1) > length(buf)
            resize!(buf, newlen(pos + $n))
        end
    end)
end

struct WriteClosure{JS, arraylike, T} # T is the type of the parent object/array being written
    buf::Vector{UInt8}
    pos::Ptr{Int}
    indent::Int
    depth::Int
    style::JS
    allownan::Bool
    objids::Base.IdSet{Any} # to track circular references
end

# API.applyeach calls f(::String, val), but we want to call
# lower(T, ::Symbol, val), so translate here
@generated function fieldsym(::Type{T}, key) where {T}
    ex = quote
        # @show T, key, val
    end
    if key == String
        for i = 1:fieldcount(T)
            fnm = fieldname(T, i)
            nm = String(fnm)
            push!(ex.args, :(key == $nm && return $(Meta.quot(fnm))))
        end
    end
    push!(ex.args, :(return key))
    return ex
end

@inline function indent(buf, pos, ind, depth)
    if ind > 0
        n = ind * depth + 1
        @checkn n
        buf[pos] = UInt8('\n')
        for i = 1:(n - 1)
            buf[pos + i] = UInt8(' ')
        end
        pos += n
    end
    return pos
end

@inline function (f::WriteClosure{JS, arraylike, T})(key, val) where {JS, arraylike, T}
    pos = unsafe_load(f.pos)
    buf = f.buf
    ind = f.indent
    pos = indent(buf, pos, ind, f.depth)
    # if not an array, we need to write the key + ':'
    if !arraylike
        pos = _string(buf, pos, key)
        @checkn 1
        buf[pos] = UInt8(':')
        pos += 1
        if ind > 0
            @checkn 1
            buf[pos] = UInt8(' ')
            pos += 1
        end
        lowered = lower(f.style, T, fieldsym(T, key), val)
    else
        lowered = lower(f.style, val)
    end
    # check if the lowered value is in our objectid set
    if lowered in f.objids
        # if so, it's a circular reference! so we just write `null`
        pos = _null(buf, pos)
    else
        pos = json!(buf, pos, lowered, f.style, f.allownan, f.objids, ind, f.depth)
    end
    @checkn 1
    buf[pos] = UInt8(',')
    pos += 1
    # store our updated pos
    unsafe_store!(f.pos, pos)
    return Continue()
end

# assume x is lowered value
function json!(buf, pos, x, style::JSONStyle=DefaultStyle(), allownan=false, objids::Union{Nothing, Base.IdSet{Any}}=nothing, ind::Int=0, depth::Int=0)
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
        return _number(buf, pos, x, allownan)
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
        # a custom `API.applyeach` override to provide key-value pairs (more rare)
        al = arraylike(x)
        @checkn 1
        @inbounds buf[pos] = al ? UInt8('[') : UInt8('{')
        pos += 1
        pre_pos = pos
        ref = Ref(pos)
        # use an IdSet to keep track of circular references
        objids = objids === nothing ? Base.IdSet{Any}() : objids
        push!(objids, x)
        c = WriteClosure{typeof(style), al, typeof(x)}(buf, Base.unsafe_convert(Ptr{Int}, ref), ind, depth + 1, style, allownan, objids)
        GC.@preserve ref API.applyeach(c, x)
        # get updated pos
        pos = unsafe_load(c.pos)
        # in WriteClosure, we eagerly write a comma after each element
        # so for non-empty object/arrays, we can just overwrite the last comma with the closechar
        if pos > pre_pos
            pos -= 1
            pos = indent(buf, pos, ind, depth)
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

@noinline infcheck(x, allownan) = isfinite(x) || allownan || throw(ArgumentError("$x not allowed to be written in JSON spec; pass `allownan=true` to allow anyway"))

_number(buf, pos, x, allownan) = _number(buf, pos, convert(Float64, x), allownan)

@inline function _number(buf, pos, x::Union{Integer, AbstractFloat}, allownan)
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
        infcheck(x, allownan)
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
        end
    else
        bytes = codeunits(tostring(x))
        sz = sizeof(bytes)
        @checkn sz
        for i = 1:sz
            @inbounds buf[pos + i - 1] = bytes[i]
        end
        return pos + sz
    end
end
