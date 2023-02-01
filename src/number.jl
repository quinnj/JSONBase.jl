valid_char_after_number(b) = (b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r') || b == UInt8('\t') ||
    b == UInt8(',') || b == UInt8('}') || b == UInt8(']'))

function skipnumber(buf, pos, len, b)
    while true
        pos += 1
        @nextbyte(false)
        valid_char_after_number(b) && break
    end
    return pos
@label invalid
    invalid(error, buf, pos, "skipnumber")
end

@inline function parsenumber(x::LazyValue, valfunc::F) where {F}
    buf, pos = getbuf(x), getpos(x)
    len = getlength(buf)
    b = getbyte(buf, pos)
    pos, code = Parsers.parsenumber(buf, pos, len, b, valfunc)
    if Parsers.invalid(code)
        error = InvalidNumber
        @goto invalid
    end
    (pos > len || valid_char_after_number(getbyte(buf, pos))) || throw(ArgumentError("invalid character after number: $(Char(getbyte(buf, pos)))"))
    return pos

@label invalid
    invalid(error, buf, pos, "$T")
end

@inline function parseint(x::BJSONValue, valfunc::F) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    @assert bm.type == BJSONType.INT
    pos += 1
    sm = bm.size
    @assert sm.is_size_embedded
    sz = sm.embedded_size
    if sz == 1
        valfunc(__readnumber(tape, pos, Int8))
    elseif sz == 2
        valfunc(__readnumber(tape, pos, Int16))
    elseif sz == 4
        valfunc(__readnumber(tape, pos, Int32))
    elseif sz == 8
        valfunc(__readnumber(tape, pos, Int64))
    elseif sz == 16
        valfunc(__readnumber(tape, pos, Int128))
    else
        # TODO: BigInt
    end
    return pos + sz
end

@inline function parsefloat(x::BJSONValue, valfunc::F) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    @assert bm.type == BJSONType.FLOAT
    pos += 1
    sm = bm.size
    @assert sm.is_size_embedded
    sz = sm.embedded_size
    if sz == 2
        valfunc(__readnumber(tape, pos, Float16))
    elseif sz == 4
        valfunc(__readnumber(tape, pos, Float32))
    elseif sz == 8
        valfunc(__readnumber(tape, pos, Float64))
    else
        # TODO: BigFloat
    end
    return pos + sz
end