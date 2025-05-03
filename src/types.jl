
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
    events::Vector{Pair{AbstractString,Any}}
end
Attempt(choices::Vector{UInt64}, gen, max_gen) = Attempt(choices, gen, max_gen, Pair{AbstractString,Any}[])
Base.copy(attempt::Attempt) = Attempt(copy(attempt.choices), attempt.generation, attempt.max_generation, attempt.events)

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
 * `generation_start`: A timestamp from the moment before generation of the input started.
 * `call_start`: A timestamp from the moment before the input was passed to the property under test.

!!! warning "Internal"
    The properties of this struct, as well as the functions acting on it directly,
    are considered internal and not intended for use outside of the internals of
    Supposition.jl. Doing so may lead to wrong results, crashes, infinite
    loops or other undesirable behavior.
"""
mutable struct TestCase{RNG <: Random.AbstractRNG}
    prefix::Vector{UInt64}
    const rng::RNG
    max_size::UInt
    targeting_score::Option{Float64}
    attempt::Attempt
    generation_start::Option{Float64}
    call_start::Option{Float64}
end

TestCase(prefix::Vector{UInt64}, rng::Random.AbstractRNG, generation, max_generation, max_size) =
     TestCase(prefix, rng, convert(UInt, max_size), nothing,
                Attempt(UInt64[], convert(UInt, generation), convert(Int, max_generation), Pair{AbstractString,Any}[]),
                nothing, nothing)

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
 * `timeout`: The maximum amount of time `@check` attempts new examples for. Expects a `Dates.TimeType`, can be disabled by setting to `nothing`. Defaults to `nothing`.

!!! note "`timeout` & `max_examples` interaction"
    These two configurations have similar goals - putting some upper limit on the number
    of examples attempted. If both are set, whichever occurs first will stop execution.

!!! warning "Timeout behavior"
    There are some caveats regarding a set timeout:

      * If a property is tested while the timeout occurs, the existing computation
        will currently not be aborted. This is considered an implementation detail,
        and thus may change in the future.
      * If the timeout is set too small and no execution starts at all, this is also
        considered a test failure.

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
    timeout::Option{Dates.TimePeriod}
    function CheckConfig(; rng::Random.AbstractRNG, max_examples::Int, record=true,
                            verbose=false, broken=false, db::Union{Bool,ExampleDB}=true, buffer_size=100_000,
                            timeout::Union{Dates.TimePeriod, Nothing}=nothing, kws...)
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
            buffer_size,
            isnothing(timeout) ? nothing : Some(timeout))
    end
end

function merge(cc::CheckConfig; kws...)
    unknown_args = setdiff(keys(kws), propertynames(cc))
    isempty(unknown_args) || @warn "Got unsupported keyword arguments to CheckConfig! Ignoring:" Keywords=unknown_args
    cfg = ( k => get(kws, k, getproperty(cc, k)) for k in propertynames(cc) )
    CheckConfig(;cfg...)
end

"""
    Stats

A collection of various statistics of the execution of one [`@check`](@ref).

 * `attempts`: Total number of attempts to generate an input
 * `acceptions`: Number of times an input was accepted as valid
 * `rejections`: Number of times an input was `reject!`ed
 * `overruns`: Number of times an `Overrun` occurred during generation
 * `invocations`: Total number of invocations of the property under test
 * `mean_gentime`: Mean time for generating an input
 * `squared_dist_gentime`: Aggregated squared distance from the mean gentime
 * `mean_runtime`: Mean execution time of the property
 * `squared_dist_runtime`: Aggregated squared distance from the mean runtime
 * `shrinks`: Number of times a counterexample was shrunk successfully
 * `total_time`: The total (wall-clock) time used.
