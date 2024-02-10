using Test: AbstractTestSet

abstract type Result end

"""
    Pass

A result indicating that no counterexample was found.
"""
struct Pass <: Result
    best::Option{Any}
    score::Option{Float64}
end

"""
    Fail

A result indicating that a counterexample was found.
"""
struct Fail <: Result
    example
    score::Option{Float64}
end

"""
    Error

A result indicating that an error was encountered while generating or shrinking.
"""
struct Error <: Result
    example
    exception::Exception
    trace
end

mutable struct SuppositionReport <: AbstractTestSet
    description::String
    final_state::Option{TestState}
    result::Option{Result}
    time_start::Float64
    time_end::Float64
    verbose::Bool
    expect_broken::Bool
    initial_rng::Random.AbstractRNG
    function SuppositionReport(desc::String; verbose=false, rng=Random.Xoshiro(rand(Random.RandomDevice(), UInt)),
                                             broken=false, kws...)
        new(desc, nothing, nothing, time(), 0.0, verbose, broken, rng)
    end
end

Test.print_verbose(sr::SuppositionReport) = sr.verbose

struct InvalidInvocation <: Exception
    res::Test.Result
end
Base.showerror(io::IO, ii::InvalidInvocation) = (print(io, "InvalidInvocation: Can't record results from `@test` to this kind of TestSet!"); show(io, ii.res))
Test.record(::SuppositionReport, res::Test.Result) = throw(InvalidInvocation(res))

Test.record(sr::SuppositionReport, ts::TestState) = if !isnothing(sr.final_state)
    @warn "Trying to set final state twice, ignoring!" State=ts
else
    sr.final_state = Some(ts)
end

Test.record(sr::SuppositionReport, res::Supposition.Result) = if !isnothing(sr.result)
    @warn "Trying to set result twice, ignoring!" Result=res
else
    sr.result = Some(res)
end

function Test.get_test_counts(sr::SuppositionReport)
    ispass = @something(sr.result) isa Pass
    isfail = @something(sr.result) isa Fail
    iserror = @something(sr.result) isa Error
    isbroken = sr.expect_broken && (isfail | iserror)
    @assert count((ispass, isfail, iserror, isbroken)) in (1,2)
    return Test.TestCounts(
        true,
        !isbroken & ispass,
        !isbroken & isfail,
        !isbroken & iserror,
        isbroken,
        0,
        0,
        0,
        0,
        Test.format_duration(sr)
    )
end

function Test.format_duration(sr::SuppositionReport)
    (; time_start, time_end) = sr
    isnothing(time_end) && return "?s"

    dur_s = time_end - time_start
    if dur_s < 60
        string(round(dur_s, digits = 1), "s")
    else
        m, s = divrem(dur_s, 60)
        s = lpad(string(round(s, digits = 1)), 4, "0")
        string(round(Int, m), "m", s, "s")
    end
end

function Test.finish(sr::SuppositionReport)
    sr.time_end = time()

    res = @something(sr.result)

    if sr.verbose
        print_results(sr, res)
    elseif !sr.expect_broken && !(res isa Pass)
        print_results(sr, res)
    end

    if Test.get_testset_depth() != 0
        parent_ts = Test.get_testset()
        Test.record(parent_ts, sr)
        return sr
    end

    Test.print_test_results(sr)
    sr
end

print_results(sr::SuppositionReport) = print_results(sr, @something(sr.result))

function print_results(sr::SuppositionReport, p::Pass)
    if isnothing(p.best)
        @info "Property passed!" Description=sr.description
    else
        best = @something(p.best)
        score = @something(p.score)
        @info "Property passed!" Description=sr.description Best=best Score=score
    end
end

function print_results(sr::SuppositionReport, e::Error)
    errmsg = string(e.exception)
    @error "Property errored!" Description=sr.description Exception=errmsg Example=e.example
end

function print_results(sr::SuppositionReport, f::Fail)
    if isnothing(f.score)
        @error "Property doesn't hold!" Description=sr.description Example=f.example
    else
        @error "Property doesn't hold!" Description=sr.description Example=f.example Score=f.score
    end
end
