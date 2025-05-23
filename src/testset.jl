function results(sr::SuppositionReport)
    res_pass = @something(sr.result) isa Pass
    res_fail = @something(sr.result) isa Fail
    res_error = @something(sr.result) isa Error
    istimeout = @something(sr.result) isa Timeout
    expect_broken = sr.config.broken
    ispass = res_pass && !expect_broken
    iserror = res_error && !expect_broken
    isfail = (res_pass && expect_broken) || (res_fail && !expect_broken)
    isbroken = !(ispass | iserror | isfail | istimeout)
    (;ispass,isfail,iserror,isbroken,istimeout)
end

function _format_duration(sr::SuppositionReport)
    dur_s = total_time(statistics(sr))

    if isnan(dur_s)
        "?s"
    elseif dur_s < 60
        string(round(dur_s, digits = 1), "s")
    else
        m, s = divrem(dur_s, 60)
        s = lpad(string(round(s, digits = 1)), 4, "0")
        string(round(Int, m), "m", s, "s")
    end
end

Test.get_alignment(sr::SuppositionReport, depth::Int) = 2*depth + textwidth(sr.description)

@static if VERSION.major >= 1 && VERSION.minor >= 11
    # these are only defined from 1.11 onwards, earlier the printing didn't do anything anyway
    Test.print_verbose(sr::SuppositionReport) = sr.config.verbose

    Test.format_duration(sr::SuppositionReport) = _format_duration(sr)

    function Test.get_test_counts(sr::SuppositionReport)
        res = results(sr)
        (;ispass,isfail,iserror,isbroken,istimeout) = res
        @assert isone(count(values(res))) values(res)
        return Test.TestCounts(
            true,
            ispass,
            isfail,
            iserror+istimeout,
            isbroken,
            0,
            0,
            0,
            0,
            Test.format_duration(sr)
        )
    end
end # @static if

function Test.print_test_results(sr::SuppositionReport, depth_pad=0)
    # Calculate the overall number for each type so each of
    # the test result types are aligned
    res = results(sr)
    total_pass   = Int(res.ispass)
    total_fail   = Int(res.isfail)
    total_error  = Int(res.iserror)
    total_broken = Int(res.isbroken)
    dig_pass   = total_pass   > 0 ? ndigits(total_pass)   : 0
    dig_fail   = total_fail   > 0 ? ndigits(total_fail)   : 0
    dig_error  = total_error  > 0 ? ndigits(total_error)  : 0
    dig_broken = total_broken > 0 ? ndigits(total_broken) : 0
    total = total_pass + total_fail + total_error + total_broken
    dig_total = total > 0 ? ndigits(total) : 0
    # For each category, take max of digits and header width if there are
    # tests of that type
    pass_width   = dig_pass   > 0 ? max(length("Pass"),   dig_pass)   : 0
    fail_width   = dig_fail   > 0 ? max(length("Fail"),   dig_fail)   : 0
    error_width  = dig_error  > 0 ? max(length("Error"),  dig_error)  : 0
    broken_width = dig_broken > 0 ? max(length("Broken"), dig_broken) : 0
    total_width  = max(textwidth("Total"),  dig_total)
    duration = _format_duration(sr)
    duration_width = max(textwidth("Time"), textwidth(duration))
    # Calculate the alignment of the test result counts by
    # recursively walking the tree of test sets
    align = max(Test.get_alignment(sr, 0), textwidth("Test Summary:"))
    # Print the outer test set header once
    printstyled(rpad("Test Summary:", align, " "), " |", " "; bold=true)
    if pass_width > 0
        printstyled(lpad("Pass", pass_width, " "), "  "; bold=true, color=:green)
    end
    if fail_width > 0
        printstyled(lpad("Fail", fail_width, " "), "  "; bold=true, color=Base.error_color())
    end
    if error_width > 0
        printstyled(lpad("Error", error_width, " "), "  "; bold=true, color=Base.error_color())
    end
    if broken_width > 0
        printstyled(lpad("Broken", broken_width, " "), "  "; bold=true, color=Base.warn_color())
    end
    if total_width > 0 || total == 0
        printstyled(lpad("Total", total_width, " "), "  "; bold=true, color=Base.info_color())
    end
    printstyled(lpad("Time", duration_width, " "); bold=true)
    println()
    fallbackstr = " "
    subtotal = total_pass + total_fail + total_error + total_broken
    # Print test set header, with an alignment that ensures all
    # the test results appear above each other
    print(rpad(string("  "^depth_pad, sr.description), align, " "), " | ")

    n_passes = total_pass
    if n_passes > 0
        printstyled(lpad(string(n_passes), pass_width, " "), "  ", color=:green)
    elseif pass_width > 0
        # No passes at this level, but some at another level
        printstyled(lpad(fallbackstr, pass_width, " "), "  ", color=:green)
    end

    n_fails = total_fail
    if n_fails > 0
        printstyled(lpad(string(n_fails), fail_width, " "), "  ", color=Base.error_color())
    elseif fail_width > 0
        # No fails at this level, but some at another level
        printstyled(lpad(fallbackstr, fail_width, " "), "  ", color=Base.error_color())
    end

    n_errors = total_error
    if n_errors > 0
        printstyled(lpad(string(n_errors), error_width, " "), "  ", color=Base.error_color())
    elseif error_width > 0
        # No errors at this level, but some at another level
        printstyled(lpad(fallbackstr, error_width, " "), "  ", color=Base.error_color())
    end

    n_broken = total_broken
    if n_broken > 0
        printstyled(lpad(string(n_broken), broken_width, " "), "  ", color=Base.warn_color())
    elseif broken_width > 0
        # None broken at this level, but some at another level
        printstyled(lpad(fallbackstr, broken_width, " "), "  ", color=Base.warn_color())
    end

    if n_passes == 0 && n_fails == 0 && n_errors == 0 && n_broken == 0
        total_str = string(subtotal)
        printstyled(lpad(total_str, total_width, " "), "  ", color=Base.info_color())
    else
        printstyled(lpad(string(subtotal), total_width, " "), "  ", color=Base.info_color())
    end

    printstyled(lpad(duration, duration_width, " "))
    println()
