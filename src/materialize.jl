#TODO: add examples to docs
#TODO: mention how Matrix work when materializing
"""
    JSONBase.materialize(json)
    JSONBase.materialize(json, T)

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
  * Default: an instance is constructed by passing `T(val1, val2, ...)` to the type constructor
    values are matched on JSON object keys to field names; this corresponds to the "default" constructor
    structs have in Julia

Currently supported keyword arguments include:
  * `float64`: for parsing all json numbers as Float64 instead of inferring int vs. float;
    also allows parsing `NaN`, `Inf`, and `-Inf` since they are otherwise invalid JSON
  * `jsonlines`: treat the `json` input as an implicit JSON array,
    delimited by newlines, each element being parsed from each row/line in the input
  * `objectype`: a custom `AbstractDict` type to use instead of `Dict{String, Any}` as the default
    type for JSON object materialization
"""
function materialize end

"""
    JSONBase.materialize!(json, x)

Similar to [`materialize`](@ref), but materializes into an existing object `x`,
which supports the "mutable" strategy for construction; that is,
JSON object keys are matched to field names and `setproperty!(x, field, value)` is called.
"""
function materialize! end

materialize(io::Union{IO, Base.AbstractCmd}, ::Type{T}=Any; kw...) where {T} = materialize(Base.read(io), T; kw...)
materialize!(io::Union{IO, Base.AbstractCmd}, x; kw...) = materialize!(Base.read(io), x; kw...)
materialize(io::IOStream, ::Type{T}=Any; kw...) where {T} = materialize(Mmap.mmap(io), T; kw...)
materialize!(io::IOStream, x; kw...) = materialize!(Mmap.mmap(io), x; kw...)

materialize(buf::Union{AbstractVector{UInt8}, AbstractString}, ::Type{T}=Any; objecttype::Type{O}=Dict{String, Any}, kw...) where {T, O} =
    materialize(lazy(buf; kw...), T; objecttype)
materialize!(buf::Union{AbstractVector{UInt8}, AbstractString}, x; objecttype::Type{O}=Dict{String, Any}, kw...) where {O} =
    materialize!(lazy(buf; kw...), x, objecttype)

mutable struct ConvertClosure{T}
    x::T
    ConvertClosure{T}() where {T} = new{T}()
end

@inline (f::ConvertClosure{T})(x) where {T} = setfield!(f, :x, lift(T, x))

@inline function materialize(x::LazyValue, ::Type{T}=Any; objecttype::Type{O}=Dict{String, Any}) where {T, O}
    y = ConvertClosure{T}()
    pos = materialize(y, x, T, O)
    checkendpos(x, pos, T)
    return y.x
end

# for LazyValue, if x started at the beginning of the JSON input,
# then we want to ensure that the entire input was consumed
# and error if there are any trailing invalid JSON characters
@inline checkendpos(x::LazyValue, pos, ::Type{T}) where {T} = getpos(x) == 1 && _checkendpos(x, pos, T)

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

function materialize(x::BinaryValue, ::Type{T}=Any; objecttype::Type{O}=Dict{String, Any}) where {T, O}
    y = ConvertClosure{T}()
    materialize(y, x, T, O)
    return y.x
end

struct GenericObjectClosure{O, T}
    keyvals::O
end

struct GenericObjectValFunc{O, K}
    keyvals::O
    key::K
end

@inline function (f::GenericObjectValFunc{O, K})(x) where {O, K}
    KT = _keytype(f.keyvals)
    VT = _valtype(f.keyvals)
    return addkeyval!(f.keyvals, lift(KT, tostring(KT, f.key)), lift(VT, x))
end

@inline function (f::GenericObjectClosure{O, T})(key, val) where {O, T}
    pos = _materialize(GenericObjectValFunc{O, typeof(key)}(f.keyvals, key), val, _valtype(f.keyvals), T)
    return Continue(pos)
end

struct GenericArrayClosure{A, T}
    arr::A
end

struct GenericArrayValFunc{A}
    arr::A
end

@inline (f::GenericArrayValFunc{A})(x) where {A} =
    push!(f.arr, lift(eltype(f.arr), x))

@inline function (f::GenericArrayClosure{A, T})(i, val) where {A, T}
    pos = _materialize(GenericArrayValFunc{A}(f.arr), val, eltype(f.arr), T)
    return Continue(pos)
end

struct ArrayLengthClosure
    len::Ptr{Int}
end

@inline function (f::ArrayLengthClosure)(i, val)
    unsafe_store!(f.len, i)
    return Continue()
end

struct MatrixClosure{A, T}
    mat::A
    col::Int
end

struct MatrixValFunc{A}
    mat::A
    col::Int
    row::Int
end

@inline (f::MatrixValFunc{A})(x) where {A} = setindex!(f.mat, lift(eltype(f.mat), x), f.row, f.col)

@inline function (f::MatrixClosure{A, T})(i, val) where {A, T}
    # i is our row index
    pos = _materialize(MatrixValFunc(f.mat, f.col, i), val, eltype(f.mat), T)
    return Continue(pos)
end

initarray(::Type{A}) where {A <: AbstractSet} = A()
initarray(::Type{A}) where {A <: AbstractVector} = A(undef, 0)

function _materialize(valfunc::F, x::Union{LazyValue, BinaryValue}, ::Type{T}=Any, objecttype::Type{O}=Dict{String, Any}) where {F, T, O}
    return materialize(valfunc, x, T, O)
end

