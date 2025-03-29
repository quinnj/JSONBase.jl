"""
    JSONBase.binary(json) -> JSONBase.BinaryValue

Convert a JSON input (String, byte vector, IO, LazyValue, etc)
to an efficient, materialized, binary representation.
No references to the original JSON input are kept, and the binary
"tape" is independently valid/serializable (accessible via `JSONBase.gettape`).

This binary format can be particularly efficient as a materialization vs.
a generic representation (e.g. `Dict`, `Array`, etc.) when the JSON
has deeply nested structures, since the binary format is "flattened"
and avoids the need to allocate intermediate nested objects.

A [`BinaryValue`](@ref) is returned that supports the "selection" syntax,
similar to LazyValue. The `BinaryValue` can also be materialized via:
  * `JSONBase.materialize(x)`: a generic Julia representation (Dict, Array, etc.)
  * `JSONBase.materialize(x, T)`: construct an instance of user-provided `T` from the `BinaryValue`

Currently supported keyword arguments include:
  * `float64`: for parsing all json numbers as Float64 instead of inferring int vs. float;
    also allows parsing `NaN`, `Inf`, and `-Inf` since they are otherwise invalid JSON
  * `jsonlines`: treat the `json` input as an implicit JSON array,
    delimited by newlines, each element being parsed from each row/line in the input
"""
function binary end

binary(io::Union{IO, Base.AbstractCmd}; kw...) = binary(Base.read(io); kw...)
binary(io::IOStream; kw...) = binary(Mmap.mmap(io); kw...)
binary(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...) = binary(lazy(buf; kw...))

function binary(x::LazyValue)
    tape = Vector{UInt8}(undef, 512)
    i = 1
    pos, i = binary!(x, tape, i)
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
    return BinaryValue(tape, 1, gettype(tape, 1))
end

"""
    JSONBase.BinaryValue

A materialized, binary representation of a JSON value.
The `BinaryValue` type supports the "selection" syntax for
navigating the BinaryValue structure. BinaryValues can be materialized via:
  * `JSONBase.materialize`: a generic Julia representation (Dict, Array, etc.)
  * `JSONBase.materialize`: construct an instance of user-provided `T` from JSON

The BinaryValue is a "tape" of bytes that is independently valid/serializable/self-describing.

The following is a description of the binary format for
the various types of JSON values.

Each JSON value uses at least 1 byte to be encoded.
This byte is represented interally as the `BinaryMeta` primitive
type, and holds information about the type of value and
potentially some extra size information.

For `null`, `true`, and `false` values, knowing the type is sufficient,
and no additional bytes are needed for encoding.

For number values, the `BinaryMeta` byte encodes whether the number
is an integer or a float, and the number of bytes needed to encode
the number. Integers and floats are truncated to the smallest # of bytes
necessary to represent the value. For example, the number `1.0` is
encoded as a `Float16` (2 bytes), while the number `1` is encoded as
an `Int8` (1 byte). Note, however, that to reduce the total # of fully materialized
types, integers will always be materialized as `Int64`, `Int128`, or `BigInt`,
while floats will be materialized as `Float64` or `BigFloat`. The compressed
types are solely for the internal binary type representation.
`BigInt` and `BigFloat` use gmp/mpfr-specific library calls to encode
their values as strings in the binary tape and similarly to deserialize.

For string values, the string data is stored directly in the binary tape.
If the # of bytes is < 16, then the size will be encoded in the `BinaryMeta`
byte. If the # of bytes is >= 16, then the size will be encoded explicitly
as a `UInt32` value in the binary tape immediately following the `BinaryMeta`
byte. The string data is encoded as UTF-8, and escaped JSON characters
are unescaped. This allows the string data to be directly materialized from
the tape without further processing needed.

For object/array values, the `BinaryMeta` byte only encodes the type.
Immediately after the meta byte, we store the total # of non meta-bytes
the object/array elements take up. This is encoded as a `UInt32` value.
After the `UInt32` total # of bytes, we store another `UInt32` value
that encodes the # of elements in the object/array. This is followed
by the actual object/array elements recursively. The elements are encoded in the
same order as they appear in the JSON input. For objects, the keys
are encoded as strings, and the values are encoded as the corresponding
JSON values. For arrays, the elements are encoded in order.
Note again that the total # of bytes for the object/array only includes
the bytes for the elements, and not the meta byte or the 8 bytes for
the 2 sizes (total # of bytes, # of elements). So an empty object or
array will take up 9 bytes in the binary tape (1 meta byte, 4 bytes for
the total # of bytes, 4 bytes for the # of elements, 0 bytes for elements).
"""
struct BinaryValue
    tape::Vector{UInt8}
    pos::Int
    type::JSONTypes.T
