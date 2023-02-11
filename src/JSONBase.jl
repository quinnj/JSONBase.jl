module JSONBase

export Selectors

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
include("bjson.jl")
include("generic.jl")
include("struct.jl")

keyvaltostring(f) = (k, v) -> f(tostring(k), v)

function API.foreach(f, x::Union{LazyValue, BJSONValue})
    if gettype(x) == JSONTypes.OBJECT
        return parseobject(x, keyvaltostring(f))
    elseif gettype(x) == JSONTypes.ARRAY
        return parsearray(x, f)
    else
        throw(ArgumentError("`$x` is not an object or array and not eligible for selection syntax"))
    end
end

Selectors.@selectors LazyValue
Selectors.@selectors BJSONValue

end # module

#TODO
 # 3-5 common JSON processing tasks/workflows
   # eventually in docs
   # use to highlight selection syntax
   # various conversion functions
 # JSONBase.tostruct that works on LazyValue, or BSONValue
 # package docs
 # support jsonlines
 # tojson
 # topretty
 # think about JSONBase.toiterable
   # returns an iterator
   # over jsonlines, each iteration is one line
   # for array, each iteration is an element
   # for object, each iteration is a key-value pair
