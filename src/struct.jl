tostruct(io::Union{IO, Base.AbstractCmd}, T; kw...) = tostruct(Base.read(io), T; kw...)
tostruct(buf::Union{AbstractVector{UInt8}, AbstractString}, T; kw...) = tostruct(tolazy(buf; kw...), T)

function tostruct(x::Union{LazyValue, BJSONValue}, ::Type{T}) where {T}
    local y
    _tostruct(x, T, _x -> (y = _x))
    return y
end

struct Struct end
struct Mutable end
struct KwDef end
StructType(::Type{T}) where {T} = Struct()

struct StructClosure{F}
    i::Int
    fname::Symbol
    valfunc::F
end

@inline function (f::StructClosure)(val)
    f.valfunc(f.i, f.fname, val)
    return
end

_string(x::Symbol) = String(x)
_string(x) = string(x)

@generated function applyfield(::Type{T}, key, val, valfunc) where {T}
    N = fieldcount(T)
    ex = quote
        return API.Continue()
    end
    for i = 1:N
        fname = fieldname(T, i)
        ftype = fieldtype(T, i)
        str = _string(fname)
        pushfirst!(ex.args, quote
            if Selectors.eq(key, $str)
                type = gettype(val)
                if type == JSONTypes.OBJECT
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

@inline function getval(::Type{T}, vec, i) where {T}
    isassigned(vec, i) && return vec[i]
    return get(defaults(T), fieldname(T, i), nothing)
end

@generated function construct(::Type{T}, constructor, vec, valfunc::F) where {T, F}
    N = fieldcount(T)
    ex = quote
        valfunc(constructor())
        return
    end
    cons = ex.args[2].args[2]
    for i = 1:N
        push!(cons.args, :(getval(T, vec, $i)))
    end
    return ex
end

struct ToStructClosure{T}
    vec::Vector{Any}
end

struct ApplyVec
    vec::Vector{Any}
end

@inline (f::ApplyVec)(i, k, v) = f.vec[i] = v

@inline (f::ToStructClosure{T})(key, val) where {T} = applyfield(T, key, val, ApplyVec(f.vec))

defaults(_) = (;)

@inline function _tostruct(x::Union{LazyValue, BJSONValue}, ::Type{T}, valfunc::F) where {T, F}
    S = gettype(x)
    ST = StructType(T)
    if S == JSONTypes.OBJECT
        if ST == Struct()
            N = fieldcount(T)
            vec = Vector{Any}(undef, N)
            c = ToStructClosure{T}(vec)
            pos = parseobject(x, c).pos
            constructor = T <: NamedTuple ? ((x...) -> T(tuple(x...))) : T
            construct(T, constructor, vec, valfunc)
            return pos
        elseif ST == Mutable()
            error("")
        elseif ST == KwDef()
            error("")
        else
            error("Unknown struct type: `$(ST)`")
        end
    elseif S == JSONTypes.ARRAY
        
    else
        error("not supported: `$S`")
    end
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
