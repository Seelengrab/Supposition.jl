module MiniThesis

using Base
export TestCase, TestState, forced_choice!, choice!, weighted!, assume!, target!, reject

import Random
using Logging

abstract type Error <: Exception end
struct Overrun <: Error end
struct Invalid <: Error end

const Option{T} = Union{Some{T}, Nothing}

mutable struct TestCase
    prefix::Vector{UInt64}
    rng::Random.AbstractRNG
    max_size::UInt
    choices::Vector{UInt64}
    targeting_score::Option{Float64}
end

TestCase(prefix::Vector{UInt64}, rng::Random.AbstractRNG, max_size) = TestCase(prefix, rng, max_size, UInt64[], nothing)

for_choices(prefix::Vector{UInt64}) = TestCase(
    prefix,
    Random.default_rng(),
    length(prefix),
    UInt64[],
    nothing)

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

Return 1 with probability `p`, 0 otherwise.
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
        result = rand(tc.rng) < p
        forced_choice!(tc, UInt64(result))
        result
    end
end

"""
    choice!(tc::TestCase, n)

Return an integer in the range [zero(n), n]
"""
function choice!(tc::TestCase, n)
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

"""
    target!(::TestCase, score::Float64)

Add a score to target. Put an expression here!
"""
function target!(tc::TestCase, score::Float64)
    if !isnothing(tc.targeting_score)
        @warn "target! called twice on test case object. Overwriting score." TestCase=tc
    end
    tc.targeting_score = Some(score)
end

module Data

using MiniThesis

abstract type Possibility{T} end

struct Map{T, S <: Possibility{T}, F} <: Possibility{T}
    source::S
    map::F
end

Base.map(f, p::Possibility) = Map(p, f)
produce(m::Map, tc::TestCase) = m.map(produce(m.source, tc))

## Possibilities of signed integers

struct Integers <: Possibility{Int64}
    minimum::Int64
    range::UInt64
    Integers(minimum::Int64, maximum::Int64) = new(minimum, (maximum - minimum) % UInt64)
end

function produce(i::Integers, tc::TestCase)
    offset = choice!(tc, i.range)
    return i.minimum + offset
end

## Possibilities of vectors

struct Vectors{T} <: Possibility{Vector{T}}
    elements::Possibility{T}
    min_size::UInt
    max_size::UInt
end

function produce(v::Vectors{T}, tc::TestCase) where T
    result = T[]

    while true
        if length(result) < v.min_size
            forced_choice!(tc, 1)
        elseif (length(result)+1) >= v.max_size
            forced_choice!(tc, 0)
            break
        elseif !weighted!(tc, 0.9)
            break
        end
        push!(result, produce(v.elements, tc))
    end

    return result
end

## Possibilities of pairs

struct Pairs{T,S} <: Possibility{Pair{T,S}}
    first::Possibility{T}
    second::Possibility{S}
end

produce(p::Pairs, tc::TestCase) = produce(p.first, tc) => produce(p.second, tc)

## Possibility of Just a value

struct Just{T} <: Possibility{T}
    value::T
end

produce(j::Just, _::TestCase) = copy(j.value)

## Possibility of Nothing

struct Nothing{T} <: Possibility{T} end

produce(::Nothing, tc::TestCase) = reject(tc)

## Possibility of mixing?

struct MixOf{T} <: Possibility{T}
    first::Possibility{T}
    second::Possibility{T}
end

function produce(mo::MixOf, tc::TestCase)
    if iszero(choice!(tc, 1))
        produce(mo.first, tc)
    else
        produce(mo.second, tc)
    end
end

end # data module

mutable struct TestState
    rng::Random.AbstractRNG
    max_examples::UInt
    is_interesting::Any
    valid_test_cases::UInt
    calls::UInt
    result::Option{Vector{UInt64}}
    best_scoring::Option{Tuple{Float64, Vector{UInt64}}}
    test_is_trivial::Bool
end

const BUFFER_SIZE = (8 * 1024) % UInt

function TestState(rng::Random.AbstractRNG, test_function, max_examples)
    TestState(
        rng,
        max_examples,
        test_function,
        0,
        0,
        nothing,
        nothing,
        false)
end

