using JSONBase, Test

mutable struct CircularRef
    id::Int
    self::Union{Nothing, CircularRef}
end

JSONBase.lower(::Type{ThreeDates}, nm::Symbol, val) =
    nm == :date ? Dates.format(val, "yyyy_mm_dd") :
    nm == :datetime ? Dates.format(val, "yyyy/mm/dd HH:MM:SS") :
    Dates.format(val, "HH/MM/SS")

@testset "JSON output" begin
    @test JSONBase.json(nothing) == "null"
    @test JSONBase.json(true) == "true"
    @test JSONBase.json(false) == "false"
    # test the JSON output of a bunch of numbers
    @test JSONBase.json(0) == "0"
    @test JSONBase.json(1) == "1"
    @test JSONBase.json(1.0) == "1.0"
    @test JSONBase.json(1.0f0) == "1.0"
    @test JSONBase.json(1.0f1) == "10.0"
    @test JSONBase.json(1.0f-1) == "0.1"
    @test JSONBase.json(1.0f-2) == "0.01"
    @test JSONBase.json(1.0f-3) == "0.001"
    @test JSONBase.json(1.0f-4) == "0.0001"
    @test JSONBase.json(1.0f-5) == "1.0e-5"
    @test JSONBase.json(-1) == "-1"
    @test JSONBase.json(-1.0) == "-1.0"
    @test JSONBase.json(typemin(Int64)) == "-9223372036854775808"
    @test JSONBase.json(typemax(Int64)) == "9223372036854775807"
    @test JSONBase.json(BigInt(1)) == "1"
    @test JSONBase.json(BigInt(1) << 100) == "1267650600228229401496703205376"
    @test JSONBase.json(BigInt(-1)) == "-1"
    @test JSONBase.json(BigInt(-1) << 100) == "-1267650600228229401496703205376"
    @test JSONBase.json(typemin(UInt64)) == "0"
    @test JSONBase.json(typemax(UInt64)) == "18446744073709551615"
    @test_throws ArgumentError JSONBase.json(NaN)
    @test_throws ArgumentError JSONBase.json(Inf)
    @test_throws ArgumentError JSONBase.json(-Inf)
    @test JSONBase.json(NaN; allownan=true) == "NaN"
    @test JSONBase.json(Inf; allownan=true) == "Infinity"
    @test JSONBase.json(-Inf; allownan=true) == "-Infinity"
    # test the JSON output of a bunch of strings
    @test JSONBase.json("") == "\"\""
    @test JSONBase.json("a") == "\"a\""
    @test JSONBase.json("a\"b") == "\"a\\\"b\""
    @test JSONBase.json("a\\b") == "\"a\\\\b\""
    @test JSONBase.json("a\b") == "\"a\\b\""
    @test JSONBase.json("a\f") == "\"a\\f\""
    # test the JSON output of a bunch of strings with unicode characters
    @test JSONBase.json("\u2200") == "\"∀\""
    @test JSONBase.json("\u2200\u2201") == "\"∀∁\""
    @test JSONBase.json("\u2200\u2201\u2202") == "\"∀∁∂\""
    @test JSONBase.json("\u2200\u2201\u2202\u2203") == "\"∀∁∂∃\""
    # test the JSON output of a bunch of arrays
    @test JSONBase.json(Int[]) == "[]"
    @test JSONBase.json(Int[1]) == "[1]"
    @test JSONBase.json(Int[1, 2]) == "[1,2]"
    @test JSONBase.json((1, 2)) == "[1,2]"
    @test JSONBase.json(Set([2])) == "[2]"
    @test JSONBase.json([1, nothing, "hey", 3.14, true, false]) == "[1,null,\"hey\",3.14,true,false]"
    # test the JSON output of a bunch of dicts/namedtuples
    @test JSONBase.json(Dict{Int, Int}()) == "{}"
    @test JSONBase.json(Dict{Int, Int}(1 => 2)) == "{\"1\":2}"
    @test JSONBase.json((a = 1, b = 2)) == "{\"a\":1,\"b\":2}"
    @test JSONBase.json((a = nothing, b=2, c="hey", d=3.14, e=true, f=false)) == "{\"a\":null,\"b\":2,\"c\":\"hey\",\"d\":3.14,\"e\":true,\"f\":false}"
    # test the JSON output of nested array/objects
    @test JSONBase.json([1, [2, 3], [4, [5, 6]]]) == "[1,[2,3],[4,[5,6]]]"
    @test JSONBase.json(Dict{Int, Any}(1 => Dict{Int, Any}(2 => Dict{Int, Any}(3 => 4)))) == "{\"1\":{\"2\":{\"3\":4}}}"
    # now a mix of arrays and objects
    @test JSONBase.json([1, Dict{Int, Any}(2 => Dict{Int, Any}(3 => 4))]) == "[1,{\"2\":{\"3\":4}}]"
    @test JSONBase.json(Dict{Int, Any}(1 => [2, Dict{Int, Any}(3 => 4)])) == "{\"1\":[2,{\"3\":4}]}"
    # test undefined elements of an array
    arr = Vector{String}(undef, 3)
    arr[1] = "a"
    arr[3] = "b"
    @test JSONBase.json(arr) == "[\"a\",null,\"b\"]"
    # test custom struct writing
    # defined in the test/struct.jl file
    a = A(1, 2, 3, 4)
    @test JSONBase.json(a) == "{\"a\":1,\"b\":2,\"c\":3,\"d\":4}"
    x = LotsOfFields("1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35")
    @test JSONBase.json(x) == "{\"x1\":\"1\",\"x2\":\"2\",\"x3\":\"3\",\"x4\":\"4\",\"x5\":\"5\",\"x6\":\"6\",\"x7\":\"7\",\"x8\":\"8\",\"x9\":\"9\",\"x10\":\"10\",\"x11\":\"11\",\"x12\":\"12\",\"x13\":\"13\",\"x14\":\"14\",\"x15\":\"15\",\"x16\":\"16\",\"x17\":\"17\",\"x18\":\"18\",\"x19\":\"19\",\"x20\":\"20\",\"x21\":\"21\",\"x22\":\"22\",\"x23\":\"23\",\"x24\":\"24\",\"x25\":\"25\",\"x26\":\"26\",\"x27\":\"27\",\"x28\":\"28\",\"x29\":\"29\",\"x30\":\"30\",\"x31\":\"31\",\"x32\":\"32\",\"x33\":\"33\",\"x34\":\"34\",\"x35\":\"35\"}"
    # test custom struct writing with custom field names
    x = L(1, "george", 33.3)
    @test JSONBase.json(x) == "{\"id\":1,\"firstName\":\"george\",\"rate\":33.3}"
    # test custom struct writing with undef fields
    x = UndefGuy()
    x.id = 10
    @test JSONBase.json(x) == "{\"id\":10,\"name\":null}"
    # test structs with circular references
    x = CircularRef(11, nothing)
    x.self = x
    @test JSONBase.json(x) == "{\"id\":11,\"self\":null}"
    # test lowering
    x = K(123, missing)
    @test JSONBase.json(x) == "{\"id\":123,\"value\":null}"
    x = UUID(typemax(UInt128))
    @test JSONBase.json(x) == "\"ffffffff-ffff-ffff-ffff-ffffffffffff\""
    @test JSONBase.json(:a) == "\"a\""
    @test JSONBase.json(apple) == "\"apple\""
    @test JSONBase.json('a') == "\"a\""
    @test JSONBase.json('∀') == "\"∀\""
    @test JSONBase.json(v"1.2.3") == "\"1.2.3\""
    @test JSONBase.json(r"1.2.3") == "\"1.2.3\""
    @test JSONBase.json(Date(2023, 2, 23)) == "\"2023-02-23\""
    @test JSONBase.json(DateTime(2023, 2, 23, 12, 34, 56)) == "\"2023-02-23T12:34:56\""
    @test JSONBase.json(Time(12, 34, 56)) == "\"12:34:56\""
    # test field-specific lowering
    x = ThreeDates(Date(2023, 2, 23), DateTime(2023, 2, 23, 12, 34, 56), Time(12, 34, 56))
    @test JSONBase.json(x) == "{\"date\":\"2023_02_23\",\"datetime\":\"2023/02/23 12:34:56\",\"time\":\"12/34/56\"}"
    # test matrix writing
    @test JSONBase.json([1 2; 3 4]) == "[[1,3],[2,4]]"
    @test JSONBase.json((a=[1 2; 3 4],)) == "{\"a\":[[1,3],[2,4]]}"
    # singleton writing
    @test JSONBase.json(C()) == "\"C()\""
end
