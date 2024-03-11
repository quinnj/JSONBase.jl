module API

using Dates, UUIDs, Logging

export applyeach, EarlyReturn, UpdatedState, fields, mutable, kwdef,
       dictlike, addkeyval!, _keytype, _valtype,
       JSONStyle, DefaultStyle, lower, lift, choosetype, arraylike

"""
    JSONBase.applyeach(f, x) -> Union{JSONBase.EarlyReturn, Nothing}

A custom `foreach`-like function that operates specifically on `(key, val)` or `(ind, val)` pairs,
and supports short-circuiting (via `JSONBase.EarlyReturn`).

For each key-value or index-value pair in `x`, call `f(k, v)`.
If `f` returns a `JSONBase.EarlyReturn` instance, `applyeach` should
return the `EarlyReturn` immediately and stop iterating (i.e. short-circuit).
Otherwise, the return value of `f` is ignored and iteration continues.

An example overload of `applyeach` for a generic iterable would be:

```julia
function JSONBase.applyeach(f, x::MyIterable)
    for (i, v) in enumerate(x)
        ret = f(i, v)
        # if `f` returns EarlyReturn, return immediately
        ret isa JSONBase.EarlyReturn && return ret
    end
    return
end
```
"""
function applyeach end

"""
    JSONBase.EarlyReturn{T}

A wrapper type that can be used in function arguments to `applyeach`
to short-circuit iteration and return a value from `applyeach`.

Example usage:

```julia
function find_needle_in_haystack(haystack, needle)
    ret = applyeach(haystack) do k, v
        k == needle && return JSONBase.EarlyReturn(v)
    end
    ret isa JSONBase.EarlyReturn && return ret.value
    throw(ArgumentError("needle not found in haystack")
end
````
"""
struct EarlyReturn{T}
    value::T
end



@inline function applyeach(f, x::AbstractArray)
    for i in eachindex(x)
        ret = if isassigned(x, i)
            f(i, x[i])
        else
            f(i, nothing)
        end
        ret isa EarlyReturn && return ret
    end
    return
end

# appropriate definition for iterables that
# can't have #undef values
@inline function applyeach(f, x::Union{AbstractSet, Base.Generator, Core.SimpleVector})
    for (i, v) in enumerate(x)
        ret = f(i, v)
        ret isa EarlyReturn && return ret
    end
    return
end

_string(x) = String(x)
_string(x::Integer) = string(x)

# generic definition for Tuple, NamedTuple, structs
@generated function applyeach(f, x::T) where {T}
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
            ret isa EarlyReturn && return ret
        end)
    end
    push!(ex.args, :(return))
    return ex
end

function applyeach(f, x::AbstractDict)
    for (k, v) in x
        ret = f(k, v)
        ret isa EarlyReturn && return ret
    end
    return
end



"""
    JSONBase.fields(T)

Overload used by JSONBase during materialization and writing
to override default field names, values, properties. Custom type
authors overload `fields` for their type `T` and provide a NamedTuple
mapping Julia field names of their type to desired JSON field properties.

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

To add support for the "mutable" strategy for a custom type `MyType`, the definition would be:

```julia
JSONBase.mutable(::Type{<:MyType}) = true
```

Note this definition works whether `MyType` has type parameters or not due to being defined
for `MyType` and any subtypes.

For fieldnames of `T` that expect a non-lexically matching JSON object key, [`JSONBase.fields`](@ref)
can be used to map between fieldname and JSON key name.
"""
mutable(_) = false

"""
    JSONBase.kwdef(T)

Overloadable method that indicates whether a type `T` supports the
"keyword arg" strategy for construction via `JSONBase.materialize`.

Specifically, the "keyword arg" strategy requires that a type support:
  * `T(; keyvals...)`: construction by passing a collection of key-value pairs
    as keyword arguments to the type constructor; this kind of constructor is
    defined automatically when the `@kwdef` macro is used to define a type

To add support for the "keyword arg" strategy for a custom type `MyType` the definition would be:

```julia
JSONBase.kwdef(::Type{<:MyType}) = true
```

Note this definition works whether `MyType` has type parameters or not due to being defined
for `MyType` and any subtypes.

For fieldnames of `T` that expect a non-lexically matching JSON object key, [`JSONBase.fields`](@ref)
can be used to map between fieldname and JSON key name.
"""
kwdef(_) = false

"""
    JSONBase.dictlike(T)

Overloadable method that indicates whether a type `T` supports the
"dictlike" strategy for construction via `JSONBase.materialize`, which
doesn't do any field matching like the `mutable`, `kwdef`, or `struct`
strategies, but instead slurps all key-value pairs into `T`
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

Note this definition works whether `MyType` has type parameters or not due to being defined
for `MyType` and any subtypes.
"""
function dictlike end

dictlike(::Type{<:AbstractDict}) = true
dictlike(::Type{<:AbstractVector{<:Pair}}) = true
dictlike(_) = false

