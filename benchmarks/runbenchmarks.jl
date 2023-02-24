using BenchmarkTools, JSONBase, JSON, JSON3

json = """
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
"""

@btime JSON.parse(json) #   2.699 μs (63 allocations: 4.09 KiB)
@btime JSON3.read(json) #   1.521 μs (7 allocations: 5.44 KiB)
@btime JSONBase.materialize(json) #   2.736 μs (72 allocations: 4.26 KiB)
@btime JSONBase.binary(json) #   1.479 μs (21 allocations: 1.50 KiB)
x = JSONBase.binary(json)
@btime JSONBase.materialize($x)

x = JSON.parse(json)
@btime JSON.json(x)
x = JSON3.read(json)
@btime JSON3.write(x)

# julia> @btime JSONBase.materialize("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", A)
#   183.152 ns (3 allocations: 144 bytes)
# A(1, 2, 3, 4)

# julia> @btime JSONBase.materialize!("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", B)
#   240.526 ns (1 allocation: 48 bytes)
# B(1, 2, 3, 4)

# julia> @btime JSONBase.materialize("""{ "a": 1,"b": 2,"c": 3,"d": 4}""")
#   364.038 ns (9 allocations: 624 bytes)
# Dict{String, Any} with 4 entries:
#   "c" => 3
#   "b" => 2
#   "a" => 1
#   "d" => 4

# julia> @btime JSON.parse("""{ "a": 1,"b": 2,"c": 3,"d": 4}""")
#   597.848 ns (9 allocations: 640 bytes)
# Dict{String, Any} with 4 entries:
#   "c" => 3
#   "b" => 2
#   "a" => 1
#   "d" => 4

# julia> @btime JSON3.read("""{ "a": 1,"b": 2,"c": 3,"d": 4}""")
#   1.325 μs (8 allocations: 1.11 KiB)
# JSON3.Object{Base.CodeUnits{UInt8, String}, Vector{UInt64}} with 4 entries:
#   :a => 1
#   :b => 2
#   :c => 3
#   :d => 4

# julia> @btime JSON3.read("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", A)
#   1.129 μs (3 allocations: 544 bytes)
# A(1, 2, 3, 4)

# julia> @btime JSONBase.binary("""{ "a": 1,"b": 2,"c": 3,"d": 4}""")
#   185.816 ns (6 allocations: 256 bytes)
# JSONBase.BinaryValue(UInt8[0xa7, 0x10, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x8d  …  0x8b, 0x02, 0x8d, 0x63, 0x8b, 0x03, 0x8d, 0x64, 0x8b, 0x04], 1, JSONTypes.OBJECT)


julia> @btime JSONBase.json(nothing)
  23.654 ns (2 allocations: 88 bytes)
"null"

julia> @btime JSON3.write(nothing)
  53.753 ns (2 allocations: 88 bytes)
"null"

julia> @btime JSON.json(nothing)
  83.592 ns (4 allocations: 192 bytes)
"null"

