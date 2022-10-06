using Test, JSONBase

@testset "Number(::Number) conversion" begin

    @test Number(JSONBase.lazy("1")) === Int64(1)
    @test Number(JSONBase.lazy("1 ")) === Int64(1)
    @test Number(JSONBase.lazy("+1")) === Int64(1)
    @test Number(JSONBase.lazy("-1")) === Int64(-1)
    @test Number(JSONBase.lazy("1.")) === 1.0
    @test Number(JSONBase.lazy("-1.")) === -1.0
    @test Number(JSONBase.lazy("-1. ")) === -1.0
    @test Number(JSONBase.lazy("1.1")) === 1.1
    @test Number(JSONBase.lazy("1e1")) === 10.0
    @test Number(JSONBase.lazy("1E23")) === 1e23
    @test Number(JSONBase.lazy("1f23")) === 1e23
    @test Number(JSONBase.lazy("1F23")) === 1e23
    @test Number(JSONBase.lazy("100000000000000000000000")) === 100000000000000000000000

    @test Number(JSONBase.lazy("428.E+03")) === 428e3
    @test Number(JSONBase.lazy("1e+1")) === 10.0
    @test Number(JSONBase.lazy("1e-1")) === 0.1
    @test Number(JSONBase.lazy("1.1e1")) === 11.0
    @test Number(JSONBase.lazy("1.1e+1")) === 11.0
    @test Number(JSONBase.lazy("1.1e-1")) === 0.11
    @test Number(JSONBase.lazy("1.1e-01")) === 0.11
    @test Number(JSONBase.lazy("1.1e-001")) === 0.11
    @test Number(JSONBase.lazy("1.1e-0001")) === 0.11
    @test Number(JSONBase.lazy("9223372036854775807")) === 9223372036854775807
    @test Number(JSONBase.lazy("9223372036854775808")) === 9223372036854775808
    @test Number(JSONBase.lazy("170141183460469231731687303715884105727")) === 170141183460469231731687303715884105727
    # only == here because BigInt don't compare w/ ===
    @test Number(JSONBase.lazy("170141183460469231731687303715884105728")) == 170141183460469231731687303715884105728
    @test Number(JSONBase.lazy(".1")) === 0.1

    # zeros
    @test Number(JSONBase.lazy("0")) === 0
    @test Number(JSONBase.lazy("0e0")) === 0.0
    @test Number(JSONBase.lazy("-0e0")) === -0.0
    @test Number(JSONBase.lazy("+0e0")) === 0.0
    @test Number(JSONBase.lazy("0e-0")) === 0.0
    @test Number(JSONBase.lazy("-0e-0")) === -0.0
    @test Number(JSONBase.lazy("+0e-0")) === 0.0
    @test Number(JSONBase.lazy("0e+0")) === 0.0
    @test Number(JSONBase.lazy("-0e+0")) === -0.0
    @test Number(JSONBase.lazy("+0e+0")) === 0.0
    @test Number(JSONBase.lazy("0e+01234567890123456789")) === 0.0
    @test Number(JSONBase.lazy("0.00e-01234567890123456789")) === 0.0
    @test Number(JSONBase.lazy("-0e+01234567890123456789")) === 0.0
    @test Number(JSONBase.lazy("-0.00e-01234567890123456789")) === 0.0
    @test Number(JSONBase.lazy("0e291")) === 0.0
    @test Number(JSONBase.lazy("0e292")) === 0.0
    @test Number(JSONBase.lazy("0e347")) === 0.0
    @test Number(JSONBase.lazy("0e348")) === 0.0
    @test Number(JSONBase.lazy("-0e291")) === 0.0
    @test Number(JSONBase.lazy("-0e292")) === 0.0
    @test Number(JSONBase.lazy("-0e347")) === 0.0
    @test Number(JSONBase.lazy("-0e348")) === 0.0
    @test Number(JSONBase.lazy("1e310")) === Inf
    @test Number(JSONBase.lazy("-1e310")) === -Inf
    @test Number(JSONBase.lazy("1e-305")) === 1e-305
    @test Number(JSONBase.lazy("1e-306")) === 1e-306
    @test Number(JSONBase.lazy("1e-307")) === 1e-307
    @test Number(JSONBase.lazy("1e-308")) === 1e-308
    @test Number(JSONBase.lazy("1e-309")) === 1e-309
    @test Number(JSONBase.lazy("1e-310")) === 1e-310
    @test Number(JSONBase.lazy("1e-322")) === 1e-322
    @test Number(JSONBase.lazy("5e-324")) === 5e-324
    @test Number(JSONBase.lazy("4e-324")) === 5e-324
    @test Number(JSONBase.lazy("3e-324")) === 5e-324
    @test Number(JSONBase.lazy("2e-324")) === 0.0

    @test_throws ArgumentError Number(JSONBase.lazy("1e"))
    @test_throws ArgumentError Number(JSONBase.lazy("1.0ea"))
    @test_throws ArgumentError Number(JSONBase.lazy("1e+"))
    @test_throws ArgumentError Number(JSONBase.lazy("1e-"))
    @test_throws ArgumentError Number(JSONBase.lazy("."))
    @test_throws ArgumentError Number(JSONBase.lazy("1.a"))
    @test_throws ArgumentError Number(JSONBase.lazy("1e1."))
    @test_throws ArgumentError Number(JSONBase.lazy("-"))
    @test_throws ArgumentError Number(JSONBase.lazy("1.1."))
end

@testset "Other number conversions" begin

    for T in (Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128)
        @test T(JSONBase.lazy("1")) === T(1)
        @test T(JSONBase.lazy("1 ")) === T(1)
    end
    @test_throws ArgumentError Int8(JSONBase.lazy("1000"))
    @test_throws ArgumentError UInt8(JSONBase.lazy("1000"))
    @test BigInt(JSONBase.lazy("1")) == BigInt(1)
    @test BigFloat(JSONBase.lazy("1 ")) == BigFloat(1)
end