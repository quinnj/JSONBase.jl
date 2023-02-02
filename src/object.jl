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
        return Selectors.Continue(pos + 1)
    end
    while true
        key, pos = parsestring(buf, pos, len, b)
        @nextbyte
        if b != UInt8(':')
            error = ExpectedColon
            @goto invalid
        end
        pos += 1
        @nextbyte
        # we're now positioned at the start of the value
        ret = keyvalfunc(key, tolazy(buf, pos, len, b))
        ret isa Selectors.Continue || return ret
        pos = ret.pos == 0 ? skip(buf, pos, len) : ret.pos
        @nextbyte
        if b == UInt8('}')
            return Selectors.Continue(pos + 1)
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

@inline function parseobject(x::BJSONValue, keyvalfunc::F) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    bm.type == BJSONType.OBJECT || throw(ArgumentError("expected bjson object: `$(bm.type)`"))
    pos += 1
    nbytes = _readint(tape, pos, 4)
    pos += 4
    nfields = _readint(tape, pos, 4)
    pos += 4
    for _ = 1:nfields
        key, pos = parsestring(BJSONValue(tape, pos, BJSONType.STRING))
        b = BJSONValue(tape, pos, gettype(tape, pos))
        ret = keyvalfunc(key, b)
        ret isa Selectors.Continue || return ret
        pos = ret.pos == 0 ? skip(b) : ret.pos
    end
    return Selectors.Continue(pos)
end

struct GenericObjectClosure
    dict::Dict{String, Any}
end

@inline function (f::GenericObjectClosure)(key, val)
    pos = _togeneric(val, x -> f.dict[tostring(key)] = x)
    return Selectors.Continue(pos)
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
