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
@btime JSONBase.togeneric(json) #   2.736 μs (72 allocations: 4.26 KiB)
@btime JSONBase.tobjson(json) #   1.479 μs (21 allocations: 1.50 KiB)
