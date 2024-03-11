#TODO: add some example JSON to the docs here
# and make a table like the one in https://support.smartbear.com/alertsite/docs/monitors/api/endpoint/jsonpath.html
# of all the supported syntax
"""
    Selection syntax

Special "selection syntax" is provided that allows easy querying of JSON objects and arrays using a syntax similar to XPath or CSS selectors,
applied using common Julia syntax.

This syntax mainly uses various forms of `getindex` to select elements of an object or array.
Supported syntax includes:
  * `x["key"]` / `x.key` / `x[:key]` / `x[1]` - select the value associated for a key in object `x` (key can be a String, Symbol, or Integer for an array)
  * `x[:]` - select all values in object or array `x`, returned as a `Selectors.List`, which is a custom array type that supports the selection syntax
  * `x.key` - when `x` is a `List`, select the value for `key` in each element of the `List` (like a broadcasted `getindex`)
  * `x[~, key]` - recursively select all values in object or array `x` that have `key`
  * `x[~, :]` - recursively select all values in object or array `x`, returned as a flattened `List`
  * `x[:, (k, v) -> Bool]` - apply a key-value function `f` to each key-value/index-value in object or array `x`, and return a `List` of all values for which `f` returns `true`
"""
module Selectors

using Structs
import ..PtrString
import ..tostring
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

Structs.arraylike(::List) = true

function Structs.applyeach(f, x::List)
    # note that there should *never* be #undef
    # values in a list, since we only ever initialize empty
    # then push!/append! to it
    for (i, v) in enumerate(items(x))
        ret = f(i, v)
        ret isa Structs.EarlyReturn && return ret
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
eq(x::Symbol, y::PtrString) = streq(y, String(x))
eq(x::PtrString, y::Symbol) = streq(x, String(y))
eq(x::PtrString, y::PtrString) = streq(x, y)
eq(x::PtrString, y::AbstractString) = streq(x, y)
eq(x::AbstractString, y::PtrString) = streq(y, x)

function _getindex(x, key::Union{KeyInd, Integer})
    if Structs.arraylike(x) && key isa KeyInd
        # indexing an array with a key, so we check
        # each element if it's an object and if the
        # object has the key
        # like a broadcasted getindex over x
        values = List()
        Structs.applyeach(x) do _, item
            if Structs.structlike(item)
                # if array elements are objects, we do a broadcasted getproperty with `key`
                # should we try-catch and ignore KeyErrors?
                push!(values, _getindex(item, key))
            else
                # non-objects are just ignored
            end
            return
        end
        return values
    elseif Structs.structlike(x) || Structs.arraylike(x)
        # indexing object w/ key or array w/ index
        # returns a single value
        ret = Structs.applyeach(x) do k, v
            eq(k, key) && return Structs.EarlyReturn(v)
            return
        end
        ret isa Structs.EarlyReturn || throw(KeyError(key))
        return ret.value
    else
        noselection(x)
    end
end

# return all values of an object or elements of an array as a List
function _getindex(x, ::Colon)
    selectioncheck(x)
    values = List()
    Structs.applyeach(x) do _, v
        push!(values, v)
        return
    end
    return values
end

# a list is already a list of all its elements
_getindex(x::List, ::Colon) = x

# indexing object or array w/ a list of keys/indexes
function _getindex(x, inds::Inds)
    selectioncheck(x)
    values = List()
    Structs.applyeach(x) do k, v
        i = findfirst(eq(k), inds)
        i !== nothing && push!(values, v)
        return
    end
    return values
end

# return all values of an object or elements of an array as a List
# that satisfy a key-value function
function _getindex(x, S::Union{typeof(~), Colon}, f::Base.Callable)
    selectioncheck(x)
    values = List()
    Structs.applyeach(x) do k, v
        f(k, v) && push!(values, v)
        if S == ~
            if Structs.structlike(v)
                ret = _getindex(v, ~, f)
                append!(values, ret)
            elseif Structs.arraylike(v)
                ret = _getindex(v, ~, f)
                append!(values, ret)
            end
        end
        return
    end
    return values
end

function _getindex(x, ::typeof(~), key::KeyInd, val)
    selectioncheck(x)
    values = List()
    Structs.applyeach(x) do k, v
        if Structs.structlike(v)
            append!(values, _getindex(v, ~, key, val))
        elseif Structs.arraylike(v)
            append!(values, _getindex(v, ~, key, val))
        elseif eq(k, key) && eq(v[], val)
            push!(values, x)
        end
        return
    end
    return values
end

# recursively return all values of an object or elements of an array as a List (:)
# as a single flattened List; or all properties that match key
function _getindex(x, ::typeof(~), key::Union{KeyInd, Colon})
    values = List()
    if Structs.structlike(x)
        Structs.applyeach(x) do k, v
            if key === Colon()
                push!(values, v)
            elseif eq(k, key)
                if Structs.arraylike(v)
                    Structs.applyeach(v) do _, vv
                        push!(values, vv)
                        return
                    end
                else
                    push!(values, v)
                end
            end
            if Structs.structlike(v)
                ret = _getindex(v, ~, key)
                append!(values, ret)
            elseif Structs.arraylike(v)
                ret = _getindex(v, ~, key)
                append!(values, ret)
            end
            return
        end
    elseif Structs.arraylike(x)
        Structs.applyeach(x) do _, item
            if Structs.structlike(item)
                ret = _getindex(item, ~, key)
                append!(values, ret)
            elseif Structs.arraylike(item)
                ret = _getindex(item, ~, key)
                append!(values, ret)
            end
            return
        end
    else
        noselection(x)
    end
    return values
end

selectioncheck(x) = Structs.structlike(x) || Structs.arraylike(x) || noselection(x)
@noinline noselection(x) = throw(ArgumentError("Selection syntax not defined for: `$(typeof(x))))`"))

# build up propertynames by iterating over each key-value pair
function _propertynames(x)
    selectioncheck(x)
    nms = Symbol[]
    Structs.applyeach(x) do k, _
        push!(nms, tostring(Symbol, k))
        return
    end
    return nms
end

# convenience macro for defining high-level getindex/getproperty methods
macro selectors(T)
    esc(quote
        Base.getindex(x::$T, arg) = Selectors._getindex(x, arg)
        Base.getindex(x::$T, ::Colon, arg) = Selectors._getindex(x, :, arg)
        Base.getindex(x::$T, ::typeof(~), arg) = Selectors._getindex(x, ~, arg)
        Base.getindex(x::$T, ::typeof(~), key, val) = Selectors._getindex(x, ~, key, val)
        Base.getproperty(x::$T, key::Symbol) = Selectors._getindex(x, key)
        Base.propertynames(x::$T) = Selectors._propertynames(x)
        Base.hasproperty(x::$T, key::Symbol) = key in propertynames(x)
        Base.length(x::$T) = Selectors.Structs.applylength(x)
    end)
end

@selectors List

end # module