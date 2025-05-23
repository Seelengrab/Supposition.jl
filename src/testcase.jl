"""
    for_choices(prefix; rng=Random.default_rng())

Create a `TestCase` for a given set of known choices.
"""
function for_choices(prefix::Vector{UInt64}, rng::Random.AbstractRNG, generation::UInt, max_generation::Int)
    return TestCase(
        prefix,
        rng,
        convert(UInt, length(prefix)),
        nothing,
        Attempt(UInt64[],
                generation,
                max_generation,
                Pair{AbstractString,Any}[]),
        nothing,
        nothing
    )
end
for_choices(prefix::Vector{UInt64}; rng::Random.AbstractRNG=Random.default_rng(), generation=1, max_generation=-1) =
    for_choices(prefix, rng, convert(UInt, generation), max_generation)
for_choices(attempt::Attempt, rng::Random.AbstractRNG) = for_choices(attempt.choices, rng, attempt.generation, attempt.max_generation)

"""
    forced_choice(tc::TestCase, n::UInt64)

Insert a definite choice in the choice sequence.

Note that all integrity checks happen here!
"""
function forced_choice!(tc::TestCase, n::UInt64)
    if length(tc.attempt.choices) >= tc.max_size
        throw(Overrun())
    else
        push!(tc.attempt.choices, n)
        return n
    end
end

"""
    weighted(tc::TestCase, p::Float64)

Return `true` with probability `p`, `false` otherwise.
"""
function weighted!(tc::TestCase, p::Float64)
    if length(tc.attempt.choices) < length(tc.prefix)
        preordained = tc.prefix[length(tc.attempt.choices)+1]
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
    if length(tc.attempt.choices) < length(tc.prefix)
        preordained = tc.prefix[length(tc.attempt.choices)+1]
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

Reject this `TestCase` if `precondition` is `false`.
"""
function assume!(::TestCase, precondition::Bool)
    if !precondition
        throw(Invalid())
    else
        nothing
    end
end

"""
    target!(tc::TestCase, score::Float64)

Update `tc` to use `score` as the score this `TestCase` achieves during optimization.

!!! warning "Multiple Updates"
    This score can only be set once! Repeated calls will be ignored.
"""
function target!(tc::TestCase, score::Float64)
    if !isnothing(tc.targeting_score)
        @warn "`target!` called twice on test case object. Overwriting score." OldScore=@something(tc.targeting_score) NewScore=score
    end
    tc.targeting_score = Some(score)
    score
end
