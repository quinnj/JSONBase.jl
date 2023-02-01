_unsafe_string(p, len) = ccall(:jl_pchar_to_string, Ref{Base.String}, (Ptr{UInt8}, Int), p, len)

@inline function parsestring(buf, pos, len=getlength(buf), b=getbyte(buf, pos))
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
    str = _unsafe_string(pointer(buf, spos), pos - spos)
    return escaped ? unescape(str) : str, pos + 1

@label invalid
    invalid(error, buf, pos, "string")
end

function parsestring(x::BJSONValue)
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    @assert bm.type == BJSONType.STRING
    pos += 1
    sm = bm.size
    if sm.is_size_embedded
        len = sm.embedded_size
    else
        len = _readint(tape, pos, 4)
        pos += 4
    end
    str = _unsafe_string(pointer(tape, pos), len)
    return str, pos + len
end

function skipstring(buf, pos, len, b)
    pos += 1
    while true
        @nextbyte(false)
        if b == UInt8('\\')
            pos += 1
        elseif b == UInt8('"')
            return pos + 1
        end
        pos += 1
    end
@label invalid
    invalid(error, buf, pos, "skipstring")
end
