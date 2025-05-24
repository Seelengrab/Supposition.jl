###
# TestState manipulations & queries
###

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
    # No user code has run yet, so record only that we will attempt to do so
    count_attempt!(ts)

    interesting, threw = try
        @with CURRENT_TESTCASE => tc begin
            ts.is_interesting(ts, tc)
        end, nothing
    catch e
        # Interrupts are an abort signal, so rethrow
        e isa InterruptException && rethrow()
        # UndefVarError are a programmer error, so rethrow
        e isa UndefVarError && rethrow()
        # These are wanted rejections
        if e isa TestException
            e isa Overrun && count_overrun!(ts)
            e isa Invalid && count_invalid!(ts)
            return (false, false)
        end
        # true errors are always interesting
        true, Some((e, stacktrace(catch_backtrace())))
    finally
        record_durations!(ts, tc)
    end

    !(interesting isa Bool) && return (false, false)

    ts.test_is_trivial = isempty(tc.attempt.choices)
    # Now we know that the testcase was not rejected, so it is valid (true, false, or error in user code)
    count_valid!(ts)

    if !interesting
        # check for target improvement
        was_better = false
        if !isnothing(tc.targeting_score)
            score = @something tc.targeting_score
            old_score, _ = @something ts.best_scoring Some((typemin(score),nothing))
            if old_score < score
                ts.best_scoring = Some((score, copy(tc.attempt)))
                was_better = true
            end
        end

        return (false, was_better)

    else
        # Check for interestingness
        was_more_interesting = false
        if isnothing(threw) && (isnothing(ts.result) ||
                length((@something ts.result).choices) > length(tc.attempt.choices) ||
                (@something(ts.result).choices) > tc.attempt.choices)
            ts.result = Some(copy(tc.attempt))
            was_more_interesting = true
        end

        # check for target improvement
        was_better = false
        if !isnothing(tc.targeting_score)
            score = @something tc.targeting_score
            old_score, attempt = @something ts.best_scoring Some((typemin(score), (;choices=UInt[])))
            if old_score < score || (old_score == score && attempt.choices > tc.attempt.choices)
                ts.best_scoring = Some((score, copy(tc.attempt)))
                was_better = true
            end
        end

        if isnothing(ts.target_err)
            # we haven't had an error so far, but have we hit one now?
            if !isnothing(threw)
                err, trace = @something threw
                len = find_user_stack_depth(trace)
                ts.target_err = Some((err, trace, len, copy(tc.attempt)))
                return (true, true)
            end
        else # we already had an error - did we hit the same one?
            # we didn't throw, so this is strictly less interesting
            isnothing(threw) && return (false, false)
            err, trace = @something threw
            old_err, old_trace, old_len, old_attempt = @something ts.target_err
            old_frame = find_user_error_frame(old_err, old_trace)
            frame = find_user_error_frame(err, trace)
            # if the error isn't the same, it can't possibly be better
            if !(typeof(err) == typeof(old_err) && frame == old_frame)
                cache_entry = (typeof(err), frame)
                if !(cache_entry in ts.error_cache)
                    @warn "Encountered an error, but it was different from the previously seen one - Ignoring!" Error=err Location=frame
                    push!(ts.error_cache, cache_entry)
                end
                return (false, false)
            end
            was_more_interesting = true
            len = find_user_stack_depth(trace)

            was_better |= len < old_len || (len == old_len && tc.attempt.choices < old_attempt.choices) || (applicable(err_less, err, old_err) && err_less(err, old_err))
            if was_better
                ts.target_err = Some((err, trace, len, copy(tc.attempt)))
            end
        end

        return (was_more_interesting, was_better)
    end
end

"""
    find_user_error_frame(err, trace)

Try to heuristically guess where an error was actually coming from.

For example, `ErrorException` is (generally) thrown from the `error`
function, which would always report the same location if we'd naively
take the first frame of the trace. This tries to be a bit smarter (but
still fairly conservative) and return something other than the first
frame for a small number of known error-throwing functions.
"""
function find_user_error_frame end

find_user_error_frame(err, trace::Vector{StackFrame}) = first(trace)

function find_user_error_frame(err::ErrorException, trace::Vector{StackFrame})
    top_frame = first(trace)
    error_func_methods = methods(error)
    err_exc_lines = ( getproperty(em, :line) for em in error_func_methods )

    len_ok = length(trace) >= 2
    frame_is_error = top_frame.func == :error
    line_is_error = top_frame.line in err_exc_lines
    # we can special case the file here since this is only one error
    # NOTE: This can break in future versions, if the error function moves!
    file_is_error = top_frame.file === Symbol("./error.jl")
    if (len_ok & frame_is_error & line_is_error & file_is_error)
        # if there are more frames in the trace AND the top frame is just the `error` function,
        # return the frame that called `error` instead of `error` itself
        return @inbounds trace[2]
    else
        return top_frame
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

