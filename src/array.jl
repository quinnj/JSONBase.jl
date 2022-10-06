struct Array{T <: AbstractVector{UInt8}}
    buf::T
    pos::Int
end

Base.show(io::IO, x::Array) = print(io, "JSONBase.Array(", ")")

Selectors.SelectorType(::Array) = Selectors.ArrayLike()

function Selectors.foreach(f, x::Array{T}) where {T}
    pos = getpos(x)
    buf = getbuf(x)
    len = length(buf)
    i = 1
    while true
        pos += 1 # move past opening '[', or ','
        @nextbyte
        # we're now positioned at the start of the value
        ret = f(i, lazy(buf, pos, len, b))
        ret isa Selectors.Continue || return ret
        pos = ret.pos == 0 ? skip(buf, pos, len) : ret.pos
        @nextbyte
        if b == UInt8(']')
            return pos + 1
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        i += 1
    end

@label invalid
    invalid(error, buf, pos, "array")
end

function skiparray(buf, pos, len, b)
    pos += 1
    while true
        @nextbyte
        pos = skip(buf, pos, len, b)
        @nextbyte
        if b == UInt8(']')
            return pos + 1
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
    end
@label invalid
    invalid(error, buf, pos, "skiparray")
end

Selectors.@selectors Array

function materialize(x::Array)
    a = Any[]
    apos = Selectors.foreach(x) do i, v
        val, pos = materialize(v)
        push!(a, val)
        return Selectors.Continue(pos)
    end
    return a, apos
end

Base.getindex(x::Array) = materialize(x)[1]