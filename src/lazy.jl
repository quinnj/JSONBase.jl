tolazy(io::Union{IO, Base.AbstractCmd}; kw...) = tolazy(Base.read(io); kw...)

function tolazy(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...)
    len = getlength(buf)
    if len == 0
        error = UnexpectedEOF
        pos = 0
        @goto invalid
    end
    pos = 1
    @nextbyte
    return tolazy(buf, pos, len, b, Options(; kw...))

@label invalid
    invalid(error, buf, pos, Any)
end

struct LazyValue{T}
    buf::T
    pos::Int
    type::JSONTypes.T
    opts::Options
end

getlength(x::LazyValue) = getlength(getbuf(x))

function Base.show(io::IO, x::LazyValue)
    print(io, "JSONBase.LazyValue(", gettype(x), ")")
end

# TODO: change this to tobjson
Base.getindex(x::LazyValue) = togeneric(x)

API.JSONType(x::LazyValue) = gettype(x) == JSONTypes.OBJECT ? API.ObjectLike() :
    gettype(x) == JSONTypes.ARRAY ? API.ArrayLike() : nothing

function tolazy(buf, pos, len, b, opts)
    if b == UInt8('{')
        return LazyValue(buf, pos, JSONTypes.OBJECT, opts)
    elseif b == UInt8('[')
        return LazyValue(buf, pos, JSONTypes.ARRAY, opts)
    elseif b == UInt8('"')
        return LazyValue(buf, pos, JSONTypes.STRING, opts)
    elseif b == UInt8('n') && pos + 3 <= len &&
        getbyte(buf,pos + 1) == UInt8('u') &&
        getbyte(buf,pos + 2) == UInt8('l') &&
        getbyte(buf,pos + 3) == UInt8('l')
        return LazyValue(buf, pos, JSONTypes.NULL, opts)
    elseif b == UInt8('t') && pos + 3 <= len &&
        getbyte(buf,pos + 1) == UInt8('r') &&
        getbyte(buf,pos + 2) == UInt8('u') &&
        getbyte(buf,pos + 3) == UInt8('e')
        return LazyValue(buf, pos, JSONTypes.TRUE, opts)
    elseif b == UInt8('f') && pos + 4 <= len &&
        getbyte(buf,pos + 1) == UInt8('a') &&
        getbyte(buf,pos + 2) == UInt8('l') &&
        getbyte(buf,pos + 3) == UInt8('s') &&
        getbyte(buf,pos + 4) == UInt8('e')
        return LazyValue(buf, pos, JSONTypes.FALSE, opts)
    elseif b == UInt8('-') || (UInt8('0') <= b <= UInt8('9'))
        return LazyValue(buf, pos, JSONTypes.NUMBER, opts)
    else
        error = InvalidJSON
        @goto invalid
    end
@label invalid
    invalid(error, buf, pos, Any)
end

@inline function parseobject(x::LazyValue, keyvalfunc::F) where {F}
    pos = getpos(x)
    buf = getbuf(x)
    len = getlength(buf)
    b = getbyte(buf, pos)
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @nextbyte
    if b == UInt8('}')
        return API.Continue(pos + 1)
    end
    while true
        key, pos = parsestring(LazyValue(buf, pos, JSONTypes.STRING, getopts(x)))
        @nextbyte
        if b != UInt8(':')
            error = ExpectedColon
            @goto invalid
        end
        pos += 1
        @nextbyte
        # we're now positioned at the start of the value
        val = tolazy(buf, pos, len, b, getopts(x))
        ret = keyvalfunc(key, val)
        ret isa API.Continue || return ret
        pos = ret.pos == 0 ? skip(val) : ret.pos
        @nextbyte
        if b == UInt8('}')
            return API.Continue(pos + 1)
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1 # move past ','
        @nextbyte
    end
@label invalid
    invalid(error, buf, pos, "object")
end

@inline function parsearray(x::LazyValue, keyvalfunc::F) where {F}
    pos = getpos(x)
    buf = getbuf(x)
    len = getlength(buf)
    b = getbyte(buf, pos)
    if b != UInt8('[')
        error = ExpectedOpeningArrayChar
        @goto invalid
    end
    pos += 1
    @nextbyte
    if b == UInt8(']')
        return API.Continue(pos + 1)
    end
    i = 1
    while true
        # we're now positioned at the start of the value
        val = tolazy(buf, pos, len, b, getopts(x))
        ret = keyvalfunc(i, val)
        ret isa API.Continue || return ret
        pos = ret.pos == 0 ? skip(val) : ret.pos
        @nextbyte
        if b == UInt8(']')
            return API.Continue(pos + 1)
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        i += 1
        pos += 1 # move past ','
        @nextbyte
    end

@label invalid
    invalid(error, buf, pos, "array")
end

@inline function parsestring(x::LazyValue)
    buf, pos = getbuf(x), getpos(x)
    len, b = getlength(buf), getbyte(buf, pos)
    if b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    spos = pos
    escaped = false
    @nextbyte
    while b != UInt8('"')
        if b == UInt8('\\')
            # skip next character
            escaped = true
            pos += 2
        else
            pos += 1
        end
        @nextbyte(false)
    end
    return PtrString(pointer(buf, spos), pos - spos, escaped), pos + 1

@label invalid
    invalid(error, buf, pos, "string")
end

@inline function parsenumber(x::LazyValue, valfunc::F) where {F}
    buf, pos = getbuf(x), getpos(x)
    len = getlength(buf)
    b = getbyte(buf, pos)
    if getopts(x).float64
        res = Parsers.xparse2(Float64, buf, pos, len)
        if Parsers.invalid(res.code)
            error = InvalidNumber
            @goto invalid
        end
        valfunc(res.val)
        return pos + res.tlen
    else
        pos, code = Parsers.parsenumber(buf, pos, len, b, valfunc)
        if Parsers.invalid(code)
            error = InvalidNumber
            @goto invalid
        end
    end
    return pos

@label invalid
    invalid(error, buf, pos, "number")
end

function skip(x::LazyValue)
    T = gettype(x)
    if T == JSONTypes.OBJECT
        return parseobject(x, pass).pos
    elseif T == JSONTypes.ARRAY
        return parsearray(x, pass).pos
    elseif T == JSONTypes.STRING
        _, pos = parsestring(x)
        return pos
    elseif T == JSONTypes.NUMBER
        return parsenumber(x, pass)
    else
        return _togeneric(x, pass)
    end
end
