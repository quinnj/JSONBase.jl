module API

using Dates, UUIDs

export foreach, Continue, fields, mutable, kwdef,
       dictlike, addkeyval!, _keytype, _valtype,
       lower, lift, arraylike

"""
    JSONBase.foreach(f, x)

A custom `foreach` function that operates specifically on pairs,
supports short-circuiting, and can return an updated state via `JSONBase.Continue`.
For each key-value or index-value pair in `x`, call `f(k, v)`.
If `f` doesn't return an `JSONBase.Continue` instance, `foreach` should
return the non-`Continue` value immediately and stop iterating.
`foreach` should return `JSONBase.Continue` once iterating is complete.

An example overload of `foreach` for a generic iterable would be:

```julia
function JSONBase.foreach(f, x::MyIterable)
    for (i, v) in enumerate(x)
        ret = f(i, v)
        # if `f` doesn't return Continue, return immediately
        ret isa JSONBase.Continue || return ret
    end
    return JSONBase.Continue()
end
```
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

Supported properties per field include:
  * `jsonkey::String`: a key name different from `fieldname(T, nm)` that will
     be used when outputing `T` to JSON; also used in materialization, if `jsonkey`
     value is found as a JSON object key, it will be set for the indicated field
  * `default`: a default value to be used for a field in the "struct" materialization
    strategy when the field isn't present in the JSON source; note that for `mutable`
    and `kwdef` structs, it is already convenient to set default values, so
    this `default` value is ignored for those materialization strategies

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

For fieldnames of `T` that don't have a different JSON object key, [`JSONBase.fields`](@ref)
can be used to map between fieldname and JSON key.
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

For fieldnames of `T` that don't have a different JSON object key, [`JSONBase.fields`](@ref)
can be used to map between fieldname and JSON key.
"""
kwdef(_) = false

"""
    JSONBase.dictlike(T)

Overloadable method that indicates whether a type `T` supports the
"dictlike" strategy for construction via `JSONBase.materialize`, which
doesn't do any field matching like the `mutable`, `kwdef`, or `struct`
strategies, but instead just slurps up all key-value pairs into `T`
like a `Dict` or `Vector{Pair}`.

Specifically, the "dictlike" strategy requires that a type support:
  * `T()`: any empty constructor
  * `T <: AbstractDict`: `T` must subtype and implement the `AbstractDict` interface;
    JSON object key-value pairs will be added to the object via `setindex!`
  * Must support the `keytype` and `valtype` functions, which return the key and value
    types of the `T` object

To add support for the "dictlike" strategy for a custom type `MyType` the definition would be:
    
```julia
JSONBase.dictlike(::Type{<:MyType}) = true
```

Note this definition works whether `MyType` has type parameters or not due to being defined.
"""
function dictlike end

dictlike(::Type{<:AbstractDict}) = true
dictlike(::Type{<:AbstractVector{<:Pair}}) = true
dictlike(_) = false

addkeyval!(d::AbstractDict, k, v) = d[k] = v
addkeyval!(d::AbstractVector, k, v) = push!(d, k => v)

_keytype(d) = keytype(d)
_keytype(d::AbstractVector{<:Pair}) = eltype(d).parameters[1]
_valtype(d) = valtype(d)
_valtype(d::AbstractVector{<:Pair}) = eltype(d).parameters[2]

"""
    JSONBase.lower(x)
    JSONBase.lower(::Type{T}, key, val)

Allow an object `x` to be "lowered" into a JSON-compatible representation.
The 2nd method allows overloading lower for an object of type `T` for a specific
key-value representing the field name (as a Symbol) and the field value being serialized.
This allows customizing the serialization of a specific field of a type without
needing to clash with other global `lower` methods or lower an entire object
when only specific fields need custom lowering.

Examples of overloading `lower` for custom types could look like:
    
```julia
struct Unknown end
# custom sentinel value we want to be `null` in JSON
JSONBase.lower(::Type{Unknown}) = nothing

struct Person
    name::String
    birthdate::Date
end

# we want to serialize the birthdate as a string with
# a non-default format
JSONBase.lower(::Type{Person}, key, val) = key == :birthdate ? Dates.format(val, dateformat"mm/dd/yyyy") : lower(val)
```
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
    JSONBase.lift(T, x)
    JSONBase.lift(::Type{T}, key, val)

Allow a JSON-native object `x` to be converted into the custom type `T`.
This is used to allow for custom types to be constructed directly in the
materialization process.

"JSON-native object" means that `x` will be one of the following:
  * `nothing`: parsed from `null`
  * `true`/`false`: parsed from `true`/`false`
  * An `Int64`, `Int128`, `BigInt`, `Float64`, or `BigFloat` value: parsed from a JSON number (exact type will be the lowest precision required)
  * A `String`: parsed from a JSON string
  * A `Vector{Any}`: parsed from a JSON array
  * A `Dict{String, Any}`: parsed from a JSON object

Note that the types used for JSON strings, arrays, and objects can be controlled via
passing a custom [`JSONBase.Types`](@ref) object to [`JSONBase.materialize`](@ref) via
the `types` keyword argument.

Examples of overloading `lift` for custom types could look like:
    
```julia
struct Unknown end
# custom sentinel value we want from `null` in JSON
JSONBase.lift(::Type{Unknown}, ::Nothing) = Unknown()

# field-specific lift
struct Person
    name::String
    birthdate::Date
end

# we know the JSON value for the birthdate field will be
# a string with the format "mm/dd/yyyy"
JSONBase.lift(::Type{Person}, key, val) = key == :birthdate ? Dates.parse(val, dateformat"mm/dd/yyyy") : val
```
"""
function lift end

lift(::Type{T}, x) where {T} = Base.issingletontype(T) ? T() : convert(T, x)
lift(::Type{T}, key::Symbol, val) where {T} = lift(fieldtype(T, key), val)

# some default lift definitions for common types
lift(::Type{T}, ::Nothing) where {T >: Missing} = T === Any ? nothing : missing
lift(::Type{T}, x::String) where {T <: Union{VersionNumber, UUID, Dates.TimeType, Regex}} = T(x)

function lift(::Type{Char}, x::String)
    if length(x) == 1
        return x[1]
    else
        throw(ArgumentError("invalid `Char` from string value: \"$x\""))
    end
end

"""
    JSONBase.arraylike(x)

Overloadable method that allows a type `T` to be treated as an array
when being serialized to JSON via `JSONBase.json`.
Types overloading `arraylike`, must also overload `JSONBase.foreach`.
Note that default `foreach` implementations exist for `AbstractArray`,
`AbstractSet`.

An example of overloading this method for a custom type `MyType` looks like:

```julia
JSONBase.arraylike(::MyType) = true
```
"""
function arraylike end

arraylike(_) = false
arraylike(::Union{AbstractArray, AbstractSet, Tuple, Base.Generator}) = true

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
@inline function foreach(f, x::Union{AbstractSet, Base.Generator})
    for (i, v) in enumerate(x)
        ret = f(i, v)
        ret isa Continue || return ret
    end
    return Continue()
end

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

function foreach(f, x::AbstractDict)
    for (k, v) in x
        ret = f(k, v)
        ret isa Continue || return ret
    end
    return Continue()
end

# convenience function that calls API.foreach on x
# but applies the function to just the 1st item
struct ApplyOnce{F}
    f::F
end

@inline (f::ApplyOnce)(k, v) = f.f(v)

applyonce(f, x) = foreach(ApplyOnce(f), x)

end # module API