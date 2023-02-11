# only 5 bits, highest bit is whether size is embeded
primitive type SizeMeta 8 end
SizeMeta(x::UInt8) = Base.bitcast(SizeMeta, x)
Base.UInt8(x::SizeMeta) = Base.bitcast(UInt8, x)
const IS_SIZE_EMBEDDED_MASK = 0b00010000
const EMBEDDED_SIZE_MASK = 0b00001111

function Base.getproperty(x::SizeMeta, nm::Symbol)
    if nm == :is_size_embedded
        return (UInt8(x) & IS_SIZE_EMBEDDED_MASK) != 0x00
    elseif nm == :embedded_size
        return UInt8(x) & EMBEDDED_SIZE_MASK
    else
        throw(ArgumentError("invalid SizeMeta property: $nm"))
    end
end

Base.propertynames(::SizeMeta) = (:is_size_embedded, :embedded_size)

Base.show(io::IO, x::SizeMeta) = print(io, "SizeMeta(is_size_embedded=", x.is_size_embedded, ", embedded_size=", Int(x.embedded_size), ")")

function SizeMeta(is_size_embedded::Bool, embedded_size::UInt8=0x00)
    if is_size_embedded
        return SizeMeta(0x10 | (embedded_size & EMBEDDED_SIZE_MASK))
    else
        return SizeMeta(0x00 | (embedded_size & EMBEDDED_SIZE_MASK))
    end
end

sizemeta(size::Integer) = size <= EMBEDDED_SIZE_MASK, SizeMeta(size <= EMBEDDED_SIZE_MASK, size % UInt8)

# 5 highest bits are SizeMeta, lower 3 are BSONType
primitive type BJSONMeta 8 end
BJSONMeta(x::UInt8) = Base.bitcast(BJSONMeta, x)
Base.UInt8(x::BJSONMeta) = Base.bitcast(UInt8, x)

const TYPE_MASK = 0b00000111
const SIZE_MASK = 0b11111000

function Base.getproperty(x::BJSONMeta, nm::Symbol)
    if nm == :type
        return JSONTypes.T(Base.bitcast(UInt8, x) & TYPE_MASK)
    elseif nm == :size
        return SizeMeta((Base.bitcast(UInt8, x) & SIZE_MASK) >> 3)
    else
        throw(ArgumentError("invalid BJSONMeta property: $nm"))
    end
end

Base.propertynames(::BJSONMeta) = (:type, :size)

Base.show(io::IO, x::BJSONMeta) = print(io, "BJSONMeta(type=", x.type, ", size=", x.size, ")")

function BJSONMeta(type::JSONTypes.T, size::SizeMeta=SizeMeta(true))
    return BJSONMeta(UInt8(type) | (UInt8(size) << 3))
end