Checks for deterministic generation of input first.
"""
function run(ts::TestState)
    ts.start_time = Some(time())
    @debug "Checking determinism of generating values"
    determinism!(ts)
    if ts.generation_indeterminate isa Nondeterministic
        # No sense in trying to generate an input from something that we can't replay reliably
        return nothing
    end

    @debug "Starting generating values" Test=ts.is_interesting
    generate!(ts)
    @debug "Improving targeted example"
    target!(ts)
    @debug "Shrinking example"
    shrink!(ts)
    @debug "Done!"
    finalize_stats!(ts)
    nothing
end

"""
    should_keep_generating(ts::TestState)

Whether `ts` should keep generating new test cases, or whether `ts` is finished.

`true` returned here means that the given property is not trivial, there is no result yet
we have room for more examples, and we haven't hit the specified timeout yet.
"""
function should_keep_generating(ts::TestState)
    deadline = @something ts.deadline Some(typemax(Float64))
    time() >= deadline && return false
    stats = statistics(ts)

    triv = ts.test_is_trivial
    # Either we find a regular counterexample, or we error
    # both mean we can stop looking, and start shrinking
    no_result = isnothing(ts.result) & isnothing(ts.target_err)
    more_examples = invocations(stats) < ts.config.max_examples
    # this 10x ensures that we can make many more attempts than
    # we need to fill valid test cases, especially when targeting
    more_calls = attempts(stats) < (10*ts.config.max_examples)
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
            count_target!(ts)
            k = 1
            new.choices[i] += k
            while should_keep_generating(ts) && adjust(ts, new)
                count_target!(ts)
                k *= 2
                new.choices[i] += k
            end
            while k > 0
                while should_keep_generating(ts) && adjust(ts, new)
                    count_target!(ts)
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
            count_target!(ts)
            k = 1
            if new.choices[i] < k
                continue
            end
            new.choices[i] -= k

            while should_keep_generating(ts) && adjust(ts, new)
                count_target!(ts)
                if new.choices[i] < k
                    break
                end

                new.choices[i] -= k
                k *= 2
            end
            while k > 0
                while should_keep_generating(ts) && adjust(ts, new)
                    count_target!(ts)
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
    determinism!(ts::TestState)

Check if generating an example is deterministic, by first generating a random
example and then trying to replay the input, expecting to get the exact same object back.
"""
function determinism!(ts::TestState)
    original_testcase = TestCase(UInt64[], ts.rng, invocations(statistics(ts))+1, ts.config.max_examples, ts.config.buffer_size*8)
    determ_method = only(methods(determinism!, (TestState,), Supposition))

    obj1, threw1 = try
        ts.gen_input(original_testcase), false
    catch e
        # Interrupts are an abort signal, so rethrow
        e isa InterruptException && rethrow()
        # UndefVarError are a programmer error, so rethrow
        e isa UndefVarError && rethrow()
        # true errors are always interesting
        # filter this function out, since we have a guaranteed distinct callstack
        trace = filter!(stacktrace(catch_backtrace())) do frame
            is_det = frame.func === determ_method.name &&
                     frame.line === determ_method.line &&
                     frame.file === determ_method.file
            return is_det
        end
        (e, trace), true
    end

    duplicate_testcase = for_choices(original_testcase.attempt.choices, ts.rng, original_testcase.attempt.generation, original_testcase.attempt.max_generation)
    obj2, threw2 = try
        ts.gen_input(duplicate_testcase), false
    catch e
        # Interrupts are an abort signal, so rethrow
        e isa InterruptException && rethrow()
        # UndefVarError are a programmer error, so rethrow
        e isa UndefVarError && rethrow()
        # true errors are always interesting
        # filter this function out, since we have a guaranteed distinct callstack
        trace = filter!(stacktrace(catch_backtrace())) do frame
            is_det = frame.func === determ_method.name &&
                     frame.line === determ_method.line &&
                     frame.file === determ_method.file
            return is_det
        end
        (e, trace), true
    end

    # handle errors
    if (threw1 & threw2) && (obj1[1] != obj2[1] || any(Base.splat(!=), zip(obj1[2], obj2[2])))
        data = filter(splat(!=), collect(zip(obj1[2], obj2[2])))
        @debug "Nondeterminism: Threw consistent, errors distinct" O1=obj1 O2=obj2 Distinct=data
        ts.generation_indeterminate = ThrowsNondeterministic()
        return
    elseif threw1 != threw2
        @debug "Nondeterminism: Threw inconsistent" T1=threw1 T2=threw2
        ts.generation_indeterminate = ThrowsNondeterministic()
        return
    end

    # different types were generated on the same input
    if typeof(obj1) != typeof(obj2)
        @debug "Nondeterminism: Types different" O1=obj1 O2=obj2
        ts.generation_indeterminate = GenTypeNondeterministic()
        return
    end

    # types are equal, so we only need to check one object
    if isbitstype(obj1)
        # bitstypes are defined by their bitpattern, and noone can override `===`
        if obj1 !== obj2
            @debug "Nondeterminism: Bitstypes objects not identical" O1=obj1 O2=obj2
            ts.generation_indeterminate = GenObjNondeterministic()
        else
            ts.generation_indeterminate = Deterministic()
        end
        return
    end

    # This might be the only way to check whether something else doesn't
    # implement a custom method for something...
    noeq_iseq_m = only(methods(isequal, (NoEquality, NoEquality)))
    noeq_cmp_m = only(methods(==, (NoEquality, NoEquality)))

    # tricky case of mutables
    # first, check `isequal`, since that may fall back to `==` by default
    iseq_meths = methods(isequal, (typeof(obj1), typeof(obj2)))
    if isone(length(iseq_meths)) && only(iseq_meths) != noeq_iseq_m
        # non-fallback implementation, let's give it a try!
        if !isequal(obj1, obj2)
            @debug "Nondeterminism: Mutable objects not `isqeual`" O1=obj1 O2=obj2
            ts.generation_indeterminate = GenObjNondeterministic()
        else
            ts.generation_indeterminate = Deterministic()
        end
        return
    end

    # we hit the default of `isequal`, give `==` a try instead
    cmp_meths = methods(==, (typeof(obj1), typeof(obj2)))
    if isone(length(cmp_meths)) && only(cmp_meths) != noeq_cmp_m
        # non-fallback implementation, let's give it a try!
        if !(==(obj1, obj2))
            @debug "Nondeterminism: Mutable objects not `==`" O1=obj1 O2=obj2
            ts.generation_indeterminate = GenObjNondeterministic()
        else
            ts.generation_indeterminate = Deterministic()
        end
        return
    end
