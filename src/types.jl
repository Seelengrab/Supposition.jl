
###
# Exception types for internal communication
###

abstract type TestException <: Exception end
struct Overrun <: TestException end
struct Invalid <: TestException end

"""
    Option{T}

A utility alias for `Union{Some{T}, Nothing}`.
"""
const Option{T} = Union{Some{T}, Nothing}

"""
    TestCase

A struct representing a single (ongoing) test case.

 * `prefix`: A fixed set of choices that must be made first.
 * `rng`: The RNG this testcase ultimately uses to draw from. This is used to seed the
          task-local RNG object before generating begins.
 * `max_size`: The maximum number of choices this `TestCase` is allowed to make.
 * `choices`: The binary choices made so far.
 * `targeting_score`: The score this `TestCase` attempts to maximize.
"""
mutable struct TestCase{RNG <: Random.AbstractRNG}
    prefix::Vector{UInt64}
    rng::RNG
    max_size::UInt
    choices::Vector{UInt64} # should this be a BitVector instead? could make shrinking slower, but save on memory
    targeting_score::Option{Float64}
end

TestCase(prefix::Vector{UInt64}, rng::Random.AbstractRNG, max_size) = TestCase(prefix, rng, convert(UInt, max_size), UInt64[], nothing)

"""
    CheckConfig

A struct holding the initial configuration for an invocation of `@check`.

Fields:

 * `rng`: The initial RNG object given to `@check`
 * `max_examples`: The maximum number of examples allowed to be drawn with this config
 * `record`: Whether the result should be recorded in the parent testset, if there is one
"""
struct CheckConfig
    rng::Random.AbstractRNG
    max_examples::Int
    record::Bool
    function CheckConfig(; rng::Random.AbstractRNG, max_examples::Int, record=true, kws...)
        new(rng,
            max_examples,
            record)
    end
end

"""
    TestState

 * `config`: The configuration this `TestState` is running with
 * `is_interesting`: The user given property to investigate
 * `rng`: The currently used RNG
 * `valid_test_cases`: The count of (so far) valid encountered testcases
 * `result`: The choice sequence leading to a non-throwing counterexample
 * `best_scoring`: The best scoring result that was encountered during targeting
 * `target_err`: The error this test has previously encountered and the smallest choice sequence leading to it
 * `test_is_trivial`: Whether `is_interesting` is trivial, i.e. led to no choices being required
"""
mutable struct TestState
    config::CheckConfig
    is_interesting::Any
    rng::Random.AbstractRNG
    valid_test_cases::UInt
    calls::UInt
    result::Option{Vector{UInt64}}
    best_scoring::Option{Tuple{Float64, Vector{UInt64}}}
    target_err::Option{Tuple{Exception, Vector{StackFrame}, Int, Vector{UInt64}}}
    test_is_trivial::Bool
    previous_example::Option{Vector{UInt64}}
    function TestState(conf::CheckConfig, test_function, previous_example::Option{Vector{UInt64}}=nothing)
        rng_orig = try
            copy(conf.rng)
        catch e
            # we only care about this outermost `copy` call
            (e isa MethodError && e.f == copy && only(e.args) == conf.rng) || rethrow()
            rethrow(ArgumentError("Encountered a non-copyable RNG object. If you want to use a hardware RNG, seed a copyable RNG like `Random.Xoshiro` and pass that instead."))
        end
        new(
            conf,              # pass the given arguments through
            test_function,
            rng_orig,
            0,                # no tests so far
            0,                # no calls so far
            nothing,          # no result so far
            nothing,          # no target score so far
            nothing,          # no error thrown so far
            false,            # test is presumed nontrivial
            previous_example) # the choice sequence for the previous failure
    end
end

"""
    Result

An abstract type representing the ultimate result a `TestState` ended up at.
"""
abstract type Result end

"""
    ExampleDB

An abstract type representing a database of previous counterexamples.
"""
abstract type ExampleDB end

"""
    SuppositionReport <: AbstractTestSet

An `AbstractTestSet`, for recording the final result of `@check` in the context of `@testset`
"""
mutable struct SuppositionReport <: AbstractTestSet
    description::String
    record_base::String
    final_state::Option{TestState}
    result::Option{Result}
    time_start::Float64
    time_end::Option{Float64}
    verbose::Bool
    expect_broken::Bool
    config::CheckConfig
    database::ExampleDB
    function SuppositionReport(func::String; verbose::Bool=false, broken::Bool=false, description::String="", db::Union{Bool,ExampleDB}=true,
                                record_base::String="", kws...)
        desc = isempty(description) ? func : description
        database::ExampleDB = if db isa Bool
            if db
                default_directory_db()
            else
                NoRecordDB()
            end
        else
            db
        end
        conf = CheckConfig(;
            rng=Random.Xoshiro(rand(Random.RandomDevice(), UInt)),
            max_examples=10_000,
            kws...)
        new(desc, record_base, nothing, nothing, time(), nothing, verbose, broken, conf, database)
    end
end

