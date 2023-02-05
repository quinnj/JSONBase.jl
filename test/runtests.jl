using Test, JSONBase #, BenchmarkTools, JSON

@testset "JSONBase.tolazy" begin
    make(::Type{String}, x) = x
    make(::Type{SubString{String}}, x) = SubString(x)
    make(::Type{Vector{UInt8}}, x) = Vector{UInt8}(x)
    make(::Type{IOBuffer}, x) = IOBuffer(x)
    for T in (String, SubString{String}, IOBuffer, Vector{UInt8})
        @test JSONBase.gettype(JSONBase.tolazy(make(T, "1"))) == JSONBase.JSONType.NUMBER
        @test JSONBase.gettype(JSONBase.tolazy(make(T, "true"))) == JSONBase.JSONType.TRUE
        @test JSONBase.gettype(JSONBase.tolazy(make(T, "false"))) == JSONBase.JSONType.FALSE
        @test JSONBase.gettype(JSONBase.tolazy(make(T, "null"))) == JSONBase.JSONType.NULL
        @test JSONBase.gettype(JSONBase.tolazy(make(T, "[]"))) == JSONBase.JSONType.ARRAY
        @test JSONBase.gettype(JSONBase.tolazy(make(T, "{}"))) == JSONBase.JSONType.OBJECT
        @test JSONBase.gettype(JSONBase.tolazy(make(T, "\"\""))) == JSONBase.JSONType.STRING
        @test_throws ArgumentError JSONBase.tolazy(make(T, "a"))
    end
    x = JSONBase.togeneric("{}")
    @test isempty(x) && typeof(x) == Dict{String, Any}
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.LazyValue(".", 1, JSONBase.JSONType.OBJECT))
    x = JSONBase.togeneric("{\"a\": 1}")
    @test !isempty(x) && x["a"] == 1 && typeof(x) == Dict{String, Any}
    x = JSONBase.togeneric("{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": \"\", \"f\": [], \"g\": {}}")
    @test !isempty(x) && x["a"] == 1 && x["b"] === nothing && x["c"] === true && x["d"] === false && x["e"] == "" && x["f"] == Any[] && x["g"] == Dict{String, Any}()
    x = JSONBase.togeneric("[]")
    @test isempty(x) && x == Any[]
    x = JSONBase.togeneric("[1, null, true, false, \"\", [], {}]")
    @test !isempty(x) && x[1] == 1 && x[2] === nothing && x[3] === true && x[4] === false && x[5] == "" && x[6] == Any[] && x[7] == Dict{String, Any}()
    x = JSONBase.togeneric("1")
    @test x == 1
    x = JSONBase.togeneric("true")
    @test x === true
    x = JSONBase.togeneric("false")
    @test x === false
    x = JSONBase.togeneric("null")
    @test x === nothing
    x = JSONBase.togeneric("\"\"")
    @test x == ""
    x = JSONBase.togeneric("\"a\"")
    @test x == "a"
    x = JSONBase.togeneric("\"\\\"\"")
    @test x == "\""
    x = JSONBase.togeneric("\"\\\\\"")
    @test x == "\\"
    x = JSONBase.togeneric("\"\\/\"")
    @test x == "/"
    x = JSONBase.togeneric("\"\\b\"")
    @test x == "\b"
    x = JSONBase.togeneric("\"\\f\"")
    @test x == "\f"
    x = JSONBase.togeneric("\"\\n\"")
    @test x == "\n"
    x = JSONBase.togeneric("\"\\r\"")
    @test x == "\r"
    x = JSONBase.togeneric("\"\\t\"")
    @test x == "\t"
    x = JSONBase.togeneric("\"\\u0000\"")
    @test x == "\0"
    x = JSONBase.togeneric("\"\\uD83D\\uDE00\"")
    @test x == "😀"
    x = JSONBase.togeneric("\"\\u0061\"")
    @test x == "a"
    x = JSONBase.togeneric("\"\\u2028\"")
    @test x == "\u2028"
    x = JSONBase.togeneric("\"\\u2029\"")
    @test x == "\u2029"
    @test_throws ArgumentError JSONBase.togeneric("nula")
    @test_throws ArgumentError JSONBase.togeneric("nul")
    @test_throws ArgumentError JSONBase.togeneric("trub")
end

@testset "BJSONValue" begin
    @testset "BJSONMeta" begin
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
        bm = JSONBase.BJSONMeta(JSONBase.BJSONType.OBJECT)
        @test bm.type == JSONBase.BJSONType.OBJECT
        @test bm.size.is_size_embedded
    end

    make(::Type{String}, x) = x
    make(::Type{SubString{String}}, x) = SubString(x)
    make(::Type{Vector{UInt8}}, x) = Vector{UInt8}(x)
    make(::Type{IOBuffer}, x) = IOBuffer(x)
    for T in (String, SubString{String}, IOBuffer, Vector{UInt8})
        @test JSONBase.tobjson(make(T, "{}"))[] == Dict{String, Any}()
        @test JSONBase.tobjson(make(T, "1"))[] == 1
        @test JSONBase.tobjson(make(T, "3.14"))[] == 3.14
        @test JSONBase.tobjson(make(T, "true"))[] == true
        @test JSONBase.tobjson(make(T, "false"))[] == false
        @test JSONBase.tobjson(make(T, "null"))[] === nothing
        @test JSONBase.tobjson(make(T, "[]"))[] == Any[]
        @test JSONBase.tobjson(make(T, "\"\""))[] == ""
        @test_throws ArgumentError JSONBase.tobjson(make(T, "a"))
    end
    x = JSONBase.tobjson(""" {"a": 1, "b": null, "c": true, "d": false, "e": "hey there sailor", "f": [], "g": {}} """)
    @test x[] == Dict{String, Any}("a" => 1, "b" => nothing, "c" => true, "d" => false, "e" => "hey there sailor", "f" => Any[], "g" => Dict{String, Any}())
    x = JSONBase.tobjson("""{"category": "reference","author": "Nigel Rees","title": "Sayings of the Century","price": 8.95}""")
    @test x[] == Dict{String, Any}("category" => "reference", "author" => "Nigel Rees", "title" => "Sayings of the Century", "price" => 8.95)
end

@testset "General JSON" begin
    @testset "errors" for f in (JSONBase.tolazy, JSONBase.tobjson)
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
    # x = JSONBase.tolazy(json)
    # x = JSONBase.tobjson(json)
    for x in (JSONBase.tolazy(json), JSONBase.tobjson(json))
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
        @test_throws ArgumentError x[~, "book"][1].author[~]
        y = x[~, "book"][:, (i, z) -> z.author[] == "J.R.R. Tolkien"].title[] # The titles of all books by J.R.R. Tolkien
        @test y == ["The Lord of the Rings"]
        y = x[~, :][] # All properties of the root object flattened in one list/array
        @test length(y) == 20
        @test_throws KeyError x.foo
        @test_throws KeyError x.store.book[100]
    end
end
