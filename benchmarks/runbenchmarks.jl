using StructUtils, JSONBase, Chairmarks, Profile, JSON, JSON3, Test, UUIDs, Dates, OrderedCollections

struct A
  a::Int
  b::Int
  c::Int
  d::Int
end

function comp(json, T=Any)
    println("JSON.jl:")
    @show @time JSON.parse(json)
    display(@be JSON.parse(json))
    println("\nJSON3.jl:")
    @show @time JSON3.read(json)
    display(@be JSON3.read(json))
    println("\nJSONBase.materialize:")
    @show @time JSONBase.materialize(json)
    display(@be JSONBase.materialize(json))
    println("\nJSONBase.binary:")
    @show @time JSONBase.binary(json)
    display(@be JSONBase.binary(json))
    println("\nJSONBase.materialize with type:")
    @show @time JSONBase.materialize(json, T)
    display(@be JSONBase.materialize(json, T))
end

comp("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", A)
comp("""[1,2,3,4]""")

comp("""
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

@b JSON.parse(json) #   2.181 μs (63 allocations: 4.09 KiB)
@b JSON3.read(json) #   1.521 μs (7 allocations: 5.44 KiB)
@b JSONBase.materialize(json) #  2.616 μs (64 allocations: 4.10 KiB)
@b JSONBase.binary(json) #  1.429 μs (2 allocations: 608 bytes)
x = JSONBase.binary(json)
@b JSONBase.materialize($x)
# 2.704 μs (142 allocations: 5.93 KiB)

x = JSON.parse(json)
@b JSON.json(x)
@b JSONBase.json(x)
x = JSON3.read(json)
@b JSON3.write(x)



@b JSONBase.materialize("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", A)
  # 183.152 ns (3 allocations: 144 bytes)

@b JSON.parse("""{ "a": 1,"b": 2,"c": 3,"d": 4}""")
  # 597.848 ns (9 allocations: 640 bytes)

@b JSON3.read("""{ "a": 1,"b": 2,"c": 3,"d": 4}""")
  # 1.325 μs (8 allocations: 1.11 KiB)

@b JSON3.read("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", A)
  # 1.129 μs (3 allocations: 544 bytes)

@noarg mutable struct B
    a::Int
    b::Int
    c::Int
    d::Int
end

@b JSONBase.materialize("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", B)
  # 240.526 ns (1 allocation: 48 bytes)

@b JSONBase.materialize("""{ "a": 1,"b": 2,"c": 3,"d": 4}""")
  # 364.038 ns (9 allocations: 624 bytes)



@b JSONBase.binary("""{ "a": 1,"b": 2,"c": 3,"d": 4}""")
  # 138.166 ns (1 allocation: 576 bytes)

@b JSONBase.json(nothing)
  # 23.654 ns (2 allocations: 88 bytes)
"null"

@b JSON3.write(nothing)
  # 53.753 ns (2 allocations: 88 bytes)
"null"

@b JSON.json(nothing)
  # 83.592 ns (4 allocations: 192 bytes)
"null"


using JSON, JSON3, JSONBase, BenchmarkTools
const json="{\"topic\":\"trade.BTCUSDT\",\"data\":[{\"symbol\":\"BTCUSDT\",\"tick_direction\":\"PlusTick\",\"price\":\"19431.00\",\"size\":0.2,\"timestamp\":\"2022-10-18T14:50:20.000Z\",\"trade_time_ms\":\"1666104620275\",\"side\":\"Buy\",\"trade_id\":\"e6be9409-2886-5eb6-bec9-de01e1ec6bf6\",\"is_block_trade\":\"false\"},{\"symbol\":\"BTCUSDT\",\"tick_direction\":\"MinusTick\",\"price\":\"19430.50\",\"size\":1.989,\"timestamp\":\"2022-10-18T14:50:20.000Z\",\"trade_time_ms\":\"1666104620299\",\"side\":\"Sell\",\"trade_id\":\"bb706542-5d3b-5e34-8767-c05ab4df7556\",\"is_block_trade\":\"false\"},{\"symbol\":\"BTCUSDT\",\"tick_direction\":\"ZeroMinusTick\",\"price\":\"19430.50\",\"size\":0.007,\"timestamp\":\"2022-10-18T14:50:20.000Z\",\"trade_time_ms\":\"1666104620314\",\"side\":\"Sell\",\"trade_id\":\"a143da10-3409-5383-b557-b93ceeba4ca8\",\"is_block_trade\":\"false\"},{\"symbol\":\"BTCUSDT\",\"tick_direction\":\"PlusTick\",\"price\":\"19431.00\",\"size\":0.001,\"timestamp\":\"2022-10-18T14:50:20.000Z\",\"trade_time_ms\":\"1666104620327\",\"side\":\"Buy\",\"trade_id\":\"7bae9053-e42b-52bd-92c5-6be8a4283525\",\"is_block_trade\":\"false\"}]}"

#Data structure for the JSON file to parse into
struct Ticket
  symbol::String
  tick_direction::String
  price::String
  size::Float64
  timestamp::String
  trade_time_ms::String
  side::String
  trade_id::String
  is_block_trade::String
end

struct Tape
  topic::String
  data::Vector{Ticket}
end

@b JSON.parse($json)
@b JSON3.read($json)
@b JSON3.read($json, Tape)
@b JSONBase.materialize($json)
@b JSONBase.binary($json)
@b JSONBase.materialize($json, Tape)
