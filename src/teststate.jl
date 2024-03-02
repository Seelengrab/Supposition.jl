"""
    err_choices

Return the choices that led to the recorded error, if any.
If none, return `Nothing`.
"""
err_choices(ts::TestState) = if !isnothing(ts.target_err)
    Some(last(@something ts.target_err))
else
    nothing
end

"""
    CURRENT_TESTCASE

A `ScopedValue` containing the currently active test case. Intended for use in user-facing
functions like `target!` or `assume!` that need access to the current testcase, but shouldn't
require it as an argument to make the API more user friendly.

Not intended for user-side access, thus considered internal and not supported under semver.
"""
const CURRENT_TESTCASE = ScopedValue{TestCase}()

"""
    test_function(ts::TestState, tc::TestCase)

Test the function given to `ts` on the test case `tc`.

Returns a `NTuple{Bool, 2}` indicating whether `tc` is interesting and whether it is
"better" than the previously best recorded example in `ts`.
"""
function test_function(ts::TestState, tc::TestCase)
    # one call == one test of the function in `ts` for the given `TestCase`
    ts.calls += 1

    interesting, threw = try
        @with CURRENT_TESTCASE => tc begin
            ts.is_interesting(tc)
        end, nothing
    catch e
        # Interrupts are an abort signal, so rethrow
        e isa InterruptException && rethrow()
        # UndefVarError are a programmer error, so rethrow
        e isa UndefVarError && rethrow()
        # These are wanted rejections
        e isa TestException && return (false, false)
        # true errors are always interesting
        true, Some((e, stacktrace(catch_backtrace())))
    end

    !(interesting isa Bool) && return (false, false)

    if !interesting
        ts.test_is_trivial = isempty(tc.choices)
        ts.valid_test_cases += 1

        # check for target improvement
        was_better = false
        if !isnothing(tc.targeting_score)
            score = @something tc.targeting_score
            if first(@something ts.best_scoring Some((typemin(score),UInt[]))) < score
                ts.best_scoring = Some((score, Attempt(copy(tc.choices), tc.generation, tc.max_generation)))
                was_better = true
            end
        end

        return (false, was_better)

    else
        ts.test_is_trivial = isempty(tc.choices)
        ts.valid_test_cases += 1

        # Check for interestingness
        was_more_interesting = false
        if isnothing(threw) && (isnothing(ts.result) ||
                length((@something ts.result).choices) > length(tc.choices) ||
                (@something(ts.result).choices) > tc.choices)
            ts.result = Some(Attempt(copy(tc.choices), tc.generation, tc.max_generation))
            was_more_interesting = true
        end

        # check for target improvement
        was_better = false
        if !isnothing(tc.targeting_score)
            score = @something tc.targeting_score
            if first(@something ts.best_scoring Some((typemin(score), UInt[]))) < score
                ts.best_scoring = Some((score, Attempt(copy(tc.choices), tc.generation, tc.max_generation)))
                was_better = true
            end
        end

        if isnothing(ts.target_err)
            # we haven't had an error so far, but have we hit one now?
            if !isnothing(threw)
                err, trace = @something threw
                len = find_user_stack_depth(trace)
                ts.target_err = Some((err, trace, len, Attempt(copy(tc.choices), tc.generation, tc.max_generation)))
                return (true, true)
            end
        else # we already had an error - did we hit the same one?
            # we didn't throw, so this is strictly less interesting
            isnothing(threw) && return (false, false)
            err, trace = @something threw
            old_err, old_trace, old_len, old_attempt = @something ts.target_err
            old_frame = first(old_trace)
            frame = first(trace)
            # if the error isn't the same, it can't possibly be better
            if !(err == old_err && frame == old_frame)
                @warn "Encountered an error, but it was different from the previously seen one - Ignoring!" Error=err Location=frame
                return (false, false)
            end
            was_more_interesting = true
            len = find_user_stack_depth(trace)

            was_better |= len < old_len || (len == old_len && tc.choices < old_attempt.choices)
            if was_better
                ts.target_err = Some((err, trace, len, Attempt(copy(tc.choices), tc.generation, tc.max_generation)))
            end
        end

        return (was_more_interesting, was_better)
    end
end

"""
    find_user_stack_depth

Return a heuristic guess for how many functions deep in user code an error was thrown.
Falls back to the full length of the stacktrace.
"""
function find_user_stack_depth(trace)::Int
    res = findfirst(trace) do sf
        sf.func == :test_function && sf.file == Symbol(@__FILE__)
    end
    @something res Some(length(trace))
end

"""
    run(ts::TestState)

Run the checking algorithm on `ts`, generating values until we should stop, targeting
the score we want to target on and finally shrinking the result.
"""
function run(ts::TestState)
    @debug "Starting generating values" Test=ts.is_interesting
    generate!(ts)
    @debug "Improving targeted example"
    target!(ts)
    @debug "Shrinking example"
    shrink!(ts)
    @debug "Done!"
    nothing