"""
struct Stats
    attempts::Int
    acceptions::Int
    rejections::Int
    invocations::Int
    overruns::Int
    mean_gentime::Float64
    squared_dist_gentime::Float64
    mean_runtime::Float64
    squared_dist_runtime::Float64
    shrinks::Int
    total_time::Float64
    function Stats(; attempts=0,
                     acceptions=0,
                     rejections=0,
                     invocations=0,
                     overruns=0,
                     mean_gentime=NaN,
                     squared_dist_gentime=0.0,
                     mean_runtime=NaN,
                     squared_dist_runtime=0.0,
                     shrinks=0,
                     total_time=NaN,
                     kws...)
        !isempty(kws) && @warn "Got unsupported keyword arguments to Stats! Ignoring:" Keywords=keys(kws)
        new(attempts, acceptions, rejections,
            invocations, overruns, mean_gentime,
            squared_dist_gentime, mean_runtime,
            squared_dist_runtime, shrinks, total_time)
    end
end

"""
    attempts(::Stats) -> Int

Retrieve the total number of attempts that were made to generate
a potential input to the property.
"""
attempts(s::Stats)         = s.attempts

"""
    acceptions(::Stats) -> Int

Retrieve the total number of examples that were accepted by
the property, i.e. how often the property returned `true`.
"""
acceptions(s::Stats)       = s.acceptions

"""
    rejections(::Stats) -> Int

Retrieve the total number of examples that were rejected by
the property, i.e. how often an input was `reject!`ed.
"""
rejections(s::Stats)       = s.rejections

"""
    invocations(::Stats) -> Int

Retrieve the total number of times the property was invoked with
and input.

This number may be less than [`attempts`](@ref), since some inputs
may be rejected before the property is invoked.
"""
invocations(s::Stats)      = s.invocations

"""
    overruns(::Stats) -> Int

Retrieve the total number of times generating an input required more
choices than were available from the currently used choice sequence.

This can happen if you attempt to generate more data than the maximum
buffer size configured, or when shrinking the choice sequence leads
to too few choices available.
"""
overruns(s::Stats)         = s.overruns

"""
    shrinks(::Stats) -> Int

Retrieve the total number of times a counterexample was successfully
shrunk to a smaller one.
"""
shrinks(s::Stats)          = s.shrinks

"""
    runtime_mean(::Stats) -> Float64

Retrieve the mean runtime in seconds of the property under test.
"""
runtime_mean(s::Stats)     = s.mean_runtime

"""
    runtime_variance(::Stats) -> Float64

Retrieve the variance of the runtime in seconds of the property under test.
"""
runtime_variance(s::Stats) = s.squared_dist_runtime / invocations(s)

"""
    gentime_mean(::Stats) -> Float64

Retrieve the mean time in seconds of generating an example.

This counts any attempt at generating an example, including early
rejections.
"""
gentime_mean(s::Stats)     = s.mean_gentime

"""
    gentime_variance(::Stats) -> Float64

Retrieve the variance of the time in seconds of generating an example.

This counts any attempt at generating an example, including early
rejections.
"""
gentime_variance(s::Stats) = s.squared_dist_gentime / attempts(s)


"""
    total_time(::Stats) -> Float64