# Note: when calling this method manually, we don't do the checkendpos check
# which means if the input JSON has invalid trailing characters, no error will be thrown
# we also don't do the lift of whatever is materialized to T (we're assuming that is done in valfunc)
@inline function materialize(valfunc::F, x::Union{LazyValue, BinaryValue}, ::Type{T}=Any, objecttype::Type{O}=Dict{String, Any}) where {F, T, O}
    type = gettype(x)
    if type == JSONTypes.OBJECT
        #TODO: if T is a Union, then the below only really works
        # for Nothing/Missing (obviously)
        # to support a field like ::Union{StructA, StructB}
        # we could define an interface function like
        # JSONBase.choosetype(::Union, x) -> T
        # so users could overload for the union type w/ their type
        # and, given the LazyValue/BinaryValue, choose which member
        # of the union should be materialized (by returning it from choosetype)
        S = non_nothing_missing_type(T)
        if S === Any
            d = O()
            pos = applyobject(GenericObjectClosure{O, O}(d), x).pos
            valfunc(d)
            return pos
        elseif dictlike(S)
            d = S()
            pos = applyobject(GenericObjectClosure{S, O}(d), x).pos
            valfunc(d)
            return pos
        elseif mutable(S)
                y = S()
                pos = materialize!(x, y, O)
                valfunc(y)
                return pos
        elseif kwdef(S)
            kws = Pair{Symbol, Any}[]
            c = KwClosure{S, O}(kws)
            pos = applyobject(c, x).pos
            y = S(; kws...)
            valfunc(y)
            return pos
        else
            # struct fallback
            N = fieldcount(S)
            vec = Vector{Any}(undef, N)
            sc = StructClosure{S, O}(vec)
            pos = applyobject(sc, x).pos
            constructor = S <: NamedTuple ? ((x...) -> S(tuple(x...))) : S
            construct(S, constructor, vec, valfunc)
            return pos
        end
    elseif type == JSONTypes.ARRAY
        if T === Any
            A = Vector{Any}
            a = initarray(A)
            pos = applyarray(GenericArrayClosure{A, O}(a), x).pos
            valfunc(a)
            return pos
        elseif T <: Matrix
            #TODO: factor this out into a separate method
            # special-case Matrix
            # must be an array of arrays, where each array element is the same length
            # we need to peek ahead to figure out the size
            sz = applyarray(x) do i, v
                # v is the 1st column of our matrix
                # but we really just want to know the length
                gettype(v) == JSONTypes.ARRAY || throw(ArgumentError("expected array of arrays for materializing"))
                ref = Ref(0)
                alc = ArrayLengthClosure(Base.unsafe_convert(Ptr{Int}, ref))
                GC.@preserve ref applyarray(alc, v)
                # by returning the len here, we're short-circuiting the initial
                # applyarray call
                return unsafe_load(alc.len)
            end
            m = T(undef, (sz, sz))
            # now we do the actual parsing to fill in our matrix
            cont = applyarray(x) do i, v
                # i is the column index of our matrix
                # v is the 1st column of our matrix
                mc = MatrixClosure{T, O}(m, i)
                return applyarray(mc, v)
            end
            valfunc(m)
            return cont.pos
        else
            a = initarray(T)
            pos = applyarray(GenericArrayClosure{T, O}(a), x).pos
            valfunc(a)
            return pos
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
@generated function applyfield(::Type{T}, objecttype::Type{O}, key, val, valfunc::F) where {T, O, F}
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
        str = String(fname)
        push!(ex.args, quote
            field = get(fds, $(Meta.quot(fname)), nothing)
            str = field !== nothing && haskey(field, :jsonkey) ? field.jsonkey : $str
            if Selectors.eq(key, str)
                c = ValFuncClosure($i, $(Meta.quot(fname)), valfunc)
                pos = _materialize(c, val, $ftype, $O)
                return Continue(pos)
            end
        end)
    end
    # if no fields matched this json key, then we return Continue()
    # here to signal that the value should be skipped
    push!(ex.args, :(return Continue()))
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

struct StructClosure{T, O}
    vec::Vector{Any}
end

struct ApplyStruct{T}
    vec::Vector{Any}
end

@inline (f::ApplyStruct{T})(i, k, v) where {T} = setindex!(f.vec, lift(T, k, v), i)
@inline (f::StructClosure{T, O})(key, val) where {T, O} = applyfield(T, O, key, val, ApplyStruct{T}(f.vec))

struct KwClosure{T, O}
    kws::Vector{Pair{Symbol, Any}}
end

struct ApplyKw{T}
    kws::Vector{Pair{Symbol, Any}}
end

@inline (f::ApplyKw{T})(i, k, v) where {T} = push!(f.kws, k => lift(T, k, v))
@inline (f::KwClosure{T, O})(key, val) where {T, O} = applyfield(T, O, key, val, ApplyKw{T}(f.kws))

struct MutableClosure{T, O}
    x::T
end

struct ApplyMutable{T}
    x::T
end

@inline (f::ApplyMutable{T})(i, k, v) where {T} = setproperty!(f.x, k, lift(T, k, v))
@inline (f::MutableClosure{T, O})(key, val) where {T, O} = applyfield(T, O, key, val, ApplyMutable(f.x))

function materialize!(x::Union{LazyValue, BinaryValue}, ::Type{T}, objecttype::Type{O}=Dict{String, Any}) where {T, O}
    y = T()
    materialize!(x, y, O)
    return y
end

function materialize!(x::Union{LazyValue, BinaryValue}, y::T, objecttype::Type{O}=Dict{String, Any}) where {T, O}
    if dictlike(T)
        goc = GenericObjectClosure{T, O}(y)
        return applyobject(goc, x).pos
    else
        mc = MutableClosure{T, O}(y)
        return applyobject(mc, x).pos
    end
end
