# only 5 bits, highest bit is whether size is embeded
# lower 4 bits are size of value
# not used at all for objects/arrays
# for strings, if sizeof string is < 16 bytes, then
# the size is embedded and no Int32 is needed after
# the BinaryMeta byte
# for numbers, we encode the # of bytes used for the
# int/float; BigInt/BigFloat are 0 and have their size stored
# in an Int8 right after BinaryMeta byte
# Int128 is store as 15, since that's the max in 4 bits
# used in conjunction w/ an embedded JSONTypes.T
# in BinaryMeta for an entire byte of metadata
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

# 5 highest bits are SizeMeta, lower 3 are JSONTypes.T
primitive type BinaryMeta 8 end
BinaryMeta(x::UInt8) = Base.bitcast(BinaryMeta, x)
Base.UInt8(x::BinaryMeta) = Base.bitcast(UInt8, x)

const TYPE_MASK = 0b00000111
const SIZE_MASK = 0b11111000

function Base.getproperty(x::BinaryMeta, nm::Symbol)
    if nm == :type
        return JSONTypes.T(Base.bitcast(UInt8, x) & TYPE_MASK)
    elseif nm == :size
        return SizeMeta((Base.bitcast(UInt8, x) & SIZE_MASK) >> 3)
    else
        throw(ArgumentError("invalid BinaryMeta property: $nm"))
    end
end

Base.propertynames(::BinaryMeta) = (:type, :size)

Base.show(io::IO, x::BinaryMeta) = print(io, "BinaryMeta(type=", x.type, ", size=", x.size, ")")

function BinaryMeta(type::JSONTypes.T, size::SizeMeta=SizeMeta(true))
    return BinaryMeta(UInt8(type) | (UInt8(size) << 3))
end