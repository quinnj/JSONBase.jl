"""
    JSONBase.Key

Represents the key of a JSON object. A lazy string-like type, but currently
only supports comparison via `==` with other strings. Otherwise, call
`String` to get the actual string value.
"""
struct Key{T <: AbstractVector{UInt8}}
    buf::T
    pos::Int
    len::Int
    escaped::Bool
end

_unsafe_string(p, len) = ccall(:jl_pchar_to_string, Ref{Base.String}, (Ptr{UInt8}, Int), p, len)

function Base.String(x::Key)
    str = GC.@preserve x _unsafe_string(pointer(x.buf, x.pos), x.len)
    return x.escaped ? unescape(str) : str
end

Base.show(io::IO, x::Key) = print(io, string("JSONBase.Key(\"", Base.String(x), "\")"))

Base.getindex(x::Key) = Base.String(x)

import Base: ==
function ==(x::AbstractString, y::Key)
    if !y.escaped
        sizeof(x) == y.len && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(x), pointer(y.buf, y.pos), y.len) == 0
    else
        x == Base.String(y)
    end
end
==(y::Key, x::AbstractString) = x == y
function Selectors.eq(x::Symbol, y::Key)
    if !y.escaped
        sizeof(x) == y.len && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), x, pointer(y.buf, y.pos), y.len) == 0
    else
        x == Base.String(y)
    end
end
Selectors.eq(y::Key, x::Symbol) = Selectors.eq(x, y)

@inline function readkey(buf, pos, len=length(buf), b=getbyte(buf, pos))
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
    return Key(buf, spos, pos - spos, escaped), pos + 1

@label invalid
    invalid(error, buf, pos, "string")
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

struct String{T <: AbstractVector{UInt8}}
    buf::T
    pos::Int
end

function Base.String(x::String)
    key, _ = readkey(x.buf, x.pos)
    return Base.String(key)
end

Base.show(io::IO, x::String) = print(io, "JSONBase.String(\"", Base.String(x), "\")")

function materialize(x::String)
    key, pos = readkey(x.buf, x.pos)
    return Base.String(key), pos
end
Base.getindex(x::String) = Base.String(x)