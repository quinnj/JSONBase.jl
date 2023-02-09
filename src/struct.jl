tostruct(io::Union{IO, Base.AbstractCmd}, T; kw...) = tostruct(Base.read(io), T; kw...)
tostruct(buf::Union{AbstractVector{UInt8}, AbstractString}, T; kw...) = tostruct(tolazy(buf; kw...), T)

function tostruct(x::Union{LazyValue, BJSONValue}, ::Type{T}) where {T}
    local y
    _tostruct(x, T, _x -> (y = _x))
    return y
end

struct StructClosure{F}
    i::Int
    fname::Symbol
    valfunc::F
end

@inline function (f::StructClosure)(val)
    return API.Continue(f.valfunc(f.i, f.fname, val))
end

@generated function applyfield(::Type{T}, key, val, valfunc) where {T}
    N = fieldcount(T)
    ex = quote
        return API.Continue()
    end
    for i = 1:N
        fname = fieldname(T, i)
        ftype = fieldtype(T, i)
        str = String(fname)
        pushfirst!(ex.args, quote
            if Selectors.eq(key, $str)
                if API.JSONType($ftype) == API.ObjectLike()
                    c = StructClosure($i, $(Meta.quot(fname)), valfunc)
                    pos = _tostruct(val, $ftype, c)
                    return API.Continue(pos)
                else
                    c = StructClosure($i, $(Meta.quot(fname)), valfunc)
                    pos = _togeneric(val, c)
                    return API.Continue(pos)
                end
            end
        end)
    end
    pushfirst!(ex.args, :(Base.@_inline_meta))
    # str = sprint(show, ex)
    # println(str)
    return ex
end

struct ToStructClosure{T}
    vec::Vector{Any}
end

@inline (f::ToStructClosure{T})(key, val) where {T} = applyfield(T, key, val, (i, k, v) -> f.vec[i] = v)

defaults(_) = (;)

function _tostruct(x::Union{LazyValue, BJSONValue}, ::Type{T}, valfunc) where {T}
    N = fieldcount(T)
    if N == 0
        valfunc(T())
        return API.Continue()
    end
    vec = Vector{Any}(undef, N)
    c = ToStructClosure{T}(vec)
    pos = parseobject(x, c)
    constructor = T <: Tuple ? tuple : T <: NamedTuple ? ((x...) -> T(tuple(x...))) : T
    defs = defaults(T)
    Base.@nexprs 32 i -> begin
        if isassigned(vec, i)
            x_i = vec[i]::fieldtype(T, i) # TODO: is fieldtype assert to restrictive here?
            if N == i
                valfunc(Base.@ncall(i, constructor, x))
                @goto done
            end
        elseif !isempty(defs) && haskey(defs, fieldname(T, i))
            x_i = defs[fieldname(T, i)]::fieldtype(T, i)
            if N == i
                valfunc(Base.@ncall(i, constructor, x))
                @goto done
            end
        else
            x_i = nothing
            if N == i
                valfunc(Base.@ncall(i, constructor, x))
                @goto done
            end
        end
    end
    valfunc(constructor(x_1, x_2, x_3, x_4, x_5, x_6, x_7, x_8, x_9, x_10, x_11, x_12, x_13, x_14, x_15, x_16,
             x_17, x_18, x_19, x_20, x_21, x_22, x_23, x_24, x_25, x_26, x_27, x_28, x_29, x_30, x_31, x_32, map(i->isassigned(values, i) ? values[i] : nothing, 33:N)...))
@label done
    return pos
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
