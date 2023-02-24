"""
    JSONBase.lazy(json; kw...)

Detect the initial JSON value in `json`, returning a
`JSONBase.LazyValue` instance. `json` input can be:
  * `AbstractString`
  * `AbstractVector{UInt8}`
  * `IO` stream
  * `Base.AbstractCmd`

The `JSONBase.LazyValue` supports the "selection" syntax
for lazily navigating the JSON value. Lazy values can be
materialized via:
  * `JSONBase.binary`: an efficient, read-only binary format
  * `JSONBase.materialize(x)`: a generic Julia representation (Dict, Array, etc.)
  * `JSONBase.materialize(x, T)`: construct an instance of user-provided `T` from JSON

Currently supported keyword arguments include:
  * `float64`: for parsing all json numbers as Float64 instead of inferring int vs. float
  * `jsonlines`: 
"""
function lazy end

lazy(io::Union{IO, Base.AbstractCmd}; kw...) = lazy(Base.read(io); kw...)
lazy(io::IOStream; kw...) = lazy(Mmap.mmap(io); kw...)

@inline function lazy(buf::Union{AbstractVector{UInt8}, AbstractString}; kw...)
    len = getlength(buf)
    if len == 0
        error = UnexpectedEOF
        pos = 0
        @goto invalid
    end
    pos = 1
    @nextbyte
    return lazy(buf, pos, len, b, Options(; kw...))

@label invalid
    invalid(error, buf, pos, Any)
end

"""
    JSONBase.LazyValue

A lazy representation of a JSON value. The `LazyValue` type
supports the "selection" syntax for lazily navigating the JSON value.
Lazy values can be materialized via:
  * `JSONBase.binary`: an efficient, read-only binary format
  * `JSONBase.materialize`: a generic Julia representation (Dict, Array, etc.)
  * `JSONBase.materialize`: construct an instance of user-provided `T` from JSON
"""
struct LazyValue{T}
    buf::T
    pos::Int
    type::JSONTypes.T
    opts::Options
end

getlength(x::LazyValue) = getlength(getbuf(x))

function Base.show(io::IO, x::LazyValue)
    print(io, "JSONBase.LazyValue(", gettype(x), ")")
end

# TODO: change this to binary
Base.getindex(x::LazyValue) = materialize(x)

API.JSONType(x::LazyValue) = gettype(x) == JSONTypes.OBJECT ? ObjectLike() :
    gettype(x) == JSONTypes.ARRAY ? ArrayLike() : nothing

# core method that detects what JSON value is at the current position
# and immediately returns an appropriate LazyValue instance
@inline function lazy(buf, pos, len, b, opts)
    if opts.jsonlines
        return LazyValue(buf, pos, JSONTypes.ARRAY, opts)
    elseif b == UInt8('{')
        return LazyValue(buf, pos, JSONTypes.OBJECT, opts)
    elseif b == UInt8('[')
        return LazyValue(buf, pos, JSONTypes.ARRAY, opts)
    elseif b == UInt8('"')
        return LazyValue(buf, pos, JSONTypes.STRING, opts)
    elseif b == UInt8('n') && pos + 3 <= len &&
        getbyte(buf,pos + 1) == UInt8('u') &&
        getbyte(buf,pos + 2) == UInt8('l') &&
        getbyte(buf,pos + 3) == UInt8('l')
        return LazyValue(buf, pos, JSONTypes.NULL, opts)
    elseif b == UInt8('t') && pos + 3 <= len &&
        getbyte(buf,pos + 1) == UInt8('r') &&
        getbyte(buf,pos + 2) == UInt8('u') &&
        getbyte(buf,pos + 3) == UInt8('e')
        return LazyValue(buf, pos, JSONTypes.TRUE, opts)
    elseif b == UInt8('f') && pos + 4 <= len &&
        getbyte(buf,pos + 1) == UInt8('a') &&
        getbyte(buf,pos + 2) == UInt8('l') &&
        getbyte(buf,pos + 3) == UInt8('s') &&
        getbyte(buf,pos + 4) == UInt8('e')
        return LazyValue(buf, pos, JSONTypes.FALSE, opts)
    elseif b == UInt8('-') || (UInt8('0') <= b <= UInt8('9'))
        #TODO: have relaxed_number parsing keyword arg to
        # allow leading '+', 'Inf', 'NaN', etc.?
        return LazyValue(buf, pos, JSONTypes.NUMBER, opts)
    else
        error = InvalidJSON
        @goto invalid
    end
