module JSONBase

export Selectors

getbuf(x) = getfield(x, :buf)
getpos(x) = getfield(x, :pos)

include("utils.jl")
include("selectors.jl")
using .Selectors
include("string.jl")
include("number.jl")
include("array.jl")
include("object.jl")

struct True{T}
    buf::T
    pos::Int
end

Base.show(io::IO, x::True) = print(io, "JSONBase.True(", ")")
materialize(x::True) = true, x.pos + 4
Base.Bool(x::True) = true
Base.getindex(::True) = true

struct False{T}
    buf::T
    pos::Int
end

Base.show(io::IO, x::False) = print(io, "JSONBase.False(", ")")
materialize(x::False) = false, x.pos + 5
Base.Bool(x::False) = false
Base.getindex(::False) = false

struct Null{T}
    buf::T
    pos::Int
end

Base.show(io::IO, x::Null) = print(io, "JSONBase.Null(", ")")
materialize(x::Null) = nothing, x.pos + 4
Base.Nothing(::Null) = nothing
Base.getindex(::Null) = nothing

# high-level user API functions
lazy(io::Union{IO, Base.AbstractCmd}; kw...) = lazy(Base.read(io); kw...)
lazy(str::AbstractString; kw...) = lazy(codeunits(str); kw...)

function lazy(buf::AbstractVector{UInt8}; kw...)
    len = length(buf)
    if len == 0
        error = UnexpectedEOF
        pos = 0
        @goto invalid
    end
    pos = 1
    @nextbyte
    return lazy(buf, pos, len, b)

@label invalid
    invalid(error, buf, pos, Any)
end

# reads as little as necessary to return a lazy value
const Value{T} = Union{Object{T}, Array{T}, String{T}, Number{T}, True{T}, False{T}, Null{T}}

function lazy(buf, pos, len, b)
    if b == UInt8('{')
        return Object(buf, pos)
    elseif b == UInt8('[')
        return Array(buf, pos)
    elseif b == UInt8('"')
        return String(buf, pos)
    elseif pos + 3 <= len &&
        b            == UInt8('n') &&
        buf[pos + 1] == UInt8('u') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('l')
        return Null(buf, pos)
    elseif pos + 3 <= len &&
        b            == UInt8('t') &&
        buf[pos + 1] == UInt8('r') &&
        buf[pos + 2] == UInt8('u') &&
        buf[pos + 3] == UInt8('e')
        return True(buf, pos)
    elseif pos + 4 <= len &&
        b            == UInt8('f') &&
        buf[pos + 1] == UInt8('a') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('s') &&
        buf[pos + 4] == UInt8('e')
        return False(buf, pos)
    else
        return Number(buf, pos)
    end
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

# high-level user API functions
read(io::Union{IO, Base.AbstractCmd}; kw...) = read(Base.read(io); kw...)
read(str::AbstractString; kw...) = read(codeunits(str); kw...)

read(buf::AbstractVector{UInt8}; kw...) = lazy(buf; kw...)[]

function __init__()
    resize!(empty!(BIGINT), Threads.nthreads())
    resize!(empty!(BIGFLOAT), Threads.nthreads())
    return
end

end # module
