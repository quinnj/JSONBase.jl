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

@testset "JSONBase.tostruct" begin

    obj = JSONBase.tostruct("""{ "a": 1,"b": 2,"c": 3,"d": 4}""", A)
    @test obj == A(1, 2, 3, 4)
    # test order doesn't matter
    obj2 = JSONBase.tostruct("""{ "d": 1,"b": 2,"c": 3,"a": 4}""", A)
    @test obj2 == A(4, 2, 3, 1)
    @test JSONBase.tostruct("{}", C) === C()
end