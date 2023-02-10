using Test, JSONBase

@testset "JSONBase.parsenumber conversion" begin
    @test JSONBase.togeneric(JSONBase.tolazy("1")) === Int64(1)
    @test JSONBase.togeneric(JSONBase.tolazy("1 ")) === Int64(1)
    @test JSONBase.togeneric(JSONBase.tolazy("-1")) === Int64(-1)
    @test JSONBase.togeneric(JSONBase.tolazy("1.")) === 1.0
    @test JSONBase.togeneric(JSONBase.tolazy("-1.")) === -1.0
    @test JSONBase.togeneric(JSONBase.tolazy("-1. ")) === -1.0
    @test JSONBase.togeneric(JSONBase.tolazy("1.1")) === 1.1
    @test JSONBase.togeneric(JSONBase.tolazy("1e1")) === 10.0
    @test JSONBase.togeneric(JSONBase.tolazy("1E23")) === 1e23
    @test JSONBase.togeneric(JSONBase.tolazy("1f23")) === 1f23
    @test JSONBase.togeneric(JSONBase.tolazy("1F23")) === 1f23
    @test JSONBase.togeneric(JSONBase.tolazy("100000000000000000000000")) === 100000000000000000000000

    @test JSONBase.togeneric(JSONBase.tolazy("428.E+03")) === 428e3
    @test JSONBase.togeneric(JSONBase.tolazy("1e+1")) === 10.0
    @test JSONBase.togeneric(JSONBase.tolazy("1e-1")) === 0.1
    @test JSONBase.togeneric(JSONBase.tolazy("1.1e1")) === 11.0
    @test JSONBase.togeneric(JSONBase.tolazy("1.1e+1")) === 11.0
    @test JSONBase.togeneric(JSONBase.tolazy("1.1e-1")) === 0.11
    @test JSONBase.togeneric(JSONBase.tolazy("1.1e-01")) === 0.11
    @test JSONBase.togeneric(JSONBase.tolazy("1.1e-001")) === 0.11
    @test JSONBase.togeneric(JSONBase.tolazy("1.1e-0001")) === 0.11
    @test JSONBase.togeneric(JSONBase.tolazy("9223372036854775807")) === 9223372036854775807
    @test JSONBase.togeneric(JSONBase.tolazy("9223372036854775808")) === 9223372036854775808
    @test JSONBase.togeneric(JSONBase.tolazy("170141183460469231731687303715884105727")) === 170141183460469231731687303715884105727
    # only == here because BigInt don't compare w/ ===
    @test JSONBase.togeneric(JSONBase.tolazy("170141183460469231731687303715884105728")) == 170141183460469231731687303715884105728

    # zeros
    @test JSONBase.togeneric(JSONBase.tolazy("0")) === 0
    @test JSONBase.togeneric(JSONBase.tolazy("0e0")) === 0.0
    @test JSONBase.togeneric(JSONBase.tolazy("-0e0")) === -0.0
    @test JSONBase.togeneric(JSONBase.tolazy("0e-0")) === 0.0
    @test JSONBase.togeneric(JSONBase.tolazy("-0e-0")) === -0.0
    @test JSONBase.togeneric(JSONBase.tolazy("0e+0")) === 0.0
    @test JSONBase.togeneric(JSONBase.tolazy("-0e+0")) === -0.0
    @test JSONBase.togeneric(JSONBase.tolazy("0e+01234567890123456789")) == big"0.0"
    @test JSONBase.togeneric(JSONBase.tolazy("0.00e-01234567890123456789")) == big"0.0"
    @test JSONBase.togeneric(JSONBase.tolazy("-0e+01234567890123456789")) == big"0.0"
    @test JSONBase.togeneric(JSONBase.tolazy("-0.00e-01234567890123456789")) == big"0.0"
    @test JSONBase.togeneric(JSONBase.tolazy("0e291")) === 0.0
    @test JSONBase.togeneric(JSONBase.tolazy("0e292")) === 0.0
    @test JSONBase.togeneric(JSONBase.tolazy("0e347")) == big"0.0"
    @test JSONBase.togeneric(JSONBase.tolazy("0e348")) == big"0.0"
    @test JSONBase.togeneric(JSONBase.tolazy("-0e291")) === 0.0
    @test JSONBase.togeneric(JSONBase.tolazy("-0e292")) === 0.0
    @test JSONBase.togeneric(JSONBase.tolazy("-0e347")) == big"0.0"
    @test JSONBase.togeneric(JSONBase.tolazy("-0e348")) == big"0.0"
    @test JSONBase.togeneric(JSONBase.tolazy("1e310")) == big"1e310"
    @test JSONBase.togeneric(JSONBase.tolazy("-1e310")) == big"-1e310"
    @test JSONBase.togeneric(JSONBase.tolazy("1e-305")) === 1e-305
    @test JSONBase.togeneric(JSONBase.tolazy("1e-306")) === 1e-306
    @test JSONBase.togeneric(JSONBase.tolazy("1e-307")) === 1e-307
    @test JSONBase.togeneric(JSONBase.tolazy("1e-308")) === 1e-308
    @test JSONBase.togeneric(JSONBase.tolazy("1e-309")) === 1e-309
    @test JSONBase.togeneric(JSONBase.tolazy("1e-310")) === 1e-310
    @test JSONBase.togeneric(JSONBase.tolazy("1e-322")) === 1e-322
    @test JSONBase.togeneric(JSONBase.tolazy("5e-324")) === 5e-324
    @test JSONBase.togeneric(JSONBase.tolazy("4e-324")) === 5e-324
    @test JSONBase.togeneric(JSONBase.tolazy("3e-324")) === 5e-324
    @test JSONBase.togeneric(JSONBase.tolazy("2e-324")) === 0.0

    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("1e"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("1.0ea"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("1e+"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("1e-"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("."))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("1.a"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("1e1."))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("-"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("1.1."))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("+0e0"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("+0e+0"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("+0e-0"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy(".1"))
    @test_throws ArgumentError JSONBase.togeneric(JSONBase.tolazy("+1"))
end
