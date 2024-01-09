module JSONBase

export Selectors

using Mmap, Dates, UUIDs
using Parsers

include("utils.jl")

include("interfaces.jl")
using .API

pass(args...) = Continue(0)

struct LengthClosure
  len::Ptr{Int}
end

# for use in apply* functions
@inline function (f::LengthClosure)(_, _)
  cur = unsafe_load(f.len)
  unsafe_store!(f.len, cur + 1)
  return Continue()
end

include("selectors.jl")
using .Selectors

include("lazy.jl")
include("binary.jl")

const Values = Union{LazyValue, BinaryValue}

# allow LazyValue/BinaryValue to participate in
# selection syntax by overloading applyeach
@inline function API.applyeach(f, x::Values)
  if gettype(x) == JSONTypes.OBJECT
      return applyobject(keyvaltostring(f), x)
  elseif gettype(x) == JSONTypes.ARRAY
      return applyarray(f, x)
  else
      throw(ArgumentError("`$x` is not an object or array and not eligible for selection syntax"))
  end
end

Base.getindex(x::Values) = materialize(x)
Selectors.objectlike(x::Values) = gettype(x) == JSONTypes.OBJECT
API.arraylike(x::Values) = gettype(x) == JSONTypes.ARRAY

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

# HACK to avoid inference recursion limit and the de-optimization:
# This works since know the inference recursion will terminate due to the fact that this
# method is only called when materializing a struct with definite number of fields, i.e.
# that is not self-referencing, so it is guaranteed that there are no cycles in a recursive
# `materialize` call. Especially, the `fieldcount` call in the struct fallback case within
# the `materialize` should have errored for this case.
# TODO we should revisit this hack when we start to support https://github.com/quinnj/JSONBase.jl/issues/3
function validate_recursion_relation_sig(f, nargs::Int, sig)
  @nospecialize f sig
  sig = Base.unwrap_unionall(sig)
  @assert sig isa DataType "unexpected `recursion_relation` call"
  @assert sig.name === Tuple.name "unexpected `recursion_relation` call"
  @assert length(sig.parameters) == nargs "unexpected `recursion_relation` call"
  @assert sig.parameters[1] == typeof(f) "unexpected `recursion_relation` call"
  return sig
end
@static if hasfield(Method, :recursion_relation)
  let applyobject_recursion_relation = function (
          method::Method, topmost::Union{Nothing,Method},
          @nospecialize(sig), @nospecialize(topmostsig))
          # Core.println("applyobject")
          # Core.println("  method = ", method)
          # Core.println("  topmost = ", topmost)
          # Core.println("  sig = ", sig)
          # Core.println("  topmostsig = ", topmostsig)
          sig = validate_recursion_relation_sig(applyobject, 3, sig)
          topmostsig = validate_recursion_relation_sig(applyobject, 3, topmostsig)
          return sig.parameters[2] ≠ topmostsig.parameters[2]
      end
      method = only(methods(applyobject, (Any,LazyValue,)))
      method.recursion_relation = applyobject_recursion_relation
  end
  let applyfield_recursion_relation = function (
          method::Method, topmost::Union{Nothing,Method},
          @nospecialize(sig), @nospecialize(topmostsig))
          # Core.println("applyfield")
          # Core.println("  method = ", method)
          # Core.println("  topmost = ", topmost)
          # Core.println("  sig = ", sig)
          # Core.println("  topmostsig = ", topmostsig)
          sig = validate_recursion_relation_sig(applyfield, 7, sig)
          topmostsig = validate_recursion_relation_sig(applyfield, 7, topmostsig)
          return sig.parameters[2] ≠ topmostsig.parameters[2]
      end
      method = only(methods(applyfield, (Type,Any,Type,Any,Any,Any)))
      method.recursion_relation = applyfield_recursion_relation
  end
  let _materialize_recursion_relation = function (
          method::Method, topmost::Union{Nothing,Method},
          @nospecialize(sig), @nospecialize(topmostsig))
          # Core.println("_materialize")
          # Core.println("  method = ", method)
          # Core.println("  topmost = ", topmost)
          # Core.println("  sig = ", sig)
          # Core.println("  topmostsig = ", topmostsig)
          sig = validate_recursion_relation_sig(_materialize, 6, sig)
          topmostsig = validate_recursion_relation_sig(_materialize, 6, topmostsig)
          return sig.parameters[4] ≠ topmostsig.parameters[4]
      end
      method = only(methods(_materialize, (Any,LazyValue,Type,Any,Type)))
      method.recursion_relation = _materialize_recursion_relation
  end
end

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
       # start with lazy, API.applyeach on LazyValue
       # preallocate tape buffer, call binary! w/ preallocated buffer
       # in keyvalfunc to API.applyeach,
       # then call materialize
     # large, deeply nested json structures
       # use selection syntax to lazily navigate
       # then binary, materialize, materialize
     # how to form json
       # create Dict/NamedTuple/Array and call tojson
       # use struct and call tojson
       # support jsonlines output
