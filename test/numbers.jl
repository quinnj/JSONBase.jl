using Test, JSONBase

@testset "Numbers tests 1: `$f`" for f in (JSONBase.lazy, JSONBase.binary)
    @test JSONBase.materialize(f("1")) === Int64(1)
    @test JSONBase.materialize(f("1 ")) === Int64(1)
    @test JSONBase.materialize(f("-1")) === Int64(-1)
    @test JSONBase.materialize(f("1.")) === 1.0
    @test JSONBase.materialize(f("-1.")) === -1.0
    @test JSONBase.materialize(f("-1. ")) === -1.0
    @test JSONBase.materialize(f("1.1")) === 1.1
    @test JSONBase.materialize(f("1e1")) === 10.0
    @test JSONBase.materialize(f("1E23")) === 1e23
    # @test JSONBase.materialize(f("1f23")) === 1f23
    # @test JSONBase.materialize(f("1F23")) === 1f23
    @test JSONBase.materialize(f("100000000000000000000000")) === 100000000000000000000000
    for T in (Int8, Int16, Int32, Int64, Int128)
        @test JSONBase.materialize(f(string(T(1)))) == T(1)
        @test JSONBase.materialize(f(string(T(-1)))) == T(-1)
    end
end

@testset "Numbers tests 2: `$f`" for f in (JSONBase.lazy, JSONBase.binary)
    @test JSONBase.materialize(f("428.E+03")) === 428e3
    @test JSONBase.materialize(f("1e+1")) === 10.0
    @test JSONBase.materialize(f("1e-1")) === 0.1
    @test JSONBase.materialize(f("1.1e1")) === 11.0
    @test JSONBase.materialize(f("1.1e+1")) === 11.0
    @test JSONBase.materialize(f("1.1e-1")) === 0.11
    @test JSONBase.materialize(f("1.1e-01")) === 0.11
    @test JSONBase.materialize(f("1.1e-001")) === 0.11
    @test JSONBase.materialize(f("1.1e-0001")) === 0.11
    @test JSONBase.materialize(f("9223372036854775807")) === 9223372036854775807
    @test JSONBase.materialize(f("9223372036854775808")) === 9223372036854775808
    @test JSONBase.materialize(f("170141183460469231731687303715884105727")) === 170141183460469231731687303715884105727
    # only == here because BigInt don't compare w/ ===
    @test JSONBase.materialize(f("170141183460469231731687303715884105728")) == 170141183460469231731687303715884105728
    # BigFloat
    @test JSONBase.materialize(f("1.7976931348623157e310")) == big"1.7976931348623157e310"
end

@testset "Zeros: `$f`" for f in (JSONBase.lazy, JSONBase.binary)
    # zeros
    @test JSONBase.materialize(f("0")) === Int64(0)
    @test JSONBase.materialize(f("0e0")) === 0.0
    @test JSONBase.materialize(f("-0e0")) === -0.0
    @test JSONBase.materialize(f("0e-0")) === 0.0
    @test JSONBase.materialize(f("-0e-0")) === -0.0
    @test JSONBase.materialize(f("0e+0")) === 0.0
    @test JSONBase.materialize(f("-0e+0")) === -0.0
    @test JSONBase.materialize(f("0e+01234567890123456789")) == big"0.0"
    @test JSONBase.materialize(f("0.00e-01234567890123456789")) == big"0.0"
    @test JSONBase.materialize(f("-0e+01234567890123456789")) == big"0.0"
    @test JSONBase.materialize(f("-0.00e-01234567890123456789")) == big"0.0"
    @test JSONBase.materialize(f("0e291")) === 0.0
    @test JSONBase.materialize(f("0e292")) === 0.0
    @test JSONBase.materialize(f("0e347")) == big"0.0"
    @test JSONBase.materialize(f("0e348")) == big"0.0"
    @test JSONBase.materialize(f("-0e291")) === 0.0
    @test JSONBase.materialize(f("-0e292")) === 0.0
    @test JSONBase.materialize(f("-0e347")) == big"0.0"
    @test JSONBase.materialize(f("-0e348")) == big"0.0"
    @test JSONBase.materialize(f("2e-324")) === 0.0
end

@testset "Extremes: `$f`" for f in (JSONBase.lazy, JSONBase.binary)
    @test JSONBase.materialize(f("1e310")) == big"1e310"
    @test JSONBase.materialize(f("-1e310")) == big"-1e310"
    @test JSONBase.materialize(f("1e-305")) === 1e-305
    @test JSONBase.materialize(f("1e-306")) === 1e-306
    @test JSONBase.materialize(f("1e-307")) === 1e-307
    @test JSONBase.materialize(f("1e-308")) === 1e-308
    @test JSONBase.materialize(f("1e-309")) === 1e-309
    @test JSONBase.materialize(f("1e-310")) === 1e-310
    @test JSONBase.materialize(f("1e-322")) === 1e-322
    @test JSONBase.materialize(f("5e-324")) === 5e-324
    @test JSONBase.materialize(f("4e-324")) === 5e-324
    @test JSONBase.materialize(f("3e-324")) === 5e-324
end

@testset "Number errors: `$f`" for f in (JSONBase.lazy, JSONBase.binary)
    @test_throws ArgumentError JSONBase.materialize(f("1e"))
    @test_throws ArgumentError JSONBase.materialize(f("1.0ea"))
    @test_throws ArgumentError JSONBase.materialize(f("1e+"))
    @test_throws ArgumentError JSONBase.materialize(f("1e-"))
    @test_throws ArgumentError JSONBase.materialize(f("."))
    @test_throws ArgumentError JSONBase.materialize(f("1.a"))
    @test_throws ArgumentError JSONBase.materialize(f("1e1."))
    @test_throws ArgumentError JSONBase.materialize(f("-"))
    @test_throws ArgumentError JSONBase.materialize(f("1.1."))
    @test_throws ArgumentError JSONBase.materialize(f("+0e0"))
    @test_throws ArgumentError JSONBase.materialize(f("+0e+0"))
    @test_throws ArgumentError JSONBase.materialize(f("+0e-0"))
    @test_throws ArgumentError JSONBase.materialize(f(".1"))
    @test_throws ArgumentError JSONBase.materialize(f("+1"))
end
