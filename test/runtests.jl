using Test, JSONBase, UUIDs, Dates, OrderedCollections #, BenchmarkTools, JSON

# helper struct for testing reading json from files
struct File end

function makefile(x)
    nm, io = mktemp()
    write(io, x)
    seekstart(io)
    close(io)
    return nm
end

make(::Type{String}, x) = x
make(::Type{SubString{String}}, x) = SubString(x)
make(::Type{Vector{UInt8}}, x) = Vector{UInt8}(x)
make(::Type{IOBuffer}, x) = IOBuffer(x)
function make(::Type{File}, x)
    _, io = mktemp()
    write(io, x)
    seekstart(io)
    return io
end

@testset "JSONBase.lazy" begin
    for T in (String, SubString{String}, IOBuffer, Vector{UInt8}, File)
        @test JSONBase.gettype(JSONBase.lazy(make(T, "1"))) == JSONBase.JSONTypes.NUMBER
        @test JSONBase.gettype(JSONBase.lazy(make(T, "true"))) == JSONBase.JSONTypes.TRUE
        @test JSONBase.gettype(JSONBase.lazy(make(T, "false"))) == JSONBase.JSONTypes.FALSE
        @test JSONBase.gettype(JSONBase.lazy(make(T, "null"))) == JSONBase.JSONTypes.NULL
        @test JSONBase.gettype(JSONBase.lazy(make(T, "[]"))) == JSONBase.JSONTypes.ARRAY
        @test JSONBase.gettype(JSONBase.lazy(make(T, "{}"))) == JSONBase.JSONTypes.OBJECT
        @test JSONBase.gettype(JSONBase.lazy(make(T, "\"\""))) == JSONBase.JSONTypes.STRING
        @test_throws ArgumentError JSONBase.lazy(make(T, "a"))
    end
    # JSON.jl pre-1.0 compat
    x = JSONBase.parse("{}")
    @test isempty(x) && typeof(x) == Dict{String, Any}
    x = JSONBase.parsefile(makefile("{}"))
    @test isempty(x) && typeof(x) == Dict{String, Any}
    x = JSONBase.materialize("{}")
    @test isempty(x) && typeof(x) == Dict{String, Any}
    @test_throws ArgumentError JSONBase.materialize(JSONBase.LazyValue(".", 1, JSONBase.JSONTypes.OBJECT, JSONBase.OPTIONS))
    x = JSONBase.lazy("1")
    @test_throws ArgumentError JSONBase.API.applyeach((k, v) -> nothing, x)
    x = JSONBase.materialize("{\"a\": 1}")
    @test !isempty(x) && x["a"] == 1 && typeof(x) == Dict{String, Any}
    x = JSONBase.materialize("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [], \"g\": {}}")
    @test !isempty(x) && x["a"] == 1 && x["b"] === nothing && x["c"] === true && x["d"] === false && x["e"] == "" && x["f"] == Any[] && x["g"] == Dict{String, Any}()
    x = JSONBase.materialize("[]")
    @test isempty(x) && x == Any[]
    x = JSONBase.materialize("[1, null, true, false, \"\", [], {}]")
    @test !isempty(x) && x[1] == 1 && x[2] === nothing && x[3] === true && x[4] === false && x[5] == "" && x[6] == Any[] && x[7] == Dict{String, Any}()
    x = JSONBase.materialize("1")
    @test x == 1
    x = JSONBase.materialize("true")
    @test x === true
    x = JSONBase.materialize("false")
    @test x === false
    x = JSONBase.materialize("null")
    @test x === nothing
    x = JSONBase.materialize("\"\"")
    @test x == ""
    x = JSONBase.materialize("\"a\"")
    @test x == "a"
    x = JSONBase.materialize("\"\\\"\"")
    @test x == "\""
    x = JSONBase.materialize("\"\\\\\"")
    @test x == "\\"
    x = JSONBase.materialize("\"\\/\"")
    @test x == "/"
    x = JSONBase.materialize("\"\\b\"")
    @test x == "\b"
    x = JSONBase.materialize("\"\\f\"")
    @test x == "\f"
    x = JSONBase.materialize("\"\\n\"")
    @test x == "\n"
    x = JSONBase.materialize("\"\\r\"")
    @test x == "\r"
    x = JSONBase.materialize("\"\\t\"")
    @test x == "\t"
    x = JSONBase.materialize("\"\\u0000\"")
    @test x == "\0"
    x = JSONBase.materialize("\"\\uD83D\\uDE00\"")
    @test x == "😀"
    x = JSONBase.materialize("\"\\u0061\"")
    @test x == "a"
    x = JSONBase.materialize("\"\\u2028\"")
    @test x == "\u2028"
    x = JSONBase.materialize("\"\\u2029\"")
    @test x == "\u2029"
    @test_throws ArgumentError JSONBase.materialize("nula")
    @test_throws ArgumentError JSONBase.materialize("nul")
    @test_throws ArgumentError JSONBase.materialize("trub")
    # float64 keyword arg
    @test JSONBase.materialize("1", float64=true) === 1.0
    @test JSONBase.materialize("[1, 2, 3.14, 10]", float64=true) == [1.0, 2.0, 3.14, 10.0]
    @test JSONBase.materialize("{\"a\": 1, \"b\": 2.0, \"c\": 3.14, \"d\": 10}", float64=true) == Dict("a" => 1.0, "b" => 2.0, "c" => 3.14, "d" => 10.0)
    # allownan is just an alias for float64=true
    @test JSONBase.materialize("NaN"; allownan=true) === NaN
    @test JSONBase.materialize("Inf"; allownan=true) === Inf
    @test JSONBase.materialize("-Inf"; float64=true) === -Inf
    @test JSONBase.materialize("+1.0"; float64=true) === 1.0
    # JSONBase.Options
    opts = JSONBase.Options(jsonlines=true)
    opts2 = JSONBase.withopts(opts; jsonlines=false)
    @test !opts2.jsonlines
    # jsonlines support
    @test JSONBase.materialize("1"; jsonlines=true) == [1]
    @test JSONBase.materialize("1 \t"; jsonlines=true) == [1]
    @test JSONBase.materialize("1 \t\r"; jsonlines=true) == [1]
    @test JSONBase.materialize("1 \t\r\n"; jsonlines=true) == [1]
    @test JSONBase.materialize("1 \t\r\nnull"; jsonlines=true) == [1, nothing]
    # missing newline
    @test_throws ArgumentError JSONBase.materialize("1 \t\bnull"; jsonlines=true)
    @test_throws ArgumentError JSONBase.materialize(""; jsonlines=true)
    @test JSONBase.materialize("1\n2\n3\n4"; jsonlines=true) == [1, 2, 3, 4]
    @test JSONBase.materialize("[1]\n[2]\n[3]\n[4]"; jsonlines=true) == [[1], [2], [3], [4]]
    @test JSONBase.materialize("{\"a\": 1}\n{\"b\": 2}\n{\"c\": 3}\n{\"d\": 4}"; jsonlines=true) == [Dict("a" => 1), Dict("b" => 2), Dict("c" => 3), Dict("d" => 4)]
    @test JSONBase.materialize("""
    ["Name", "Session", "Score", "Completed"]
    ["Gilbert", "2013", 24, true]
    ["Alexa", "2013", 29, true]
    ["May", "2012B", 14, false]
    ["Deloise", "2012A", 19, true]
    """; jsonlines=true, float64=true) ==
    [["Name", "Session", "Score", "Completed"],
     ["Gilbert", "2013", 24.0, true],
     ["Alexa", "2013", 29.0, true],
     ["May", "2012B", 14.0, false],
     ["Deloise", "2012A", 19.0, true]]
    @test JSONBase.materialize("""
    {"name": "Gilbert", "wins": [["straight", "7♣"], ["one pair", "10♥"]]}
    {"name": "Alexa", "wins": [["two pair", "4♠"], ["two pair", "9♠"]]}
    {"name": "May", "wins": []}
    {"name": "Deloise", "wins": [["three of a kind", "5♣"]]}
    """; jsonlines=true) ==
    [Dict("name" => "Gilbert", "wins" => [["straight", "7♣"], ["one pair", "10♥"]]),
     Dict("name" => "Alexa", "wins" => [["two pair", "4♠"], ["two pair", "9♠"]]),
     Dict("name" => "May", "wins" => []),
     Dict("name" => "Deloise", "wins" => [["three of a kind", "5♣"]])]
    # LazyObject with all possible JSON types
    x = JSONBase.lazy("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [], \"g\": {}}")
    @test length(x) == 7
    if VERSION >= v"1.7"
        @test sprint(show, x) == "LazyObject{String} with 7 entries:\n  \"a\" => JSONBase.LazyValue(1)\n  \"b\" => JSONBase.LazyValue(nothing)\n  \"c\" => JSONBase.LazyValue(true)\n  \"d\" => JSONBase.LazyValue(false)\n  \"e\" => JSONBase.LazyValue(\"\")\n  \"f\" => LazyValue[]\n  \"g\" => LazyObject{String}()"
    end
    # LazyArray with all possible JSON types
    x = JSONBase.lazy("[1, null, true, false, \"\", [], {}]")
    @test length(x) == 7
    if VERSION >= v"1.7"
        @test sprint(show, x) == "7-element LazyArray{String}:\n JSONBase.LazyValue(1)\n JSONBase.LazyValue(nothing)\n JSONBase.LazyValue(true)\n JSONBase.LazyValue(false)\n JSONBase.LazyValue(\"\")\n LazyValue[]\n LazyObject{String}()"
    end
    # error cases
    @test_throws ArgumentError JSONBase.materialize("{\"a\" 1}")
    x = JSONBase.lazy("{}")
    @test_throws ArgumentError JSONBase.applyarray((i, v) -> nothing, x)
    @test_throws ArgumentError JSONBase.applystring(nothing, x)
    x = JSONBase.lazy("{}"; float64=true)
    @test_throws ArgumentError JSONBase.applynumber(x -> nothing, x)
