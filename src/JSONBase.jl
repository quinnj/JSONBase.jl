module JSONBase

export Selectors

using Mmap
using Parsers

getbuf(x) = getfield(x, :buf)
getpos(x) = getfield(x, :pos)
gettape(x) = getfield(x, :tape)
gettype(x) = getfield(x, :type)
getopts(x) = getfield(x, :opts)

include("utils.jl")

include("interfaces.jl")
using .API

pass(args...) = API.Continue(0)

include("selectors.jl")
using .Selectors

include("lazy.jl")
include("binary.jl")
include("materialize.jl")

keyvaltostring(f) = (k, v) -> f(tostring(String, k), v)

function API.foreach(f, x::Union{LazyValue, BinaryValue})
    if gettype(x) == JSONTypes.OBJECT
        return parseobject(x, keyvaltostring(f))
    elseif gettype(x) == JSONTypes.ARRAY
        return parsearray(x, f)
    else
        throw(ArgumentError("`$x` is not an object or array and not eligible for selection syntax"))
    end
end

Selectors.@selectors LazyValue
Selectors.@selectors BinaryValue

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
       # start with lazy, API.foreach on LazyValue
       # preallocate tape buffer, call binary! w/ preallocated buffer
       # in keyvalfunc to API.foreach,
       # then call materialize
     # large, deeply nested json structures
       # use selection syntax to lazily navigate
       # then binary, materialize, materialize
     # how to form json
       # create Dict/NamedTuple/Array and call tojson
       # use struct and call tojson
       # support jsonlines output
 # JSONBase.materialize that works on LazyValue, or BSONValue
   # JSONBase.fields overload to give names, types, excludes, defaults, etc.
   # docs for kwdef/mutable
 # package docs
 # tojson
 # topretty
 # checkout JSON5, Amazon Ion?
 # special-case Matrix when reading/writing?
 # think about JSONBase.walk
   # pass in keyvalfunc that gets wrapped/passed to API.foreach
   # then we recursively walk LazyValues
