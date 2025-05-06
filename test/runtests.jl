using Supposition
using Supposition: Data, test_function, shrink_remove, shrink_redistribute,
        NoRecordDB, UnsetDB, Attempt, DEFAULT_CONFIG, CURRENT_TESTCASE, TestCase, TestState,
        choice!, weighted!, Stats, add_invocation, add_validation, add_invalidation,
        add_overrun, add_call_duration, add_gen_duration, add_shrink, gentime_mean, runtime_mean,
        runtime_variance, statistics, shrinks, overruns, attempts, acceptions, rejections, invocations,
        online_mean, total_time, improvements, add_improvement, counterexample
using Test
using Aqua
using Random
using Logging
using Dates
using Statistics: mean, std, var
using InteractiveUtils: subtypes
using ScopedValues: @with
using .Threads: @spawn
import Pkg
import RequiredInterfaces
const RI = RequiredInterfaces

function sum_greater_1000(_, tc::TestCase)
    ls = Data.produce!(tc, Data.Vectors(Data.Integers(0, 10_000); min_size=UInt(0), max_size=UInt(1_000)))
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
        @testset "Stale dependencies" begin
            Aqua.test_stale_deps(Supposition; ignore)
        end
    end
    @testset "Interfaces" begin
        possibility_subtypes = filter(!=(Supposition.Composed), subtypes(Data.Possibility))
        @testset "Possibility" RI.check_implementations(Supposition.Data.Possibility, possibility_subtypes)
        comp = @composed (i=Data.Integers(0,10),) -> i
        @testset "Composed" RI.check_implementations(Supposition.Data.Possibility, (typeof(comp),))
        @testset "ExampleDB" RI.check_implementations(Supposition.ExampleDB)
    end
    # Write your tests here.
    @testset "test function interesting" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), Returns(true))
        tc = TestCase(UInt[], Random.default_rng(), 1, 10_000, 10_000)
        @test first(test_function(ts, tc))
        @test @something(ts.result).choices == []

        ts.result = Some(Attempt(UInt[1,2,3,4],1,10_000))
        tc = TestCase(UInt[], Random.default_rng(), 1, 10_000, 10_000)
        @test first(test_function(ts, tc))
        @test @something(ts.result).choices == []

        tc = TestCase(UInt[1,2,3,4], Random.default_rng(), 1, 10_000, 10_000)
        @test !first(test_function(ts, tc))
        @test @something(ts.result).choices == []
    end

    @testset "test function valid" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), Returns(false))

        tc = TestCase(UInt[], Random.default_rng(), 1, 10_000, 10_000)
        @test !first(test_function(ts, tc))
        @test isnothing(ts.result) && isnothing(ts.target_err)

        ts.result = Some(Attempt(UInt[1,2,3,4],1,10_000))
        @test begin
            test_function(ts, TestCase(UInt[], Random.default_rng(), 1, 10_000, 10_000))
            @something(ts.result).choices == UInt[1,2,3,4]
        end
    end

    @testset "test function invalid" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), (_, _) -> Supposition.reject!())

        tc = TestCase(UInt[], Random.default_rng(), 1, 10_000, 10_000)
        @test !first(test_function(ts, tc))
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "shrink remove" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), Returns(true))
        ts.result = Some(Attempt(UInt[1,2,3], 1, 10_000))

        @test @something(shrink_remove(ts, Attempt(UInt[1,2],1,10_000), UInt(1))).choices == [1]
        @test @something(shrink_remove(ts, Attempt(UInt[1,2],1,10_000), UInt(2))).choices == UInt[]

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), Returns(true))
        ts.result = Some(Attempt(UInt[1,2,3,4,5], 1,10_000))
        @test @something(shrink_remove(ts, Attempt(UInt[1,2,3,4],1,10_000), UInt(2))).choices == [1,2]

        function second_is_five(_, tc::TestCase)
            ls = [ choice!(tc, 10) for _ in 1:3 ]
            last(ls) == 5
        end
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), second_is_five)
        ts.result = Some(Attempt(UInt[1,2,5,4,5],1,10_000))
        @test @something(shrink_remove(ts, Attempt(UInt[1,2,5,4,5],1,10_000), UInt(2))).choices == UInt[1,2,5]

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), sum_greater_1000)
        ts.result = Some(Attempt(UInt[1,1,10_000,1,10_000],1,10_000))
        @test isnothing(shrink_remove(ts, Attempt(UInt[1,1,0,1,1001,0],1,10_000), UInt(1)))
    end

    @testset "shrink redistribute" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), Returns(true))

        ts.result = Some(Attempt(UInt[500,500,500,500],1,10_000))
        @test @something(shrink_redistribute(ts, Attempt(UInt[500,500],1, 10_000), UInt(1))).choices == UInt[0, 1000]

        ts.result = Some(Attempt(UInt[500,500,500,500],1,10_000))
        @test @something(shrink_redistribute(ts, Attempt(UInt[500,500,500],1, 10_000), UInt(2))).choices == UInt[0, 500, 1000]
    end

    @testset "finds small list" begin
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), sum_greater_1000)
        Supposition.run(ts)
        # This tests the _exact_ IR of Data.Vectors!
        @test @something(ts.result).choices == UInt[1,1,1001]
    end

    @testset "finds small list even with bad lists" begin
        struct BadList <: Data.Possibility{Vector{Int64}} end
        function produce!(tc::TestCase, ::BadList)
            n = choice!(tc, 10)
            [ choice!(tc, 10_000) for _ in 1:n ]
        end

        function bl_sum_greater_1000(_, tc::TestCase)
            ls = produce!(tc, BadList())
            sum(ls) > 1000
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), bl_sum_greater_1000)
        Supposition.run(ts)
        @test @something(ts.result).choices == UInt[1,1001]
    end

    @testset "reduces additive pairs" begin
        function int_sum_greater_1000(_, tc::TestCase)
            n = choice!(tc, 1_000)
            m = choice!(tc, 1_000)

            return (n+m) > 1_000
        end
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), int_sum_greater_1000)
        Supposition.run(ts)
        @test @something(ts.result).choices == [1,1000]
    end

    @testset "test cases satisfy preconditions" begin
        function test(_, tc::TestCase)
            n = choice!(tc, 10)
            assume!(tc, !iszero(n))
            iszero(n)
        end
        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), test)
        Supposition.run(ts)
        @test isnothing(ts.result) && isnothing(ts.target_err)
    end

    @testset "finds local maximum" begin
        function test_maxima(_, tc::TestCase)
            m = Float64(choice!(tc, 1000))
            n = Float64(choice!(tc, 1000))

            score = -((m - 500.0)^2.0 + (n - 500.0)^2.0)
            target!(tc, score)
            return m == 500 || n == 500
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), test_maxima)
        Supposition.run(ts)
        @test !isnothing(ts.result)
    end

    @testset "can target score upwards to interesting" begin
        function target_upwards(_, tc::TestCase)
            n = Float64(choice!(tc, 1_000))
            m = Float64(choice!(tc, 1_000))
            score = n+m
            target!(tc, score)
            score >= 2000.0
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), target_upwards)
        Supposition.run(ts)
        @test ts.result != nothing
    end

    @testset "can target score upwards without failing" begin
        function target_upwards_nofail(_, tc::TestCase)
            n = Float64(choice!(tc, 1_000))
            m = Float64(choice!(tc, 1_000))
            score = n+m
            target!(tc, score)
            false
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), target_upwards_nofail)
        Supposition.run(ts)
        @test ts.result == nothing
        @test ts.target_err == nothing
        @test ts.best_scoring != nothing
        @test first(something(ts.best_scoring)) == 2000.0
    end

    @testset "targeting when most don't benefit" begin
        function no_benefit(_, tc::TestCase)
            choice!(tc, 1_000)
            choice!(tc, 1_000)
            score = Float64(choice!(tc, 1_000))
            target!(tc, score)
            score >= 1_000
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), no_benefit)
        Supposition.run(ts)
        @test ts.result != nothing
    end

    @testset "can target score downwards" begin
        function target_downwards(_, tc::TestCase)
            n = Float64(choice!(tc, 1_000))
            m = Float64(choice!(tc, 1_000))
            score = n+m
            target!(tc, -score)
            score <= 0.0
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), target_downwards)
        Supposition.run(ts)
        @test !isnothing(ts.result)
        @test !isnothing(ts.best_scoring)
        @test first(something(ts.best_scoring)) == 0.0
    end

    @testset "mapped possibility" begin
        @testset "Single Map" begin
            function map_pos(_, tc::TestCase)
                n = Data.produce!(tc, map(n -> 2n, Data.Integers(0, 5)))
                isodd(n)
            end

            conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=100)
            ts = TestState(conf, Returns(nothing), map_pos)
            Supposition.run(ts)
            @test ts.result == nothing
            @test ts.target_err == nothing
        end
        @testset "Multi Map" begin
            function multi_map_pos(_, tc::TestCase)
                n = Data.produce!(tc, map((n,m) -> 2*n*m, Data.Integers(0, 5), Data.Integers(0, 5)))
                isodd(n)
            end

            conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=100)
            ts = TestState(conf, Returns(nothing), multi_map_pos)
            Supposition.run(ts)
            @test ts.result == nothing
            @test ts.target_err == nothing
        end
    end

    @testset "selected possibility" begin
        function sel_pos(_, tc::TestCase)
            n = Data.produce!(tc, Data.satisfying(iseven, Data.Integers(0,5)))
            return isodd(n)
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), sel_pos)
        Supposition.run(ts)
        @test ts.result == nothing
        @test ts.target_err == nothing
    end

    @testset "bound possibility" begin
        function bound_pos(_, tc::TestCase)
            t = Data.produce!(tc, Data.bind(Data.Integers(0, 5)) do m
                Data.pairs(Data.just(m), Data.Integers(m, m+10))
            end)
            last(t) < first(t) || (first(t)+10) < last(t)
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), bound_pos)
        Supposition.run(ts)
        @test ts.result == nothing
        @test ts.target_err == nothing
    end

    @testset "cannot witness nothing" begin
        function witness_nothing(_, tc::TestCase)
            Data.produce!(tc, nothing)
            return false
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), witness_nothing)
        Supposition.run(ts)
        @test ts.result == nothing
        @test ts.target_err == nothing
    end

    @testset "can draw mixture" begin
        function draw_mix(_, tc::TestCase)
            m = Data.produce!(tc, Data.OneOf(Data.Integers(-5, 0), Data.Integers(2,5)))
            return (-5 > m) || (m > 5) || (m == 1)
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), draw_mix)
        Supposition.run(ts)
        @test ts.result == nothing
        @test ts.target_err == nothing
    end

    @testset "impossible weighted" begin
        function impos(_, tc::TestCase)
            for _ in 1:10
                if weighted!(tc, 0.0)
                    @assert false
                end
            end

            return false
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), impos)
        Supposition.run(ts)
        @test ts.result == nothing
        @test ts.target_err == nothing
    end

    @testset "guaranteed weighted" begin
        function guaran(_, tc::TestCase)
            for _ in 1:10
                if !weighted!(tc, 1.0)
                    @assert false
                end
            end

            return false
        end

        conf = Supposition.CheckConfig(; rng=Random.default_rng(), max_examples=10_000)
        ts = TestState(conf, Returns(nothing), guaran)
        Supposition.run(ts)
        @test ts.result == nothing
        @test ts.target_err == nothing
    end

    @testset "boolean unbiased" begin
        vs = example(Data.Booleans(), 1_000_000)
        m = mean(vs)
        # being off from perfect by +-5% is acceptable
        @test m ≈ 0.5 rtol=0.05
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

    @testset "Error shrinking" begin
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

        @testset "Only log distinct errors once" begin
            checked_inputs = UInt8[]
            logs, sr = Test.collect_test_logs() do
                redirect_stderr(devnull) do
                    @check db=false record=false function doubleError(i=Data.Integers{UInt8}())
                        push!(checked_inputs, i)
                        i > 10 && error("input was >")
                        error("input was <=")
                    end
                end
            end
            @test length(logs) in (1,2)
            final_error, _ = @something(@something(sr.final_state).target_err)
            leq_10 = any(<=(10), checked_inputs)
            gt_10 = any(>(10), checked_inputs)
            warnings = filter!(logs) do record
                record.level == Logging.Warn
            end
            @test leq_10 && gt_10 != isempty(warnings)
            @test all(warnings) do record
                record.kwargs[:Error] != final_error
            end
        end
    end

    integer_types = (
        unsigned.(int_types)...,
        int_types...
    )
    @testset "Can find the smallest even Integer" begin
        @testset for T in integer_types
            gen = Data.Integers{T}()
            sr = @check record=false broken=true isodd(gen)
            @test counterexample(sr) == Some((typemin(T),))
        end
    end

    @testset "size bounds on vectors" begin
        vecgen = Data.Vectors(Data.Integers(0,10); min_size=UInt(1), max_size=UInt(3))
        @check function bounds(ls=vecgen)
            1 <= length(ls) <= 3
        end
    end

    @testset "Can find close-to-maximum vector length" begin
        upper_limit = rand(150:1000)
        offset = rand(10:50)
        vecgen = Data.Vectors(Data.Integers{UInt8}(); min_size=min(500, upper_limit)-2*offset, max_size=upper_limit+2*offset)
        sr = @check db=NoRecordDB() record=false broken=true function findArr(v=vecgen)
                length(v) < (upper_limit-offset)
            end;
        @test @something(sr.result) isa Supposition.Fail
        arr = only(@something(sr.result).example);
        @test length(arr) == (upper_limit-offset)
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

    @testset "Floating point clamping" begin
        nums = Data.Floats{Float64}(;nans=false)
        @check function floatclamp(a=nums, b=nums)
            lower, upper = minmax(a, b)
            inner = Data.Floats(;nans=false, minimum=lower, maximum=upper)
            num = produce!(inner)
            lower <= num <= upper
        end

        @check function floatclamp_type(T=Data.SampledFrom((Float16, Float32, Float64)))
            nums = Data.Floats{T}(;nans=false)
            a = produce!(nums)
            b = produce!(nums)
            lower, upper = minmax(a, b)
            inner = Data.Floats{T}(;nans=false, minimum=lower, maximum=upper)
            num = produce!(inner)
            lower <= num <= upper
        end

        # test conversion
        @test Data.Floats(;minimum=4, maximum=5) isa Data.AllFloats
        @test Data.Floats{Float64}(;minimum=4, maximum=5) isa Data.Floats{Float64}

        # test invariant checks
        @test_throws ArgumentError Data.Floats(;minimum=NaN)
        @test_throws ArgumentError Data.Floats(;maximum=NaN)
        @test_throws ArgumentError Data.Floats(;minimum=2.0, maximum=1.0)
    end

    @testset "@check API" begin
        # These tests are for accepted syntax, not functionality, so only one example is fine
        API_conf = Supposition.merge(DEFAULT_CONFIG[]; verbose=verb, max_examples=1)
        @testset "regular use" begin
            @with DEFAULT_CONFIG => API_conf begin
                @check function singlearg(i=Data.Integers(0x0, 0xff))
                    i isa Integer
                end
                @check function twoarg(i=Data.Integers(0x0, 0xff), f=Data.Floats{Float16}())
                    i isa Integer && f isa AbstractFloat
                end

                preexisting = Data.Integers{Int8}()
                @testset "Single Arg, No Comma" begin
                    @check (a=Data.Integers{Int8}()) -> a isa Int8
                    @check (a=Data.Integers{Int16}()) = a isa Int16
                end
                @testset "Single Arg, With Comma" begin
                    @check (a=Data.Integers{Int8}(),) -> a isa Int8
                    @check (a=Data.Integers{Int16}(),) = a isa Int16
                end
                @testset "Multi-Arg" begin
                    @check (a=Data.Integers{Int8}(),b=preexisting) -> a isa Int8 && b isa Int8
                    @check (a=Data.Integers{Int16}(),b=preexisting) -> a isa Int16 && b isa Int8
                end
                @testset "Named Anonymous" begin
                    @check named_prop(a=Data.Integers{Int8}(),b=preexisting) -> a isa Integer && b isa Integer
                    @check named_prop(Data.Integers{Int8}(),preexisting)
                    @check inlinedef(a=Data.Floats()) = a isa AbstractFloat
                    @check inlinedef(Data.Floats{Float16}())
                end
            end
        end

        @testset "interdependent generation" begin
            Supposition.@check config=API_conf function depend(a=Data.Integers(0x0, 0xff), b=Data.Integers(a, 0xff))
                a <= b
            end
        end

        @testset "Custom RNG" begin
            Supposition.@check config=API_conf rng=Xoshiro(1) function foo(i=Data.Integers(0x0, 0xff))
                i isa Integer
            end
        end

        @testset "Calling function outside Supposition" begin
            double(x) = 2x
            Supposition.@check config=API_conf function doubleprop(i=Data.Integers(0x0, 0xff))
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

        @testset "event!" begin
            @testset "With Failure" begin
                sr = @check db=false record=false broken=true function isf16(f=Data.Floats{Float16}())
                    event!("Number is", f)
                    !(f isa Float16)
                end
                res = @something sr.result
                events = res.events
                @test res.example.f == only(events)[2]
                @test only(events)[1] == "Number is"
            end

            @testset "With Error" begin
                sr = @check db=false record=false broken=true function isi16(f=Data.Integers{Int16}())
                    event!(f)
                    f isa String || error("")
                end
                res = @something sr.result
                events = res.events
                @test res.example.f == only(events)[2]
            end

            @testset "With Pass" begin
                sr = @check db=false record=false max_examples=10 function isi16(f=Data.Integers{Int16}())
                    event!("Though shalt not record!")
                    true
                end
                res = @something sr.result
                @test isempty(res.events)
            end

            @testset "With Score" begin
                sr = @check db=false record=false function isi16(f=Data.Integers{Int16}())
                    event!("Though shalt not record!")
                    target!(-f)
                    true
                end
                res = @something sr.result
                @test !isempty(res.events)
                @test only(res.events)[2] == "Though shalt not record!"
                @test @something(res.best).f == typemin(Int16)+1
                @test @something(res.score) == typemax(Int16)
            end
        end

        @testset "@event!" begin
            sr = @check db=false record=false broken=true function log_is_exprstring(f=Data.Integers{Int16}())
                # this fails intentionally!
                @event!(f*2) isa Vector || error("")
            end
            res = @something sr.result
            events = res.events
            @test !isempty(events)
            # don't hardcode the string value, the printing is not stable
            # for most expressions...
            # this still only tests one expression, but getting arbitrary ones
            # into `@event!` is tricky
            @test first(only(events)) == string(:(f*2))
            @check function use_event_result(f=Data.Integers{Int16}())
                res = @event!(2f)
                iseven(res)
            end
        end

        @testset "targeting score" begin
            high = 0xaaaaaaaaaaaaaaaa # a reckless disregard for gravity
            @check verbose=verb function target_test(i=Data.Integers(zero(UInt),high))
                target!(1/abs(high - i))
                i < high+1
            end
        end

        @testset "Wrong usage" begin
            int_err = ArgumentError("Can't `produce!` from objects of type `Type{$Int}` for argument `i`, `@check` requires arguments of type `Possibility`!")
            err = try
                @check record=false function foo(i=Int)
                    i isa Int
                end
            catch e
                e
            end
            @test err isa Supposition.InvalidInvocation
            @test err.res isa Test.Error
            @test err.res.value == string(int_err)

            one_err = ArgumentError("Can't `produce!` from objects of type `$Int` for argument `i`, `@check` requires arguments of type `Possibility`!")
            err = try
                @check record=false function foo(i=1)
                    i isa Int
                end
            catch e
                e
            end
            @test err isa Supposition.InvalidInvocation
            @test err.res isa Test.Error
            @test err.res.value == string(one_err)
        end
    end

    @testset "@composed API" begin
        @testset "Basic usage" begin
            gen = Supposition.@composed function uint8tup(
                    a=Data.Integers{UInt8}(),
                    b=Data.Integers{UInt8}())
                (a,b)
            end

            @testset "Expected return types" begin
                @test gen isa Supposition.Composed{:uint8tup}
                @test Data.postype(gen) === Tuple{UInt8, UInt8}
                @test example(gen) isa Tuple{UInt8, UInt8}
            end

            @testset "Can call function defined through `@composed`" begin
                @test uint8tup(1,2) === (1,2)
            end

            @testset "Can use anonymous function" begin
                preexisting = Data.Integers{Int8}()

                @testset "Single Argument, No comma" begin
                    one_arg_no_comma = @composed (a=Data.Integers{Int8}()) -> a isa Int8
                    @test one_arg_no_comma isa Supposition.Composed
                    @test Data.postype(one_arg_no_comma) === Bool
                    @test example(one_arg_no_comma) isa Bool
                    one_arg_no_comma = @composed (a=preexisting) -> a isa Int8
                    @test one_arg_no_comma isa Supposition.Composed
                    @test Data.postype(one_arg_no_comma) === Bool
                    @test example(one_arg_no_comma) isa Bool
                end

                @testset "Single Argument, With comma" begin
                    one_arg_with_comma = @composed (a=Data.Integers{Int8}(),) -> a isa Int8
                    @test one_arg_with_comma isa Supposition.Composed
                    @test Data.postype(one_arg_with_comma) === Bool
                    one_arg_with_comma = @composed (a=preexisting,) -> a isa Int8
                    @test one_arg_with_comma isa Supposition.Composed
                    @test Data.postype(one_arg_with_comma) === Bool
                    @test example(one_arg_with_comma) isa Bool
                end

                @testset "Multiple Arguments" begin
                    multi_arg = @composed (a=Data.Integers{Int8}(),b=preexisting) -> a isa Int8 && b isa Int8
                    @test multi_arg isa Supposition.Composed
                    @test Data.postype(multi_arg) === Bool
                    @test example(multi_arg) isa Bool
                end

                @testset "Named anon" begin
                    named = @composed named_anon(a=Data.Integers{Int8}(),b=preexisting) -> a isa Int8 && b isa Int8
                    @test named isa Supposition.Composed{:named_anon}
                    @test Data.postype(named) === Bool
                    @test example(named) isa Bool
                    @test named_anon(Int8(1), Int8(2))
                end
            end

            @testset "Can compose through existing function" begin
                foo(a,b) = a+b
                preexisting = Data.Integers{Int8}()
                existing = @composed foo(Data.Integers{Int8}(), preexisting)
                @test existing isa Supposition.Composed{:foo}
                @test Data.postype(existing) === Int8
                @test example(existing) isa Int8
                # can still call the existing function
                @test foo(1,2) === 3
            end
        end

        @testset "Using external generators" begin
            text = Data.Text(Data.AsciiCharacters(); max_len=10)
            g2 = Supposition.@composed function stringcat(
                    t=text,
                    b=Data.Integers{UInt8}())
                string(t, b)
            end

            @testset "Expected return types" begin
                @test g2 isa Supposition.Composed{:stringcat}
                @test Data.postype(g2) === String
                @test example(g2) isa String
            end

            @check function stringcatcorrect(s=g2)
                # The range-syntax in the regex captures all ASCII
                contains(s, r"[\0-\x7f]*-?\d+")
            end

            @testset "Can call defined function" begin
                @test stringcat("foo", "1") === "foo1"
            end
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
                j = produce!(Data.Integers(zero(i), i))
                i,j
            end
            @test example(gen) isa Tuple{UInt8,UInt8}
            @check function in_check(t=gen)
                i = produce!(Data.Integers(minmax(t...)...))
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

        @testset "UnsetDB" begin
            @testset "DirectoryDB as fallback" begin
                current_project = dirname(Pkg.project().path)
                current_dir = pwd()
                Pkg.activate(;temp=true)
                tmp_dir = dirname(Pkg.project().path)
                cd(tmp_dir)
                sr = @check record=false broken=true expected_failure(Data.Integers{Int64}())
                @test ispath(joinpath(tmp_dir, "test", "SuppositionDB"))
                @test sr.config.db isa Supposition.DirectoryDB
                cd(current_dir)
                Pkg.activate(current_project)
            end
            @testset "Can't record to UnsetDB" begin
                retr_err = ArgumentError("Can't `retrieve` from an UnsetDB! Did you mean to use a `DirectoryDB`?")
                res_err = try
                     @check record=false broken=true db=UnsetDB() expected_failure(Data.Integers{Int64}())
                catch e
                    e
                end
                @test res_err isa Supposition.InvalidInvocation
                @test res_err.res isa Test.Error
                @test res_err.res.value == string(retr_err)
                record_err = ArgumentError("Can't `record!` to an UnsetDB! Did you mean to use a `NoRecordDB`?")
                res_err = try
                     @check record=false broken=true function illegalModify(i=Data.Integers{Int8}())
                        sr = Test.get_testset()
                        sr.config = Supposition.merge(sr.config; db=UnsetDB())
                        false
                    end
                catch e
                    e
                end
                @test res_err == record_err
            end
        end

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
            @test @something(cached).choices == @something(@something(sr.final_state).result).choices

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

        @testset "Ensure checking function also regenerates from RNG correctly" begin
            vec = Data.Vectors(Data.Integers{UInt8}();min_size=5,max_size=5);
            rngvec = map(vec) do v
               v .= rand(UInt8, length(v))
            end

            sr = @check db=false record=false broken=true function third_is_not_five(v=rngvec)
                event!("ACTUAL DATA", v)
                v[3] != 5
            end
            @test @something(sr.result).example.v[3] == 5
            @test @something(sr.result).example[1] == @something(sr.result).events[1][2]
        end
    end

    @testset "Reporting behavior" begin
        pass(_) = true
        fail(_) = false
        err(_) = error()
        db = Supposition.NoRecordDB()

        pass_sr       = @check db=db record=false pass(Data.Just("Dummy"))
        # silence the expected printing
        fail_sr, err_sr, broke_pass_sr, timeout_sr = redirect_stderr(devnull) do
            fail_sr       = @check db=db record=false fail(Data.Just("Dummy"))
            err_sr        = @check db=db record=false err(Data.Just("Dummy"))
            broke_pass_sr = @check db=db record=false broken=true pass(Data.Just("Dummy"))
            timeout_sr    = @check db=db record=false timeout=Nanosecond(1) pass(Data.Just("Dummy"))
            fail_sr, err_sr, broke_pass_sr, timeout_sr
        end
        broke_fail_sr    = @check db=db record=false broken=true fail(Data.Just("Dummy"))
        broke_err_sr     = @check db=db record=false broken=true err(Data.Just("Dummy"))

        @testset "Result types" begin
            @test @something(pass_sr.result)       isa Supposition.Pass
            @test @something(broke_pass_sr.result) isa Supposition.Pass
            @test @something(fail_sr.result)       isa Supposition.Fail
            @test @something(broke_fail_sr.result) isa Supposition.Fail
            @test @something(err_sr.result)        isa Supposition.Error
            @test @something(broke_err_sr.result)  isa Supposition.Error
            @test @something(timeout_sr.result)    isa Supposition.Timeout
        end

        @testset "Pass" begin
            @test  Supposition.results(pass_sr).ispass
            @test !Supposition.results(pass_sr).isfail
            @test !Supposition.results(pass_sr).iserror
            @test !Supposition.results(pass_sr).isbroken
            @test !Supposition.results(pass_sr).istimeout
        end

        @testset "Fail" begin
            @test !Supposition.results(fail_sr).ispass
            @test  Supposition.results(fail_sr).isfail
            @test !Supposition.results(fail_sr).iserror
            @test !Supposition.results(fail_sr).isbroken
            @test !Supposition.results(fail_sr).istimeout
        end

        @testset "Error" begin
            @test !Supposition.results(err_sr).ispass
            @test !Supposition.results(err_sr).isfail
            @test  Supposition.results(err_sr).iserror
            @test !Supposition.results(err_sr).isbroken
            @test !Supposition.results(err_sr).istimeout
        end

        @testset "Timeout" begin
            @test !Supposition.results(timeout_sr).ispass
            @test !Supposition.results(timeout_sr).isfail
            @test !Supposition.results(timeout_sr).iserror
            @test !Supposition.results(timeout_sr).isbroken
            @test  Supposition.results(timeout_sr).istimeout
        end

        @testset "Broken Pass" begin
            @test !Supposition.results(broke_pass_sr).ispass
            @test  Supposition.results(broke_pass_sr).isfail
            @test !Supposition.results(broke_pass_sr).iserror
            @test !Supposition.results(broke_pass_sr).isbroken
            @test !Supposition.results(broke_pass_sr).istimeout
        end

        @testset "Broken Fail" begin
            @test !Supposition.results(broke_fail_sr).ispass
            @test !Supposition.results(broke_fail_sr).isfail
            @test !Supposition.results(broke_fail_sr).iserror
            @test  Supposition.results(broke_fail_sr).isbroken
            @test !Supposition.results(broke_fail_sr).istimeout
        end

        @testset "Broken Error" begin
            @test !Supposition.results(broke_err_sr).ispass
            @test !Supposition.results(broke_err_sr).isfail
            @test !Supposition.results(broke_err_sr).iserror
            @test  Supposition.results(broke_err_sr).isbroken
            @test !Supposition.results(broke_err_sr).istimeout
        end

        @testset "Alignment" begin
            and_Ive_been_through_the_desert_in_a_func_with_long_name(_) = true
            sr = @check record=false and_Ive_been_through_the_desert_in_a_func_with_long_name(Data.Booleans())
            # I really wish `redirect_std*` would take an IOBuffer
            printed_output = mktemp() do _, io
                redirect_stdout(io) do
                    Test.print_test_results(sr)
                end
                seekstart(io)
                read(io, String)
            end
            first_pipe, second_pipe = findall(==('|'), printed_output)
            newline = findfirst(==('\n'), printed_output)
            @test first_pipe == (second_pipe-newline)
        end
    end

    @testset "Default Config" begin
        conf = Supposition.CheckConfig(;
            rng=Xoshiro(0),
            max_examples=10,
            db=NoRecordDB(),
            record=false
        )
        intgen = Data.Integers{Int}()
        @with DEFAULT_CONFIG => conf begin
            local unrecorded_report::Supposition.SuppositionReport
            local   recorded_report::Supposition.SuppositionReport
            @testset "RecordNotOverwritten" begin
                unrecorded_report = redirect_stderr(devnull) do
                    # This one must NOT be recorded! It must still run though
                    @check broken=true function This_Is_Known_Passing_Ignore_In_CI_As_Long_As_Its_Not_In_The_Final_Testset_Report(i=intgen)
                        true
                    end
                end
                # This one MUST be recorded!
                recorded_report = @check record=true function truthy(i=Data.Integers{Int8}())
                    true
                end
            end
            @test invocations(statistics(unrecorded_report)) == 10
            @test invocations(statistics(recorded_report))   == 10
        end

        @testset "Partially overwrite given Config" begin
            res = @check config=conf max_examples=100 function passConfFailTestFailTest(i=intgen)
                true
            end
            @test invocations(statistics(res)) == 100
        end

        @testset "Buffer Size" begin
            vecgen = Data.Vectors(Data.Integers{UInt8}(); min_size=10)
            res = @check max_examples=500 buffer_size=1 record=false function passConfFailTestFailTest(v=vecgen)
                isempty(v)
            end
            # all of these must have been rejected as an Overrun, so no call should ever take place
            @test iszero(acceptions(statistics(res)))
            # 5000 instead of 500 since the upper limit is 10*max_examples
            @test overruns(statistics(res)) == 5000
        end

        @testset "Timeouts" begin
            @testset "Hit timeout" begin
                sr = @check record=false timeout=Millisecond(100) (x=Data.Integers{Int8}()) -> (sleep(0.01); return true)
                @test !isnothing(sr.result)
                @test @something(sr.result) isa Supposition.Pass
                fs = @something sr.final_state
                stats = statistics(sr)
                @test (@something(fs.start_time) + total_time(stats)) >= @something(fs.deadline)
                @test invocations(statistics(fs)) < sr.config.max_examples
            end

            @testset "No run happened" begin
                sr = @check record=false broken=true timeout=Nanosecond(1) (x=Data.Integers{Int8}()) -> return true
                @test !isnothing(sr.result)
                @test @something(sr.result) isa Supposition.Timeout
                @test iszero(invocations(statistics(sr)))
            end
        end
    end

    @testset "show" begin
    @testset "2-arg show" begin
        @testset "repr is evalable: $pos" for pos in (
                Data.Integers{UInt8}(),
                Data.Integers(0x1,0xfe),
                Data.Floats{Float16}(),
                Data.Floats{Float16}(;minimum=3.0, maximum=7.0),
                Data.Floats{Float16}(;minimum=3.0),
                Data.Floats{Float16}(;maximum=7.0),
                Data.Floats(),
                Data.Floats(;minimum=3.0, maximum=7.0),
                Data.Floats(;minimum=3.0),
                Data.Floats(;maximum=7.0),
                Data.Booleans(),
                Data.Pairs(Data.Booleans(), Data.Booleans()),
                Data.Vectors(Data.Booleans();max_size=1),
                Data.Dicts(Data.Booleans(),Data.Booleans();max_size=1),
                Data.AsciiCharacters(),
                Data.Characters(),
                Data.UnicodeCharacters(),
                Data.Text(Data.AsciiCharacters();max_len=1),
                Data.SampledFrom(0:10),
                Data.filter(iseven, Data.Just(0:10)),
                Data.map(sqrt, Data.Just(0:10)),
                Data.map(+, Data.Just(1), Data.Just(2)),
                Data.Just(1),
                Data.Floats() | Data.Booleans(),
                Data.WeightedNumbers([.1, .2, .7]),
                Data.WeightedSample(1:3, [.1, .2, .7]),
                )
            @test eval(Meta.parse(repr(pos))) == pos
        end
    end
    @testset "3-arg show" begin
        @testset "Integers" begin
            @test occursin("Produce an integer of type $Int", repr("text/plain", Data.Integers{Int}()))
            limited_repr = repr("text/plain", Data.Integers(5, 10))
            @test occursin("Integers", limited_repr)
            @test occursin("Int64", limited_repr)
            @test occursin("[5, 10]", limited_repr)
            bitint_repr = repr("text/plain", Data.BitIntegers())
            @testset "BitIntegers: $T" for T in (
                    UInt8, Int8, UInt16, Int16, UInt32, Int32, UInt64, Int64, UInt128, Int128
                )
                @test occursin(string(T), bitint_repr)
            end
        end
        @testset "Floats" begin
            @test occursin("of type Float16", repr("text/plain", Data.Floats{Float16}()))
            @test occursin("isinf: never", repr("text/plain", Data.Floats{Float16}(;infs=false)))
            @test occursin("isnan: never", repr("text/plain", Data.Floats{Float16}(;nans=false)))
            minmax_float16 = Data.Floats{Float16}(;minimum=4.0, maximum=5.0)
            @test occursin("4.0 <= x <= 5.0", repr("text/plain", minmax_float16))
            @test occursin("isinf: never", repr("text/plain", minmax_float16))
            @test occursin("isinf: maybe", repr("text/plain", Data.Floats{Float16}(;minimum=4.0)))
            @test occursin("isinf: maybe", repr("text/plain", Data.Floats{Float16}(;maximum=5.0)))
            @test occursin("AllFloats", repr("text/plain", Data.Floats()))
            @test occursin("AllFloats", repr("text/plain", Data.AllFloats()))
            minmax_allfloats = Data.Floats(;minimum=4.0, maximum=5.0)
            @test occursin("4.0 <= x <= 5.0", repr("text/plain", minmax_allfloats))
            @test occursin("isinf: never", repr("text/plain", minmax_allfloats))
            @test occursin("isinf: maybe", repr("text/plain", Data.Floats(;minimum=4.0)))
            @test occursin("isinf: maybe", repr("text/plain", Data.Floats(;maximum=5.0)))
            @test occursin("true and false have a probability of 50%", repr("text/plain", Data.Booleans()))
        end
        @testset "Data.Pairs" begin
            pair_repr = repr("text/plain", Data.Pairs(Data.Booleans(), Data.Characters()))
            @test occursin("Pairs", pair_repr)
            @test occursin(r"From[\w\s\.]+Booleans", pair_repr)
            @test occursin(r"From[\w\s\.]+Characters", pair_repr)
            @test occursin("Pair{Bool, Char}", pair_repr)
        end
        @testset "Data.Vectors" begin
            vec_repr = repr("text/plain", Data.Vectors(Data.Booleans(); min_size=10, max_size=50))
            @test occursin("Vectors", vec_repr)
            # show the interval of the length
            @test occursin("[10, 50]", vec_repr)
            # show the `Possibility` for elements
            @test occursin("Booleans()", vec_repr)
            # show the target vector type
            @test occursin("Vector{Bool}", vec_repr)
        end
        @testset "Data.Dicts" begin
            dict_repr = repr("text/plain", Data.Dicts(Data.Booleans(), Data.Characters(); min_size=10, max_size=50))
            @test occursin("Dicts", dict_repr)
            # show the interval of the length
            @test occursin("[10, 50]", dict_repr)
            # show the `Possibility` for keys
            @test occursin("Booleans()", dict_repr)
            # show the `Possibility` for values
            @test occursin("Characters", dict_repr)
            # show the target Dict type
            @test occursin("Dict{Bool, Char}", dict_repr)
        end
        @testset "`Char`" begin
            ascii_char_repr = repr("text/plain", Data.AsciiCharacters())
            @test occursin("AsciiCharacters", ascii_char_repr)
            @test occursin("isascii returns true", ascii_char_repr)
            char_repr = repr("text/plain", Data.Characters())
            @test occursin("Characters", char_repr)
            @test occursin("well-formed", char_repr)
            uni_char_repr = repr("text/plain", Data.UnicodeCharacters())
            @test occursin("UnicodeCharacters", uni_char_repr)
            @test occursin("ismalformed", uni_char_repr)
        end
        @testset "Text" begin
            text_repr = repr("text/plain", Data.Text(Data.AsciiCharacters(); min_len=10, max_len=50))
            @test occursin("Text", text_repr)
            # show the interval of the length
            @test occursin("[10, 50]", text_repr)
            # show the `Possibility` for individual characters
            @test occursin("AsciiCharacters()", text_repr)
            @test occursin("String", text_repr)
        end
        @testset "SampledFrom" begin
            sf_repr = repr("text/plain", Data.SampledFrom((sin, cos)))
            @test occursin("SampledFrom", sf_repr)
            @test occursin("(sin, cos)", sf_repr)
            @test occursin("equal probability", sf_repr)
        end
        @testset "filter" begin
            satis_repr = repr("text/plain", filter(isinf, Data.Integers{Int8}()))
            @test occursin("Satisfying", satis_repr)
            @test occursin("Integers{Int8}", satis_repr)
            @test occursin("isinf", satis_repr)
            @test begin
                repr("text/plain", filter(Data.Integers{UInt8}()) do i
                    Data.produce!(Data.Just(i)) isa UInt16
                end)
                true # dummy pass, this used to throw
            end
        end
        @testset "map" begin
            @testset "single map" begin
                map_repr = repr("text/plain", map(sqrt, Data.Integers{UInt8}()))
                @test occursin("Map", map_repr)
                @test occursin("Integers{UInt8}", map_repr)
                @test occursin("Float64", map_repr)
                @test occursin("sqrt", map_repr)
                @test begin
                    repr("text/plain", map(Data.Integers{UInt8}()) do i
                        Data.produce!(Data.Just(i))
                    end)
                    true # dummy pass, this used to throw
                end
                f = rand()
                str = repr("text/plain", map(sqrt, Data.Just(f)))
                exp = "sqrt($f)"
                @test occursin(exp, str)
            end
            @testset "multi map" begin
                map_repr = repr("text/plain", map(+, Data.Integers{UInt8}(), Data.Integers{Int}()))
                @test occursin("MultiMap", map_repr)
                @test occursin("Integers{UInt8}", map_repr)
                @test occursin("Integers{$Int}", map_repr)
                @test occursin("+", map_repr)
                @test begin
                    repr("text/plain", map(Data.Integers{UInt8}()) do i
                        Data.produce!(Data.Just(i))
                    end)
                    true # dummy pass, this used to throw
                end
                f = rand()
                str = repr("text/plain", map(+, Data.Just(f), Data.Just(1.0)))
                exp = "+($f, 1.0)"
                @test occursin(exp, str)
            end
        end
        @testset "Just" begin
            # a totally random number for testing
            just_repr = repr("text/plain", Data.Just(4))
            @test occursin("Just", just_repr)
            @test occursin("4", just_repr)
        end
        @testset "OneOf" begin
            of_repr = repr("text/plain", Data.Just(4) | Data.Integers{UInt8}())
            @test occursin("OneOf", of_repr)
            @test occursin("Just(4)", of_repr)
            @test occursin("Integers{UInt8}", of_repr)
        end
        @testset "Bind" begin
            intbind(o) = Data.Integers(o,o)
            bind_repr = repr("text/plain", Data.Bind(Data.Just(4), intbind))
            @test occursin("Bind", bind_repr)
            @test occursin("Just(4)", bind_repr)
            @test occursin("intbind", bind_repr)
        end
        @testset "Recursive" begin
            recwrap(pos) = map(tuple, pos)
            recr_repr = repr("text/plain", Data.recursive(recwrap, Data.Characters(); max_layers=3))
            @test occursin("Recursive", recr_repr)
            @test occursin("Characters", recr_repr)
            @test occursin("recwrap", recr_repr)
            @test occursin("2", recr_repr)
        end
        @testset "WeightedNumbers" begin
            wn_repr = repr("text/plain", Data.WeightedNumbers([.1, .2, .7]))
            @test occursin("WeightedNumbers", wn_repr)
            @test occursin("1:3", wn_repr)
            @test occursin("10.00% : 1", wn_repr)
            @test occursin("20.00% : 2", wn_repr)
            @test occursin("70.00% : 3", wn_repr)
        end
        @testset "WeightedSample" begin
            wn_repr = repr("text/plain", Data.WeightedSample(("foo", "bar", "baz"), [.1, .2, .7]))
            @test occursin("WeightedSample", wn_repr)
            @test occursin("10.00% : foo", wn_repr)
            @test occursin("20.00% : bar", wn_repr)
            @test occursin("70.00% : baz", wn_repr)
        end
    end
    end

    @testset "Utility" begin
        @testset for T in (Float16, Float32, Float64)
            @check function floatfunc(f=Data.Floats{T}())
                orig = bitstring(f)
                reassembled = bitstring(Supposition.assemble(T, Supposition.tear(f)...))
                orig == reassembled
            end
        end
    end

    @testset "Dicts" begin
        @check function dictlen(m=Data.Integers(0, 200),n=Data.Integers(0,m))
            k = Data.Integers{UInt8}()
            v = Data.Integers{Int8}()
            d = Data.produce!(Data.Dicts(k,v;min_size=n,max_size=m))
            n <= length(d) <= m
        end
    end

    @testset "Weighted Numbers" begin
        datgen = map(Data.Vectors(Data.Integers(1, 10_000); min_size=1, max_size=100)) do v
            v ./ sum(v)
        end
        @check max_examples=1000 function correctly_biased(weights=datgen,data=Data.Vectors(Data.WeightedNumbers(weights); min_size=1_000, max_size=10_000))
            n = length(data)
            counts = zeros(length(weights))
            for d in data
                counts[d] += 1.0
            end
            sw = sum(weights)
            all(zip(counts, weights)) do (c,w)
                # We're giving +-5% leeway, and comparing the
                # big numbers prevents troubles through roundoff
                isapprox(c, (w/sw)*n; atol=0.05*length(data))
            end
        end
    end

    @testset "Characters" begin
        @check ascii_allascii(c=Data.AsciiCharacters()) -> isascii(c)
        @check chars_nonmalformed(c=Data.Characters()) -> !Base.ismalformed(c)
        # There isn't anything left to check for here
        @check allascii(c=Data.UnicodeCharacters()) -> c isa Char
    end

    @testset "Statistics" begin
        @testset "individual calls" begin
            # TODO: Replace this with stateful property based testing
            @test add_invocation(Stats())         == Supposition.merge(Stats(); invocations=1)
            @test add_validation(Stats())         == Supposition.merge(Stats(); acceptions=1)
            @test add_invalidation(Stats())       == Supposition.merge(Stats(); rejections=1)
            @test add_overrun(Stats())            == Supposition.merge(Stats(); overruns=1)
            @test add_shrink(Stats())             == Supposition.merge(Stats(); shrinks=1)
            @test add_improvement(Stats())        == Supposition.merge(Stats(); improvements=1)
            dur = rand()
            @test add_call_duration(Stats(), dur) == Supposition.merge(Stats(); mean_runtime=dur, squared_dist_runtime=0.0)
            @test add_gen_duration(Stats(), dur)  == Supposition.merge(Stats(); mean_gentime=dur, squared_dist_gentime=0.0)
        end

        # the maximum is only here to prevent edge cases with overflow
        sleep_durs = Data.Vectors(Data.Floats{Float64}(;nans=false,infs=false, minimum=0.001, maximum=100.0); min_size=2)
        @check function online_mean_oracle(durations=sleep_durs)
            runtime_mean, runtime_variance = foldl(enumerate(durations); init=(NaN, 0.0)) do (mu, sig²), (n, val)
                online_mean(mu, sig², n, val)
            end
            runtime_variance = runtime_variance / length(durations)
            var_oracle = var(durations; corrected=false)
            mean_oracle = mean(durations)
            # The online variance should not be too far off; +-5%
            var_correct = @event! isapprox(runtime_variance, var_oracle; rtol=0.05)
            # Our targets are tight - the calculated mean should be well within 1σ.
            mean_correct = @event! isapprox(runtime_mean, mean_oracle; atol=std(durations))
            var_correct & mean_correct
        end

        @testset "Long generation & fast property" begin
            # This ensures that the duration of the generation of input
            # does not influence the statistics about the duration of the call.
            gen = map(Data.Just(0x1)) do x
                sleep(0.05) # 50 ms sleep is AGES
                return x
            end
            stats = statistics(@check max_examples=10 db=false record=false (x=gen) -> true)
            # The property is so trivial, calls here should never EVER take this long.
            # If it does, something is seriously wacky in the environment where the test is run.
            @test runtime_mean(stats) < 0.01
            @test gentime_mean(stats) ≈ 0.05 rtol=0.05
        end

        @testset "Aggregated counts" begin
            @testset "Trivial property" begin
                truthy(_) = true
                sr = @check max_examples=500 record=false truthy(Data.Integers{UInt8}())
                stats = statistics(sr)
                @test shrinks(stats)      == 0
                @test overruns(stats)     == 0
                @test attempts(stats)     == 500
                @test acceptions(stats)   == 500
                @test rejections(stats)   == 0
                @test invocations(stats)  == 500
                @test improvements(stats) == 0
            end
            @testset "Targeted improvement" begin
                target = Ref{Float64}(rand(Random.RandomDevice(), Float64))
                # We have to be pretty limited in what we generate here,
                # since most Float64 are not in Float32 or Float16.
                # Also disallow NaNs and Infs, since those can't be
                # generated from the above `rand` invocation at all.
                sr = @check db=false broken=true record=false function findzero(i=Data.Floats{Float64}(;nans=false,infs=false))
                    target!(-abs(target[]-i))
                    target[] != i
                end
                # we expect to find the equality
                @test @something(sr.result) isa Supposition.Fail
                stats = statistics(sr)
                # targeting is necessary
                @test !iszero(improvements(stats))
                # this is for the RNG seed
                @test isone(shrinks(stats))
            end
        end
    end

    @testset "SuppositionReport API" begin
        @testset "Counterexample" begin
            sr = @check db=false record=false broken=true function find_target(f=Data.Integers{UInt8}())
                f == typemax(Int)
            end
            @test counterexample(sr) == Some((0x0,))
        end
    end
end
