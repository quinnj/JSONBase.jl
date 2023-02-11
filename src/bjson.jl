tobjson(io::Union{IO, Base.AbstractCmd}; kw...) = tobjson(Base.read(io); kw...)
tobjson(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...) = tobjson(tolazy(buf; kw...))

function tobjson(x::LazyValue)
    tape = Vector{UInt8}(undef, 128)
    i = 1
    pos, i = tobjson!(x, tape, i)
    buf = getbuf(x)
    len = getlength(buf)
    if getpos(x) == 1
        if pos <= len
            b = getbyte(buf, pos)
            while b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')
                pos += 1
                pos > len && break
                b = getbyte(buf, pos)
            end
        end
        if (pos - 1) != len
            invalid(InvalidChar, getbuf(x), pos, Any)
        end
    end
    resize!(tape, i - 1)
    return BJSONValue(tape, 1, gettype(tape, 1))
end

struct BJSONValue
    tape::Vector{UInt8}
    pos::Int
    type::JSONTypes.T
end

Base.getindex(x::BJSONValue) = togeneric(x)

function API.JSONType(x::BJSONValue)
    T = gettype(x)
    return T == JSONTypes.OBJECT ? API.ObjectLike() :
        T == JSONTypes.ARRAY ? API.ArrayLike() : nothing
end

function gettype(tape::Vector{UInt8}, pos::Int)
    bm = BJSONMeta(getbyte(tape, pos))
    return bm.type
end

include("bjsonutils.jl")

function reallocate!(x::LazyValue, tape, i)
    # println("reallocating...")
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
    pos, f.i = tobjson!(v, f.tape, i)
    f.nfields += 1
    return API.Continue(pos)
end

mutable struct BJSONArrayClosure
    tape::Vector{UInt8}
    i::Int
    nelems::Int
end

@inline function (f::BJSONArrayClosure)(_, v)
    pos, f.i = tobjson!(v, f.tape, f.i)
    f.nelems += 1
    return API.Continue(pos)
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

@inline function tobjson!(x::LazyValue, tape, i)
    if gettype(x) == JSONTypes.OBJECT
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
        tape[tape_i] = UInt8(BJSONMeta(JSONTypes.OBJECT, sm))
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
    elseif gettype(x) == JSONTypes.ARRAY
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
        tape[tape_i] = UInt8(BJSONMeta(JSONTypes.ARRAY, sm))
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
    elseif gettype(x) == JSONTypes.STRING
        y, pos = parsestring(x)
        return pos, _tobjson(y, tape, i, x)
    elseif gettype(x) == JSONTypes.NUMBER
        c = BJSONNumberClosure(tape, i, Ref(0), x)
        pos = parsenumber(x, c)
        return pos, c.newi[]
    elseif gettype(x) == JSONTypes.NULL
        @check 1
        tape[i] = UInt8(BJSONMeta(JSONTypes.NULL))
        return getpos(x) + 4, i + 1
    elseif gettype(x) == JSONTypes.TRUE
        @check 1
        tape[i] = UInt8(BJSONMeta(JSONTypes.TRUE))
        return getpos(x) + 4, i + 1
    elseif gettype(x) == JSONTypes.FALSE
        @check 1
        tape[i] = UInt8(BJSONMeta(JSONTypes.FALSE))
        return getpos(x) + 5, i + 1
    else
        error("Invalid JSON type")
    end
end

function embedded_sizemeta(n)
    es, sm = sizemeta(n)
    es || throw(ArgumentError("`$n` is too large to encode in BJSON"))
    return sm
end

@inline function _tobjson(y::PtrString, tape, i, x)
    n = y.len
    embedded_size, sm = sizemeta(n)
    @check 1 + (embedded_size ? 0 : 4) + n
    tape[i] = UInt8(BJSONMeta(JSONTypes.STRING, sm))
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

# encode numbers in bson tape
function writenumber(y::T, tape, i, x::LazyValue) where {T <: Number}
    n = sizeof(y)
    sm = embedded_sizemeta(min(15, n))
    @check 1 + n
    tape[i] = UInt8(BJSONMeta(y isa Integer ? JSONTypes.INT : JSONTypes.FLOAT, sm))
    i += 1
    return _writenumber(y, tape, i)
end

# NOTE! you must pre-@check before calling this
function _writenumber(y::T, tape, i) where {T <: Number}
    n = sizeof(y)
    ptr = convert(Ptr{T}, pointer(tape, i))
    unsafe_store!(ptr, y)
    return i + n
end

# use the same strategy as Serialization for BigInt
function writenumber(y::BigInt, tape, i, x::LazyValue)
    n = Base.GMP.MPZ.sizeinbase(y, 62) + 2
    sm = embedded_sizemeta(0)
    @check 1 + 1 + n
    @assert n < 128
    tape[i] = UInt8(BJSONMeta(JSONTypes.INT, sm))
    i += 1
    tape[i] = n % Int8
    i += 1
    Base.GMP.MPZ.get_str!(pointer(tape, i), 62, y)
    return i + n
end

@inline function readnumber(tape, i, ::Type{BigInt})
    n = tape[i]
    i += 1
    @assert (i + n - 1) <= length(tape)
    x = BigInt()
    Base.GMP.MPZ.set_str!(x, pointer(tape, i), 62)
    return x, i + n
end

@static if VERSION < v"1.9.0-"
    const libmpfr = Base.MPFR.libmpfr
else
    const libmpfr = :libmpfr
end

