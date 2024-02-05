"""
    TestState

 * `rng`: The RNG object this test is ultimately drawing from
 * `max_examples`: The maximum number of examples to draw
 * `is_interesting`: The user given property to investigate
 * `valid_test_cases`: The count of (so far) valid encountered testcases
 * `result`: The resulting shrunken choice sequence, if any
 * `best_scoring`: The best scoring result that was encountered during shrinking
 * `test_is_trivial`: Whether `is_interesting` is trivial, i.e. led to no choices being required
"""
mutable struct TestState
    rng::Random.AbstractRNG
    max_examples::UInt
    is_interesting::Any
    valid_test_cases::UInt
    calls::UInt
    result::Option{Vector{UInt64}}
    best_scoring::Option{Tuple{Float64, Vector{UInt64}}}
    test_is_trivial::Bool
    function TestState(rng::Random.AbstractRNG, test_function, max_examples)
        new(
            rng,              # pass the given arguments through
            max_examples,
            test_function,
            0,                # no tests so far
            0,                # no calls so far
            nothing,          # no result so far
            nothing,          # no target score so far
            false)            # test is presumed nontrivial
    end
end

"""
    CURRENT_TESTCASE

A `ScopedValue` containing the currently active test case. Intended for use in user-facing
functions like `target!` or `assume!` that need access to the current testcase, but shouldn't
require it as an argument to make the API more user friendly.
"""
const CURRENT_TESTCASE = ScopedValue{TestCase}()

"""
    test_function(ts::TestState, tc::TestCase)

Test the function given to `ts` on the test case `tc`.

Returns a `NTuple{Bool, 2}` indicating whether `tc` is interesting and whether it is
"better" than the previously best recorded example in `ts`.

!!! note "Targeting"
    If the function given to `ts` never targets anything, the second element of
    the returned tuple will always be `false`.
"""
function test_function(ts::TestState, tc::TestCase)
    # one call == one test of the function in `ts` for the given `TestCase`
    ts.calls += 1

    interesting = try
        @with CURRENT_TESTCASE => tc begin
            ts.is_interesting(tc)
        end
    catch e
        e isa Error && return (false, false)
        # TODO: instead of rethrowing, try to handle this explicitly by marking it as an error-shrink?
        # could be more interesting, by shrinking e.g. the length of a stacktrace while keeping the error
        # origin the same, to get the same failure earlier.
        rethrow()
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
                ts.best_scoring = Some((score, tc.choices))
                was_better = true
            end
        end

        return (false, was_better)

    else
        ts.test_is_trivial = isempty(tc.choices)
        ts.valid_test_cases += 1

        # Check for interestingness
        was_more_interesting = false
        if isnothing(ts.result) ||
                length(@something ts.result) > length(tc.choices) ||
                @something(ts.result) > tc.choices
            ts.result = Some(tc.choices)
            was_more_interesting = true
        end

        # check for target improvement
        was_better = false
        if !isnothing(tc.targeting_score)
            score = @something tc.targeting_score
            if first(@something ts.best_scoring Some((typemin(score), UInt[]))) < score
                ts.best_scoring = Some((score, tc.choices))
                was_better = true
            end
        end

        return (was_more_interesting, was_better)
    end
end

"""
    run(ts::TestState)

Run the checking algorithm on `ts`, generating values until we should stop, targeting
the score we want to target on and finally shrinking the result.
"""
function run(ts::TestState)
    @debug "Starting generating values"
    generate!(ts)
    @debug "Improving targeted example"
    target!(ts)
    @debug "Shrinking targeted example"
    shrink!(ts)
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
    no_result = isnothing(ts.result)
    more_examples = ts.valid_test_cases < ts.max_examples
    # this 10x ensures that we can make many more calls than
    # we need to fill valid test cases, especially when targeting
    more_calls = ts.calls < (10*ts.max_examples)
    ret = !triv & no_result & more_examples & more_calls
    return ret
end

"""
    adjust(ts::TestState, attempt)

Adjust `ts` by testing for the choices given by `attempt`.

Returns whether `attempt` gave a better score than the best recorded
score in `ts`.

Used exclusively for targeting.
"""
function adjust(ts::TestState, attempt::Vector{UInt64})
    result = test_function(ts, for_choices(attempt))
    last(result)
end

"""
    target!(ts::TestState)

If `ts` has a target to go towards set, this will try to climb towards that target
by adjusting the choice sequence until `ts` shouldn't generate anymore.
"""
function target!(ts::TestState)
    !isnothing(ts.result) && return
    isnothing(ts.best_scoring) && return

    while should_keep_generating(ts)
        # It may happen that choices is all zeroes, and that targeting upwards
        # doesn't do anything. In this case, the loop will run until max_examples
        # is exhausted.

        # can we climb up?
        new = copy(last(@something ts.best_scoring))
        i = rand(ts.rng, 1:length(new))
        new[i] += 1

        if adjust(ts, new)
            k = 1
            new[i] += k
            while should_keep_generating(ts) && adjust(ts, new)
                k *= 2
                new[i] += k
            end
            while k > 0
                while should_keep_generating(ts) && adjust(ts, new)
                    new[i] += k
                end
                k ÷= 2
            end
        end

        # Or should we climb down?
        new = copy(last(@something ts.best_scoring))
        if new[i] < 1
            continue
        end

        new[i] -= 1
        if adjust(ts, new)
            k = 1
            if new[i] < k
                continue
            end
            new[i] -= k

            while should_keep_generating(ts) && adjust(ts, new)
                if new[i] < k
                    break
                end

                new[i] -= k
                k *= 2
            end
            while k > 0
                while should_keep_generating(ts) && adjust(ts, new)
                    if new[i] < k
                        break
                    end

                    new[i] -= k
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
const BUFFER_SIZE = Ref((8 * 1024) % UInt)

"""
    generate(ts::TestState)

Try to generate an example that falsifies the property given to `ts`.
"""
function generate!(ts::TestState)
    while should_keep_generating(ts) & (isnothing(ts.best_scoring) || (ts.valid_test_cases <= ts.max_examples÷2))
        tc = TestCase(UInt64[], ts.rng, BUFFER_SIZE[])
        test_function(ts, tc)
    end
end

"""
    consider(ts::TestState, choices) -> Bool

Returns whether the given choices are a conceivable example for the testcase given by `ts`.
"""
function consider(ts::TestState, choices::Vector{UInt64})::Bool
    if choices == @something(ts.result, Some(nothing))
        true
    else
        first(test_function(ts, for_choices(choices)))
    end
end
