togeneric(io::Union{IO, Base.AbstractCmd}; kw...) = togeneric(Base.read(io); kw...)
togeneric(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...) = togeneric(tolazy(buf; kw...))

function togeneric(x::Union{LazyValue, BJSONValue})
    local y
    _togeneric(x, _x -> (y = _x))
    return y
end

struct GenericObjectClosure
    dict::Dict{String, Any}
end

@inline function (f::GenericObjectClosure)(key, val)
    pos = _togeneric(val, x -> f.dict[tostring(key)] = x)
    return API.Continue(pos)
end

struct GenericArrayClosure
    arr::Vector{Any}
end

@inline function (f::GenericArrayClosure)(i, val)
    pos = _togeneric(val, x -> push!(f.arr, x))
    return API.Continue(pos)
end

@inline function _togeneric(x::LazyValue, valfunc::F) where {F}
    T = gettype(x)
    if T == JSONTypes.OBJECT
        d = Dict{String, Any}()
        pos = parseobject(x, GenericObjectClosure(d)).pos
        valfunc(d)
        return pos
    elseif T == JSONTypes.ARRAY
        a = Any[]
        pos = parsearray(x, GenericArrayClosure(a)).pos
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

@inline function _togeneric(x::BJSONValue, valfunc::F) where {F}
    T = gettype(x)
    if T == JSONTypes.OBJECT
        d = Dict{String, Any}()
        pos = parseobject(x, GenericObjectClosure(d)).pos
        valfunc(d)
        return pos
    elseif T == JSONTypes.ARRAY
        a = Any[]
        pos = parsearray(x, GenericArrayClosure(a)).pos
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
