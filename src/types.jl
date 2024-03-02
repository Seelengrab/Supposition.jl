
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
 * `generation`: The "generation" this `TestCase` was made in. Can be used for determining how far along in the generation process we are (higher is further).
 * `max_generation`: The maximum "generation" this `TestCase` could have been made in. Does not necessarily exist.
 * `max_size`: The maximum number of choices this `TestCase` is allowed to make.
 * `choices`: The binary choices made so far.
 * `targeting_score`: The score this `TestCase` attempts to maximize.
"""
mutable struct TestCase{RNG <: Random.AbstractRNG}
    prefix::Vector{UInt64}
    const rng::RNG
    const generation::UInt
    const max_generation::Int
    max_size::UInt
    choices::Vector{UInt64} # should this be a BitVector instead? could make shrinking slower, but save on memory
    targeting_score::Option{Float64}
end

TestCase(prefix::Vector{UInt64}, rng::Random.AbstractRNG, generation, max_generation, max_size) =
     TestCase(prefix, rng, convert(UInt, generation), convert(Int, max_generation), convert(UInt, max_size), UInt64[], nothing)

"""
    CheckConfig

A struct holding the initial configuration for an invocation of `@check`.

Fields:

 * `rng`: The initial RNG object given to `@check`
 * `max_examples`: The maximum number of examples allowed to be drawn with this config. `-1` means infinite drawing (careful!).
 * `record`: Whether the result should be recorded in the parent testset, if there is one
"""
struct CheckConfig
    rng::Random.AbstractRNG
    max_examples::Int
    record::Bool
    function CheckConfig(; rng::Random.AbstractRNG, max_examples::Int, record=true, kws...)
        !isempty(kws) && @warn "Got unsupported keyword arguments to CheckConfig! Ignoring:" Keywords=keys(kws)
        new(rng,
            max_examples,
            record)
    end
end

"""
    DEFAULT_CONFIG

A `ScopedValue` holding the `CheckConfig` that will be used by default & as a fallback.

Currently uses these values:

 * `rng`: `Random.Xoshiro(rand(Random.RandomDevice(), UInt))`
 * `max_examples`: `10_000`
 * `record`: `true`

`@check` will use a _new_ instance of `Random.Xoshiro` by itself.
"""
const DEFAULT_CONFIG = ScopedValue{CheckConfig}(CheckConfig(;
    rng=Random.Xoshiro(rand(Random.RandomDevice(), UInt)),
    max_examples=10_000,
    record=true
))

function merge(cc::CheckConfig; kws...)
    cfg = ( k => get(kws, k, getproperty(cc, k)) for k in propertynames(cc) )
    CheckConfig(;cfg...)
end

struct Attempt
    choices::Vector{UInt64}
    generation::UInt
    max_generation::Int
end
Base.copy(attempt::Attempt) = Attempt(copy(attempt.choices), attempt.generation, attempt.max_generation)

"""
    TestState

 * `config`: The configuration this `TestState` is running with
 * `is_interesting`: The user given property to investigate
 * `rng`: The currently used RNG
 * `valid_test_cases`: The count of (so far) valid encountered testcases
 * `calls`: The number of times `is_interesting` was called in total
 * `result`: The choice sequence leading to a non-throwing counterexample
 * `best_scoring`: The best scoring result that was encountered during targeting
 * `target_err`: The error this test has previously encountered and the smallest choice sequence leading to it
 * `test_is_trivial`: Whether `is_interesting` is trivial, i.e. led to no choices being required
 * `previous_example`: The previously recorded attempt (if any).
"""
mutable struct TestState
    config::CheckConfig
    is_interesting::Any
    rng::Random.AbstractRNG
    valid_test_cases::UInt
    calls::UInt
    result::Option{Attempt}
    best_scoring::Option{Tuple{Float64, Attempt}}
    target_err::Option{Tuple{Exception, Vector{StackFrame}, Int, Attempt}}
    test_is_trivial::Bool
    previous_example::Option{Attempt}
    function TestState(conf::CheckConfig, test_function, previous_example::Option{Attempt}=nothing)
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

Required methods:

  * `records(::ExampleDB)`: Returns an iterable of all currently recorded counterexamples.
  * `record!(::ExampleDB, key, value)`: Record the counterexample `value` under the key `key`.
  * `retrieve(::ExampleDB, key)::Option`: Retrieve the previously recorded counterexample stored under `key`.
        Return `nothing` if no counterexample was stored under that key.
"""
abstract type ExampleDB end

@required ExampleDB begin
    records(::ExampleDB)
    record!(::ExampleDB, ::Any, ::Any)
    retrieve(::ExampleDB, ::Any)
end

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
                                record_base::String="", rng=Random.Xoshiro(rand(Random.RandomDevice(), UInt)), config=DEFAULT_CONFIG[], kws...)
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
        conf = merge(config; rng, kws...)
        new(desc, record_base, nothing, nothing, time(), nothing, verbose, broken, conf, database)
    end
end

