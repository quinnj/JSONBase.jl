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
        return pos + 1
    end
    i = 1
    while true
        # we're now positioned at the start of the value
        ret = keyvalfunc(i, tolazy(buf, pos, len, b))
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
        pos += 1 # move past ','
        @nextbyte
    end

@label invalid
    invalid(error, buf, pos, "array")
end

@inline function parsearray(x::BJSONValue, keyvalfunc::F) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    bm.type == BJSONType.ARRAY || throw(ArgumentError("expected bjson array: `$(bm.type)`"))
    pos += 1
    nbytes = _readint(tape, pos, 4)
    pos += 4
    nfields = _readint(tape, pos, 4)
    pos += 4
    for i = 1:nfields
        b = BJSONValue(tape, pos, gettype(tape, pos))
        ret = keyvalfunc(i, b)
        ret isa Selectors.Continue || return ret
        pos = ret.pos == 0 ? skip(b) : ret.pos
    end
    return pos
end

struct GenericArrayClosure
    arr::Vector{Any}
end

@inline function (f::GenericArrayClosure)(i, val)
    pos = _togeneric(val, x -> push!(f.arr, x))
    return Selectors.Continue(pos)
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