@label invalid
    invalid(error, buf, pos, Any)
end

@noinline _parseobject(keyvalfunc::F, x::LazyValue) where {F} =
    parseobject(keyvalfunc, x)

# core JSON object parsing function
# takes a `keyvalfunc` that is applied to each key/value pair
# `keyvalfunc` is provided a PtrString => LazyValue pair
# to materialize the key, call `tostring(key)`
# this is done automatically in selection syntax via `keyvaltostring` transformer
# returns an Continue(pos) value that notes the next position where parsing should
# continue (selection syntax requires Continue to be returned from foreach)
@inline function parseobject(keyvalfunc::F, x::LazyValue) where {F}
    pos = getpos(x)
    buf = getbuf(x)
    len = getlength(buf)
    opts = getopts(x)
    b = getbyte(buf, pos)
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @nextbyte
    if b == UInt8('}')
        return Continue(pos + 1)
    end
    while true
        # parsestring returns key as a PtrString
        key, pos = parsestring(LazyValue(buf, pos, JSONTypes.STRING, getopts(x)))
        @nextbyte
        if b != UInt8(':')
            error = ExpectedColon
            @goto invalid
        end
        pos += 1
        @nextbyte
        # we're now positioned at the start of the value
        val = lazy(buf, pos, len, b, opts)
        ret = keyvalfunc(key, val)
        # if ret is not an Continue, then we're 
        # short-circuiting parsing via selection syntax
        # so return immediately
        ret isa Continue || return ret
        # if keyvalfunc didn't materialize `val` and return an
        # updated `pos`, then we need to skip val ourselves
        pos = ret.pos == 0 ? skip(val) : ret.pos
        @nextbyte
        if b == UInt8('}')
            return Continue(pos + 1)
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1 # move past ','
        @nextbyte
    end
@label invalid
    invalid(error, buf, pos, "object")
end

# jsonlines is unique because it's an *implicit* array
# so newlines are valid delimiters (not ignored whitespace)
# and EOFs are valid terminators (not errors)
# these checks are injected after we've processed the "line"
# so we need to check for EOFs and newlines
macro jsonlines_checks()
    esc(quote
        # if we're at EOF, then we're done
        pos > len && return Continue(pos)
        # now we want to ignore whitespace, but *not* newlines
        b = getbyte(buf, pos)
        while b == UInt8(' ') || b == UInt8('\t')
            pos += 1
            pos > len && return Continue(pos)
            b = getbyte(buf, pos)
        end
        # any combo of '\r', '\n', or '\r\n' is a valid delimiter
        foundr = false
        if b == UInt8('\r')
            foundr = true
            pos += 1
            pos > len && return Continue(pos)
            b = getbyte(buf, pos)
        end
        if b == UInt8('\n')
            pos += 1
            pos > len && return Continue(pos)
            b = getbyte(buf, pos)
        elseif !foundr
            # if we didn't find a newline and we're not EOF
            # then that's an error; only whitespace, newlines,
            # and EOFs are valid in between lines
            error = ExpectedNewline
            @goto invalid
        end
        while b == UInt8(' ') || b == UInt8('\t')
            pos += 1
            pos > len && return Continue(pos)
            b = getbyte(buf, pos)
        end
    end)
end

@noinline _parsearray(keyvalfunc::F, x::LazyValue) where {F} =
    parsearray(keyvalfunc, x)