function test_function(ts::TestState, tc::TestCase)
    ts.calls += 1
    interesting = try
        ts.is_interesting(tc)
    catch e
        e isa Error && return (false, false)
        rethrow()
    end
    !(interesting isa Bool) && return (false, false)
    if !interesting
        ts.test_is_trivial = isempty(tc.choices)
        ts.valid_test_cases += 1
        was_better = false

        if !isnothing(tc.targeting_score)
            score = @something tc.targeting_score
            if first(@something ts.best_scoring Some((typemin(score),))) < score
                ts.best_scoring = Some((score, copy(tc.choices)))
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
            ts.result = Some(copy(tc.choices))
            was_more_interesting = true
        end

        # check for target improvement
        was_better = false
        if !isnothing(tc.targeting_score)
            score = @something tc.targeting_score
            if first(@something ts.best_scoring Some((typemin(score),))) < score
                ts.best_scoring = Some((score, copy(tc.choices)))
                was_better = true
            end
        end

        return (was_more_interesting, was_better)
    end
end

function run(ts::TestState)
    generate!(ts)
    target!(ts)
    shrink!(ts)
    nothing
end

function should_keep_generating(ts::TestState)
    triv = ts.test_is_trivial 
    no_result = isnothing(ts.result)
    more_examples =  ts.valid_test_cases < ts.max_examples
    more_calls = ts.calls < (10*ts.max_examples)
    ret = !triv & no_result & more_examples & more_calls
    return ret
end

function adjust(ts::TestState, attempt::Vector{UInt64})
    result = test_function(ts, for_choices(attempt))
    last(result)
end

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
            res = adjust(ts, new)
            while should_keep_generating(ts) && res
                k *= 2
                new[i] += k
                res = adjust(ts, new)
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

function generate!(ts::TestState)
    while should_keep_generating(ts) & (isnothing(ts.best_scoring) || (ts.valid_test_cases <= ts.max_examples÷2))
        test_function(ts, TestCase(UInt64[], ts.rng, BUFFER_SIZE))
    end
end

function consider(ts::TestState, choices::Vector{UInt64})::Bool
    if choices == @something(ts.result, Some(nothing))
        true
    else
        first(test_function(ts, for_choices(choices)))
    end
end

"""
    windows(array, a, b)

Split `array` into three windows, with split points at `a` and `b`.
The split points belong to the middle window.
"""
function windows(array, a,b)
    head = @view array[begin:a-1]
    middle = @view array[a:b]
    tail = @view array[b+1:end]
    head, middle, tail
end

"""
    shrink_remove(ts::TestState, attempt::Vector{UInt64}, k::UInt)

Try to shrink `attempt` by removing `k` elements at a time
"""
function shrink_remove(ts::TestState, attempt::Vector{UInt64}, k::UInt)::Option{Vector{UInt64}}
    k > length(attempt) && return nothing
    valid = ( (j, j+k-1) for j in (length(attempt)-k+1):-1:1 )
    for (x,y) in valid
        head, _, tail = windows(attempt, x, y)
        new = UInt[head; tail]
        if consider(ts, new)
            return Some(new)
        elseif x > 1 && new[x-1] > 0
            new[x-1] -= 1
            if consider(ts, new)
                return Some(new)
            end
        end
    end
    nothing
end

"""
    shrink_zeros(::TestSTate, attempt::Vector{UInt64}, k::UInt)

Try to shrink `attempt` by setting `k` elements at a time to zero.    
"""
function shrink_zeros(ts::TestState, attempt::Vector{UInt64}, k::UInt)
    k >= length(attempt) && return nothing
    valid = ( (j, j+k) for j in (length(attempt)-k):-1:1 )
    
    for (x,y) in valid
        if all(iszero, @view attempt[x:y-1])
            continue
        end
        head, _, tail = windows(attempt, x, y)
        new = [head; zeros(UInt64, y-x); tail]
        if consider(ts, new)
            return Some(new)
        end
    end
    nothing
end