end

BinaryValue(tape::Vector{UInt8}, pos::Int) = BinaryValue(tape, pos, gettype(tape, pos))

function gettype(tape::Vector{UInt8}, pos::Int)
    bm = BinaryMeta(getbyte(tape, pos))
    return bm.type
end

# only used for showing BinaryValue
struct BinaryObject <: AbstractDict{String, BinaryValue}
    tape::Vector{UInt8}
    pos::Int
end

struct BinaryArray <: AbstractVector{BinaryValue}
    tape::Vector{UInt8}
    pos::Int
end

const BinaryValues = Union{BinaryValue, BinaryObject, BinaryArray}

include("binaryutils.jl")

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

struct BinaryObjectClosure{T}
    tape::Vector{UInt8}
    x::LazyValue{T}
    tape_i::Int # the position in the tape where we store the current i
    tape_nfields::Int # the position in the tape where we store the current nfields
end

function (f::BinaryObjectClosure{T})(k, v) where {T}
    # first we encode the key
    i = Int(readnumber(f.tape, f.tape_i, Int32))
    i = _binary(k, f.tape, i, f.x)
    # then we encode the value recursively
    pos, i = binary!(v, f.tape, i)
    # update our i
    _writenumber(i % Int32, f.tape, f.tape_i)
    # update our nfields
    nfields = readnumber(f.tape, f.tape_nfields, Int32)
    _writenumber(nfields + Int32(1), f.tape, f.tape_nfields)
    return pos
end

struct BinaryArrayClosure
    tape::Vector{UInt8}
    tape_i::Int
    tape_nelems::Int
end

function (f::BinaryArrayClosure)(::Int, v)
    i = Int(readnumber(f.tape, f.tape_i, Int32))
    pos, i = binary!(v, f.tape, i)
    # update our i
    _writenumber(i % Int32, f.tape, f.tape_i)
    # update our nelems
    nelems = readnumber(f.tape, f.tape_nelems, Int32)
    _writenumber(nelems + Int32(1), f.tape, f.tape_nelems)
    return pos
end

struct BinaryNumberClosure{T}
    tape::Vector{UInt8}
    i::Int
    newi::Ptr{Int}
    x::LazyValue{T}
end

function (f::BinaryNumberClosure{T})(y::Y) where {T, Y}
    i = _binary(y, f.tape, f.i, f.x)
    unsafe_store!(f.newi, i)
    return
end