# core JSON array parsing function
# takes a `keyvalfunc` that is applied to each index => value element
# `keyvalfunc` is provided a Int => LazyValue pair
# foreach always requires a key-value pair function
# so we use the index as the key
# returns an Continue(pos) value that notes the next position where parsing should
# continue (selection syntax requires Continue to be returned from foreach)
@inline function parsearray(keyvalfunc::F, x::LazyValue) where {F}
    pos = getpos(x)
    buf = getbuf(x)
    len = getlength(buf)
    opts = getopts(x)
    jsonlines = opts.jsonlines
    b = getbyte(buf, pos)
    if !jsonlines
        if b != UInt8('[')
            error = ExpectedOpeningArrayChar
            @goto invalid
        end
        pos += 1
        @nextbyte
        if b == UInt8(']')
            return Continue(pos + 1)
        end
    else
        opts = withopts(opts, jsonlines=false)
    end
    i = 1
    while true
        # we're now positioned at the start of the value
        val = lazy(buf, pos, len, b, opts)
        ret = keyvalfunc(i, val)
        ret isa Continue || return ret
        pos = ret.pos == 0 ? skip(val) : ret.pos
        if jsonlines
            @jsonlines_checks
        else
            @nextbyte
            if b == UInt8(']')
                return Continue(pos + 1)
            elseif b != UInt8(',')
                error = ExpectedComma
                @goto invalid
            end
            i += 1
            pos += 1 # move past ','
            @nextbyte
        end
    end

@label invalid
    invalid(error, buf, pos, "array")
end

# core JSON string parsing function
# returns a PtrString and the next position to parse
# a PtrString is a semi-lazy, internal-only representation
# that notes whether escape characters were encountered while parsing
# or not. It allows materialize, _binary, etc. to deal
# with the string data appropriately without forcing a String allocation
# should NEVER be visible to users though!
@inline function parsestring(x::LazyValue)
    buf, pos = getbuf(x), getpos(x)
    len, b = getlength(buf), getbyte(buf, pos)
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
    return PtrString(pointer(buf, spos), pos - spos, escaped), pos + 1

@label invalid
    invalid(error, buf, pos, "string")
end

@noinline _parsenumber(valfunc::F, x::LazyValue) where {F} =
    parsenumber(valfunc, x)

# core JSON number parsing function
# we rely on functionality in Parsers to help infer what kind
# of number we're parsing; valid return types include:
# Int64, Int128, BigInt, Float64 or BigFloat
@inline function parsenumber(valfunc::F, x::LazyValue) where {F}
    buf, pos = getbuf(x), getpos(x)
    len = getlength(buf)
    b = getbyte(buf, pos)
    if getopts(x).float64
        res = Parsers.xparse2(Float64, buf, pos, len)
        if Parsers.invalid(res.code)
            error = InvalidNumber
            @goto invalid
        end
        valfunc(res.val)
        return pos + res.tlen
    else
        pos, code = Parsers.parsenumber(buf, pos, len, b, valfunc)
        if Parsers.invalid(code)
            error = InvalidNumber
            @goto invalid
        end
    end
    return pos

@label invalid
    invalid(error, buf, pos, "number")
end

# efficiently skip over a JSON value
# for object/array/number, we pass a no-op keyvalfunc (pass)
# to parseobject/parsearray/parsenumber
# for string, we just ignore the returned PtrString
# and for bool/null, we call materialize since it
# is already efficient for skipping
@inline function skip(x::LazyValue)
    T = gettype(x)
    if T == JSONTypes.OBJECT
        return _parseobject(pass, x).pos
    elseif T == JSONTypes.ARRAY
        return _parsearray(pass, x).pos
    elseif T == JSONTypes.STRING
        _, pos = parsestring(x)
        return pos
    elseif T == JSONTypes.NUMBER
        return _parsenumber(pass, x)
    else
        return _materialize(pass, x)
    end
end
