# scoped enum
module JSONType
    primitive type T 8 end
    T(x::UInt8) = Base.bitcast(T, x)
    Base.UInt8(x::T) = Base.bitcast(UInt8, x)
    const NULL = T(0x00)
    const FALSE = T(0x01)
    const TRUE = T(0x02)
    const NUMBER = T(0x03)
    const STRING = T(0x04)
    const ARRAY = T(0x05)
    const OBJECT = T(0x06)
    const names = Dict(
        NULL => "NULL",
        FALSE => "FALSE",
        TRUE => "TRUE",
        NUMBER => "NUMBER",
        STRING => "STRING",
        ARRAY => "ARRAY",
        OBJECT => "OBJECT",
    )
    Base.show(io::IO, x::T) = print(io, "JSONType.", names[x])
end

struct LazyValue{T}
    buf::T
    pos::Int
    type::JSONType.T
end

function Base.show(io::IO, x::LazyValue)
    print(io, "JSONBase.LazyValue(", gettype(x), ")")
end

API.JSONLike(x::LazyValue) = gettype(x) == JSONType.OBJECT ? API.ObjectLike() :
    gettype(x) == JSONType.ARRAY ? API.ArrayLike() : nothing
Selectors.@selectors LazyValue

# BJSONValue
# scoped enum
module BJSONType
    primitive type T 8 end
    T(x::UInt8) = Base.bitcast(T, x)
    Base.UInt8(x::T) = Base.bitcast(UInt8, x)
    const NULL = T(0x00)
    const FALSE = T(0x01)
    const TRUE = T(0x02)
    const INT = T(0x03)
    const FLOAT = T(0x04)
    const STRING = T(0x05)
    const ARRAY = T(0x06)
    const OBJECT = T(0x07)
    const names = Dict(
        NULL => "NULL",
        FALSE => "FALSE",
        TRUE => "TRUE",
        INT => "INT",
        FLOAT => "FLOAT",
        STRING => "STRING",
        ARRAY => "ARRAY",
        OBJECT => "OBJECT",
    )
    Base.show(io::IO, x::T) = print(io, "BJSONType.", names[x])
end

struct BJSONValue
    tape::Vector{UInt8}
    pos::Int
    type::BJSONType.T
end

function API.JSONLike(x::BJSONValue)
    T = gettype(x)
    return T == BJSONType.OBJECT ? API.ObjectLike() :
        T == BJSONType.ARRAY ? API.ArrayLike() : nothing
end
Selectors.@selectors BJSONValue

function gettype(tape::Vector{UInt8}, pos::Int)
    bm = BJSONMeta(getbyte(tape, pos))
    return bm.type
end
