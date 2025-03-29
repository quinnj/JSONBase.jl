module JSONBase

using Mmap, Dates, UUIDs, Logging
using Parsers, StructUtils

import StructUtils: Selectors

include("utils.jl")

abstract type AbstractJSONStyle <: StructUtils.StructStyle end
struct JSONStyle{ObjectType} <: AbstractJSONStyle end

StructUtils.fieldtagkey(::Type{<:AbstractJSONStyle}) = :json

objecttype(::JSONStyle{ObjectType}) where {ObjectType} = ObjectType

const DEFAULT_OBJECT_TYPE = Dict{String, Any}
JSONStyle() = JSONStyle{DEFAULT_OBJECT_TYPE}()

pass(args...) = nothing

include("lazy.jl")
include("binary.jl")

const Values = Union{LazyValue, BinaryValue}

# allow LazyValue/BinaryValue to participate in
# selection syntax by overloading applyeach
function StructUtils.applyeach(::StructUtils.StructStyle, f, x::Values)
    if gettype(x) == JSONTypes.OBJECT
        return applyobject(f, x)
    elseif gettype(x) == JSONTypes.ARRAY
        return _applyarray(f, x)
    else
        throw(ArgumentError("`$x` is not an object or array and not eligible for selection syntax"))
    end
end

Base.getindex(x::Values) = materialize(x)
StructUtils.structlike(x::Values) = gettype(x) == JSONTypes.OBJECT
StructUtils.arraylike(x::Values) = gettype(x) == JSONTypes.ARRAY
StructUtils.nulllike(x::Values) = gettype(x) == JSONTypes.NULL

# this defines convenient getindex/getproperty methods
Selectors.@selectors LazyValue
Selectors.@selectors BinaryValue

include("materialize.jl")
include("json.jl")

# convenience aliases for pre-1.0 JSON compat
parse(source; kw...) = materialize(source; kw...)
parsefile(file; kw...) = materialize(open(file); kw...)
@doc (@doc materialize) parse
@doc (@doc materialize) parsefile

print(io::IO, obj, indent=nothing) = json(io, obj; pretty=something(indent, 0))
print(a, indent=nothing) = print(stdout, a, indent)
@doc (@doc json) print

json(a, indent::Integer) = json(a; pretty=indent)

end # module

#TODO
 # 3-5 common JSON processing tasks/workflows
   # eventually in docs
   # use to highlight selection syntax
   # various conversion functions
     # working w/ small JSON
       # convert to Dict
       # pick 1 or 2 properties out
       # convert to struct
     # abstract JSON
       # use type field to figure out concrete subtype
       # convert to concrete struct
     # large jsonlines/object/array production processing
       # iterate each line: lazy, binary, materialize
       # start with lazy, StructUtils.applyeach on LazyValue
       # preallocate tape buffer, call binary! w/ preallocated buffer
       # in keyvalfunc to StructUtils.applyeach,
       # then call materialize
     # large, deeply nested json structures
       # use selection syntax to lazily navigate
       # then binary, materialize, materialize
     # how to form json
       # create Dict/NamedTuple/Array and call tojson
       # use struct and call tojson
       # support jsonlines output