end

@testset "Non-default object types: `JSONBase.$f`" for f in (JSONBase.lazy, JSONBase.binary)
    # test dicttype keyword arg
    @test JSONBase.materialize(f("{\"a\": 1, \"b\": 2, \"c\": 3}"); dicttype=Dict{String, Int}) isa Dict{String, Int}
    @test JSONBase.materialize(f("{\"a\": 1, \"b\": 2, \"c\": 3}"); dicttype=Vector{Pair{String, Int}}) isa Vector{Pair{String, Int}}
    @test JSONBase.materialize(f("{\"a\": 1, \"b\": 2, \"c\": 3}"); dicttype=OrderedDict{String, Int}) isa OrderedDict{String, Int}
    x = JSONBase.materialize(f("{\"a\": 1, \"b\": 2, \"c\": 3}"); dicttype=OrderedDict{Symbol, Int})
    @test x[:a] == 1 && x[:b] == 2 && x[:c] == 3
end

@testset "BinaryValue" begin
    @testset "BinaryMeta" begin
        em, sm = JSONBase.sizemeta(1)
        @test em
        @test sm.is_size_embedded
        @test sm.embedded_size == 1
        em, sm = JSONBase.sizemeta(15)
        @test em
        @test sm.is_size_embedded
        @test sm.embedded_size == 15
        em, sm = JSONBase.sizemeta(16)
        @test !em
        @test !sm.is_size_embedded
        @test sm.embedded_size == 0
        bm = JSONBase.BinaryMeta(JSONBase.JSONTypes.OBJECT)
        @test bm.type == JSONBase.JSONTypes.OBJECT
        @test bm.size.is_size_embedded
    end

    for T in (String, SubString{String}, IOBuffer, Vector{UInt8}, File)
        @test JSONBase.binary(make(T, "{}"))[] == Dict{String, Any}()
        @test JSONBase.binary(make(T, "1"))[] == 1
        @test JSONBase.binary(make(T, "3.14"))[] == 3.14
        @test JSONBase.binary(make(T, "true"))[] == true
        @test JSONBase.binary(make(T, "false"))[] == false
        @test JSONBase.binary(make(T, "null"))[] === nothing
        @test JSONBase.binary(make(T, "[] "))[] == Any[]
        @test JSONBase.binary(make(T, "\"\""))[] == ""
        @test_throws ArgumentError JSONBase.binary(make(T, "a"))
    end
    x = JSONBase.binary(""" {"a": 1, "b": null, "c": true, "d": false, "e": "hey there sailor", "f": [], "g": {}} """)
    @test x[] == Dict{String, Any}("a" => 1, "b" => nothing, "c" => true, "d" => false, "e" => "hey there sailor", "f" => Any[], "g" => Dict{String, Any}())
    x = JSONBase.binary("""{"category": "reference","author": "Nigel Rees","title": "Sayings of the Century","price": 8.95}""")
    @test x[] == Dict{String, Any}("category" => "reference", "author" => "Nigel Rees", "title" => "Sayings of the Century", "price" => 8.95)
    x = JSONBase.binary("\"abc\"")
    # these aren't really part of the public API, but are good for test coverage
    @test JSONBase.applystring(x) do s
        @test JSONBase.tostring(String, s) == "abc"
    end == 5
    pstr, _ = JSONBase.applystring(nothing, x)
    @test JSONBase.Selectors.eq(:abc, "abc")
    @test JSONBase.Selectors.eq(:abc, pstr)
    @test JSONBase.Selectors.eq(pstr, :abc)
    @test JSONBase.Selectors.eq(pstr, pstr)
    @test JSONBase.Selectors.eq("abc", pstr)
    # BinaryObject with all possible JSON types
    x = JSONBase.binary("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [], \"g\": {}}")
    @test length(x) == 7
    if VERSION >= v"1.7"
        @test sprint(show, x) == "BinaryObject with 7 entries:\n  \"a\" => JSONBase.BinaryValue(1)\n  \"b\" => JSONBase.BinaryValue(nothing)\n  \"c\" => JSONBase.BinaryValue(true)\n  \"d\" => JSONBase.BinaryValue(false)\n  \"e\" => JSONBase.BinaryValue(\"\")\n  \"f\" => BinaryValue[]\n  \"g\" => BinaryObject()"
    end
    # BinaryArray with all possible JSON types
    x = JSONBase.binary("[1, null, true, false, \"\", [], {}]")
    @test length(x) == 7
    if VERSION >= v"1.7"
        @test sprint(show, x) == "7-element BinaryArray:\n JSONBase.BinaryValue(1)\n JSONBase.BinaryValue(nothing)\n JSONBase.BinaryValue(true)\n JSONBase.BinaryValue(false)\n JSONBase.BinaryValue(\"\")\n BinaryValue[]\n BinaryObject()"
    end
