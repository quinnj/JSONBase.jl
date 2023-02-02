module Selectors

export List

function foreach end
struct ObjectLike end
struct ArrayLike end
const ObjectOrArrayLike = Union{ObjectLike, ArrayLike}
SelectorType(x) = nothing

struct Continue
    pos::Int
end

Continue() = Continue(0)

struct List{T} <: AbstractVector{T}
    items::Vector{T}
end

items(x::List) = getfield(x, :items)
Base.getindex(x::List) = map(getindex, items(x))
List(T=Any) = List(T[])
List(T, n) = List(Vector{T}(undef, n))
List(n::Integer) = List(Any, n)
Base.size(x::List) = size(items(x))
Base.eltype(::List{T}) where {T} = T
Base.isassigned(x::List, args::Integer...) = isassigned(items(x), args...)
Base.setindex!(x::List, item, i::Int) = setindex!(items(x), item, i)

Base.push!(x::List, item) = push!(items(x), item)
Base.append!(x::List, items_to_append) = append!(items(x), items_to_append)

SelectorType(::List) = ArrayLike()
function foreach(f, items::List)
    for (i, x) in enumerate(getfield(items, :items))
        ret = f(i, x)
        ret isa Continue || return ret
    end
    return
end

const KeyInd = Union{AbstractString, Symbol}
const Inds = Union{AbstractVector{<:KeyInd}, NTuple{N, <:KeyInd} where {N},
    AbstractVector{<:Integer}, NTuple{N, <:Integer} where {N}}

eq(x) = y -> eq(x, y)
eq(x, y) = isequal(x, y)
eq(x::Symbol, y::AbstractString) = isequal(String(x), y)
eq(x::AbstractString, y::Symbol) = isequal(x, String(y))

function _getindex(::ObjectOrArrayLike, x, key::Union{KeyInd, Integer})
    ret = foreach(x) do k, v
        return eq(k, key) ? v : Continue()
    end
    ret isa Continue && throw(KeyError(key))
    return ret
end

function _getindex(::ArrayLike, x, key::KeyInd)
    values = List()
    foreach(x) do _, item
        ST = SelectorType(item)
        if ST === ObjectLike()
            ret = _getindex(ST, item, key)
            if ret isa List
                append!(values, ret)
            elseif !(ret isa Continue)
                push!(values, ret)
            end
        end
        return Continue()
    end
    return values
end

function _getindex(::ObjectOrArrayLike, x, ::Colon)
    values = List()
    foreach(x) do _, v
        push!(values, v)
        return Continue()
    end
    return values
end

_getindex(::ArrayLike, x::List, ::Colon) = x

function _getindex(::ObjectOrArrayLike, x, inds::Inds)
    values = List()
    foreach(x) do k, v
        i = findfirst(eq(k), inds)
        i !== nothing && push!(values, v)
        return Continue()
    end
    return values
end

_getindex(ST::ObjectOrArrayLike, x, f::Base.Callable) = _getindex(ST, x, f(x))

function _getindex(::ObjectOrArrayLike, x, ::Colon, f::Base.Callable)
    values = List()
    foreach(x) do k, v
        f(k, v) && push!(values, v)
        return Continue()
    end
    return values
end

function _getindex(::ObjectLike, x, ::typeof(~), key::Union{KeyInd, Colon})
    values = List()
    foreach(x) do k, v
        ST = SelectorType(v)
        if key === Colon()
            push!(values, v)
        elseif eq(k, key)
            if ST === ArrayLike()
                foreach(v) do _, vv
                    push!(values, vv)
                    return Continue()
                end
            else
                push!(values, v)
            end
        end
        if ST === ObjectLike()
            ret = _getindex(ObjectLike(), v, ~, key)
            append!(values, ret)
        elseif ST === ArrayLike()
            ret = _getindex(ArrayLike(), v, ~, key)
            append!(values, ret)
        end
        return Continue()
    end
    return values
end

function _getindex(::ArrayLike, x, ::typeof(~), key::Union{KeyInd, Colon})
    values = List()
    foreach(x) do _, item
        ST = SelectorType(item)
        if ST === ObjectLike()
            ret = _getindex(ObjectLike(), item, ~, key)
            append!(values, ret)
        elseif ST === ArrayLike()
            ret = _getindex(ArrayLike(), item, ~, key)
            append!(values, ret)
        end
        return Continue()
    end
    return values
end

_getindex(::Nothing, args...) = throw(ArgumentError("Selection syntax not defined for: `$(args[1])`"))

macro selectors(T)
    esc(quote
        Base.getindex(x::$T, arg) = Selectors._getindex(Selectors.SelectorType(x), x, arg)
        Base.getindex(x::$T, ::Colon, arg) = Selectors._getindex(Selectors.SelectorType(x), x, :, arg)
        Base.getindex(x::$T, ::typeof(~), arg) = Selectors._getindex(Selectors.SelectorType(x), x, ~, arg)
        Base.getproperty(x::$T, key::Symbol) = Selectors._getindex(Selectors.SelectorType(x), x, key)
    end)
end

@selectors List

end # module