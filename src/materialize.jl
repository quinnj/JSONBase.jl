#TODO: add examples to docs
"""
    JSONBase.materialize(json)
    JSONBase.materialize(json, T)
    JSONBase.parse(json)
    JSONBase.parsefile(filename)

Materialize a JSON input (string, vector, stream, LazyValue, BinaryValue, etc.) into a generic
Julia representation (Dict, Array, etc.) (1st method), or construct an instance of type `T` from JSON input (2nd method).
Specifically, the following default materializations are used for untyped materialization:
  * JSON object => `$DEFAULT_OBJECT_TYPE`
  * JSON array => `Vector{Any}`
  * JSON string => `String`
  * JSON number => `Int64`, `Int128`, `BigInt`, `Float64`, or `BigFloat`
  * JSON true => `true`
  * JSON false => `false`
  * JSON null => `nothing`

When a type `T` is given for materialization, there are 3 construction "strategies" available:
  * `JSONBase.mutable(T)`: an instance is constructed via `T()`, then fields are set via `setproperty!(obj, field, value)`
  * `JSONBase.kwdef(T)`: an instance is constructed via `T(; field=value...)`, i.e. passed as keyword argumnents to the type constructor
  * Default: an instance is constructed by passing `T(val1, val2, ...)` to the type constructor;
    values are matched on JSON object keys to field names; this corresponds to the "default" constructor
    structs have in Julia

For the unique case of nested JSON arrays and prior knowledge of the expected dimensionality,
a target type `T` can be given as an `AbstractArray{T, N}` subtype. In this case, the JSON array data is materialized as an
n-dimensional array, where: the number of JSON array nestings must match the Julia array dimensionality (`N`),
nested JSON arrays at matching depths are assumed to have equal lengths, and the length of
the innermost JSON array is the 1st dimension length and so on. For example, the JSON array `[[[1.0,2.0]]]`
would be materialized as a 3-dimensional array of `Float64` with sizes `(2, 1, 1)`, when called
like `JSONBase.materialize("[[[1.0,2.0]]]", Array{Float64, 3})`. Note that n-dimensional Julia
arrays are written to json as nested JSON arrays by default, to enable lossless materialization,
though the dimensionality must still be provided to the call to `materialize`.

For materializing JSON into an existing object, see [`materialize!`](@ref).

Currently supported keyword arguments include:
  * `float64`: for parsing all json numbers as Float64 instead of inferring int vs. float;
    also allows parsing `NaN`, `Inf`, and `-Inf` since they are otherwise invalid JSON
  * `jsonlines`: treat the `json` input as an implicit JSON array,
    delimited by newlines, each element being parsed from each row/line in the input
  * `dicttype`: a custom `AbstractDict` type to use instead of `$DEFAULT_OBJECT_TYPE` as the default
    type for JSON object materialization
  * `style`: a custom [`JSONStyle`](@ref) subtype instance to be used in calls to `lift`. This allows over-riding
    default lift behavior for non-owned types.
"""
function materialize end

"""
    JSONBase.materialize!(json, x)

Similar to [`materialize`](@ref), but materializes into an existing object `x`,
which supports the "mutable" strategy for construction; that is,
JSON object keys are matched to field names and `setproperty!(x, field, value)` is called.
`materialize!` supports the same keyword arguments as [`materialize`](@ref).
"""
function materialize! end

materialize(io::Union{IO, Base.AbstractCmd}, ::Type{T}=Any; kw...) where {T} = materialize(Base.read(io), T; kw...)
materialize!(io::Union{IO, Base.AbstractCmd}, x; kw...) = materialize!(Base.read(io), x; kw...)
materialize(io::IOStream, ::Type{T}=Any; kw...) where {T} = materialize(Mmap.mmap(io), T; kw...)
materialize!(io::IOStream, x; kw...) = materialize!(Mmap.mmap(io), x; kw...)

materialize(buf::Union{AbstractVector{UInt8}, AbstractString}, ::Type{T}=Any; dicttype::Type{O}=DEFAULT_OBJECT_TYPE, style::AbstractJSONStyle=JSONReadStyle{dicttype}(), kw...) where {T, O} =
    materialize(lazy(buf; kw...), T; style)
materialize!(buf::Union{AbstractVector{UInt8}, AbstractString}, x; dicttype::Type{O}=DEFAULT_OBJECT_TYPE, style::AbstractJSONStyle=JSONReadStyle{dicttype}(), kw...) where {O} =
    materialize!(lazy(buf; kw...), x, style)

materialize!(x::Values, ::Type{T}, style::AbstractJSONStyle) where {T} = StructUtils.make!(style, T, x)
materialize!(x::Values, y::T, style::AbstractJSONStyle) where {T} = StructUtils.make!(style, y, x)