function binary!(x::LazyValue, tape, i)
    if gettype(x) == JSONTypes.OBJECT
        meta_i = i
        @check 1 + 4 + 4
        # skip past our BinaryMeta tape slot for now
        i += 1
        # now we're going to note the current position in the tape
        # which is where we'll *eventually* store the total # of bytes
        # but we're actually going to use it to keep track of our
        # current position in the tape (i) while we recursively encode
        # all the object fields
        tape_i = i
        i += 4
        # we're also noting the position to where we'll store
        # the # of fields in the object, which we'll use to update from our
        # BinaryObjectClosure for each field we process
        tape_nfields = i
        _writenumber(Int32(0), tape, tape_nfields)
        i += 4
        # we've now skipped 8 bytes for total # of bytes (4) and # of fields (4)
        # now we can start writing the fields
        # log our current i in our total bytes slot
        _writenumber(i % Int32, tape, tape_i)
        c = BinaryObjectClosure(tape, x, tape_i, tape_nfields)
        pos = applyobject(c, x)
        # we've now recursively serialized all the object key/value fields
        # compute SizeMeta, even though we write nfields unconditionally
        _, sm = sizemeta(0)
        # note: we pre-@checked earlier by leaving a slot for our BM byte
        tape[meta_i] = UInt8(BinaryMeta(JSONTypes.OBJECT, sm))
        # compute and store total # of bytes
        # first we read the ending `i` from our tape_i slot
        i = Int(readnumber(tape, tape_i, Int32))
        nbytes = (i - meta_i) - # total bytes consumed so far
            1 - # for BinaryMeta
            4 - # for total # of bytes
            4 # for # of fields
        _writenumber(nbytes % Int32, tape, tape_i)
        # for the # of fields, it was incrementally updated
        # in applyobject, so no need to do anything further
        return pos, i
    elseif gettype(x) == JSONTypes.ARRAY
        # skip past our BinaryMeta tape slot for now
        meta_i = i
        @check 1 + 4 + 4
        i += 1
        # now we're going to note the current position in the tape
        # where we'll store the total # of bytes for the array
        # but we're actually going to use it to keep track of our
        # current position in the tape while we encode all the
        # array elements
        tape_i = i
        i += 4
        # we're also noting the position to where we'll store
        # the # of elements in the array, which we'll update in our
        # BinaryArrayClosure for each element we process
        tape_nelems = i
        _writenumber(Int32(0), tape, tape_nelems)
        i += 4
        # we've now skipped 8 bytes for total # of bytes (4) and # of elements (4)
        # now we can start writing the elements
        _writenumber(i % Int32, tape, tape_i)
        c = BinaryArrayClosure(tape, tape_i, tape_nelems)
        pos = applyarray(c, x)
        # compute SizeMeta, even though we write nelems unconditionally
        #TODO: store eltype in SizeMeta or 0x1f if not homogenous?
        _, sm = sizemeta(0)
        tape[meta_i] = UInt8(BinaryMeta(JSONTypes.ARRAY, sm))
        i = Int(readnumber(tape, tape_i, Int32))
        nbytes = (i - meta_i) - # total bytes consumed so far
            1 - # for BinaryMeta
            4 - # for total # of bytes
            4 # for # of elements
        # store total # of bytes
        _writenumber(nbytes % Int32, tape, tape_i)
        # for the # of elements, it was incrementally updated
        # in applyarray, so no need to do anything further
        return pos, i
    elseif gettype(x) == JSONTypes.STRING
        y, pos = applystring(nothing, x)
        return pos, _binary(y, tape, i, x)
    elseif gettype(x) == JSONTypes.NUMBER
        # we're being tricksy hobbits here
        # we make a Ref that we want to use to track the new i
        # once we've parsed the number, *BUT* we don't want to
        # actually allocate the Ref on the heap, so we use
        # unsafe_convert to convert it to a Ptr{Int}
        # then we pass that Ptr{Int} to our BinaryNumberClosure
        # which will use it to store the new i
        # because the Ref never crosses a function "line", its allocation
        # is elided by the compiler, but we make sure it lives during our
        # applynumber call via GC.@preserve
        # Jameson Nash vouched that this is fine as long as we use a bitstype
        # for the ref, which we do (Int)
        rx = Ref(0)
        c = BinaryNumberClosure(tape, i, Base.unsafe_convert(Ptr{Int}, rx), x)
        GC.@preserve rx begin
            pos = applynumber(c, x)
            # now we retrieve the new i from our ref pointer
            i = unsafe_load(c.newi)
        end
        return pos, i
    elseif gettype(x) == JSONTypes.NULL
        @check 1
        tape[i] = UInt8(BinaryMeta(JSONTypes.NULL))
        return getpos(x) + 4, i + 1
    elseif gettype(x) == JSONTypes.TRUE
        @check 1
        tape[i] = UInt8(BinaryMeta(JSONTypes.TRUE))
        return getpos(x) + 4, i + 1
    elseif gettype(x) == JSONTypes.FALSE
        @check 1
        tape[i] = UInt8(BinaryMeta(JSONTypes.FALSE))
        return getpos(x) + 5, i + 1
    else
        error("Invalid JSON type")
    end
end

function embedded_sizemeta(n)
    es, sm = sizemeta(n)
    es || throw(ArgumentError("`$n` is too large to encode in Binary"))
    return sm
end

function _binary(y::PtrString, tape, i, x)
    n = y.len
    embedded_size, sm = sizemeta(n)
    @check 1 + (embedded_size ? 0 : 4) + n
    tape[i] = UInt8(BinaryMeta(JSONTypes.STRING, sm))
    i += 1
    if !embedded_size
        i = _writenumber(n % Int32, tape, i)
    end
    return unsafe_copyto!(y, tape, i, x)
end

function Base.unsafe_copyto!(ptrstr::PtrString, tape::Vector{UInt8}, i, x) # x is LazyValue
    @check ptrstr.len
    if ptrstr.escaped
        return i + GC.@preserve tape unsafe_unescape_to_buffer(ptrstr.ptr, ptrstr.len, pointer(tape, i))
    else
        GC.@preserve tape ccall(:memcpy, Ptr{Cvoid}, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(tape, i), ptrstr.ptr, ptrstr.len)
        return i + ptrstr.len
    end
end