# Note: we could expose this as part of the dictlike API
addkeyval!(d::AbstractDict, k, v) = d[k] = v
addkeyval!(d::AbstractVector, k, v) = push!(d, k => v)

_keytype(d) = keytype(d)
_keytype(d::AbstractVector{<:Pair}) = eltype(d).parameters[1]
_valtype(d) = valtype(d)
_valtype(d::AbstractVector{<:Pair}) = eltype(d).parameters[2]

"""
    JSONStyle

Similar to the `IndexStyle` or `BroadcastStyle` traits in Base, the `JSONStyle` trait
allows defining a custom struct subtype like `struct CustomJSONSTyle <: JSONBase.JSONStyle end`
and then passing to `JSONBase.json` or `JSONBase.materialize` where calls to [`JSONBase.lower`](@ref)
and [`JSONBase.lift`](@ref) will receive the custom style as a 1st argument. This allows defining
`lower`/`lift` methods on non-owned types without pirating default method definition or affecting other
possible style overrides. This ultimately allows complete, flexible control over serialization and
deserialization of any type, owned or not.

# Example

```julia
# custom styles must subtype the abstract type `JSONBase.JSONStyle`
struct CustomJSONStyle <: JSONBase.JSONStyle end

struct N
    id::Int
    uuid::UUID
end

# override default UUID serialization behavior (write out as a number instead of a string)
JSONBase.lower(::CustomJSONStyle, x::UUID) = UInt128(x)

# default serialization is unaffected by new style definition
JSONBase.json(UUID(typemax(UInt128)))
# "\"ffffffff-ffff-ffff-ffff-ffffffffffff\""

# must pass custom style to override default behavior
JSONBase.json(UUID(typemax(UInt128)); style=CustomJSONStyle())
# "340282366920938463463374607431768211455" # written as unquoted number instead of default UUID serialization as a string

# override the UUID serialization behavior only for our N struct
JSONBase.lower(::CustomJSONStyle, ::Type{N}, key, val) = key == :uuid ? UInt128(val) : JSONBase.lower(val)

JSONBase.json(N(0, UUID(typemax(UInt128))); style=CustomJSONStyle())
# "{\"id\":0,\"uuid\":340282366920938463463374607431768211455}"

# override the default UUID deserialization behavior (expecting to deserialize from a string)
JSONBase.lift(::CustomJSONStyle, ::Type{UUID}, x) = UUID(UInt128(x))

JSONBase.materialize("340282366920938463463374607431768211455", UUID; style=CustomJSONStyle())
# UUID("ffffffff-ffff-ffff-ffff-ffffffffffff")

# override the default UUID deserialization only for our N struct
JSONBase.lift(::CustomJSONStyle, ::Type{N}, key, val) = key == :uuid ? UUID(UInt128(val)) : JSONBase.lift(N, key, val)

JSONBase.materialize("{\"id\": 0, \"uuid\": 340282366920938463463374607431768211455}", N; style=CustomJSONStyle())
# N(0, UUID("ffffffff-ffff-ffff-ffff-ffffffffffff"))
```
"""
abstract type JSONStyle end
struct DefaultStyle <: JSONStyle end

"""
    JSONBase.lower(x)
    JSONBase.lower(::Type{T}, key, val)
    JSONBase.lower(::Structs.StructStyle, x)
    JSONBase.lower(::Structs.StructStyle, ::Type{T}, key, val)

Allow an object `x` to be "lowered" into a JSON-compatible representation.
The 2nd method allows overloading lower for an object of type `T` for a specific
key-value representing the field name (as a Symbol) and the field value being serialized.
This allows customizing the serialization of a specific field of a type without
needing to clash with other global `lower` methods or lower an entire object
when only specific fields need custom lowering.

The latter 2 methods take a custom [`JSONStyle`](@ref) struct as a 1st argument and allow
over-riding the lowering of non-owned types.

Examples of overloading `lower` for custom types could look like:
    
```julia
struct Unknown end
# custom sentinel value we want to be `null` in JSON
JSONBase.lower(::Type{Unknown}) = nothing

struct Person
    name::String
    birthdate::Date
end

# we want to serialize the birthdate as a string with a non-default date format
# note for non-:birthdate fields, we call `lower(val)` to get the default lowering
JSONBase.lower(::Type{Person}, key, val) = key == :birthdate ? Dates.format(val, dateformat"mm/dd/yyyy") : lower(val)
```
"""
function lower end

lower(x) = x
# allow field-specific lowering for types
lower(::Type{T}, key, val) where {T} = lower(val)

# default style fallbacks
lower(::Structs.StructStyle, x) = lower(x)
lower(::Structs.StructStyle, ::Type{T}, key, val) where {T} = lower(T, key, val)