"""
    shrink_reduce(::TestState, attempt::Vector{UInt64})

Try to shrink `attempt` by making the elements smaller.
"""
function shrink_reduce(ts::TestState, attempt::Vector{UInt64})
    new = copy(attempt)
    for i in reverse(1:length(attempt))
        res = bin_search_down(1, new[i], n -> begin
            new[i] = n
            consider(ts, new)
        end)
        new[i] = @something res Some(new[i])
    end

    if new == attempt
        nothing
    else
        Some(new)
    end
end

"""
    shrink_sort(::TestState, attempt::Vector{UInt64}, k::UInt)

Try to shrink `attempt` by sorting `k` contiguous elements at a time.
"""
function shrink_sort(ts::TestState, attempt::Vector{UInt64}, k::UInt)
    k >= length(attempt) && return nothing

    valid = ( (j-k+1, j) for j in length(attempt):-1:k)
    for (x,y) in valid
        head, middle, tail = windows(attempt, x, y)
        issorted(middle) && continue
        newmid = sort(middle)
        new = [head; newmid; tail]
        consider(ts, new) && return Some(new)
    end
    nothing
end

"""
    shrink_swap(::TestState, attempt::Vector{UInt64}, k::UInt)

Try to shrink `attempt` by swapping two elements length `k` apart.
"""
function shrink_swap(ts::TestState, attempt::Vector{UInt64}, k::UInt)
    valid = ( (j-k+1, j) for j in (length(attempt):-1:k))
    for (x,y) in valid
        attempt[x] == attempt[y] && continue
        new = copy(attempt)
        new[y] = attempt[x]

        res = bin_search_down(0, attempt[y], n -> begin
            new[x] = n
            consider(ts, new) 
        end)
        if !isnothing(res)
            new[x] = @something res
            return Some(new)
        end
    end
    nothing
end

"""
    shrink_redistribute(ts::TestState, attempt::Vector{UInt64}, k::UInt)

Try to shrink `attempt` by redistributing value between two elements length `k` apart.
"""
function shrink_redistribute(ts::TestState, attempt::Vector{UInt64}, k::UInt)
    length(attempt) < k && return nothing
    new = copy(attempt)
    valid = ( (j,j+k) for j in 1:(length(attempt)-k))
    for (x,y) in valid
        iszero(attempt[x]) && continue
        res = bin_search_down(0, attempt[x], n -> begin
            new[x] = n
            new[y] = attempt[x] + attempt[y] - n
            consider(ts, new)
        end)
        if !isnothing(res)
            v = @something res
            new[x] = v
            new[y] = attempt[x] + attempt[y] - v
        end
    end
    if new == attempt
        return nothing
    else
        return Some(new)
    end
end

function shrink!(ts::TestState)
    isnothing(ts.result) && return
    attempt = copy(@something ts.result)
    improved = true
    while improved
        improved = false

        for k in UInt.((8,4,2,1))
            while true
                res = shrink_remove(ts, attempt, k)
                attempt = @something res break
                improved = true
            end
        end

        for k in UInt.((8,4,2))
            while true
                res = shrink_zeros(ts, attempt, k)
                attempt = @something res break
                improved = true
            end
        end

        res = shrink_reduce(ts, attempt)
        if !isnothing(res)
            attempt = @something res
            improved = true
        end

        for k in UInt.((8,4,2))
            while true
                res = shrink_sort(ts, attempt, k)
                attempt = @something res break
                improved = true
            end
        end

        for k in UInt.((2,1))
            while true
                res = shrink_swap(ts, attempt, k)
                attempt = @something res break
                improved = true
            end
        end

        for k in UInt.((2,1))
            while true
                res = shrink_redistribute(ts, attempt, k)
                attempt = @something res break
                improved = true
            end
        end
    end
end

function bin_search_down(low, high, pred)
    pred(low) && return Some(low)
    !pred(high) && return nothing

    while (low+1) < high
        mid = low + (high - low)÷2
        if pred(mid)
            high = mid
        else
            low = mid
        end
    end
    Some(high)
end

function main()
    function test(tc::TestCase)
        n = @something choice!(tc, 1001)
        m = @something choice!(tc, 1001)
        score = n + m
        target!(tc, score)
        score >= 2000
    end
    ts = TestState(Random.default_rng(), test, 1000)
    run(ts)
    @assert !isnothing(ts.result)
end

end # MiniThesis module