end

record_name(sr::SuppositionReport) = sr.record_base * "_" * sr.description

struct InvalidInvocation <: Exception
    res::Test.Result
end
function Base.showerror(io::IO, ii::InvalidInvocation)
    print(io, "InvalidInvocation: ")
    msg = if ii.res isa Test.Error
        "Got an error from outside the testsuite!"
    else
        "Can't record results from `@test` to this kind of TestSet!"
    end
    println(io, msg)
    show(io, ii.res)
end
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

function Test.finish(sr::SuppositionReport)
    # if the report doesn't have a result, we probably got
    # an error outside of the testsuite somewhere, somehow
    # either way, trying to print a nonexistent result
    # can't be done, so just return instead
    isnothing(sr.result) && return sr
    res = @something(sr.result)
    expect_broken = sr.config.broken

    # this is a failure, so record the result in the db
    # timeouts are like a failure, but there is nothing to record
    if !(res isa Pass || res isa Timeout)
        ts = @something sr.final_state
        attempt::Attempt = @something err_choices(ts) ts.result begin
            @warn "Unexpected result!" Res=res
            nothing
        end
        record!(sr.config.db, record_name(sr), attempt)
    end

    # we can only record if there's a parent `@testset`
    if Test.get_testset_depth() != 0
        parent_ts = Test.get_testset()
        sr.config.record && Test.record(parent_ts, sr)

        # we only need to explicitly `show` if we're not the outermost AbstractTestset
        if sr.config.verbose || # always show the result
           (!expect_broken && !(res isa Pass)) || # we expected it to pass, but it failed/errored
           (expect_broken && res isa Pass)        # we expected it to fail, but it passed
            io = IOContext(stderr, :supposition_subtestset=>true)
            show(io, MIME"text/plain"(), sr)
        end
    end

    # this will be returned from a top-level `@check`, which will invoke `show`
    sr
end