Retrieve the total time taken for this fuzzing process.
"""
total_time(s::Stats)       = s.total_time

function Base.:(==)(a::Stats, b::Stats)
    a.attempts             ==  b.attempts             &&
    a.acceptions           ==  b.acceptions           &&
    a.rejections           ==  b.rejections           &&
    a.invocations          ==  b.invocations          &&
    a.overruns             ==  b.overruns             &&
    # these two need === since they're floats and use NaN
    # as an auxilliary; NaN === NaN is true (up to bitpatterns)
    a.mean_runtime         === b.mean_runtime         &&
    a.squared_dist_runtime === b.squared_dist_runtime &&
    a.shrinks              ==  b.shrinks
end

function merge(stats::Stats; kws...)
    unknown_args = setdiff(keys(kws), propertynames(stats))
    isempty(unknown_args) || @warn "Got unsupported keyword arguments to Stats! Ignoring:" Keywords=unknown_args
    data = ( k => get(kws, k, getproperty(stats, k)) for k in propertynames(stats) )
    Stats(;data...)
end

"""
    TestState

 * `config`: The configuration this `TestState` is running with
 * `is_interesting`: The user given property to investigate
 * `rng`: The currently used RNG
 * `stats`: A collection of statistics about this `TestState`
 * `result`: The choice sequence leading to a non-throwing counterexample
 * `best_scoring`: The best scoring result that was encountered during targeting
 * `target_err`: The error this test has previously encountered and the smallest choice sequence leading to it
 * `error_cache`: A cache of errors encountered during shrinking that were not of the same type as the first found one, or are from a different location
 * `test_is_trivial`: Whether `is_interesting` is trivial, i.e. led to no choices being required
 * `previous_example`: The previously recorded attempt (if any).
 * `start_time`: The point in time when this execution started. `nothing` means execution has not yet started.
 * `deadline`: The point in time (if any) after which no new examples will be generated.
"""
mutable struct TestState
    config::CheckConfig
    is_interesting::Any
    rng::Random.AbstractRNG
    stats::Stats
    result::Option{Attempt}
    best_scoring::Option{Tuple{Float64, Attempt}}
    target_err::Option{Tuple{Exception, Vector{StackFrame}, Int, Attempt}}
    error_cache::Vector{Tuple{Type, StackFrame}}
    test_is_trivial::Bool
    previous_example::Option{Attempt}
    start_time::Option{Float64}
    deadline::Option{Float64}
    function TestState(conf::CheckConfig, test_function, previous_example::Option{Attempt}=nothing)
        rng_orig = try
            copy(conf.rng)
        catch e
            # we only care about this outermost `copy` call
            (e isa MethodError && e.f == copy && only(e.args) == conf.rng) || rethrow()
            rethrow(ArgumentError("Encountered a non-copyable RNG object. If you want to use a hardware RNG, seed a copyable RNG like `Random.Xoshiro` and pass that instead."))
        end
        error_cache = Tuple{Type,StackFrame}[]
        deadline = if !isnothing(conf.timeout)
            Some(time() + Dates.tons(@something(conf.timeout))*1e-9)
        else
            nothing
        end
        new(
            conf,              # pass the given arguments through
            test_function,
            rng_orig,
            Stats(),
            nothing,          # no result so far
            nothing,          # no target score so far
            nothing,          # no error thrown so far
            error_cache,      # for display purposes only
            false,            # test is presumed nontrivial
            previous_example, # the choice sequence for the previous failure
            nothing,           # for keeping track of the total execution time
            deadline)         # for timeout purposes
    end
end

"""
    Result

An abstract type representing the ultimate result a `TestState` ended up at.
"""
abstract type Result end

"""
    Pass

A result indicating that no counterexample was found.
"""
struct Pass <: Result
    best::Option{Any}
    events::Vector{Pair{AbstractString,Any}}
    score::Option{Float64}
end

"""
    Fail

A result indicating that a counterexample was found.
"""
struct Fail <: Result
    example::NamedTuple
    events::Vector{Pair{AbstractString,Any}}
    score::Option{Float64}
end

"""
    Error

A result indicating that an error was encountered while generating or shrinking.
"""
struct Error <: Result
    example::NamedTuple
    events::Vector{Pair{AbstractString,Any}}
    exception::Exception
    trace
end

"""
    Timeout