function writenumber(y::BigFloat, tape, i, x::LazyValue)
    # adapted from Base.MPFR.string_mpfr
    pc = Ref{Ptr{UInt8}}()
    n = ccall((:mpfr_asprintf, libmpfr), Cint,
              (Ptr{Ptr{UInt8}}, Ptr{UInt8}, Ref{BigFloat}...),
              pc, "%Re", y)
    @assert n >= 0 "mpfr_asprintf failed"
    n += 1 # add null terminator
    p = pc[]
    sm = embedded_sizemeta(0)
    @check 1 + 1 + n
    @assert n < 128
    tape[i] = UInt8(BJSONMeta(JSONTypes.FLOAT, sm))
    i += 1
    tape[i] = n % Int8
    i += 1
    unsafe_copyto!(pointer(tape, i), p, n)
    ccall((:mpfr_free_str, libmpfr), Cvoid, (Ptr{UInt8},), p)
    return i + n
end

@inline function readnumber(tape, i, ::Type{BigFloat})
    n = tape[i]
    i += 1
    @assert (i + n - 1) <= length(tape)
    z = BigFloat()
    err = ccall((:mpfr_set_str, libmpfr), Int32, (Ref{BigFloat}, Cstring, Int32, Base.MPFR.MPFRRoundingMode), z, pointer(tape, i), 0, Base.MPFR.ROUNDING_MODE[])
    err == 0 || throw(ArgumentError("invalid bjson BigFloat"))
    i += n
    return z, i
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
@inline function readnumber(tape, i, ::Type{T}) where {T}
    @assert (sizeof(T) + i - 1) <= length(tape)
    ptr = Base.bitcast(Ptr{T}, pointer(tape, i))
    return unsafe_load(ptr)
end

@inline function parseobject(x::BJSONValue, keyvalfunc::F) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    bm.type == JSONTypes.OBJECT || throw(ArgumentError("expected bjson object: `$(bm.type)`"))
    pos += 1
    nbytes = readnumber(tape, pos, Int32)
    pos += 4
    nfields = readnumber(tape, pos, Int32)
    pos += 4
    for _ = 1:nfields
        key, pos = parsestring(BJSONValue(tape, pos, JSONTypes.STRING))
        b = BJSONValue(tape, pos, gettype(tape, pos))
        ret = keyvalfunc(key, b)
        ret isa API.Continue || return ret
        pos = ret.pos == 0 ? skip(b) : ret.pos
    end
    return API.Continue(pos)
end

@inline function parsearray(x::BJSONValue, keyvalfunc::F) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    bm.type == JSONTypes.ARRAY || throw(ArgumentError("expected bjson array: `$(bm.type)`"))
    pos += 1
    nbytes = readnumber(tape, pos, Int32)
    pos += 4
    nfields = readnumber(tape, pos, Int32)
    pos += 4
    for i = 1:nfields
        b = BJSONValue(tape, pos, gettype(tape, pos))
        ret = keyvalfunc(i, b)
        ret isa API.Continue || return ret
        pos = ret.pos == 0 ? skip(b) : ret.pos
    end
    return API.Continue(pos)
end

function parsestring(x::BJSONValue)
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    @assert bm.type == JSONTypes.STRING
    pos += 1
    sm = bm.size
    if sm.is_size_embedded
        len = sm.embedded_size
    else
        len = readnumber(tape, pos, Int32)
        pos += 4
    end
    return PtrString(pointer(tape, pos), len, false), pos + len
end

@inline function parseint(x::BJSONValue, valfunc::F) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    @assert bm.type == JSONTypes.INT
    pos += 1
    sm = bm.size
    @assert sm.is_size_embedded
    sz = sm.embedded_size
    if sz == 1
        valfunc(Int64(readnumber(tape, pos, Int8)))
    elseif sz == 2
        valfunc(Int64(readnumber(tape, pos, Int16)))
    elseif sz == 4
        valfunc(Int64(readnumber(tape, pos, Int32)))
    elseif sz == 8
        valfunc(readnumber(tape, pos, Int64))
    elseif sz == 15
        valfunc(readnumber(tape, pos, Int128))
    elseif sz == 0
        val, pos = readnumber(tape, pos, BigInt)
        valfunc(val)
        return pos
    else
        throw(ArgumentError("invalid bjson int size: $sz"))
    end
    return pos + sz
end

@inline function parsefloat(x::BJSONValue, valfunc::F) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BJSONMeta(getbyte(tape, pos))
    @assert bm.type == JSONTypes.FLOAT
    pos += 1
    sm = bm.size
    @assert sm.is_size_embedded
    sz = sm.embedded_size
    if sz == 2
        valfunc(Float64(readnumber(tape, pos, Float16)))
    elseif sz == 4
        valfunc(Float64(readnumber(tape, pos, Float32)))
    elseif sz == 8
        valfunc(readnumber(tape, pos, Float64))
    elseif sz == 0
        val, pos = readnumber(tape, pos, BigFloat)
        valfunc(val)
        return pos
    else
        throw(ArgumentError("invalid bjson float size: $sz"))
    end
    return pos + sz
end

function skip(x::BJSONValue)
    tape = gettape(x)
    pos = getpos(x)
    T = gettype(x)
    if T == JSONTypes.OBJECT || T == JSONTypes.ARRAY
        pos += 1
        nbytes = readnumber(tape, pos, Int32)
        return pos + 8 + nbytes
    elseif T == JSONTypes.STRING
        sm = BJSONMeta(getbyte(tape, pos)).size
        pos += 1
        if sm.is_size_embedded
            return pos + sm.embedded_size
        else
            return pos + 4 + readnumber(tape, pos, Int32)
        end
    else
        bm = BJSONMeta(getbyte(tape, pos))
        pos += 1
        return pos + bm.size.embedded_size
    end
end
