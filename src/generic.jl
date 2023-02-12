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
togeneric(buf::Union{AbstractVector{UInt8}, AbstractString};
    objecttype=Dict{String, Any}, arraytype=Vector{Any}, kw...) =
    togeneric(tolazy(buf; kw...); objecttype, arraytype)

@inline function togeneric(x::LazyValue; objecttype::Type{O}=Dict{String, Any}, arraytype::Type{A}=Vector{Any}) where {O, A}
    local y
    pos = togeneric(_x -> (y = _x), x, objecttype, arraytype)
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

function togeneric(x::BJSONValue; objecttype::Type{O}=Dict{String, Any}, arraytype::Type{A}=Vector{Any}) where {O, A}
    local y
    togeneric(_x -> (y = _x), x, objecttype, arraytype)
    return y
end

struct GenericObjectClosure{O, A}
    keyvals::O
end

_push!(d::AbstractDict, k, v) = d[k] = v
_push!(d, k, v) = push!(d, k => v)

@inline function (f::GenericObjectClosure{O, A})(key, val) where {O, A}
    pos = togeneric(x -> _push!(f.keyvals, tostring(key), x), val, O, A)
    return API.Continue(pos)
end

struct GenericArrayClosure{O, A}
    arr::A
end

@inline function (f::GenericArrayClosure{O, A})(i, val) where {O, A}
    pos = togeneric(x -> push!(f.arr, x), val, O, A)
    return API.Continue(pos)
end

function togeneric(valfunc::F, x::LazyValue, objecttype::Type{O}=Dict{String, Any}, arraytype::Type{A}=Vector{Any}) where {F, O, A}
    T = gettype(x)
    if T == JSONTypes.OBJECT
        d = objecttype()
        pos = parseobject(x, GenericObjectClosure{O, A}(d)).pos
        valfunc(d)
        return pos
    elseif T == JSONTypes.ARRAY
        a = arraytype(undef, 0)
        sizehint!(a, 16)
        pos = parsearray(x, GenericArrayClosure{O, A}(a)).pos
        valfunc(a)
        return pos
    elseif T == JSONTypes.STRING
        str, pos = parsestring(x)
        valfunc(tostring(str))
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

@inline function togeneric(valfunc::F, x::BJSONValue, objecttype::Type{O}=Dict{String, Any}, arraytype::Type{A}=Vector{Any}) where {F, O, A}
    T = gettype(x)
    if T == JSONTypes.OBJECT
        d = objecttype()
        pos = parseobject(x, GenericObjectClosure{O, A}(d)).pos
        valfunc(d)
        return pos
    elseif T == JSONTypes.ARRAY
        a = arraytype(undef, 0)
        sizehint!(a, 16)
        #TODO: should we sizehint! the array here w/ actual length from BJSONValue?
        pos = parsearray(x, GenericArrayClosure{O, A}(a)).pos
        valfunc(a)
        return pos
    elseif T == JSONTypes.STRING
        str, pos = parsestring(x)
        valfunc(tostring(str))
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
