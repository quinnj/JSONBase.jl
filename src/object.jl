struct Object{T <: AbstractVector{UInt8}}
    buf::T
    pos::Int
end

Selectors.SelectorType(::Object) = Selectors.ObjectLike()

Base.show(io::IO, x::Object) = print(io, "JSONBase.Object(", ")")

function Selectors.foreach(f, x::Object)
    pos = getpos(x)
    buf = getbuf(x)
    len = length(buf)
    while true
        pos += 1 # move past opening '{', or ','
        @nextbyte
        key, pos = readkey(buf, pos, len, b)
        @nextbyte
        if b != UInt8(':')
            error = ExpectedColon
            @goto invalid
        end
        pos += 1
        @nextbyte
        # we're now positioned at the start of the value
        ret = f(key, lazy(buf, pos, len, b))
        ret isa Selectors.Continue || return ret
        pos = ret.pos == 0 ? skip(buf, pos, len) : ret.pos
        @nextbyte
        if b == UInt8('}')
            return pos + 1
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
    end

@label invalid
    invalid(error, buf, pos, "object")
end

function skipobject(buf, pos, len, b)
    while true
        pos += 1 # move past opening '{', or ','
        @nextbyte
        pos = skipstring(buf, pos, len, b)
        @nextbyte
        if b != UInt8(':')
            error = ExpectedColon
            @goto invalid
        end
        pos += 1
        @nextbyte
        pos = skip(buf, pos, len, b)
        @nextbyte
        if b == UInt8('}')
            return pos + 1
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
    end
@label invalid
    invalid(error, buf, pos, "skipobject")
end

# lazy selection operations
Selectors.@selectors Object

# materialize
function materialize(x::Object)
    d = Dict{Key, Any}()
    opos = Selectors.foreach(x) do k, v
        val, pos = materialize(v)
        d[k] = val
        return Selectors.Continue(pos)
    end
    return d, opos
end
Base.getindex(x::Object) = materialize(x)[1]
