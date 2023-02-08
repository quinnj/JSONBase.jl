tostruct(io::Union{IO, Base.AbstractCmd}, T; kw...) = tostruct(Base.read(io), T; kw...)
tostruct(buf::Union{AbstractVector{UInt8}, AbstractString}, T; kw...) = tostruct(tolazy(buf; kw...), T)

@inline function applyfield(::Type{T}, key, val, valfunc) where {T}
    N = fieldcount(T)
    Base.@nexprs 32 i -> begin
        if i <= N
            # TODO: allow serialization name mapping
            s_i = fieldname(T, i)
            k_i = String(s_i)
            if Selectors.eq(k_i, key)
                pos = _togeneric(val, x -> valfunc(i, s_i, x))
                return API.Continue(pos)
            end
        end
    end
    if N > 32
        for i = 33:N
            s = fieldname(T, i)
            k = String(s)
            if Selectors.eq(k, key)
                pos = _togeneric(val, x -> valfunc(i, s, x))
                return API.Continue(pos)
            end
        end
    end
    return API.Continue(0)
end

struct ToStructClosure{T}
    vec::Vector{Any}
end

@inline (f::ToStructClosure{T})(key, val) where {T} = applyfield(T, key, val, (i, k, v) -> f.vec[i] = v)

defaults(_) = (;)

function tostruct(x::Union{LazyValue, BJSONValue}, ::Type{T}) where {T}
    N = fieldcount(T)
    N == 0 && return T()
    vec = Vector{Any}(undef, N)
    c = ToStructClosure{T}(vec)
    pos = parseobject(x, c)
    constructor = T <: Tuple ? tuple : T <: NamedTuple ? ((x...) -> T(tuple(x...))) : T
    defs = defaults(T)
    Base.@nexprs 32 i -> begin
        if isassigned(vec, i)
            x_i = vec[i]::fieldtype(T, i) # TODO: is fieldtype assert to restrictive here?
        elseif !isempty(defs)
            # TODO: should use serialization name instead of fieldname here
            x_i = get(defs, fieldname(T, i), nothing)
        else
            x_i = nothing
        end
        if N == i
            return Base.@ncall(i, constructor, x)
        end
    end
    return constructor(x_1, x_2, x_3, x_4, x_5, x_6, x_7, x_8, x_9, x_10, x_11, x_12, x_13, x_14, x_15, x_16,
             x_17, x_18, x_19, x_20, x_21, x_22, x_23, x_24, x_25, x_26, x_27, x_28, x_29, x_30, x_31, x_32, map(i->isassigned(values, i) ? values[i] : nothing, 33:N)...)
end

function tokwstruct(x::Union{LazyValue, BJSONValue}, ::Type{T}) where {T}
    N = fieldcount(T)
    N == 0 && return T()
    error("not implemented")
end

# mutable struct
tostruct!(io::Union{IO, Base.AbstractCmd}, y; kw...) = tostruct!(Base.read(io), y; kw...)
tostruct!(buf::Union{AbstractVector{UInt8}, AbstractString}, y; kw...) = tostruct!(tolazy(buf; kw...), y)

struct ToMutableStructClosure{T}
    x::T
end

(f::ToMutableStructClosure{T})(key, val) where {T} = applyfield(T, key, val, (i, k, v) -> setfield!(f.x, k, v))

tostruct!(x::Union{LazyValue, BJSONValue}, ::Type{T}) where {T} = tostruct!(x, T())

function tostruct!(x::Union{LazyValue, BJSONValue}, y::T) where {T}
    c = ToMutableStructClosure{T}(y)
    pos = parseobject(x, c)
    return y
end
