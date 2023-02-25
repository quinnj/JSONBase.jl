module API

using Dates, UUIDs

export foreach, Continue, fields, mutable, kwdef, lower, upcast, JSONType, ObjectLike, ArrayLike

"""
    JSONBase.foreach(f, x)

A custom `foreach` function that operates specifically on pairs,
supports short-circuiting, and can return an updated state via `JSONBase.Continue`.
For each key-value or index-value pair in `x`, call `f(k, v)`.
If `f` doesn't return an `JSONBase.Continue` instance, `foreach` should
return the non-`Continue` value immediately and stop iterating.
`foreach` should return `JSONBase.Continue` once iterating is complete.
"""
function foreach end

"""
    JSONBase.Continue(state)

A special sentinel value for use with `JSONBase.foreach`, that indicates
that `foreach` should continue iterating.
"""
struct Continue
    pos::Int
end

Continue() = Continue(0)

"""
    JSONBase.fields(T)

Overload used by JSONBase during materialization and writing
to override default field names, values, properties.

An example definition for a custom type `MyType` would be:

```julia
JSONBase.fields(::Type{<:MyType}) = (
    field1 = (jsonkey="field_1", default=10)
)
```
"""
function fields end

fields(_) = (;)

"""
    JSONBase.mutable(T)

Overloadable method that indicates whether a type `T` supports the
"mutable" strategy for construction via `JSONBase.materialize`.

Specifically, the "mutable" strategy requires that a type support:
  * `T()`: construction with a no-arg constructor
  * `setproperty!(x, name, value)`: when JSON object keys are found that match a property name, the value is set via `setproperty!`

To add support for the "mutable" strategy for a custom type `MyType` the definition would be:

```julia
JSONBase.mutable(::Type{<:MyType}) = true
```

Note this definition works whether `MyType` has type parameters or not due to being defined
for *any* `MyType`.
"""
mutable(_) = false

"""
    JSONBase.kwdef(T)

Overloadable method that indicates whether a type `T` supports the
"keyword arg" strategy for construction via `JSONBase.materialize`.

Specifically, the "keyword arg" strategy requires that a type support:
  * `T(; keyvals...)`: construction by passing a collection of key-value pairs
    as keyword arguments to the type constructor; this kind of constructor is
    defined automatically when `@kwdef` is used to define a type

To add support for the "keyword arg" strategy for a custom type `MyType` the definition would be:

```julia
JSONBase.kwdef(::Type{<:MyType}) = true
```

Note this definition works whether `MyType` has type parameters or not due to being defined
for *any* `MyType`.
"""
kwdef(_) = false

"""
    JSONBase.lower(x)
    JSONBase.lower(::Type{T}, key, val)

Allow an object `x` to be "lowered" into a JSON-compatible representation.
The 2nd method allows overloading lower for an object of type `T` for a specific
key-value representing the field name (as a String) and the field value being serialized.
This allows customizing the serialization of a specific field of a type without
needing to clash with other global `lower` methods.
"""
function lower end

lower(x) = x
# allow field-specific lowering for types
lower(::Type{T}, key, val) where {T} = lower(val)

# some default lowerings for common types
lower(::Missing) = nothing
lower(x::Symbol) = String(x)
lower(x::Union{Enum, AbstractChar, VersionNumber, Cstring, Cwstring, UUID, Dates.TimeType}) = string(x)
lower(x::Regex) = x.pattern
lower(x::Matrix) = eachcol(x)

"""
    JSONBase.upcast(T, x)

Allow a JSON-natural object `x` to be converted into a more general type `T`.
This is used to allow for more general types to be used in the
JSONBase materialization process.
"""
function upcast end

upcast(::Type{T}, x) where {T} = convert(T, x)

upcast(::Type{T}, key::Symbol, val) where {T} = upcast(fieldtype(T, key), val)
@generated function upcast(::Type{T}, key::AbstractString, val) where {T}
    ex = quote
        @show T, key, val
    end
    for i = 1:fieldcount(T)
        nm = String(fieldname(T, i))
        push!(ex.args, :(key == $nm && return upcast($(fieldtype(T, i)), val)))
    end
    push!(ex.args, :(return val))
    return ex
end

# some default upcasts for common types
upcast(::Type{T}, ::Nothing) where {T >: Missing} = T === Any ? nothing : missing
upcast(::Type{T}, x::String) where {T <: Union{VersionNumber, UUID, Dates.TimeType, Regex}} = T(x)

function upcast(::Type{Char}, x::String)
    if length(x) == 1
        return x[1]
    else
        throw(ArgumentError("invalid `Char` from string value: \"$x\""))
    end
end

abstract type JSONType end

JSONType(::T) where {T} = JSONType(T)

struct ObjectLike <: JSONType end
struct ArrayLike <: JSONType end
const ObjectOrArrayLike = Union{ObjectLike, ArrayLike}

JSONType(::Type{<:Union{AbstractArray, AbstractSet, Tuple}}) = ArrayLike()

@inline function foreach(f, x::AbstractArray)
    for i in eachindex(x)
        ret = if isassigned(x, i)
            f(i, x[i])
        else
            f(i, nothing)
        end
        ret isa Continue || return ret
    end
    return Continue()
end

# appropriate definition for iterables that
# can't have #undef values
@inline function foreach(f, x::AbstractSet)
    for (i, v) in enumerate(x)
        ret = f(i, v)
        ret isa Continue || return ret
    end
    return Continue()
end

JSONType(::Type{T}) where {T} = isstructtype(T) ? ObjectLike() : nothing
JSONType(::Type{String}) = nothing

_string(x) = String(x)
_string(x::Integer) = string(x)

# generic definition for Tuple, NamedTuple, structs
@generated function foreach(f, x::T) where {T}
    N = fieldcount(T)
    ex = quote
        Base.@_inline_meta
        fds = fields(T)
    end
    for i = 1:N
        fname = fieldname(T, i)
        ftype = fieldtype(T, i)
        str = _string(fname)
        push!(ex.args, quote
            field = get(fds, $(Meta.quot(fname)), nothing)
            str = field !== nothing && haskey(field, :jsonkey) ? field.jsonkey : $str
            ret = if isdefined(x, $i)
                f(str, getfield(x, $i))
            else
                f(str, nothing)
            end
            ret isa Continue || return ret
        end)
    end
    push!(ex.args, :(return Continue()))
    return ex
end

JSONType(::Type{<:AbstractDict}) = ObjectLike()

function foreach(f, x::AbstractDict)
    for (k, v) in x
        ret = f(k, v)
        ret isa Continue || return ret
    end
    return Continue()
end

end # module API