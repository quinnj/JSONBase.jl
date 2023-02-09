"""
    Selection syntax

Special "selection syntax" is provided that allows easy querying of JSON objects and arrays using a syntax similar to XPath or CSS selectors.
This syntax mainly uses various forms of `getindex` to select elements of an object or array.
Supported syntax includes:
  * `x["key"]` / `x.key` / `x[:key]` - select the value associated with the key `"key"` in object `x`
  * `x[:]` - select all values in object or array `x`, returned as a `Selectors.List`
  * `x.key` - when `x` is a `List`, select the value for key `key` in each element of the `List`
  * `x[~, key]` - recursively select all values in object or array `x` that have a key `key`
  * `x[~, :]` - recursively select all values in object or array `x`, returned as a flattened `List`
  * `x[:, (k, v) -> Bool]` - apply a key-value function `f` to each key-value/index-value in object or array `x`, and return a `List` of all values for which `f` returns `true`
"""
module Selectors

import ..API: foreach, Continue, JSONType, ObjectLike, ArrayLike, ObjectOrArrayLike
import ..PtrString
import ..streq

export List

"""
    List(...)

A custom array wrapper that supports the Selectors selection syntax.
"""
struct List{T} <: AbstractVector{T}
    items::Vector{T}
end

items(x::List) = getfield(x, :items)
Base.getindex(x::List) = map(getindex, items(x))
List(T=Any) = List(T[])
Base.size(x::List) = size(items(x))
Base.eltype(::List{T}) where {T} = T
Base.isassigned(x::List, args::Integer...) = isassigned(items(x), args...)

Base.push!(x::List, item) = push!(items(x), item)
Base.append!(x::List, items_to_append) = append!(items(x), items_to_append)

JSONType(::List) = ArrayLike()

function foreach(f, x::List)
    # note that there should *never* be #undef
    # values in a list, since we only ever initialize
    # one empty, then push!/append! to it
    for (i, v) in enumerate(items(x))
        ret = f(i, v)
        ret isa Continue || return ret
    end
    return Continue()
end

const KeyInd = Union{AbstractString, Symbol}
const Inds = Union{AbstractVector{<:KeyInd}, NTuple{N, <:KeyInd} where {N},
    AbstractVector{<:Integer}, NTuple{N, <:Integer} where {N}}

eq(x) = y -> eq(x, y)
eq(x, y) = isequal(x, y)
eq(x::Symbol, y::AbstractString) = isequal(String(x), y)
eq(x::AbstractString, y::Symbol) = isequal(x, String(y))
eq(x::Symbol, y::PtrString) = streq(y, String(x))
eq(x::PtrString, y::Symbol) = streq(x, String(y))
eq(x::PtrString, y::PtrString) = streq(x, y)
eq(x::PtrString, y::AbstractString) = streq(x, y)
eq(x::AbstractString, y::PtrString) = streq(y, x)

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
        ST = JSONType(item)
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
        ST = JSONType(v)
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
        ST = JSONType(item)
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
        Base.getindex(x::$T, arg) = Selectors._getindex(Selectors.JSONType(x), x, arg)
        Base.getindex(x::$T, ::Colon, arg) = Selectors._getindex(Selectors.JSONType(x), x, :, arg)
        Base.getindex(x::$T, ::typeof(~), arg) = Selectors._getindex(Selectors.JSONType(x), x, ~, arg)
        Base.getproperty(x::$T, key::Symbol) = Selectors._getindex(Selectors.JSONType(x), x, key)
    end)
end

@selectors List

end # module