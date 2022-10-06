using Test, JSONBase

x = JSONBase.lazy(Vector{UInt8}("""
{
    "int": 1,
    "float": 2.1,
    "bool1": true,
    "bool2": false,
    "none": null,
    "str": "\\"hey there sailor\\"",
    "obj": {
                "a": 1,
                "b": null,
                "c": [null, 1, "hey"],
                "d": [1.2, 3.4, 5.6]
            },
    "arr": [null, 1, "hey"],
    "arr2": [1.2, 3.4, 5.6]
}
"""))
@test typeof(x) <: JSONBase.Object
state = iterate(x, 1)
@test state !== nothing
(key, val), st = state
@test typeof(key) <: JSONBase.Key
@test key == "int"
@test typeof(val) <: JSONBase.Number
@test val == 1

kvs = collect(x)


function itr(x)
    @inline JSONBase.Selectors.foreach(x) do k, v
    end
    return
end

# lazy indexing selection support
json = Vector{UInt8}("""
{
  "store": {
    "book": [
      {
        "category": "reference",
        "author": "Nigel Rees",
        "title": "Sayings of the Century",
        "price": 8.95
      },
      {
        "category": "fiction",
        "author": "Herman Melville",
        "title": "Moby Dick",
        "isbn": "0-553-21311-3",
        "price": 8.99
      },
      {
        "category": "fiction",
        "author": "J.R.R. Tolkien",
        "title": "The Lord of the Rings",
        "isbn": "0-395-19395-8",
        "price": 22.99
      }
    ],
    "bicycle": {
      "color": "red",
      "price": 19.95
    }
  },
  "expensive": 10
}
""")
x = JSONBase.lazy(json)

x.store.book[1]