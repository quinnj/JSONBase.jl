module JSONBase

export Selectors

using Parsers

getbuf(x) = getfield(x, :buf)
getpos(x) = getfield(x, :pos)
gettape(x) = getfield(x, :tape)
gettype(x) = getfield(x, :type)
pass(args...) = nothing

include("utils.jl")
include("selectors.jl")
using .Selectors

include("types.jl")
include("string.jl")
include("number.jl")
include("array.jl")
include("object.jl")
include("lazy.jl")
include("bjson.jl")

# high-level user API functions
tolazy(io::Union{IO, Base.AbstractCmd}; kw...) = tolazy(Base.read(io); kw...)

togeneric(io::Union{IO, Base.AbstractCmd}; kw...) = togeneric(Base.read(io); kw...)
togeneric(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...) = togeneric(tolazy(buf; kw...))
function togeneric(x::Union{LazyValue, BJSONValue})
    local y
    _togeneric(x, _x -> (y = _x))
    return y
end

Base.getindex(x::Union{LazyValue, BJSONValue}) = togeneric(x)

tobjson(io::Union{IO, Base.AbstractCmd}; kw...) = tobjson(Base.read(io); kw...)
tobjson(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...) = tobjson(tolazy(buf; kw...))
function tobjson(x::LazyValue)
    tape = Vector{UInt8}(undef, 128)
    i = 1
    pos, i = _tobjson(x, tape, i)
    resize!(tape, i - 1)
    return BJSONValue(tape, 1, gettype(tape, 1))
end

# pos points to the start of a value
# and we want to skip to the next byte after the end of the value
function skip(buf, pos, len, b=getbyte(buf, pos))
    if b == UInt8('{')
        return skipobject(buf, pos, len, b)
    elseif b == UInt8('[')
        return skiparray(buf, pos, len, b)
    elseif b == UInt8('"')
        return skipstring(buf, pos, len, b)
    elseif pos + 3 <= len &&
        b            == UInt8('n') &&
        buf[pos + 1] == UInt8('u') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('l')
        return pos + 4
    elseif pos + 3 <= len &&
        b            == UInt8('t') &&
        buf[pos + 1] == UInt8('r') &&
        buf[pos + 2] == UInt8('u') &&
        buf[pos + 3] == UInt8('e')
        return pos + 4
    elseif pos + 4 <= len &&
        b            == UInt8('f') &&
        buf[pos + 1] == UInt8('a') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('s') &&
        buf[pos + 4] == UInt8('e')
        return pos + 5
    else
        return skipnumber(buf, pos, len, b)
    end
end

function skip(x::BJSONValue)
    tape = gettape(x)
    pos = getpos(x)
    T = gettype(x)
    if T == BJSONType.OBJECT || T == BJSONType.ARRAY
        pos += 1
        nbytes = _readint(tape, pos, 4)
        return pos + 8 + nbytes
    elseif T == BJSONType.STRING
        sm = BJSONMeta(getbyte(tape, pos)).size
        pos += 1
        if sm.is_size_embedded
            return pos + sm.embedded_size
        else
            return pos + 4 + _readint(tape, pos, 4)
        end
    else
        bm = BJSONMeta(getbyte(tape, pos))
        pos += 1
        return pos + bm.size.embedded_size
    end
end

function __init__()
    return
end

end # module

#TODO
 # JSONBase.tostruct that works on LazyValue, or BSONValue
 # make single skip(x::LazyValue) function; make sure perf matches current skipobject/skiparray implementations