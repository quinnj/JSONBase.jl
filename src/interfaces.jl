module API

"""
    API.foreach(f, x)

A custom `foreach` function that operates specifically on pairs,
supports short-circuiting, and can return an updated state via `API.Continue`.
For each key-value or index-value pair in `x`, call `f(k, v)`.
If `f` doesn't return an `API.Continue` instance, `foreach` should
return the non-`Continue` value immediately and stop iterating.
`foreach` should return `API.Continue` once iterating is complete.
"""
function foreach end

"""
    API.Continue(state)

A special sentinel value for use with `API.foreach`, that indicates
that `foreach` should continue iterating.
"""
struct Continue
    pos::Int
end

Continue() = Continue(0)

abstract type JSONType end

JSONType(x::T) where {T} = JSONType(T)

struct ObjectLike <: JSONType end
struct ArrayLike <: JSONType end
const ObjectOrArrayLike = Union{ObjectLike, ArrayLike}

JSONType(::Type{<:Union{AbstractArray, AbstractSet, Tuple}}) = ArrayLike()

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

JSONType(::Type{T}) where {T} = isstructtype(T) ? ObjectLike() : nothing
JSONType(::Type{String}) = nothing

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