end

"""
    should_keep_generating(ts::TestState)

Whether `ts` should keep generating new test cases, or whether `ts` is finished.

`true` returned here means that the given property is not trivial, there is no result yet
and we have room for more examples.
"""
function should_keep_generating(ts::TestState)
    triv = ts.test_is_trivial
    # Either we find a regular counterexample, or we error
    # both mean we can stop looking, and start shrinking
    no_result = isnothing(ts.result) & isnothing(ts.target_err)
    more_examples = ts.valid_test_cases < ts.config.max_examples
    # this 10x ensures that we can make many more calls than
    # we need to fill valid test cases, especially when targeting
    more_calls = ts.calls < (10*ts.config.max_examples)
    ret = !triv & no_result & more_examples & more_calls
    return ret
end

"""
    adjust(ts::TestState, attempt)

Adjust `ts` by testing for the choices given by `attempt`.

Returns whether `attempt` was by some measure better than the previously
best attempt.
"""
function adjust(ts::TestState, attempt::Attempt)
    result = test_function(ts, for_choices(attempt.choices, copy(ts.rng), attempt.generation, attempt.max_generation))
    last(result)
end

"""
    target!(ts::TestState)

If `ts` has a target to go towards set, this will try to climb towards that target
by adjusting the choice sequence until `ts` shouldn't generate anymore.

If `ts` is currently tracking an error it encountered, it will try to minimize the
stacktrace there instead.
"""
function target!(ts::TestState)
    !(isnothing(ts.result) && isnothing(ts.target_err)) && return
    isnothing(ts.best_scoring) && return
    @debug "Targeting" Score=!isnothing(ts.best_scoring) Err=!isnothing(ts.target_err)

    while should_keep_generating(ts)
        # It may happen that choices is all zeroes, and that targeting upwards
        # doesn't do anything. In this case, the loop will run until max_examples
        # is exhausted.

        # can we climb up?
        new = copy(last(@something ts.target_err ts.best_scoring))
        i = rand(ts.rng, 1:length(new.choices))
        new.choices[i] += 1

        if adjust(ts, new)
            k = 1
            new.choices[i] += k
            while should_keep_generating(ts) && adjust(ts, new)
                k *= 2
                new.choices[i] += k
            end
            while k > 0
                while should_keep_generating(ts) && adjust(ts, new)
                    new.choices[i] += k
                end
                k ÷= 2
            end
        end

        # Or should we climb down?
        new = copy(last(@something ts.target_err ts.best_scoring))
        if new.choices[i] < 1
            continue
        end

        new.choices[i] -= 1
        if adjust(ts, new)
            k = 1
            if new.choices[i] < k
                continue
            end
            new.choices[i] -= k

            while should_keep_generating(ts) && adjust(ts, new)
                if new.choices[i] < k
                    break
                end

                new.choices[i] -= k
                k *= 2
            end
            while k > 0
                while should_keep_generating(ts) && adjust(ts, new)
                    if new.choices[i] < k
                        break
                    end

                    new.choices[i] -= k
                end
                k ÷= 2
            end
        end
    end
end

"""
    BUFFER_SIZE

The default maximum buffer size to use for a test case.
"""
const BUFFER_SIZE = Ref((100 * 1024) % UInt)

"""
    generate(ts::TestState)

Try to generate an example that falsifies the property given to `ts`.
"""
function generate!(ts::TestState)

    # 1) try to reproduce a previous failure
    if !isnothing(ts.previous_example)
        attempt = @something ts.previous_example
        # FIXME: the RNG should be stored too!
        tc = for_choices(attempt.choices, ts.rng, attempt.generation, attempt.max_generation)
        test_function(ts, tc)
    end

    # 2) try to generate new counterexamples
    while should_keep_generating(ts) & # no result
            (isnothing(ts.best_scoring) || # no score
             (ts.valid_test_cases <= ts.config.max_examples÷2))
        # +1, since we this test case is for the *next* call
        tc = TestCase(UInt64[], ts.rng, ts.calls+1, ts.config.max_examples, BUFFER_SIZE[])
        test_function(ts, tc)
    end
end

"""
    consider(ts::TestState, attempt::Attempt) -> Bool

Returns whether the given choices are a conceivable example for the testcase given by `ts`.
"""
function consider(ts::TestState, attempt::Attempt)::Bool
    compare = @something(ts.result, Some((;choices=nothing))).choices
    if attempt.choices == compare
        true
    else
        first(test_function(ts, for_choices(attempt.choices, copy(ts.rng), attempt.generation, attempt.max_generation)))
    end
end