# encode numbers in tape
function writenumber(y::T, tape, i, x::LazyValue) where {T <: Number}
    n = sizeof(y)
    # we call min(15, n) here because
    # Int128 _would_ be 16 bytes, but we only have 4 bits to encode the size
    # so we call it 15 instead
    # there's no risk of confusing this with BigInt
    # since it always uses 0 as the embedded size and
    # encodes the actual # bytes in the next byte
    sm = embedded_sizemeta(min(15, n))
    @check 1 + n
    tape[i] = UInt8(BinaryMeta(y isa Integer ? JSONTypes.INT : JSONTypes.FLOAT, sm))
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
    # gmp library call to get the number of bytes needed to store the BigInt
    # we add 2 for potential negative sign and null terminator
    # as recommended by the gmp docs
    # we use base 62 to make the string representation
    # as compact as possible
    n = Base.GMP.MPZ.sizeinbase(y, 62) + 2
    # embedded size is always 0 for BigInt
    sm = embedded_sizemeta(0)
    # need 1 for meta byte, 1 for size byte, and n for the string
    @check 1 + 1 + n
    @assert n < 256 "BigInt too large to encode in Binary: `$y`"
    # first we store our BinaryMeta byte
    tape[i] = UInt8(BinaryMeta(JSONTypes.INT, sm))
    i += 1
    # then we store the # of bytes needed to store the BigInt
    # god so help me if anyone ever files a bug saying
    # they have a JSON int that needs more than 255 bytes to store
    tape[i] = n % UInt8
    i += 1
    GC.@preserve tape y Base.GMP.MPZ.get_str!(pointer(tape, i), 62, y)
    return i + n
end

function readnumber(tape, i, ::Type{BigInt})
    n = tape[i]
    i += 1
    @assert (i + n - 1) <= length(tape)
    x = BigInt()
    GC.@preserve tape Base.GMP.MPZ.set_str!(x, pointer(tape, i), 62)
    return x, i + n
end

@static if VERSION < v"1.9.0-"
    const libmpfr = :libmpfr
else
    const libmpfr = Base.MPFR.libmpfr
end

function writenumber(y::BigFloat, tape, i, x::LazyValue)
    # adapted from Base.MPFR.string_mpfr
    # mpfr_asprintf allocates a string for us
    # that has the BigFloat written out
    # and it returns the # of bytes _excluding_ the null terminator
    # in the written string
    # we use the %Ra (hex) format specifier since it maintains
    # full precision while being shorter than %Re (that Base uses for display)
    pc = Ref{Ptr{UInt8}}()
    n = ccall((:mpfr_asprintf, libmpfr), Cint,
              (Ptr{Ptr{UInt8}}, Ptr{UInt8}, Ref{BigFloat}...),
              pc, "%Ra", y)
    @assert n >= 0 "mpfr_asprintf failed"
    n += 1 # add null terminator
    p = pc[]
    # embedded size is always 0 for BigFloat
    sm = embedded_sizemeta(0)
    # need 1 for meta byte, 1 for size byte, and n for the string
    @check 1 + 1 + n
    @assert n < 256 "BigFloat too large to encode in Binary: `$y` would take $n bytes"
    # first we store our BinaryMeta byte
    tape[i] = UInt8(BinaryMeta(JSONTypes.FLOAT, sm))
    i += 1
    # then we store the # of bytes needed to store the BigFloat
    tape[i] = n % UInt8
    i += 1
    GC.@preserve tape unsafe_copyto!(pointer(tape, i), p, n)
    ccall((:mpfr_free_str, libmpfr), Cvoid, (Ptr{UInt8},), p)
    return i + n
end

function readnumber(tape, i, ::Type{BigFloat})
    n = tape[i]
    i += 1
    @assert (i + n - 1) <= length(tape)
    z = BigFloat()
    # mpfr library function to read a string into our BigFloat `z` variable
    err = GC.@preserve tape ccall((:mpfr_set_str, libmpfr), Int32, (Ref{BigFloat}, Cstring, Int32, Base.MPFR.MPFRRoundingMode), z, pointer(tape, i), 0, Base.MPFR.ROUNDING_MODE[])
    err == 0 || throw(ArgumentError("invalid binary BigFloat"))
    i += n
    return z, i
end

function _binary(y::Integer, tape, i, x::LazyValue)
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
end

function _binary(y::AbstractFloat, tape, i, x::LazyValue)
    if Float16(y) == y
        return writenumber(Float16(y), tape, i, x)
    elseif Float32(y) == y
        return writenumber(Float32(y), tape, i, x)
    elseif Float64(y) == y
        return writenumber(Float64(y), tape, i, x)
    else
        return writenumber(y, tape, i, x)
    end
end

# reading
function readnumber(tape, i, ::Type{T}) where {T}
    @assert (sizeof(T) + i - 1) <= length(tape)
    ptr = Base.bitcast(Ptr{T}, pointer(tape, i))
    return unsafe_load(ptr)