abstract type AbstractJSONReadStyle <: AbstractJSONStyle end
struct JSONReadStyle{ObjectType} <: AbstractJSONReadStyle end

objecttype(::JSONReadStyle{OT}) where {OT} = OT

StructUtils.arraylike(::AbstractJSONReadStyle, ::Type{<:Tuple}) = false

@inline function StructUtils.choosetype(f::F, style::AbstractJSONStyle, ::Type{Any}, x::Values, tags) where {F}
    # generic materialization, choose appropriate default type
    type = gettype(x)
    if type == JSONTypes.OBJECT
        return f(style, objecttype(style), x, tags)
    elseif type == JSONTypes.ARRAY
        return f(style, Vector{Any}, x, tags)
    elseif type == JSONTypes.STRING
        return f(style, String, x, tags)
    elseif type == JSONTypes.NUMBER
        return f(style, Number, x, tags)
    elseif type == JSONTypes.INT
        return f(style, Integer, x, tags)
    elseif type == JSONTypes.FLOAT
        return f(style, AbstractFloat, x, tags)
    elseif type == JSONTypes.TRUE || type == JSONTypes.FALSE
        return f(style, Bool, x, tags)
    elseif type == JSONTypes.NULL
        return f(style, Nothing, x, tags)
    else
        throw(ArgumentError("cannot choose type for JSON type $type"))
    end
end

@inline function materialize(x::LazyValue, ::Type{T}=Any; dicttype::Type{O}=DEFAULT_OBJECT_TYPE, style::AbstractJSONStyle=JSONReadStyle{dicttype}()) where {T, O}
    vc = StructUtils.ValueClosure{T}()
    pos = StructUtils.make(vc, style, T, x)
    getisroot(x) && checkendpos(x, T, pos)
    return vc.x
end

# for LazyValue, if x started at the beginning of the JSON input,
# then we want to ensure that the entire input was consumed
# and error if there are any trailing invalid JSON characters
@inline function checkendpos(x::LazyValue, ::Type{T}, pos) where {T}
    buf = getbuf(x)
    len = getlength(buf)
    if pos <= len
        b = getbyte(buf, pos)
        while b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')
            pos += 1
            pos > len && break
            b = getbyte(buf, pos)
        end
    end
    if (pos - 1) != len
        invalid(InvalidChar, buf, pos, T)
    end
    return nothing
end

function materialize(x::BinaryValue, ::Type{T}=Any; dicttype::Type{O}=DEFAULT_OBJECT_TYPE, style::AbstractJSONStyle=JSONReadStyle{dicttype}()) where {T, O}
    return StructUtils.make(style, T, x)
end

mutable struct LiftClosure{T, JS, TG, F}
    style::JS
    tags::TG
    f::F
    LiftClosure{T}(style::JS, tags::TG, f::F) where {T, JS, TG, F} = new{T, JS, TG, F}(style, tags, f)
end

@inline (f::LiftClosure{T, JS, TG, F})(x) where {T, JS, TG, F} = StructUtils.lift(f.f, f.style, T, x, f.tags)
@inline (f::LiftClosure{T, JS, F})(x::PtrString) where {T, JS, F} = StructUtils.lift(f.f, f.style, T, tostring(T, x), f.tags)

@inline StructUtils.lift(f::F, style::AbstractJSONStyle, ::Type{T}, x::PtrString, tags) where {F, T} = StructUtils.lift(f, style, T, tostring(T, x), tags)

@inline function StructUtils.lift(f::F, style::AbstractJSONStyle, ::Type{T}, x::Values, tags::TG) where {F, T, TG}
    y = LiftClosure{T}(style, tags, f)
    type = gettype(x)
    if type == JSONTypes.STRING
        return _applystring(y, x)
    elseif x isa LazyValue && type == JSONTypes.NUMBER
        return _applynumber(y, x)
    elseif x isa BinaryValue && type == JSONTypes.INT # only BinaryValue
        return applyint(y, x)
    elseif x isa BinaryValue && type == JSONTypes.FLOAT # only BinaryValue
        return applyfloat(y, x)
    elseif type == JSONTypes.NULL
        y(nothing)
        return getpos(x) + (x isa BinaryValue ? 1 : 4)
    elseif type == JSONTypes.TRUE
        y(true)
        return getpos(x) + (x isa BinaryValue ? 1 : 4)
    elseif type == JSONTypes.FALSE
        y(false)
        return getpos(x) + (x isa BinaryValue ? 1 : 5)
    elseif Base.issingletontype(T)
        y(nothing) # calls default lift which calls T() for singletons
        if type == JSONTypes.ARRAY
            return applyarray(pass, x)
        elseif type == JSONTypes.OBJECT
            return applyobject(pass, x)
        else
            throw(ArgumentError("cannot lift $x to $T"))
        end
    else
        throw(ArgumentError("cannot lift $x to $T"))
    end
end
