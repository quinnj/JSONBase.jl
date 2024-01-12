#TODO: add examples to docs
"""
    JSONBase.materialize(json)
    JSONBase.materialize(json, T)
    JSONBase.parse(json)
    JSONBase.parsefile(filename)

Materialize a JSON input (string, vector, stream, LazyValue, BinaryValue, etc.) into a generic
Julia representation (Dict, Array, etc.) (1st method), or construct an instance of type `T` from JSON input (2nd method).
Specifically, the following default materializations are used for untyped materialization:
  * JSON object => `Dict{String, Any}`
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
  * `dicttype`: a custom `AbstractDict` type to use instead of `Dict{String, Any}` as the default
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

materialize(buf::Union{AbstractVector{UInt8}, AbstractString}, ::Type{T}=Any; style::JSONStyle=DefaultStyle(), dicttype::Type{O}=Dict{String, Any}, kw...) where {T, O} =
    materialize(lazy(buf; kw...), T; style, dicttype)
materialize!(buf::Union{AbstractVector{UInt8}, AbstractString}, x; style::JSONStyle=DefaultStyle(), dicttype::Type{O}=Dict{String, Any}, kw...) where {O} =
    materialize!(lazy(buf; kw...), x, style, dicttype)

mutable struct ConvertClosure{JS, T}
    style::JS
    x::T
    ConvertClosure{T}(style::JS) where {JS <: JSONStyle, T} = new{JS, T}(style)
end

@inline (f::ConvertClosure{JS, T})(x) where {JS, T} = setfield!(f, :x, lift(f.style, T, x))

# in `materialize`, given an initial LazyValue/BinaryValue
# and a possible Union or abstract type `T`, we want to
# concretize to a more specific type based on runtime values in `x`
# `choosetype` can be overloaded for custom scenarios, but by default
# we can at least cover the case where `T` is a Union
# and `x` is an object, array, or string and strip away any
# `Nothing` or `Missing` types (very common Union types)
function API.choosetype(::Type{T}, x) where {T}
    if T isa Union
        type = gettype(x)
        if type == JSONTypes.OBJECT ||
            type == JSONTypes.ARRAY ||
            type == JSONTypes.STRING
            return non_nothing_missing_type(T)
        end
    end
    return T
end

@inline function materialize(x::LazyValue, ::Type{T}=Any; style::JSONStyle=DefaultStyle(), dicttype::Type{O}=Dict{String, Any}) where {T, O}
    y = ConvertClosure{T}(style)
    pos = materialize(y, x, choosetype(style, T, x), style, O)
    checkendpos(x, pos, T)
    return y.x
end

# for LazyValue, if x started at the beginning of the JSON input,
# then we want to ensure that the entire input was consumed
# and error if there are any trailing invalid JSON characters
@inline checkendpos(x::LazyValue, pos, ::Type{T}) where {T} = getisroot(x) && _checkendpos(x, pos, T)

function _checkendpos(x::LazyValue, pos, ::Type{T}) where {T}
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

function materialize(x::BinaryValue, ::Type{T}=Any; style::JSONStyle=DefaultStyle(), dicttype::Type{O}=Dict{String, Any}) where {T, O}
    y = ConvertClosure{T}(style)
    materialize(y, x, choosetype(style, T, x), style, O)
    return y.x
end

struct GenericObjectClosure{JS, O, T}
    style::JS
    keyvals::O
end

struct GenericObjectValFunc{JS, O, K}
    style::JS
    keyvals::O
    key::K
end

@inline function (f::GenericObjectValFunc{JS, O, K})(x) where {JS, O, K}
    KT = _keytype(f.keyvals)
    VT = _valtype(f.keyvals)
    return addkeyval!(f.keyvals, lift(f.style, KT, tostring(KT, f.key)), lift(f.style, VT, x))
end

@inline function (f::GenericObjectClosure{JS, O, T})(key, val) where {JS, O, T}
    pos = _materialize(GenericObjectValFunc{JS, O, typeof(key)}(f.style, f.keyvals, key), val, choosetype(f.style, _valtype(f.keyvals), val), f.style, T)
    return UpdatedState(pos)
end

struct GenericArrayClosure{JS, A, T}
    style::JS
    arr::A
end

struct GenericArrayValFunc{JS, A}
    style::JS
    arr::A
end

@inline (f::GenericArrayValFunc{JS, A})(x) where {JS, A} =
    push!(f.arr, lift(f.style, eltype(f.arr), x))

@inline function (f::GenericArrayClosure{JS, A, T})(i, val) where {JS, A, T}
    pos = _materialize(GenericArrayValFunc{JS, A}(f.style, f.arr), val, choosetype(f.style, eltype(f.arr), val), f.style, T)
    return UpdatedState(pos)
end

# recursively build up multidimensional array dimensions
# "[[1.0],[2.0]]" => (1, 2)
# "[[1.0,2.0]]" => (2, 1)
# "[[[1.0]],[[2.0]]]" => (1, 1, 2)
# "[[[1.0],[2.0]]]" => (1, 2, 1)
# "[[[1.0,2.0]]]" => (2, 1, 1)
# length of innermost array is 1st dim
function discover_dims(x)
    @assert gettype(x) == JSONTypes.ARRAY
    len = API.applylength(x)
    ret = applyarray(x) do i, v
        if gettype(v) == JSONTypes.ARRAY
            return EarlyReturn(discover_dims(v))
        else
            return EarlyReturn(())
        end
    end
    return (ret.value..., len)
end

struct MultiDimClosure{JS, A, T}
    style::JS
    arr::A
    dims::Vector{Int}
    cur_dim::Base.RefValue{Int}
end

@inline function (f::MultiDimClosure{JS, A, T})(i, val) where {JS, A, T}
    f.dims[f.cur_dim[]] = i
    if gettype(val) == JSONTypes.ARRAY
        f.cur_dim[] -= 1
        pos = applyarray(f, val)
        f.cur_dim[] += 1
    else
        pos = _materialize(MultiDimValFunc(f.style, f.arr, f.dims), val, choosetype(f.style, eltype(f.arr), val), f.style, T)
    end
    return UpdatedState(pos)
end

struct MultiDimValFunc{JS, A}
    style::JS
    arr::A
    dims::Vector{Int}
end

@inline (f::MultiDimValFunc{JS, A})(x) where {JS, A} = setindex!(f.arr, lift(f.style, eltype(f.arr), x), f.dims...)

initarray(::Type{A}) where {A <: AbstractSet} = A()
initarray(::Type{A}) where {A <: AbstractVector} = A(undef, 0)

function _materialize(valfunc::F, x::Values, ::Type{T}=Any, style::JSONStyle=DefaultStyle(), dicttype::Type{O}=Dict{String, Any}) where {F, T, O}
    return materialize(valfunc, x, T, style, O)
end

# Note: when calling this method manually, we don't do the checkendpos check
# which means if the input JSON has invalid trailing characters, no error will be thrown here
# we also don't do the lift of whatever is materialized to T (we're assuming that is done in valfunc)
# choosetype should also have been called on T to ensure it's not a Union/abstract type
@inline function materialize(valfunc::F, x::Values, ::Type{T}=Any, style::JSONStyle=DefaultStyle(), dicttype::Type{O}=Dict{String, Any}) where {F, T, O}
    JS = typeof(style)
    type = gettype(x)
    if type == JSONTypes.OBJECT
        # because of the default `choosetype` fallback
        # we shouldn't get a Union for T and can assume
        # T is the final object type
        if T === Any
            d = O()
            pos = applyobject(GenericObjectClosure{JS, O, O}(style, d), x)
            valfunc(d)
            return pos
        elseif dictlike(T)
            d = T()
            pos = applyobject(GenericObjectClosure{JS, T, O}(style, d), x)
            valfunc(d)
            return pos
        elseif mutable(T)
            y = T()
            pos = materialize!(x, y, style, O)
            valfunc(y)
            return pos
        elseif kwdef(T)
            kws = Pair{Symbol, Any}[]
            c = KwClosure{JS, T, O}(style, kws)
            pos = applyobject(c, x)
            y = T(; kws...)
            valfunc(y)
            return pos
        else
            # struct fallback
            N = fieldcount(T)
            vec = Vector{Any}(undef, N)
            sc = StructClosure{JS, T, O}(style, vec)
            pos = applyobject(sc, x)
            constructor = T <: NamedTuple ? ((x...) -> T(tuple(x...))) : T
            construct(T, constructor, vec, valfunc)
            return pos
        end
    elseif type == JSONTypes.ARRAY
        if T === Any
            A = Vector{Any}
            a = initarray(A)
            pos = applyarray(GenericArrayClosure{JS, A, O}(style, a), x)
            valfunc(a)
            return pos
        elseif T <: AbstractArray && ndims(T) > 1
            # special-case multidimensional arrays
            # first we discover the final dimensions
            dims = discover_dims(x)
            m = T(undef, dims)
            n = ndims(m)
            # now we do the actual parsing to fill in our n-dimensional array
            pos = applyarray(MultiDimClosure{JS, typeof(m), T}(style, m, ones(n), Ref(n)), x)
            valfunc(m)
            return pos
        elseif T <: AbstractArray || T <: AbstractSet
            a = initarray(T)
            pos = applyarray(GenericArrayClosure{JS, T, O}(style, a), x)
            valfunc(a)
            return pos
        else
            # edge case where we support materializing a struct from a json array
            # the struct fields are assumed to be in the same order as the json array elements
            # and the default constructor is used with positional arguments from the json array
            if mutable(T)
                y = T()
                pos = materialize!(x, y, style, O)
                valfunc(y)
                return pos
            elseif kwdef(T)
                kws = Pair{Symbol, Any}[]
                c = KwIndexClosure{JS, T, O}(style, kws)
                pos = applyarray(c, x)
                y = T(; kws...)
                valfunc(y)
                return pos
            else
                A = Vector{Any}
                a = initarray(A)
                pos = applyarray(GenericArrayClosure{JS, A, O}(style, a), x)
                constructor = T <: Tuple ? tuple : T <: NamedTuple ? ((x...) -> T(tuple(x...))) : T
                valfunc(constructor(a...))
                return pos
            end
        end
    elseif type == JSONTypes.STRING
        str, pos = applystring(nothing, x)
        valfunc(tostring(T, str))
        return pos
    elseif x isa LazyValue && type == JSONTypes.NUMBER # only LazyValue
        return applynumber(valfunc, x)
    elseif x isa BinaryValue && type == JSONTypes.INT # only BinaryValue
        return applyint(valfunc, x)
    elseif x isa BinaryValue && type == JSONTypes.FLOAT # only BinaryValue
        return applyfloat(valfunc, x)
    elseif type == JSONTypes.NULL
        valfunc(nothing)
        return getpos(x) + (x isa BinaryValue ? 1 : 4)
    elseif type == JSONTypes.TRUE
        valfunc(true)
        return getpos(x) + (x isa BinaryValue ? 1 : 4)
    else
        @assert type == JSONTypes.FALSE "type = $type"
        valfunc(false)
        return getpos(x) + (x isa BinaryValue ? 1 : 5)
    end
end

struct ValFuncClosure{F}
    i::Int
    fname::Symbol
    valfunc::F
end

@inline function (f::ValFuncClosure)(val)
    f.valfunc(f.i, f.fname, val)
    return
end

# NOTE: care needs to be taken in applyfield to not inline too much,
# since we're essentially duplicating the inner quote block for each
# field of struct T, which may have a lot of fields
# applyfield is used by each struct materialization strategy (mutable, kwdef, struct)
# it takes a `key` and `val` parsed from json, then compares `key`
# with field names in `T` and when a match is found, determines how
# to materialize `val` (via recursively calling materialize)
# passing `valfunc` along to be applied to the final materialized value
@generated function applyfield(::Type{T}, style::JS, dicttype::Type{O}, key, val, valfunc::F) where {T, JS <: JSONStyle, O, F}
    N = fieldcount(T)
    ex = quote
        Base.@_inline_meta
        fds = fields($T)
    end
    for i = 1:N
        fname = fieldname(T, i)
        ftype = fieldtype(T, i)
        # performance note: this is the main reason this is a generated function and not
        # a macro unrolling fields: we want the field name as a String w/o paying a runtime cost
        # if the runtime can do that statically at some point, we could un-generate this function
        str = String(fname)
        push!(ex.args, quote
            field = get(fds, $(Meta.quot(fname)), nothing)
            str = field !== nothing && haskey(field, :jsonkey) ? field.jsonkey : $str
            if Selectors.eq(key, str)
                c = ValFuncClosure($i, $(Meta.quot(fname)), valfunc)
                typ = choosetype(style, $T, key, $ftype, val)
                pos = _materialize(c, val, typ, style, $O)
                return UpdatedState(pos)
            end
        end)
    end
    # if no fields matched this json key, then we return nothing
    # here to signal that the value should be skipped
    push!(ex.args, :(return))
    # str = sprint(show, ex)
    # println(str)
    return ex
end

@inline function getval(::Type{T}, vec, nm, i) where {T}
    FT = fieldtype(T, i)
    @inbounds begin
        isassigned(vec, i) && return vec[i]::FT
    end
    # TODO: we could maybe allow an `argtype` option to
    # fields that would be less restrictive than FT here
    # one use-case is that I have a custom constructor
    # that takes `nothing` as a positional arg, but
    # uses a more type-stable sentinel value for the field if `nothing`
    fds = fields(T)
    field = get(fds, nm, nothing)
    if field !== nothing && haskey(field, :default)
        return field.default::FT
    else
        return nothing::FT
    end
end

@generated function construct(::Type{T}, constructor, vec, valfunc::F) where {T, F}
    N = fieldcount(T)
    ex = quote
        valfunc(constructor())
        return
    end
    cons = ex.args[2].args[2]
    for i = 1:N
        push!(cons.args, :(getval(T, vec, $(Meta.quot(fieldname(T, i))), $i)))
    end
    return ex
end

struct StructClosure{JS, T, O}
    style::JS
    vec::Vector{Any}
end

struct ApplyStruct{JS, T}
    style::JS
    vec::Vector{Any}
end

@inline (f::ApplyStruct{JS, T})(i, k, v) where {JS, T} = setindex!(f.vec, lift(f.style, T, k, v), i)
@inline (f::StructClosure{JS, T, O})(key, val) where {JS, T, O} = applyfield(T, f.style, O, key, val, ApplyStruct{JS, T}(f.style, f.vec))

struct KwClosure{JS, T, O}
    style::JS
    kws::Vector{Pair{Symbol, Any}}
end

struct ApplyKw{JS, T}
    style::JS
    kws::Vector{Pair{Symbol, Any}}
end

@inline (f::ApplyKw{JS, T})(i, k, v) where {JS, T} = push!(f.kws, k => lift(f.style, T, k, v))
@inline (f::KwClosure{JS, T, O})(key, val) where {JS, T, O} = applyfield(T, f.style, O, key, val, ApplyKw{JS, T}(f.style, f.kws))

struct KwIndexClosure{JS, T, O}
    style::JS
    kws::Vector{Pair{Symbol, Any}}
end

@inline (f::KwIndexClosure{JS, T, O})(i, val) where {JS, T, O} = applyfield(T, f.style, O, fieldname(T, i), val, ApplyKw{JS, T}(f.style, f.kws))

struct MutableClosure{JS, T, O}
    style::JS
    x::T
end

struct ApplyMutable{JS, T}
    style::JS
    x::T
end

@inline (f::ApplyMutable{JS, T})(i, k, v) where {JS, T} = setproperty!(f.x, k, lift(f.style, T, k, v))
@inline (f::MutableClosure{JS, T, O})(key, val) where {JS, T, O} = applyfield(T, f.style, O, key, val, ApplyMutable(f.style, f.x))

# when applying json array elements to a mutable by index
struct MutableIndexClosure{JS, T, O}
    style::JS
    x::T
end

@inline (f::MutableIndexClosure{JS, T, O})(i, val) where {JS, T, O} = applyfield(T, f.style, O, fieldname(T, i), val, ApplyMutable(f.style, f.x))

function materialize!(x::Values, ::Type{T}, style::JSONStyle=DefaultStyle(), dicttype::Type{O}=Dict{String, Any}) where {T, O}
    y = T()
    materialize!(x, y, style, O)
    return y
end

function materialize!(x::Values, y::T, style::JSONStyle=DefaultStyle(), dicttype::Type{O}=Dict{String, Any}) where {T, O}
    JS = typeof(style)
    type = gettype(x)
    if type == JSONTypes.OBJECT
        if dictlike(T)
            goc = GenericObjectClosure{JS, T, O}(style, y)
            return applyobject(goc, x)
        else
            mc = MutableClosure{JS, T, O}(style, y)
            return applyobject(mc, x)
        end
    elseif type == JSONTypes.ARRAY
        # the JSON source is an array, so we're going to
        # apply each element to `y` in order, assuming each array element is the right field
        # for y in corresponding field index order
        return applyarray(MutableIndexClosure{JS, T, O}(style, y), x)
    else
        throw(ArgumentError("cannot materialize! from a non-object/array JSON instance"))
    end
end