end

# core object processing function for binary format
# we're really just reading the number of fields
# then looping over them to call keyvalfunc on the
# key-value pairs.
# follows the same rules as applyobject on LazyValue for returning
function applyobject(keyvalfunc::F, x::BinaryValues) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BinaryMeta(getbyte(tape, pos))
    bm.type == JSONTypes.OBJECT || throw(ArgumentError("expected binary object: `$(bm.type)`"))
    pos += 1
    nbytes = readnumber(tape, pos, Int32)
    pos += 4
    nfields = readnumber(tape, pos, Int32)
    pos += 4
    for _ = 1:nfields
        key, pos = applystring(nothing, BinaryValue(tape, pos, JSONTypes.STRING))
        b = BinaryValue(tape, pos, gettype(tape, pos))
        ret = keyvalfunc(key, b)
        ret isa StructUtils.EarlyReturn && return ret
        pos = (ret isa Int && ret > pos) ? ret : skip(b)
    end
    return pos
end

function applyarray(keyvalfunc::F, x::BinaryValues) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BinaryMeta(getbyte(tape, pos))
    bm.type == JSONTypes.ARRAY || throw(ArgumentError("expected binary array: `$(bm.type)`"))
    pos += 1
    nbytes = readnumber(tape, pos, Int32)
    pos += 4
    nfields = readnumber(tape, pos, Int32)
    pos += 4
    for i = 1:nfields
        b = BinaryValue(tape, pos, gettype(tape, pos))
        ret = keyvalfunc(i, b)
        ret isa StructUtils.EarlyReturn && return ret
        pos = (ret isa Int && ret > pos) ? ret : skip(b)
    end
    return pos
end

_applystring(f::F, x::BinaryValue) where {F} = applystring(f, x)
# return a PtrString for an embedded string in binary format
# we return a PtrString to allow callers flexibility
# in how they want to materialize/compare/etc.
function applystring(f::F, x::BinaryValue) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BinaryMeta(getbyte(tape, pos))
    @assert bm.type == JSONTypes.STRING
    pos += 1
    sm = bm.size
    if sm.is_size_embedded
        len = Int(sm.embedded_size)
    else
        len = Int(readnumber(tape, pos, Int32))
        pos += 4
    end
    # hardcode `false` for `escaped` since we unescaped when writing to the tape
    str = PtrString(pointer(tape, pos), len, false)
    if f === nothing
        return str, pos + len
    else
        f(str)
        return pos + len
    end
end

# reading an integer from binary format involves
# inspecting the BinaryMeta byte to determine the
# # of bytes the integer takes for encoding,
# or switching to BigInt decoding if the embedded size is 0
function applyint(valfunc::F, x::BinaryValue) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BinaryMeta(getbyte(tape, pos))
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
        throw(ArgumentError("invalid binary int size: $sz"))
    end
    return pos + sz
end

function applyfloat(valfunc::F, x::BinaryValue) where {F}
    tape = gettape(x)
    pos = getpos(x)
    bm = BinaryMeta(getbyte(tape, pos))
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
        throw(ArgumentError("invalid binary float size: $sz"))
    end
    return pos + sz
end

# efficiently skip over a binary value
# for object/array, we know to skip over the 9 meta bytes
# and read the 2-5 bytes for the total # of bytes to skip over
# for all the fields/elements.
function skip(x::BinaryValue)
    tape = gettape(x)
    pos = getpos(x)
    T = gettype(x)
    if T == JSONTypes.OBJECT || T == JSONTypes.ARRAY
        pos += 1
        nbytes = readnumber(tape, pos, Int32)
        return pos + 8 + nbytes
    elseif T == JSONTypes.STRING
        sm = BinaryMeta(getbyte(tape, pos)).size
        pos += 1
        # for strings, we need to check if their size
        # is embedded in the BinaryMeta byte
        if sm.is_size_embedded
            return pos + sm.embedded_size
        else
            # if not, we read the size from the next 4 bytes
            # after the meta byte
            return pos + 4 + readnumber(tape, pos, Int32)
        end
    elseif T == JSONTypes.INT || T == JSONTypes.FLOAT
        bm = BinaryMeta(getbyte(tape, pos))
        pos += 1
        sz = bm.size.embedded_size
        if sz == 0
            # if the size is 0, then we need to read the next byte
            # to skip the BigInt/BigFloat
            return pos + 1 + Int(getbyte(tape, pos))
        end
        return pos + (sz == 15 ? 16 : sz)
    else
        return pos + 1
    end
end
