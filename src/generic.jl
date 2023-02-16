"""
    JSONBase.togeneric(json)

Materialize a JSON input (string, vector, stream, LazyValue, BJSONValue, etc.) into a generic
Julia representation (Dict, Array, etc.). Specifically, the following materializations are used:
  * JSON object => `Dict{String, Any}`
  * JSON array => `Vector{Any}`
  * JSON string => `String`
  * JSON number => `Int64`, `Int128`, `BigInt`, `Float64`, or `BigFloat`
  * JSON true => `true`
  * JSON false => `false`
  * JSON null => `nothing`

Supported keyword arguments include:
  * `jsonlines`: 
  * `float64`: 
  * `objecttype`: 
  * `arraytype`: 
"""
function togeneric end

togeneric(io::Union{IO, Base.AbstractCmd}; kw...) = togeneric(Base.read(io); kw...)
togeneric(buf::Union{AbstractVector{UInt8}, AbstractString}; types::Type{<:Types}=TYPES, kw...) =
    togeneric(tolazy(buf; kw...); types)

@inline function togeneric(x::LazyValue; types::Type{<:Types}=TYPES)
    local y
    pos = togeneric(_x -> (y = _x), x, types)
    buf = getbuf(x)
    len = getlength(buf)
    if getpos(x) == 1
        if pos <= len
            b = getbyte(buf, pos)
            while b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')
                pos += 1
                pos > len && break
                b = getbyte(buf, pos)
            end
        end
        if (pos - 1) != len
            invalid(InvalidChar, getbuf(x), pos, Any)
        end
    end
    return y
end

function togeneric(x::BJSONValue; types::Type{<:Types}=TYPES)
    local y
    togeneric(_x -> (y = _x), x, types)
    return y
end

struct GenericObjectClosure{O, T}
    keyvals::O
end

_push!(d::AbstractDict, k, v) = d[k] = v
_push!(d, k, v) = push!(d, k => v)

@inline function (f::GenericObjectClosure{O, T})(key, val) where {O, T}
    pos = togeneric(x -> _push!(f.keyvals, tostring(stringtype(T), key), x), val, T)
    return API.Continue(pos)
end

struct GenericArrayClosure{A, T}
    arr::A
end

@inline function (f::GenericArrayClosure{A, T})(i, val) where {A, T}
    pos = togeneric(x -> push!(f.arr, x), val, T)
    return API.Continue(pos)
end

function togeneric(valfunc::F, x::LazyValue, types::Type{Types{O, A, S}}=TYPES) where {F, O, A, S}
    T = gettype(x)
    if T == JSONTypes.OBJECT
        d = O()
        pos = parseobject(x, GenericObjectClosure{O, types}(d)).pos
        valfunc(d)
        return pos
    elseif T == JSONTypes.ARRAY
        a = A(undef, 0)
        sizehint!(a, 16)
        pos = parsearray(x, GenericArrayClosure{A, types}(a)).pos
        valfunc(a)
        return pos
    elseif T == JSONTypes.STRING
        str, pos = parsestring(x)
        valfunc(tostring(S, str))
        return pos
    elseif T == JSONTypes.NUMBER
        return parsenumber(x, valfunc)
    elseif T == JSONTypes.NULL
        valfunc(nothing)
        return getpos(x) + 4
    elseif T == JSONTypes.TRUE
        valfunc(true)
        return getpos(x) + 4
    else
        @assert T == JSONTypes.FALSE
        valfunc(false)
        return getpos(x) + 5
    end
end

@inline function togeneric(valfunc::F, x::BJSONValue, T::Type{Types{O, A, S}}=TYPES) where {F, O, A, S}
    T = gettype(x)
    if T == JSONTypes.OBJECT
        d = O()
        pos = parseobject(x, GenericObjectClosure{O, T}(d)).pos
        valfunc(d)
        return pos
    elseif T == JSONTypes.ARRAY
        a = A(undef, 0)
        sizehint!(a, 16)
        #TODO: should we sizehint! the array here w/ actual length from BJSONValue?
        pos = parsearray(x, GenericArrayClosure{A, T}(a)).pos
        valfunc(a)
        return pos
    elseif T == JSONTypes.STRING
        str, pos = parsestring(x)
        valfunc(tostring(S, str))
        return pos
    elseif T == JSONTypes.INT
        return parseint(x, valfunc)
    elseif T == JSONTypes.FLOAT
        return parsefloat(x, valfunc)
    elseif T == JSONTypes.NULL
        valfunc(nothing)
        return getpos(x) + 1
    elseif T == JSONTypes.TRUE
        valfunc(true)
        return getpos(x) + 1
    else
        @assert T == JSONTypes.FALSE
        valfunc(false)
        return getpos(x) + 1
    end
end
