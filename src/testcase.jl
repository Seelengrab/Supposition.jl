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
    for_choices(prefix, rng=Random.default_rng())

Create a `TestCase` for a given set of known choices.
"""
function for_choices(prefix::Vector{UInt64}, rng=Random.default_rng())
    return TestCase(
        prefix,
        rng,
        convert(UInt, length(prefix)),
        UInt64[],
        nothing)
end

"""
    forced_choice(tc::TestCase, n::UInt64)

Insert a definite choice in the choice sequence.

Note that all integrity checks happen here!
"""
function forced_choice!(tc::TestCase, n::UInt64)
    if length(tc.choices) >= tc.max_size
        throw(Overrun())
    else
        push!(tc.choices, n)
        return n
    end
end

"""
    weighted(tc::TestCase, p::Float64)

Return `true` with probability `p`, `false` otherwise.
"""
function weighted!(tc::TestCase, p::Float64)
    if length(tc.choices) < length(tc.prefix)
        preordained = tc.prefix[length(tc.choices)+1]
        if preordained > 1
            throw(Invalid())
        else
            isone(forced_choice!(tc, preordained))
        end
    else
        # the interval drawn from here is [0, 1.0)
        result = rand(tc.rng) < p
        forced_choice!(tc, UInt64(result))
        result
    end
end

"""
    choice!(tc::TestCase, n)

Force a number of choices to occur, taking from the existing prefix first.
If the prefix is exhausted, draw from `[zero(n), n]` instead.
"""
function choice!(tc::TestCase, n::UInt)
    if length(tc.choices) < length(tc.prefix)
        preordained = tc.prefix[length(tc.choices)+1]
        if preordained > n
            throw(Invalid())
        else
            forced_choice!(tc, preordained)
        end
    else
        result = rand(tc.rng, zero(n):n)
        forced_choice!(tc, UInt(result))
    end
end

function choice!(tc::TestCase, n::Int)
    n >= 0 || throw(ArgumentError("Can't make a negative number of choices!"))
    choice!(tc, n % UInt) % Int
end

function choice!(tc::TestCase, values::AbstractVector)
    n = length(values)
    forced_i = choice!(tc, n - 1) + 1
    values[forced_i]
end

"""
    reject(::TestCase)

Mark this test case as invalid.
"""
function reject(::TestCase)
    throw(Invalid())
end

"""
    assume!(::TestCase, precondition::Bool)

If this precondition is not met, abort the test and mark this test case as invalid.
"""
function assume!(::TestCase, precondition::Bool)
    if !precondition
        throw(Invalid())
    else
        nothing
    end
end

function target!(tc::TestCase, score::Float64)
    if !isnothing(tc.targeting_score)
        @warn "`target!` called twice on test case object. Overwriting score." OldScore=@something(tc.targeting_score) NewScore=score
    end
    tc.targeting_score = Some(score)
    score
end
