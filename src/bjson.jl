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
        return BJSONType.T(Base.bitcast(UInt8, x) & TYPE_MASK)
    elseif nm == :size
        return SizeMeta((Base.bitcast(UInt8, x) & SIZE_MASK) >> 3)
    else
        throw(ArgumentError("invalid BJSONMeta property: $nm"))
    end
end

function BJSONMeta(type::BJSONType.T, size::SizeMeta=SizeMeta(true))
    return BJSONMeta(UInt8(type) | (UInt8(size) << 3))
end

function reallocate!(x::LazyValue, tape, i)
    len = getlength(getbuf(x))
    pos = getpos(x)
    tape_len = ceil(Int, ((len * i) ÷ pos) * 1.05)
    resize!(tape, tape_len)
    return
end

macro check(n)
    esc(quote
        if (i + $n) > length(tape)
            reallocate!(x, tape, i)
        end
    end)
end

mutable struct BJSONObjectClosure{T}
    tape::Vector{UInt8}
    i::Int
    x::LazyValue{T}
    nfields::Int
end

@inline function (f::BJSONObjectClosure{T})(k, v) where {T}
    i = _tobjson(k, f.tape, f.i, f.x)
    pos, f.i = _tobjson(v, f.tape, i)
    f.nfields += 1
    return Selectors.Continue(pos)
end

mutable struct BJSONArrayClosure
    tape::Vector{UInt8}
    i::Int
    nelems::Int
end

@inline function (f::BJSONArrayClosure)(_, v)
    pos, f.i = _tobjson(v, f.tape, f.i)
    f.nelems += 1
    return Selectors.Continue(pos)
end

struct BJSONStringClosure{T}
    tape::Vector{UInt8}
    i::Int
    newi::Base.RefValue{Int}
    x::LazyValue{T}
end

@inline function (f::BJSONStringClosure{T})(str::PtrString) where {T}
    f.newi[] = unsafe_copyto!(str, f.tape, f.i, f.x)
    return
end

struct BJSONNumberClosure{T}
    tape::Vector{UInt8}
    i::Int
    newi::Base.RefValue{Int}
    x::LazyValue{T}
end

@inline function (f::BJSONNumberClosure{T})(y::Y) where {T, Y}
    f.newi[] = _tobjson(y, f.tape, f.i, f.x, true)
    return
end

function _tobjson(x::LazyValue, tape, i)
    if gettype(x) == JSONType.OBJECT
        tape_i = i
        @check 1 + 4 + 4
        # skip past our BJSONMeta tape slot for now
        # skip 8 bytes for total # of bytes (4) and # of fields (4)
        i += 1 + 4 + 4
        # now we can start writing the fields
        c = BJSONObjectClosure(tape, i, x, 0)
        pos = parseobject(x, c).pos
        # compute SizeMeta, even though we write nfields unconditionally
        _, sm = sizemeta(c.nfields)
        # note: we pre-@checked earlier
        tape[tape_i] = UInt8(BJSONMeta(BJSONType.OBJECT, sm))
        # store total # of bytes
        i = c.i
        nbytes = (i - tape_i) - # total bytes consumed so far
            1 - # for BJSONMeta
            4 - # for total # of bytes
            4 # for # of fields
        _writenumber(Int32(nbytes), tape, tape_i + 1)
        # store # of elements
        _writenumber(Int32(c.nfields), tape, tape_i + 5)
        return pos, i
    elseif gettype(x) == JSONType.ARRAY
        # skip past our BJSONMeta tape slot for now
        tape_i = i
        @check 1 + 4 + 4
        i += 1
        # skip 8 bytes for total # of bytes (4) and # of elements (4)
        i += 8
        # now we can start writing the elements
        c = BJSONArrayClosure(tape, i, 0)
        pos = parsearray(x, c).pos
        # compute SizeMeta, even though we write nelems unconditionally
        _, sm = sizemeta(c.nelems)
        # store eltype in BJSONMeta size or 0x1f if not homogenous
        tape[tape_i] = UInt8(BJSONMeta(BJSONType.ARRAY, sm))
        i = c.i
        nbytes = (i - tape_i) - # total bytes consumed so far
            1 - # for BJSONMeta
            4 - # for total # of bytes
            4 # for # of fields
        # store total # of bytes
        _writenumber(Int32(nbytes), tape, tape_i + 1)
        # store # of elements
        _writenumber(Int32(c.nelems), tape, tape_i + 5)
        return pos, i
    elseif gettype(x) == JSONType.STRING
        y, pos = parsestring(getbuf(x), getpos(x))
        return pos, _tobjson(y, tape, i, x)
    elseif gettype(x) == JSONType.NUMBER
        c = BJSONNumberClosure(tape, i, Ref(0), x)
        pos = parsenumber(x, c)
        return pos, c.newi[]
    elseif gettype(x) == JSONType.NULL
        @check 1
        tape[i] = UInt8(BJSONMeta(BJSONType.NULL))
        return getpos(x) + 4, i + 1
    elseif gettype(x) == JSONType.TRUE
        @check 1
        tape[i] = UInt8(BJSONMeta(BJSONType.TRUE))
        return getpos(x) + 4, i + 1
    elseif gettype(x) == JSONType.FALSE
        @check 1
        tape[i] = UInt8(BJSONMeta(BJSONType.FALSE))
        return getpos(x) + 5, i + 1
    else
        error("Invalid JSON type")
    end
end

