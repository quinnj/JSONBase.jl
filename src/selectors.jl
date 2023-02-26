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

import ..API: foreach, Continue, objectlike, arraylike
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

arraylike(::Type{List}) = true

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

function _getindex(x, key::Union{KeyInd, Integer})
    if arraylike(x) && key isa KeyInd
        values = List()
        foreach(x) do _, item
            if objectlike(item)
                ret = _getindex(item, key)
                if ret isa List
                    append!(values, ret)
                elseif !(ret isa Continue)
                    push!(values, ret)
                end
            end
            return Continue()
        end
        return values
    elseif objectlike(x) || arraylike(x)
        ret = foreach(x) do k, v
            return eq(k, key) ? v : Continue()
        end
        ret isa Continue && throw(KeyError(key))
        return ret
    else
        noselection(x)
    end
end

function _getindex(x, ::Colon)
    selectioncheck(x)
    values = List()
    foreach(x) do _, v
        push!(values, v)
        return Continue()
    end
    return values
end

_getindex(x::List, ::Colon) = x

function _getindex(x, inds::Inds)
    selectioncheck(x)
    values = List()
    foreach(x) do k, v
        i = findfirst(eq(k), inds)
        i !== nothing && push!(values, v)
        return Continue()
    end
    return values
end

function _getindex(x, f::Base.Callable)
    selectioncheck(x)
    return _getindex(x, f(x))
end

function _getindex(x, ::Colon, f::Base.Callable)
    selectioncheck(x)
    values = List()
    foreach(x) do k, v
        f(k, v) && push!(values, v)
        return Continue()
    end
    return values
end

function _getindex(x, ::typeof(~), key::Union{KeyInd, Colon})
    values = List()
    if objectlike(x)
        foreach(x) do k, v
            if key === Colon()
                push!(values, v)
            elseif eq(k, key)
                if arraylike(v)
                    foreach(v) do _, vv
                        push!(values, vv)
                        return Continue()
                    end
                else
                    push!(values, v)
                end
            end
            if objectlike(v)
                ret = _getindex(v, ~, key)
                append!(values, ret)
            elseif arraylike(v)
                ret = _getindex(v, ~, key)
                append!(values, ret)
            end
            return Continue()
        end
    elseif arraylike(x)
        foreach(x) do _, item
            if objectlike(item)
                ret = _getindex(item, ~, key)
                append!(values, ret)
            elseif arraylike(item)
                ret = _getindex(item, ~, key)
                append!(values, ret)
            end
            return Continue()
        end
    else
        noselection(x)
    end
    return values
end

selectioncheck(x) = objectlike(x) || arraylike(x) || noselection(x)
@noinline noselection(x) = throw(ArgumentError("Selection syntax not defined for: `$x`"))

macro selectors(T)
    esc(quote
        Base.getindex(x::$T, arg) = Selectors._getindex(x, arg)
        Base.getindex(x::$T, ::Colon, arg) = Selectors._getindex(x, :, arg)
        Base.getindex(x::$T, ::typeof(~), arg) = Selectors._getindex(x, ~, arg)
        Base.getproperty(x::$T, key::Symbol) = Selectors._getindex(x, key)
    end)
end

@selectors List

end # module