A result indicating that no examples whatsoever were attempted,
due to reaching the timeout before a single example concluded.
"""
struct Timeout <: Result
    duration::Dates.TimePeriod
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
        new(desc, record_base, nothing, nothing, conf)
    end
end

function Base.show(io::IO, m::MIME"text/plain", sr::SuppositionReport)
    (;ispass,isfail,iserror,isbroken,istimeout) = results(sr)
    expect_broken = sr.config.broken
    if istimeout
        show_timeout(io, m, sr)
    elseif expect_broken && isfail
        # the test passed unexpectedly
        show_fix_broken(io, m, sr)
    elseif isfail
        # the test failed unexpectedly
        show_result(io, m, sr)
    elseif iserror
        # the test errored unexpectedly
        show_error(io, m, sr)
    elseif ispass
        # the test passed
        show_pass(io, m, sr)
    elseif isbroken
        # the test is expectedly broken
        show_broken(io, m, sr)
    end

    get(io, :supposition_subtestset, false) && write(io, '\n')
end

function show_arguments(io, ::MIME"text/plain", res::Union{Fail,Error})
    print(io, styled"""

      {underline:Arguments:}
    """)
    for k in keys(res.example)
        v = res.example[k]
        val = repr(v)
        print(io, styled"      {code:$k::$(typeof(v)) = $val}")
        k != last(keys(res.example)) && println(io)
    end
end

function show_events(io, ::MIME"text/plain", res::Result)
    print(io, styled"""


      {underline:Events:}
    """)
    for idx in eachindex(res.events)
        label, obj = res.events[idx]
        o = repr(obj)
        println(io, "    ", label)
        print(io, styled"        {code:$o}")
        idx != lastindex(res.events) && println(io)
    end
end

function show_result(io::IO, m::MIME"text/plain", sr::SuppositionReport)
    res::Fail = @something sr.result

    print(io, styled"""
    {error,bold:Found counterexample}
      {underline:Context:} $(sr.description)
    """)

    show_arguments(io, m, res)
    !isempty(res.events) && show_events(io, m, res)
end

function show_error(io::IO, m::MIME"text/plain", sr::SuppositionReport)
    res::Error = @something sr.result

    print(io, styled"""
    {error,bold:Encountered an error}
      {underline:Context:} $(sr.description)
    """)

    show_arguments(io, m, res)
    !isempty(res.events) && show_events(io, m, res)

    buf = IOContext(IOBuffer(), :color=>true)
    write(buf, "  ") # indentation for the message from `showerror`
    Base.showerror(buf, res.exception)
    Base.show_backtrace(buf, res.trace)
    seekstart(buf.io)

    print(io, styled"""


      {underline:Exception:}
        Message:
    """)

    write(io, "    ")
    join(io, eachline(buf; keep=true), "    ")
end

function show_pass(io::IO, m::MIME"text/plain", sr::SuppositionReport)
    res::Pass = @something sr.result

    print(io, styled"""
    {green,bold:Test passed}
      {underline:Context:} $(sr.description)""")

    if !isnothing(res.score)
        score = @something res.score
        print(io, styled"""


          {underline:Score:} {code:$score}""")
    end

    !sr.config.verbose && return

    !isempty(res.events) && show_events(io, m, res)
end

function show_fix_broken(io::IO, m::MIME"text/plain", sr::SuppositionReport)
    res::Pass = @something sr.result

    print(io, styled"""
    {red,bold:Test is marked broken, but passed}
      {underline:Context:} $(sr.description)

          Remove {code:broken=true} from {code:@check} invocation or passed-in {code:CheckConfig}.""")

    !sr.config.verbose && return

    !isempty(res.events) && show_events(io, m, res)
end

function show_broken(io::IO, m::MIME"text/plain", sr::SuppositionReport)
    res::Union{Error,Fail} = @something sr.result
    cause = res isa Error ? "Error" : "Failure"

    print(io, styled"""
    {yellow,bold:Test is known broken (Result: $cause)}
      {underline:Context:} $(sr.description)""")

    !sr.config.verbose && return

    !isempty(res.events) && show_events(io, m, res)
end

function show_timeout(io::IO, _::MIME"text/plain", sr::SuppositionReport)
    res::Timeout = @something sr.result

    print(io, styled"""
    {blue,bold:Hit timeout before any tests concluded (Timeout: $(res.duration))}
      {underline:Context:} $(sr.description)""")
end