# some default lowerings for common types
lower(::Missing) = nothing
lower(x::Symbol) = String(x)
lower(x::Union{Enum, AbstractChar, VersionNumber, Cstring, Cwstring, UUID, Dates.TimeType, Type, Logging.LogLevel}) = string(x)
lower(x::Regex) = x.pattern
lower(x::AbstractArray{<:Any,0}) = x[1]
lower(x::AbstractArray{<:Any, N}) where {N} = (view(x, ntuple(_ -> :, N - 1)..., j) for j in axes(x, N))
lower(x::AbstractVector) = x

"""
    JSONBase.lift(T, x)
    JSONBase.lift(::Type{T}, key, val)
    JSONBase.lift(::Structs.StructStyle, T, x)
    JSONBase.lift(::Structs.StructStyle, ::Type{T}, key, val)

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

Note that the type used for JSON objects can be controlled via
passing a custom dict type via the `dicttype` keyword argument to [`JSONBase.materialize`](@ref).

The latter 2 methods take a custom [`JSONStyle`](@ref) struct as a 1st argument and allow
over-riding the lifting of non-owned types.

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
lift(::Type{T}, key, val) where {T} = lift(fieldtype(T, key), val)

# default style fallbacks
lift(::Structs.StructStyle, ::Type{T}, x) where {T} = lift(T, x)
lift(::Structs.StructStyle, ::Type{T}, key, val) where {T} = lift(T, key, val)

# some default lift definitions for common types
lift(::Type{T}, ::Nothing) where {T >: Missing} = T === Any ? nothing : missing
lift(::Type{T}, x::String) where {T <: Union{VersionNumber, UUID, Dates.TimeType, Regex}} = T(x)

# bit of an odd case, but support 0-dimensional array lifting from scalar value
function lift(::Type{A}, x) where {A <: AbstractArray{T, 0}} where {T}
    m = A(undef)
    m[1] = lift(T, x)
    return m
end

function lift(::Type{Char}, x::String)
    if length(x) == 1
        return x[1]
    else
        throw(ArgumentError("invalid `Char` from string value: \"$x\""))
    end
end

"""
    JSONBase.choosetype(T, x) -> S
    JSONBase.choosetype(T, key, FT, val) -> S
    JSONBase.choosetype(::Structs.StructStyle, T, x) -> S
    JSONBase.choosetype(::Structs.StructStyle, T, key, FT, val) -> S

Interface to allow "choosing" the right type `S` for materialization
in cases where it would otherwise be ambiguous or unknown.
The type `T` is the abstact or Union type we want to disambiguate.
`x` is a `JSONBase.LazyValue` or `JSONBase.BinaryValue` where fields
can be accessed using the selection syntax. `S` is the more specific type
to be deserialized based on the "runtime" JSON values.

The 2nd method allows overloading `choosetype` on a parent type `T` for a specific
field where the `key` is the field name (as a Symbol), `FT` is the field type,
and `x` is the `JSONBase.LazyValue` or `JSONBase.BinaryValue` for the field value.
This allows customizing the materialization of a specific field of a type without
needing to clash with other global `choosetype` methods.

The latter 2 methods take a custom [`JSONStyle`](@ref) struct as a 1st argument and allow
over-riding the type choice of non-owned types.

# Examples

Examples of overloading `choosetype` for custom types could look like:

```julia
abstract type Vehicle end

struct Car <: Vehicle
    type::String
    make::String
    model::String
    seatingCapacity::Int
    topSpeed::Float64
end

struct Truck <: Vehicle
    type::String
    make::String
    model::String
    payloadCapacity::Float64
end

# overload choosetype for the Vehicle type to choose between Car and Truck
# based on the `type` field value
JSONBase.choosetype(::Type{Vehicle}, x) = x.type[] == "car" ? Car : Truck

JSONBase.materialize("{\"type\": \"car\",\"make\": \"Mercedes-Benz\",\"model\": \"S500\",\"seatingCapacity\": 5,\"topSpeed\": 250.1}", Vehicle)
# returns Car("car", "Mercedes-Benz", "S500", 5, 250.1)
```
"""
function choosetype end

choosetype(::Type{T}, key, ::Type{FT}, val) where {T, FT} = choosetype(FT, val)

# default style fallbacks
choosetype(::Structs.StructStyle, ::Type{T}, x) where {T} = choosetype(T, x)
choosetype(::Structs.StructStyle, ::Type{T}, key, ::Type{FT}, val) where {T, FT} = choosetype(T, key, FT, val)

"""
    JSONBase.arraylike(x)

Overloadable method that allows a type `T` to be treated as an array
when being serialized to JSON via `JSONBase.json`.
Types overloading `arraylike`, must also overload `JSONBase.applyeach`.
Note that default `applyeach` implementations exist for `AbstractArray`,
and `AbstractSet`.

An example of overloading this method for a custom type `MyType` looks like:

```julia
JSONBase.arraylike(::MyType) = true
```
"""
function arraylike end

arraylike(_) = false
arraylike(::Union{AbstractArray, AbstractSet, Tuple, Base.Generator, Core.SimpleVector}) = true

end # module API