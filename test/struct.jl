struct A
    a::Int
    b::Int
    c::Int
    d::Int
end

mutable struct B
    a::Int
    b::Int
    c::Int
    d::Int
    B() = new()
end

JSONBase.StructType(::Type{B}) = JSONBase.Mutable()

struct C
end

struct D
    a::Int
    b::Float64
    c::String
end

struct LotsOfFields
    x1::String
    x2::String
    x3::String
    x4::String
    x5::String
    x6::String
    x7::String
    x8::String
    x9::String
    x10::String
    x11::String
    x12::String
    x13::String
    x14::String
    x15::String
    x16::String
    x17::String
    x18::String
    x19::String
    x20::String
    x21::String
    x22::String
    x23::String
    x24::String
    x25::String
    x26::String
    x27::String
    x28::String
    x29::String
    x30::String
    x31::String
    x32::String
    x33::String
    x34::String
    x35::String
end

struct Wrapper
    x::NamedTuple{(:a, :b), Tuple{Int, String}}
end

mutable struct UndefGuy
    id::Int
    name::String
    UndefGuy() = new()
end

struct E
    id::Int
    a::A
end

Base.@kwdef struct F
    id::Int
    rate::Float64
    name::String
end

JSONBase.StructType(::Type{F}) = JSONBase.KwDef()

Base.@kwdef struct G
    id::Int
    rate::Float64
    name::String
    f::F
end

@testset "JSONBase.tostruct" begin
    obj = JSONBase.tostruct("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", A)
    @test obj == A(1, 2, 3, 4)
    # test order doesn't matter
    obj2 = JSONBase.tostruct("""{ "d": 1,"b": 2,"c": 3,"a": 4}""", A)
    @test obj2 == A(4, 2, 3, 1)
    # NamedTuple
    obj = JSONBase.tostruct("""{ "d": 1,"b": 2,"c": 3,"a": 4}""", NamedTuple{(:a, :b, :c, :d), Tuple{Int, Int, Int, Int}})
    @test obj == (a = 4, b = 2, c = 3, d = 1)
    @test JSONBase.tostruct("{}", C) === C()
    obj = JSONBase.tostruct!("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", B)
    @test obj.a == 1 && obj.b == 2 && obj.c == 3 && obj.d == 4
    obj = JSONBase.tostruct("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", B)
    @test obj.a == 1 && obj.b == 2 && obj.c == 3 && obj.d == 4
    obj = JSONBase.tostruct("""{ "a": 1,"b": 2.0,"c": "3"}""", D)
    @test obj == D(1, 2.0, "3")
    obj = JSONBase.tostruct("""{ "x1": "1","x2": "2","x3": "3","x4": "4","x5": "5","x6": "6","x7": "7","x8": "8","x9": "9","x10": "10","x11": "11","x12": "12","x13": "13","x14": "14","x15": "15","x16": "16","x17": "17","x18": "18","x19": "19","x20": "20","x21": "21","x22": "22","x23": "23","x24": "24","x25": "25","x26": "26","x27": "27","x28": "28","x29": "29","x30": "30","x31": "31","x32": "32","x33": "33","x34": "34","x35": "35"}""", LotsOfFields)
    @test obj == LotsOfFields("1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35")
    obj = JSONBase.tostruct("""{ "x": {"a": 1, "b": "2"}}""", Wrapper)
    @test obj == Wrapper((a=1, b="2"))
    obj = JSONBase.tostruct!("""{ "id": 1, "name": "2"}""", UndefGuy)
    @test obj.id == 1 && obj.name == "2"
    obj = JSONBase.tostruct!("""{ "id": 1}""", UndefGuy)
    @test obj.id == 1 && !isdefined(obj, :name)
    obj = JSONBase.tostruct("""{ "id": 1, "a": {"a": 1, "b": 2, "c": 3, "d": 4}}""", E)
    @test obj == E(1, A(1, 2, 3, 4))
    obj = JSONBase.tostruct("""{ "id": 1, "rate": 2.0, "name": "3"}""", F)
    @test obj == F(1, 2.0, "3")
    obj = JSONBase.tokwstruct("""{ "id": 1, "rate": 2.0, "name": "3", "f": {"id": 1, "rate": 2.0, "name": "3"}}""", G)
end
