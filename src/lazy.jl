function tolazy(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...)
    len = getlength(buf)
    if len == 0
        error = UnexpectedEOF
        pos = 0
        @goto invalid
    end
    pos = 1
    @nextbyte
    return tolazy(buf, pos, len, b)

@label invalid
    invalid(error, buf, pos, Any)
end

function tolazy(buf, pos, len, b)
    if b == UInt8('{')
        return LazyValue(buf, pos, JSONType.OBJECT)
    elseif b == UInt8('[')
        return LazyValue(buf, pos, JSONType.ARRAY)
    elseif b == UInt8('"')
        return LazyValue(buf, pos, JSONType.STRING)
    elseif b == UInt8('n') && pos + 3 <= len &&
        getbyte(buf,pos + 1) == UInt8('u') &&
        getbyte(buf,pos + 2) == UInt8('l') &&
        getbyte(buf,pos + 3) == UInt8('l')
        return LazyValue(buf, pos, JSONType.NULL)
    elseif b == UInt8('t') && pos + 3 <= len &&
        getbyte(buf,pos + 1) == UInt8('r') &&
        getbyte(buf,pos + 2) == UInt8('u') &&
        getbyte(buf,pos + 3) == UInt8('e')
        return LazyValue(buf, pos, JSONType.TRUE)
    elseif b == UInt8('f') && pos + 4 <= len &&
        getbyte(buf,pos + 1) == UInt8('a') &&
        getbyte(buf,pos + 2) == UInt8('l') &&
        getbyte(buf,pos + 3) == UInt8('s') &&
        getbyte(buf,pos + 4) == UInt8('e')
        return LazyValue(buf, pos, JSONType.FALSE)
    elseif b == UInt8('-') || (UInt8('0') <= b <= UInt8('9'))
        return LazyValue(buf, pos, JSONType.NUMBER)
    else
        error = InvalidJSON
        @goto invalid
    end
@label invalid
    invalid(error, buf, pos, Any)
end

function Selectors.foreach(f, x::LazyValue)
    if gettype(x) == JSONType.OBJECT
        return parseobject(x, f)
    elseif gettype(x) == JSONType.ARRAY
        return parsearray(x, f)
    else
        throw(ArgumentError("`$x` is not an object or array and not eligible for selection syntax"))
    end
end

@inline function _togeneric(x::LazyValue, valfunc::F) where {F}
    if gettype(x) == JSONType.OBJECT
        d = Dict{String, Any}()
        pos = parseobject(x, GenericObjectClosure(d))
        valfunc(d)
        return pos
    elseif gettype(x) == JSONType.ARRAY
        a = Any[]
        pos = parsearray(x, GenericArrayClosure(a))
        valfunc(a)
        return pos
    elseif gettype(x) == JSONType.STRING
        str, pos = parsestring(getbuf(x), getpos(x))
        valfunc(str)
        return pos
    elseif gettype(x) == JSONType.NUMBER
        return parsenumber(x, valfunc)
    elseif gettype(x) == JSONType.NULL
        valfunc(nothing)
        return getpos(x) + 4
    elseif gettype(x) == JSONType.TRUE
        valfunc(true)
        return getpos(x) + 4
    elseif gettype(x) == JSONType.FALSE
        valfunc(false)
        return getpos(x) + 5
    else
        error("Invalid JSON type")
    end
end
