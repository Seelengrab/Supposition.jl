using Supposition
using Supposition: Data, test_function, shrink_remove, shrink_redistribute, NoRecordDB
using Test
using Aqua
using Random
using Logging
using Statistics: mean
using .Threads: @spawn
import RequiredInterfaces
const RI = RequiredInterfaces

function sum_greater_1000(tc::TestCase)
    ls = Data.produce(Data.Vectors(Data.Integers(0, 10_000); min_size=UInt(0), max_size=UInt(1_000)), tc)
    sum(ls) > 1_000
end

# whether printing of `@check` should be verbose or not
# this is only used because otherwise, there's no way to tell
# whether the tests actually passed on earlier versions
const verb = VERSION.major == 1 && VERSION.minor < 11

@testset "Supposition.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Supposition; ambiguities = false, stale_deps=false)
        # stdlib woes?
        ignore = VERSION >= v"1.11" ? [:ScopedValues] : Symbol[]
        Aqua.test_stale_deps(Supposition; ignore)
    end
    @testset "Interfaces" begin
        @testset "Possibility" RI.check_implementations(Supposition.Data.Possibility)
        @testset "ExampleDB" RI.check_implementations(Supposition.ExampleDB)
    end
    # Write your tests here.
    @testset "test function interesting" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(true))
        tc = TestCase(UInt[], Random.default_rng(), 10_000)
        @test first(test_function(ts, tc))
        @test @something(ts.result) == []

        ts.result = Some([1,2,3,4])
        tc = TestCase(UInt[], Random.default_rng(), 10_000)
        @test first(test_function(ts, tc))
        @test @something(ts.result) == []

        tc = TestCase(UInt[1,2,3,4], Random.default_rng(), 10_000)
        @test !first(test_function(ts, tc))
        @test @something(ts.result) == []
    end

    @testset "test function valid" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(false))

        tc = TestCase(UInt[], Random.default_rng(), 10_000)
        @test !first(test_function(ts, tc))
        @test isnothing(ts.result) && isnothing(ts.target_err)

        ts.result = Some([1,2,3,4])
        test_function(ts, TestCase(UInt[], Random.default_rng(), 10_000))
        @test @something(ts.result) == UInt[1,2,3,4]
    end

    @testset "test function invalid" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, _ -> throw(Supposition.Invalid()))

        tc = TestCase(UInt[], Random.default_rng(), 10_000)
        @test !first(test_function(ts, tc))
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "shrink remove" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(true))
        ts.result = Some(UInt[1,2,3])

        @test @something(shrink_remove(ts, UInt[1,2], UInt(1))) == [1]
        @test @something(shrink_remove(ts, UInt[1,2], UInt(2))) == UInt[]

        ts.result = Some(UInt[1,2,3,4,5])
        @test @something(shrink_remove(ts, UInt[1,2,3,4], UInt(2))) == [1,2]

        function second_is_five(tc::TestCase)
            ls = [ choice!(tc, 10) for _ in 1:3 ]
            last(ls) == 5
        end
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, second_is_five)
        ts.result = Some(UInt[1,2,5,4,5])
        @test @something(shrink_remove(ts, UInt[1,2,5,4,5], UInt(2))) == UInt[1,2,5]

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, sum_greater_1000)
        ts.result = Some(UInt[1,10_000,1,10_000])
        @test @something(shrink_remove(ts, UInt[1,0,1,1001,0], UInt(2))) == UInt[1,1001,0]

        ts.result = Some(UInt[1,10_000,1,10_000])
        @test isnothing(shrink_remove(ts, UInt[1,0,1,1001,0], UInt(1)))
    end

    @testset "shrink redistribute" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(true))

        ts.result = Some(UInt[500,500,500,500])
        @test @something(shrink_redistribute(ts, UInt[500,500], UInt(1))) == UInt[0, 1000]

        ts.result = Some(UInt[500,500,500,500])
        @test @something(shrink_redistribute(ts, UInt[500,500,500], UInt(2))) == UInt[0, 500, 1000]
    end

    @testset "finds small list" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, sum_greater_1000)
        Supposition.run(ts)
        @test @something(ts.result) == [1,1001,0]
    end

    @testset "finds small list debug" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, sum_greater_1000)
        ts.result = Some(UInt[1,0,1,1001,0])
        @test @something(shrink_remove(ts, UInt[1,0,1,1001,0], UInt(2))) == [1,1001,0]
        @test @something(ts.result) == UInt[1,1001,0]
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

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, bl_sum_greater_1000)
        Supposition.run(ts)
        @test @something(ts.result) == UInt[1,1001]
    end

    @testset "reduces additive pairs" begin
        function int_sum_greater_1000(tc::TestCase)
            n = choice!(tc, 1_000)
            m = choice!(tc, 1_000)

            return (n+m) > 1_000
        end
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, int_sum_greater_1000)
        Supposition.run(ts)
        @test @something(ts.result) == [1,1000]
    end

    @testset "test cases satisfy preconditions" begin
        function test(tc::TestCase)
            n = choice!(tc, 10)
            assume!(tc, !iszero(n))
            iszero(n)
        end
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, test)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "finds local maximum" begin
        function test_maxima(tc::TestCase)
            m = Float64(choice!(tc, 1000))
            n = Float64(choice!(tc, 1000))

            score = -((m - 500.0)^2.0 + (n - 500.0)^2.0)
            target!(tc, score)
            return m == 500 || n == 500
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, test_maxima)
        Supposition.run(ts)
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

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, target_upwards)
        Supposition.run(ts)
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

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, target_upwards_nofail)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
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

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, no_benefit)
        Supposition.run(ts)
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

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, target_downwards)
        Supposition.run(ts)
        @test !isnothing(ts.result)
        @test !isnothing(ts.best_scoring)
        @test first(something(ts.best_scoring)) == 0.0
    end

    @testset "mapped possibility" begin
        function map_pos(tc::TestCase)
            n = Data.produce(map(n -> 2n, Data.Integers(0, 5)), tc)
            isodd(n)
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, map_pos)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "selected possibility" begin
        function sel_pos(tc::TestCase)
            n = Data.produce(Data.satisfying(iseven, Data.Integers(0,5)), tc)
            return isodd(n)
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, sel_pos)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "bound possibility" begin
        function bound_pos(tc::TestCase)
            t = Data.produce(Data.bind(Data.Integers(0, 5)) do m
                Data.pairs(Data.just(m), Data.Integers(m, m+10))
            end, tc)
            last(t) < first(t) || (first(t)+10) < last(t)
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, bound_pos)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "cannot witness nothing" begin
        function witness_nothing(tc::TestCase)
            Data.produce(nothing, tc)
            return false
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, witness_nothing)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "can draw mixture" begin
        function draw_mix(tc::TestCase)
            m = Data.produce(Data.OneOf(Data.Integers(-5, 0), Data.Integers(2,5)), tc)
            return (-5 > m) || (m > 5) || (m == 1)
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, draw_mix)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
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

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, impos)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
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

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, guaran)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "boolean unbiased" begin
        function unbias(tc::TestCase)
            vs = Data.produce(Data.Vectors(Data.Booleans(); min_size=10_000, max_size=10_000), tc)
            m = mean(vs)
            !(m ≈ 0.5)
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, unbias)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    int_types = (
        Int8,
        Int16,
        Int32,
        Int64,
        Int128
    )
    @testset "Sampling from Integers is unbiased" begin
        @testset for T in int_types
            pos = Data.Integers{T}()
            n = 5_000_000
            nums = example(pos, n)
            count_zeros = count(iszero, nums)
            count_gt_zero = count(>(zero(T)), nums)
            count_lt_zero = count(<(zero(T)), nums)
            n_nums = sizeof(T)*8
            # it's unlikely to find zeros for the larger types, so give some headroom
            @test isapprox(count_zeros/n, 1/n_nums; rtol=1)
            # negative numbers are exactly as likely as positive numbers together with zeros
            # this is because of two's complement!
            @test isapprox(count_lt_zero, count_gt_zero+count_zeros; rtol=0.01)
        end
    end

    @testset "Can find errors" begin
        sr = @check record=false broken=true db=NoRecordDB() function baba(i=Data.Integers{Int8}())
            i < -5 || error()
        end
        @test !isnothing(sr.result)
        res = @something(sr.result)
        @test res isa Supposition.Error
        @test res.example == (i = -5,)
        @test res.exception == ErrorException("")
        # This odd check is because of version differences pre-1.11
        @test 2 <= length(res.trace) <= 4
        @test res.trace[1].func == :error
        @test res.trace[2].func == :baba
    end

    integer_types = (
        unsigned.(int_types)...,
        int_types...
    )
    @testset "Can find the smallest even Integer" begin
        @testset for T in integer_types
            gen = Data.Integers{T}()
            findEven(tc) = iseven(Data.produce(gen, tc))

            conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
            ts = TestState(conf, findEven)
            Supposition.run(ts)
            obj = Data.produce(gen, Supposition.for_choices(@something(ts.result), copy(conf.rng)))
            @test obj == typemin(T)
        end
    end

    @testset "size bounds on vectors" begin
        function bounds(tc::TestCase)
            ls = Data.produce(Data.Vectors(Data.Integers(0,10); min_size=UInt(1), max_size=UInt(3)), tc)
            length(ls) < 1 || 3 < length(ls)
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, bounds)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "Can produce floats" begin
        @testset for floatT in (Float16, Float32, Float64)
            @check verbose=verb function isfloat(f=Data.Floats{floatT}())
                f isa AbstractFloat
            end
            @check verbose=verb function noinf(f=Data.Floats{floatT}(;infs=false))
                !isinf(f)
            end
            @check verbose=verb function nonan(f=Data.Floats{floatT}(;nans=false))
                !isnan(f)
            end
            @check verbose=verb function nonaninf(f=Data.Floats{floatT}(;nans=false,infs=false))
                !isnan(f) & !isinf(f)
            end
        end
    end

    @testset "@check verbose=verb API" begin
        @testset "regular use" begin
            Supposition.@check verbose=verb function singlearg(i=Data.Integers(0x0, 0xff))
                i isa Integer
            end
            Supposition.@check verbose=verb function twoarg(i=Data.Integers(0x0, 0xff), f=Data.Floats{Float16}())
                i isa Integer && f isa AbstractFloat
            end
        end

        @testset "interdependent generation" begin
            Supposition.@check verbose=verb function depend(a=Data.Integers(0x0, 0xff), b=Data.Integers(a, 0xff))
                a <= b
            end
        end

        @testset "Custom RNG" begin
            Supposition.@check verbose=verb rng=Xoshiro(1) function foo(i=Data.Integers(0x0, 0xff))
                i isa Integer
            end
        end

        @testset "Calling function outside Supposition" begin
            double(x) = 2x
            Supposition.@check verbose=verb function doubleprop(i=Data.Integers(0x0, 0xff))
                iseven(double(i))
            end
        end

        @testset "Using existing properties" begin
            add(a,b) = a+b
            commutative(a,b)   =  add(a,b) == add(b,a)
            associative(f, a, b, c) = f(f(a,b), c) == f(a, f(b,c))
            identity_add(f, a) = f(a,zero(a)) == a
            function successor(a, b)
                a,b = minmax(a,b)
                sumres = a
                for _ in one(b):b
                    sumres = add(sumres, one(b))
                end

                sumres == add(a, b)
            end

            intgen = Data.Integers{UInt}()

            @testset "Additive properties" begin
                Supposition.@check verbose=verb associative(Data.Just(add), intgen, intgen, intgen)
                Supposition.@check verbose=verb identity_add(Data.Just(add), intgen)
                int16gen = Data.Integers{UInt16}()
                Supposition.@check verbose=verb max_examples=1_000 successor(int16gen, int16gen)
                Supposition.@check verbose=verb commutative(intgen, intgen)
            end

            @testset "double `@check` of the same function, with distinct generator, doesn't clash names" begin
                allInt(x) = x isa Integer
                @check verbose=verb allInt(Data.Integers{Int}())
                @check verbose=verb allInt(Data.Integers{UInt}())
            end
        end

        @testset "targeting score" begin
            high = 0xaaaaaaaaaaaaaaaa # a reckless disregard for gravity
            @check verbose=verb function target_test(i=Data.Integers(zero(UInt),high))
                target!(1/abs(high - i))
                i < high+1
            end
        end
    end

    @testset "@composed API" begin
        @testset "Basic usage" begin
            gen = Supposition.@composed function uint8tup(
                    a=Data.Integers{UInt8}(),
                    b=Data.Integers{UInt8}())
                (a,b)
            end

            @test isstructtype(uint8tup)
            # FIXME: This is just the closure bug in disguise
            @test_broken Data.postype(gen) === Tuple{UInt8, UInt8}
            @test example(gen) isa Tuple{UInt8, UInt8}
        end

        @testset "Calling function defined outside Supposition" begin
            double(x) = 2x
            gen = Supposition.@composed function even(i=Data.Integers{UInt8}())
                double(i)
            end

            Supposition.@check verbose=verb function composeeven(g=gen)
                iseven(g)
            end
        end

        @testset "inner produce" begin
            gen = @composed function inner(i=Data.Integers{UInt8}())
                j = Data.produce!(Data.Integers(zero(i), i))
                i,j
            end
            @test example(gen) isa Tuple{UInt8,UInt8}
            @check function in_check(t=gen)
                i = Data.produce!(Data.Integers(minmax(t...)...))
                t isa Tuple{UInt8,UInt8} && i isa UInt8
            end
        end
    end

    @testset "ExampleDB" begin
        # sample a random target for the failing example to find
        # We choose from Int32 and sample from Int64 so that we can
        # *always* find a counterexample!
        rand_target = rand(Int32)
        expected_failure(i::Int64) = i < rand_target

        @testset "NoRecordDB" begin
            nrdb = Supposition.NoRecordDB()
            # marked as broken so the failure is not reported and meddles CI logs
            sr = @check record=false broken=true db=nrdb expected_failure(Data.Integers{Int64}())
            @test isempty(Supposition.records(nrdb))
            @test isnothing(Supposition.retrieve(nrdb, Supposition.record_name(sr)))
        end

        @testset "DirectoryDB" begin
            ddb = Supposition.DirectoryDB(mktempdir())

            # marked as broken so the failure is not reported and meddles CI logs
            sr = @check record=false broken=true db=ddb expected_failure(Data.Integers{Int64}())
            records = Supposition.records(ddb)

            # the name of the stored file should be the same as the record
            @test basename(only(records)) == Supposition.record_name(sr)

            # the stored choices should be the same as the actual choices
            cached = Supposition.retrieve(ddb, Supposition.record_name(sr))
            @test @something(cached) == @something(@something(sr.final_state).result)

            # running the test again should reproduce the _exact_ same failure immediately
            # marked as broken so the failure is not reported and meddles CI logs
            sr2 = @check record=false broken=true db=ddb max_examples=1 expected_failure(Data.Integers{Int64}())
            @test @something(sr2.result).example == @something(sr.result).example
        end
    end

    @testset "Randomness" begin
        #=
            Randomness is tricky - we want each run of `@check` to be 
            different from the last one, even in the same session & on the same property,
            but they should be reproducible across sessions from the stored data & RNG state.
            This means they should NOT be influenced by the global RNG, so we must seed
            the global RNG from the one we are given when starting a run.
        =#

        function genRand(i, a, b)
            push!(a, i)
            push!(b, rand(UInt))
            true
        end

        intgen = Data.Integers{UInt}()

        # For the runs where we have no shared RNG (since we by default seed from the hardware)
        # the two runs should be _completely_ uncorrelated
        data_rng_1 = UInt[]
        default_rng_1 = UInt[]
        data_rng_2 = UInt[]
        default_rng_2 = UInt[]

        @check max_examples=3 record=false genRand(intgen, Data.just(data_rng_1), Data.just(default_rng_1))
        @check max_examples=3 record=false genRand(intgen, Data.just(data_rng_2), Data.just(default_rng_2))
        @test all(Base.splat(!=), zip(data_rng_1, data_rng_2))
        @test all(Base.splat(!=), zip(default_rng_1, default_rng_2))

        # For the runs where we DO have an identical RNG the two runs should be identical,
        # even if the parent RNG is modified inbetween or tasks are spawned that may or
        # may not utilize their own RNG
        data_rng_3 = UInt[]
        default_rng_3 = UInt[]
        data_rng_4 = UInt[]
        default_rng_4 = UInt[]

        @check max_examples=3 record=false rng=Xoshiro(1) genRand(intgen, Data.just(data_rng_3), Data.just(default_rng_3))
        rand(UInt)
        fetch(@spawn(rand(UInt)))
        @check max_examples=3 record=false rng=Xoshiro(1) genRand(intgen, Data.just(data_rng_4), Data.just(default_rng_4))

        @test all(Base.splat(==), zip(data_rng_3, data_rng_4))
        @test all(Base.splat(==), zip(default_rng_3, default_rng_4))

        # Finally, we need to make sure that these invariants also hold when
        # replaying a stored counterexample from a DB
        function randFail(i, a::Ref{UInt}, b::Ref{UInt})
            a[] = i
            b[] = rand(UInt)
            false
        end

        data_rng_5 = Ref{UInt}()
        default_rng_5 = Ref{UInt}()
        data_rng_6 = Ref{UInt}()
        default_rng_6 = Ref{UInt}()

        db = Supposition.DirectoryDB(mktempdir())

        @check broken=true db=db record=false randFail(intgen, Data.just(data_rng_5), Data.just(default_rng_5))
        rand(UInt)
        fetch(@spawn(rand(UInt)))
        @check broken=true db=db max_examples=1 record=false randFail(intgen, Data.just(data_rng_6), Data.just(default_rng_6))
        @test data_rng_5[] == data_rng_6[]
        @test default_rng_5[] == default_rng_6[]
    end

    @testset "Reporting behavior" begin
        pass(_) = true
        fail(_) = false
        err(_) = error()
        db = Supposition.NoRecordDB()

        pass_sr       = @check db=db record=false pass(Data.Just("Dummy"))
        # silence the expected printing
        fail_sr, err_sr, broke_pass_sr = redirect_stderr(devnull) do
            fail_sr       = @check db=db record=false fail(Data.Just("Dummy"))
            err_sr        = @check db=db record=false err(Data.Just("Dummy"))
            broke_pass_sr = @check db=db record=false broken=true pass(Data.Just("Dummy"))
            fail_sr, err_sr, broke_pass_sr
        end
        broke_fail_sr = @check db=db record=false broken=true fail(Data.Just("Dummy"))
        broke_err_sr  = @check db=db record=false broken=true err(Data.Just("Dummy"))

        @test @something(pass_sr.result) isa Supposition.Pass
        @test @something(broke_pass_sr.result) isa Supposition.Pass
        @test @something(fail_sr.result) isa Supposition.Fail
        @test @something(broke_fail_sr.result) isa Supposition.Fail
        @test @something(err_sr.result) isa Supposition.Error
        @test @something(broke_err_sr.result) isa Supposition.Error

        @testset "Pass" begin
            @test  Supposition.results(pass_sr).ispass
            @test !Supposition.results(pass_sr).isfail
            @test !Supposition.results(pass_sr).iserror
            @test !Supposition.results(pass_sr).isbroken
        end

        @testset "Fail" begin
            @test !Supposition.results(fail_sr).ispass
            @test  Supposition.results(fail_sr).isfail
            @test !Supposition.results(fail_sr).iserror
            @test !Supposition.results(fail_sr).isbroken
        end

        @testset "Error" begin
            @test !Supposition.results(err_sr).ispass
            @test !Supposition.results(err_sr).isfail
            @test  Supposition.results(err_sr).iserror
            @test !Supposition.results(err_sr).isbroken
        end

        @testset "Broken Pass" begin
            @test !Supposition.results(broke_pass_sr).ispass
            @test  Supposition.results(broke_pass_sr).isfail
            @test !Supposition.results(broke_pass_sr).iserror
            @test !Supposition.results(broke_pass_sr).isbroken
        end

        @testset "Broken Fail" begin
            @test !Supposition.results(broke_fail_sr).ispass
            @test !Supposition.results(broke_fail_sr).isfail
            @test !Supposition.results(broke_fail_sr).iserror
            @test  Supposition.results(broke_fail_sr).isbroken
        end

        @testset "Broken Error" begin
            @test !Supposition.results(broke_err_sr).ispass
            @test !Supposition.results(broke_err_sr).isfail
            @test !Supposition.results(broke_err_sr).iserror
            @test  Supposition.results(broke_err_sr).isbroken
        end
    end
end