end

@testset "General JSON" begin
    @testset "errors" for f in (JSONBase.lazy, JSONBase.binary)
        # Unexpected character in array
        @test_throws ArgumentError f("[1,2,3/4,5,6,7]")[]
        # Unexpected character in object
        @test_throws ArgumentError f("{\"1\":2, \"2\":3 _ \"4\":5}")[]
        # Invalid escaped character
        @test_throws ArgumentError f("[\"alpha\\α\"]")[]
        # Invalid 'simple' and 'unknown value'
        @test_throws ArgumentError f("[tXXe]")[]
        @test_throws ArgumentError f("[fail]")[]
        @test_throws ArgumentError f("∞")[]
        # Invalid number
        @test_throws ArgumentError f("[5,2,-]")[]
        @test_throws ArgumentError f("[5,2,+β]")[]
        # Incomplete escape
        @test_throws ArgumentError f("\"\\")[]
        @test_throws ArgumentError f("[\"🍕\"_\"🍕\"")[]
    end # @testset "errors"
end

@testset "JSONBase.Selectors" begin
    # lazy indexing selection support
    # examples from https://support.smartbear.com/alertsite/docs/monitors/api/endpoint/jsonpath.html
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
    # x = JSONBase.lazy(json)
    # x = JSONBase.binary(json)
    for x in (JSONBase.lazy(json), JSONBase.binary(json))
        @test propertynames(x) == [:store, :expensive]
        y = x.store[:][] # All direct properties of store (not recursive).
        @test length(y) == 2 && y[1] isa Vector{Any} && y[2] isa Dict{String, Any}
        y = x.store.bicycle.color[] # The color of the bicycle in the store.
        @test y == "red"
        y = x[~, "price"][] # The prices of all items in the store.
        @test y == [8.95, 8.99, 22.99, 19.95]
        y = x.store.book[:][] # All books in the store.
        @test length(y) == 3 && eltype(y) == Dict{String, Any}
        y = x[~, "book"].title[] # The titles of all books in the store.
        @test y == ["Sayings of the Century", "Moby Dick", "The Lord of the Rings"]
        y = x[~, "book"][1][] # The first book in the store.
        @test y == Dict("category" => "reference", "author" => "Nigel Rees", "title" => "Sayings of the Century", "price" => 8.95)
        y = x[~, "book"][1].author[] # The author of the first book in the store.
        @test y == "Nigel Rees"
        # @test_throws ArgumentError x[~, "book"][1].author[~]
        y = x[~, "book"][:, (i, z) -> z.author[] == "J.R.R. Tolkien"].title[] # The titles of all books by J.R.R. Tolkien
        @test y == ["The Lord of the Rings"]
        y = x[~, :][] # All properties of the root object flattened in one list/array
        @test length(y) == 20
        @test_throws KeyError x.foo
        @test_throws KeyError x.store.book[100]
        list = x.store.book[:]
        @test eltype(list) == Any
        @test isassigned(list, 1)
        @test list[:] === list
        @test length(list[[1, 3]]) == 2
    end
    # test that we correctly skip over all kinds of values
    json = """
    {
        "a": 1,
        "a1": 3.14,
        "a2": 100000000000000000000000,
        "a3": 170141183460469231731687303715884105728,
        "a4": 1.7976931348623157e310,
        "b": null,
        "c": true,
        "d": false,
        "e": "hey there sailor",
        "f": [],
        "g": {},
        "h": [1, 2, 3],
        "i": {"a": 1, "b": 2},
        "j": [1, {"a": 1, "b": 2}, 3],
        "k": {"a": 1, "b": [1, 2, 3]},
        "l": [1, {"a": 1, "b": [1, 2, 3]}, 3],
        "m": {"a": 1, "b": {"a": 1, "b": 2}},
        "n": [1, {"a": 1, "b": {"a": 1, "b": 2}}, 3],
        "o": {"a": 1, "b": {"a": 1, "b": [1, 2, 3]}},
        "p": [1, {"a": 1, "b": {"a": 1, "b": [1, 2, 3]}}, 3],
        "q": {"a": 1, "b": {"a": 1, "b": {"a": 1, "b": 2}}},
        "r": [1, {"a": 1, "b": {"a": 1, "b": {"a": 1, "b": 2}}}, 3],
        "s": {"a": 1, "b": {"a": 1, "b": {"a": 1, "b": [1, 2, 3]}}},
        "t": [1, {"a": 1, "b": {"a": 1, "b": {"a": 1, "b": [1, 2, 3]}}}, 3],
        "z": 602
    }
    """
    for x in (JSONBase.lazy(json), JSONBase.binary(json))
        @test x.z[] == 602
    end
    json = """
    [
        {
            "a": [1, 2, 3]
        },
        {
            "a": [1, 2, 3]
        }
    ]
    """
    for x in (JSONBase.lazy(json), JSONBase.binary(json))
        @test x[~, "a"][] == [1, 2, 3, 1, 2, 3]
        @test x[:].a[] == [[1, 2, 3], [1, 2, 3]]
    end
end

include("struct.jl")
include("json.jl")
include("numbers.jl")
@static if VERSION ≥ v"1.8"
    @testset "Optimization test with JET" include("optimization.jl")
end
