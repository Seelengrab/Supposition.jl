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
        @test ts.result == Some(UInt[1,2,3,4])
    end

    @testset "test function invalid" begin
        ts = TestState(Random.default_rng(), _ -> throw(MiniThesis.Invalid()), 10_000)

        tc = TestCase(UInt[], Random.default_rng(), 10_000)
        @test !first(test_function(ts, tc))
        @test isnothing(ts.result)
    end

    @testset "shrink remove" begin
        ts = TestState(Random.default_rng(), Returns(true), 10_000)
        ts.result = Some(UInt[1,2,3])

        @test shrink_remove(ts, UInt[1,2], UInt(1)) == Some([1])
        @test shrink_remove(ts, UInt[1,2], UInt(2)) == Some(UInt[])

        ts.result = Some(UInt[1,2,3,4,5])
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

    @testset "reduces additive pairs" begin
        function int_sum_greater_1000(tc::TestCase)
            n = choice!(tc, 1_000)
            m = choice!(tc, 1_000)

            return (n+m) > 1_000
        end
        ts = TestState(Random.default_rng(), int_sum_greater_1000, 10_000)
        MiniThesis.run(ts)
        @test ts.result == Some([1,1000])
    end

    @testset "test cases satisfy preconditions" begin
        function test(tc::TestCase)
            n = choice!(tc, 10)
            assume!(tc, !iszero(n))
            iszero(n)
        end
        ts = TestState(Random.default_rng(), test, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
    end

    @testset "finds local maximum" begin
        function test_maxima(tc::TestCase)
            m = Float64(choice!(tc, 1000))
            n = Float64(choice!(tc, 1000))

            score = -((m - 500.0)^2.0 + (n - 500.0)^2.0)
            target!(tc, score)
            return m == 500 || n == 500
        end

        ts = TestState(Random.default_rng(), test_maxima, 10_000)
        MiniThesis.run(ts)
        @test !isnothing(ts.result)
    end

    @testset "can target score upwards to interesting" begin
        function target_upwards(tc::TestCase)
            n = Float64(choice!(tc, 1_000))
            m = Float64(choice!(tc, 1_000))
            score = n+m
            target!(tc, score)
            score >= 2000.0
        end

        ts = TestState(Random.default_rng(), target_upwards, 10_000)
        MiniThesis.run(ts)
        @test !isnothing(ts.result)
    end

    @testset "can target score upwards without failing" begin
        function target_upwards_nofail(tc::TestCase)
            n = Float64(choice!(tc, 1_000))
            m = Float64(choice!(tc, 1_000))
            score = n+m
            target!(tc, score)
            false
        end

        ts = TestState(Random.default_rng(), target_upwards_nofail, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
        @test !isnothing(ts.best_scoring)
        @test first(something(ts.best_scoring)) == 2000.0
    end

    @testset "targeting when most don't benefit" begin
        function no_benefit(tc::TestCase)
            choice!(tc, 1_000)
            choice!(tc, 1_000)
            score = Float64(choice!(tc, 1_000))
            target!(tc, score)
            score >= 1_000
        end

        ts = TestState(Random.default_rng(), no_benefit, 10_000)
        MiniThesis.run(ts)
        @test !isnothing(ts.result)
    end

    @testset "can target score downwards" begin
        function target_downwards(tc::TestCase)
            n = Float64(choice!(tc, 1_000))
            m = Float64(choice!(tc, 1_000))
            score = n+m
            target!(tc, -score)
            score <= 0.0
        end

        ts = TestState(Random.default_rng(), target_downwards, 10_000)
        MiniThesis.run(ts)
        @test !isnothing(ts.result)
        @test !isnothing(ts.best_scoring)
        @test first(something(ts.best_scoring)) == 0.0
    end

    @testset "mapped possibility" begin
        function map_pos(tc::TestCase)
            n = Data.produce(map(n -> 2n, Data.Integers(0, 5)), tc)
            isodd(n)
        end

        ts = TestState(Random.default_rng(), map_pos, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
    end

    @testset "selected possibility" begin
        function sel_pos(tc::TestCase)
            n = Data.produce(Data.satisfying(iseven, Data.Integers(0,5)), tc)
            return isodd(n)
        end

        ts = TestState(Random.default_rng(), sel_pos, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
    end

    @testset "bound possibility" begin
        function bound_pos(tc::TestCase)
            t = Data.produce(Data.bind(Data.Integers(0, 5)) do m
                Data.pairs(Data.just(m), Data.Integers(m, m+10))
            end, tc)
            last(t) < first(t) || (first(t)+10) < last(t)
        end

        ts = TestState(Random.default_rng(), bound_pos, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
    end

    @testset "cannot witness nothing" begin
        function witness_nothing(tc::TestCase)
            Data.produce(nothing, tc)
            return true
        end

        ts = TestState(Random.default_rng(), witness_nothing, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
    end

    @testset "can draw mixture" begin
        function draw_mix(tc::TestCase)
            m = Data.produce(Data.MixOf(Data.Integers(-5, 0), Data.Integers(2,5)), tc)
            return (-5 > m) || (m > 5) || (m == 1)
        end

        ts = TestState(Random.default_rng(), draw_mix, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
    end

    @testset "impossible weighted" begin
        function impos(tc::TestCase)
            for _ in 1:10
                if weighted!(tc, 0.0)
                    @assert false
                end
            end

            return false
        end

        ts = TestState(Random.default_rng(), impos, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
    end

    @testset "guaranteed weighted" begin
        function guaran(tc::TestCase)
            for _ in 1:10
                if !weighted!(tc, 1.0)
                    @assert false
                end
            end

            return false
        end

        ts = TestState(Random.default_rng(), guaran, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
    end

    @testset "size bounds on vectors" begin
        function bounds(tc::TestCase)
            ls = Data.produce(Data.Vectors(Data.Integers(0,10), UInt(1), UInt(3)), tc)
            length(ls) < 1 || 3 < length(ls)
        end

        ts = TestState(Random.default_rng(), bounds, 10_000)
        MiniThesis.run(ts)
        @test isnothing(ts.result)
    end
end