@inline function _tobjson(y::PtrString, tape, i, x)
    n = y.len
    embedded_size, sm = sizemeta(n)
    @check 1 + (embedded_size ? 0 : 4) + n
    tape[i] = UInt8(BJSONMeta(BJSONType.STRING, sm))
    i += 1
    if !embedded_size
        i = _writenumber(Int32(n), tape, i)
    end
    return unsafe_copyto!(y, tape, i, x)
end

@inline function Base.unsafe_copyto!(ptrstr::PtrString, tape::Vector{UInt8}, i, x) # x is LazyValue
    @check ptrstr.len
    if ptrstr.escaped
        return i + GC.@preserve tape unsafe_unescape_to_buffer(ptrstr.ptr, ptrstr.len, pointer(tape, i))
    else
        GC.@preserve tape ccall(:memcpy, Ptr{Cvoid}, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(tape, i), ptrstr.ptr, ptrstr.len)
        return i + ptrstr.len
    end
end

function embedded_sizemeta(n)
    es, sm = sizemeta(n)
    es || throw(ArgumentError("`$x` is too large to encode in BJSON"))
    return sm
end

# encode numbers in bson tape
function writenumber(y::T, tape, i, x::LazyValue) where {T <: Number}
    n = sizeof(y)
    sm = embedded_sizemeta(n)
    @check 1 + n
    tape[i] = UInt8(BJSONMeta(y isa Integer ? BJSONType.INT : BJSONType.FLOAT, sm))
    i += 1
    return _writenumber(y, tape, i)
end

# NOTE! you must pre-@check before calling this
function _writenumber(x::T, tape, i) where {T <: Number}
    n = sizeof(x)
    ptr = convert(Ptr{T}, pointer(tape, i))
    unsafe_store!(ptr, x)
    return i + n
end

# use the same strategy as Serialization for BigInt
function writenumber(y::BigInt, tape, i, x::LazyValue)
    str = string(y, base = 62)
    n = sizeof(str)
    sm = embedded_sizemeta(n)
    @check 1 + n
    tape[i] = UInt8(BJSONMeta(BJSONType.INT, sm))
    i += 1
    GC.@preserve tape str unsafe_copyto!(pointer(tape, i), pointer(str), n)
    return i + n
end

function writenumber(y::BigFloat, tape, i, x::LazyValue)
    #TODO
    error("Bigfloat not yet supported")
end

@inline function _tobjson(y::Integer, tape, i, x::LazyValue, trunc)
    if trunc
        if y <= typemax(Int8)
            return writenumber(y % Int8, tape, i, x)
        elseif y <= typemax(Int16)
            return writenumber(y % Int16, tape, i, x)
        elseif y <= typemax(Int32)
            return writenumber(y % Int32, tape, i, x)
        elseif y <= typemax(Int64)
            return writenumber(y % Int64, tape, i, x)
        elseif y <= typemax(Int128)
            return writenumber(y % Int128, tape, i, x)
        else
            return writenumber(y, tape, i, x)
        end
    else
        return writenumber(y, tape, i, x)
    end
end

@inline function _tobjson(y::AbstractFloat, tape, i, x::LazyValue, trunc)
    if trunc
        if Float16(y) == y
            return writenumber(Float16(y), tape, i, x)
        elseif Float32(y) == y
            return writenumber(Float32(y), tape, i, x)
        elseif Float64(y) == y
            return writenumber(Float64(y), tape, i, x)
        else
            return writenumber(y, tape, i, x)
        end
    else
        return writenumber(y, tape, i, x)
    end
end

# reading
IntType(n) = n == 1 ? Int8 : n == 2 ? Int16 : n == 4 ? Int32 : n == 8 ? Int64 : n == 16 ? Int128 : error("bad int type size: `$n`")
FloatType(n) = n == 2 ? Float16 : n == 4 ? Float32 : n == 8 ? Float64 : BigFloat
_readint(tape, i, n) = __readnumber(tape, i, IntType(n))

function __readnumber(tape, i, ::Type{T}) where {T}
    @assert (sizeof(T) + i - 1) <= length(tape)
    ptr = convert(Ptr{T}, pointer(tape, i))
    return unsafe_load(ptr)
end

function Selectors.foreach(f, x::BJSONValue)
    T = gettype(x)
    if T == BJSONType.OBJECT
        return parseobject(x, keyvaltostring(f))
    elseif T == BJSONType.ARRAY
        return parsearray(x, f)
    else
        throw(ArgumentError("`$x` is not an object or array and not eligible for selection syntax"))
    end
end

@inline function _togeneric(x::BJSONValue, valfunc::F) where {F}
    T = gettype(x)
    if T == BJSONType.OBJECT
        d = Dict{String, Any}()
        pos = parseobject(x, GenericObjectClosure(d)).pos
        valfunc(d)
        return pos
    elseif T == BJSONType.ARRAY
        a = Any[]
        pos = parsearray(x, GenericArrayClosure(a)).pos
        valfunc(a)
        return pos
    elseif T == BJSONType.STRING
        str, pos = parsestring(x)
        valfunc(tostring(str))
        return pos
    elseif T == BJSONType.INT
        return parseint(x, valfunc)
    elseif T == BJSONType.FLOAT
        return parsefloat(x, valfunc)
    elseif T == BJSONType.NULL
        valfunc(nothing)
        return getpos(x) + 1
    elseif T == BJSONType.TRUE
        valfunc(true)
        return getpos(x) + 1
    elseif T == BJSONType.FALSE
        valfunc(false)
        return getpos(x) + 1
    else
        error("Invalid JSON type")
    end
end
