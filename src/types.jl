
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

struct Attempt
    choices::Vector{UInt64}
    generation::UInt
    max_generation::Int
end
Base.copy(attempt::Attempt) = Attempt(copy(attempt.choices), attempt.generation, attempt.max_generation)

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
    max_size::UInt
    targeting_score::Option{Float64}
    attempt::Attempt
end

TestCase(prefix::Vector{UInt64}, rng::Random.AbstractRNG, generation, max_generation, max_size) =
     TestCase(prefix, rng, convert(UInt, max_size), nothing, Attempt(UInt64[], convert(UInt, generation), convert(Int, max_generation)))

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

function default_directory_db end

"""
    CheckConfig(;options...)

A struct holding the initial configuration for an invocation of `@check`.

Options:

 * `rng`: The initial RNG object given to `@check`. Defaults to a copyable `Random.AbstractRNG`.
 * `max_examples`: The maximum number of examples allowed to be drawn with this config. `-1` means infinite drawing (careful!). Defaults to `10_000`.
 * `record`: Whether the result should be recorded in the parent testset, if there is one. Defaults to `true`.
 * `verbose`: Whether the printing should be verbose, i.e. print even if it's a `Pass`. Defaults to `false`.
 * `broken`: Whether the invocation is expected to fail. Defaults to `false`.
 * `db`: An `ExampleDB` for recording failure cases for later replaying. Defaults to `default_directory_db()`.
 * `buffer_size`: The default maximum buffer size to use for a test case. Defaults to `100_000`.

!!! warning "Buffer Size"
    At any one point, there may be more than one active buffer being worked on.
    You can try to increase this value when you encounter a lot of `Overrun`.
    Do not set this too large, or you're very likely to run out of memory; the default
    results in ~800kB worth of choices being possible, which should be plenty for most fuzzing
    tasks. It's generally unlikely that failures only occur with very large values here, and not with
    smaller ones.
"""
struct CheckConfig
    rng::Random.AbstractRNG
    max_examples::Int
    record::Bool
    verbose::Bool
    broken::Bool
    db::ExampleDB
    buffer_size::UInt
    function CheckConfig(; rng::Random.AbstractRNG, max_examples::Int, record=true,
                            verbose=false, broken=false, db::Union{Bool,ExampleDB}=true, buffer_size=100_000, kws...)
        !isempty(kws) && @warn "Got unsupported keyword arguments to CheckConfig! Ignoring:" Keywords=keys(kws)
        database::ExampleDB = if db isa Bool
            if db
                default_directory_db()
            else
                NoRecordDB()
            end
        else
            db
        end
        new(rng,
            max_examples,
            record,
            verbose,
            broken,
            database,
            buffer_size)
    end
end

function merge(cc::CheckConfig; kws...)
    unknown_args = setdiff(keys(kws), propertynames(cc))
    isempty(unknown_args) || @warn "Got unsupported keyword arguments to CheckConfig! Ignoring:" Keywords=unknown_args
    cfg = ( k => get(kws, k, getproperty(cc, k)) for k in propertynames(cc) )
    CheckConfig(;cfg...)
end

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
 * `error_cache`: A cache of errors encountered during shrinking that were not of the same type as the first found one, or are from a different location
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
    error_cache::Vector{Tuple{Type, StackFrame}}
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
        error_cache = Tuple{Type,StackFrame}[]
        new(
            conf,              # pass the given arguments through
            test_function,
            rng_orig,
            0,                # no tests so far
            0,                # no calls so far
            nothing,          # no result so far
            nothing,          # no target score so far
            nothing,          # no error thrown so far
            error_cache,      # for display purposes only
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
    config::CheckConfig
    function SuppositionReport(func::String; description::String="",
                                record_base::String="", rng=Random.Xoshiro(rand(Random.RandomDevice(), UInt)), config=DEFAULT_CONFIG[], kws...)
        desc = isempty(description) ? func : description
        db = if config.db isa UnsetDB && !haskey(kws, :db)
            default_directory_db()
        else
            config.db
        end
        conf = merge(config; rng, db, kws...)
        new(desc, record_base, nothing, nothing, time(), nothing, conf)
    end
end

