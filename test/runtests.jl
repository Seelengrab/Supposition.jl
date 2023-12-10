using MiniThesis
using MiniThesis: Data, test_function, shrink_remove, shrink_redistribute
using Test
using Aqua
using Random
using Logging

function sum_greater_1000(tc::TestCase)
    ls = Data.produce(Data.Vectors(Data.Integers(0, 10_000), UInt(0), UInt(1_000)), tc)
    sum(ls) > 1_000
end

@testset "MiniThesis.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(MiniThesis; ambiguities = false,)
    end
    # Write your tests here.
    @testset "test function interesting" begin
        ts = TestState(Random.default_rng(), Returns(true), 10_000)
        tc = TestCase(UInt[], Random.default_rng(), 10_000)
        @test first(test_function(ts, tc))
        @test ts.result == Some([])

        ts.result = Some([1,2,3,4])
        tc = TestCase(UInt[], Random.default_rng(), 10_000)
        @test first(test_function(ts, tc))
        @test ts.result == Some([])

        tc = TestCase(UInt[1,2,3,4], Random.default_rng(), 10_000)
        @test !first(test_function(ts, tc))
        @test ts.result == Some([])
    end

    @testset "test function valid" begin
        ts = TestState(Random.default_rng(), Returns(false), 10_000)

        tc = TestCase(UInt[], Random.default_rng(), 10_000)
        @test !first(test_function(ts, tc))
        @test isnothing(ts.result)

        ts.result = Some([1,2,3,4])
        test_function(ts, TestCase(UInt[], Random.default_rng(), 10_000))
        @test ts.result == Some([1,2,3,4])
    end

    @testset "test function invalid" begin
        ts = TestState(Random.default_rng(), _ -> throw(MiniThesis.Invalid()), 10_000)

        tc = TestCase(UInt[], Random.default_rng(), 10_000)
        @test !first(test_function(ts, tc))
        @test isnothing(ts.result)
    end

    @testset "shrink remove" begin
        ts = TestState(Random.default_rng(), Returns(true), 10_000)
        ts.result = Some([1,2,3])

        @test shrink_remove(ts, UInt[1,2], UInt(1)) == Some([1])
        @test shrink_remove(ts, UInt[1,2], UInt(2)) == Some(UInt[])

        ts.result = Some([1,2,3,4,5])
        @test shrink_remove(ts, UInt[1,2,3,4], UInt(2)) == Some([1,2])

        function second_is_five(tc::TestCase)
            ls = [ choice!(tc, 10) for _ in 1:3 ]
            last(ls) == 5
        end
        ts = TestState(Random.default_rng(), second_is_five, 10_000)
        ts.result = Some(UInt[1,2,5,4,5])
        @test shrink_remove(ts, UInt[1,2,5,4,5], UInt(2)) == Some(UInt[1,2,5])

        ts = TestState(Random.default_rng(), sum_greater_1000, 10_000)
        ts.result = Some(UInt[1,10_000,1,10_000])
        @test shrink_remove(ts, UInt[1,0,1,1001,0], UInt(2)) == Some(UInt[1,1001,0])

        ts.result = Some(UInt[1,10_000,1,10_000])
        @test isnothing(shrink_remove(ts, UInt[1,0,1,1001,0], UInt(1)))
    end

    @testset "shrink redistribute" begin
        ts = TestState(Random.default_rng(), Returns(true), 10_000)

        ts.result = Some(UInt[500,500,500,500])
        @test shrink_redistribute(ts, UInt[500,500], UInt(1)) == Some(UInt[0, 1000])

        ts.result = Some(UInt[500,500,500,500])
        @test shrink_redistribute(ts, UInt[500,500,500], UInt(2)) == Some(UInt[0, 500, 1000])
    end

    @testset "finds small list" begin
        ts = TestState(Random.default_rng(), sum_greater_1000, 10_000)
        MiniThesis.run(ts)
        @test ts.result == Some([1,1001,0])
    end

    @testset "finds small list debug" begin
        ts = TestState(Random.default_rng(), sum_greater_1000, 10_000)
        ts.result = Some(UInt[1,0,1,1001,0])
        @test shrink_remove(ts, UInt[1,0,1,1001,0], UInt(2)) == Some([1,1001,0])
        @test ts.result == Some(UInt[1,1001,0])
    end

    @testset "finds small list even with bad lists" begin
        struct BadList <: Data.Possibility{Vector{Int64}} end
        function produce(::BadList, tc::TestCase)
            n = choice!(tc, 10)
            [ choice!(tc, 10_000) for _ in 1:n ]
        end

        function bl_sum_greater_1000(tc::TestCase)
            ls = produce(BadList(), tc)
            sum(ls) > 1000
        end

        ts = TestState(Random.default_rng(), bl_sum_greater_1000, 10_000)
        MiniThesis.run(ts)
        @test ts.result == Some(UInt[1,1001])
    end
end
