module API

function foreach end

struct Continue
    pos::Int
end

Continue() = Continue(0)

abstract type JSONType end

struct ObjectLike <: JSONType end
struct ArrayLike <: JSONType end
const ObjectOrArrayLike = Union{ObjectLike, ArrayLike}

JSONType(::Union{AbstractArray, AbstractSet, Tuple}) = ArrayLike()

function foreach(f, x::AbstractArray)
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
function foreach(f, x::AbstractSet)
    for (i, v) in enumerate(x)
        ret = f(i, v)
        ret isa Continue || return ret
    end
    return Continue()
end

JSONType(_) = ObjectLike()

# generic definition for Tuple, NamedTuple, structs
function foreach(f, x::T) where {T}
    N = fieldcount(T)
    N == 0 && return Continue()
    # unroll 1st 32 fields for type stability + perf
    Base.@nexprs 32 i -> begin
        k_i = fieldname(T, i)
        ret = if !isdefined(x, i)
            f(k_i, nothing)
        else
            f(k_i, getfield(x, i))
        end
        ret isa Continue || return ret
        N == i && return Continue()
    end
    if N > 32
        for i = 33:N
            k = fieldname(T, i)
            ret = if !isdefined(x, i)
                f(k, nothing)
            else
                f(k, getfield(x, i))
            end
            ret isa Continue || return ret
        end
    end
    return Continue()
end

end # module API