end

"""
    generate!(ts::TestState)

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
             (acceptions(statistics(ts)) <= ts.config.max_examples÷2))
        # +1, since this test case is for the *next* call
        tc = TestCase(UInt64[], ts.rng, invocations(statistics(ts))+1, ts.config.max_examples, ts.config.buffer_size*8)
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

statistics(ts::TestState)      = ts.stats
# `isnan` encodes whether the TestState is still executing
# TODO: introduce an explicit verb to query this
count_attempt!(ts::TestState)  = !isnan(total_time(ts.stats)) ? ts.stats : (ts.stats = add_attempt(ts.stats))
count_call!(ts::TestState)     = !isnan(total_time(ts.stats)) ? ts.stats : (ts.stats = add_invocation(ts.stats))
count_valid!(ts::TestState)    = !isnan(total_time(ts.stats)) ? ts.stats : (ts.stats = add_validation(ts.stats))
count_invalid!(ts::TestState)  = !isnan(total_time(ts.stats)) ? ts.stats : (ts.stats = add_invalidation(ts.stats))
count_overrun!(ts::TestState)  = !isnan(total_time(ts.stats)) ? ts.stats : (ts.stats = add_overrun(ts.stats))
count_shrink!(ts::TestState)   = !isnan(total_time(ts.stats)) ? ts.stats : (ts.stats = add_shrink(ts.stats))
count_target!(ts::TestState)   = !isnan(total_time(ts.stats)) ? ts.stats : (ts.stats = add_improvement(ts.stats))
finalize_stats!(ts::TestState) = !isnan(total_time(ts.stats)) ? ts.stats : (ts.stats = add_total_duration(ts.stats, time() - @something(ts.start_time)))

function record_durations!(ts::TestState, tc::TestCase)
    !isnan(total_time(ts.stats)) && return ts.stats

    t_record = time()
    if !isnothing(tc.call_start)
        # This happens when an input was rejected before the call started
        call_start = @something(tc.call_start)
        ts.stats = add_call_duration(ts.stats, t_record - call_start)
        if !isnothing(tc.generation_start)
            ts.stats = add_gen_duration(ts.stats, call_start - @something(tc.generation_start))
        end
    elseif !isnothing(tc.generation_start) # We got an error during generation
        ts.stats = add_gen_duration(ts.stats, t_record - @something(tc.generation_start))
    end

    return ts.stats
end

