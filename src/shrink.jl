function shrink!(ts::TestState)
    isnothing(ts.result) && isnothing(ts.target_err) && return
    attempt = @something err_choices(ts) ts.result
    improved = true
    while improved
        improved = false

        @debug "Shrinking through dropping values"
        large_block = max(16, length(attempt.choices)>>3)
        for k in UInt.((large_block,8,4,2,1))
            while true
                res = shrink_remove(ts, attempt, k)
                attempt = @something res break
                count_shrink!(ts)
                improved = true
            end
        end

        @debug "Shrinking through floating point shrinks"
        res = shrink_float(ts, attempt)
        if !isnothing(res)
            attempt = @something res
            count_shrink!(ts)
            improved = true
        end

        @debug "Shrinking through setting zero"
        for k in UInt.((8,4,2))
            while true
                res = shrink_zeros(ts, attempt, k)
                attempt = @something res break
                count_shrink!(ts)
                improved = true
            end
        end

        @debug "Shrinking through shrinking elements"
        res = shrink_reduce(ts, attempt)
        if !isnothing(res)
            attempt = @something res
            count_shrink!(ts)
            improved = true
        end

        @debug "Shrinking through sorting views"
        for k in UInt.((8,4,2))
            while true
                res = shrink_sort(ts, attempt, k)
                attempt = @something res break
                count_shrink!(ts)
                improved = true
            end
        end

        @debug "Shrinking through swapping elements"
        for k in UInt.((2,1))
            while true
                res = shrink_swap(ts, attempt, k)
                attempt = @something res break
                count_shrink!(ts)
                improved = true
            end
        end

        @debug "Shrinking through redistributing in a window"
        for k in UInt.((2,1))
            while true
                res = shrink_redistribute(ts, attempt, k)
                attempt = @something res break
                count_shrink!(ts)
                improved = true
            end
        end
    end
end

"""
    shrink_remove(ts::TestState, attempt::Attempt, k::UInt)

Try to shrink `attempt` by removing `k` elements at a time
"""
function shrink_remove(ts::TestState, attempt::Attempt, k::UInt)::Option{Attempt}
    k > length(attempt.choices) && return nothing
    valid = ( (j, j+k-1) for j in (length(attempt.choices)-k+1):-1:1 )
    for (x,y) in valid
        head, _, tail = windows(attempt.choices, x, y)
        new = Attempt(UInt[head; tail], attempt.generation, attempt.max_generation)
        if consider(ts, new)
            return Some(new)
        elseif x > 1 && new.choices[x-1] > 0
            new.choices[x-1] -= 1
            if consider(ts, new)
                return Some(new)
            end
        end
    end
    nothing
end

function shrink_float(ts::TestState, attempt::Attempt)
    new = Attempt(copy(attempt.choices), attempt.generation, attempt.max_generation)
    for idx in eachindex(new.choices)
        old = new.choices[idx]
        old_float = reinterpret(Float64, old)
        if isnan(old_float)
            n_val = copysign(Inf, old_float)
            new.choices[idx] = reinterpret(UInt64, n_val)
            if consider(ts, new)
                return Some(new)
            end
        end
    end
    nothing
end

"""
    shrink_zeros(::TestSTate, attempt::Attempt, k::UInt)

Try to shrink `attempt` by setting `k` elements at a time to zero.
"""
function shrink_zeros(ts::TestState, attempt::Attempt, k::UInt)
    k >= length(attempt.choices) && return nothing
    valid = ( (j, j+k) for j in (length(attempt.choices)-k):-1:1 )

    for (x,y) in valid
        if all(iszero, @view attempt.choices[x:y-1])
            continue
        end
        head, _, tail = windows(attempt.choices, x, y)
        new = Attempt([head; zeros(UInt64, y-x); tail], attempt.generation, attempt.max_generation)
        if consider(ts, new)
            return Some(new)
        end
    end
    nothing
end

"""
    shrink_reduce(::TestState, attempt::Attempt)

Try to shrink `attempt` by making the elements smaller.
"""
function shrink_reduce(ts::TestState, attempt::Attempt)
    new = Attempt(copy(attempt.choices), attempt.generation, attempt.max_generation)
    for i in reverse(1:length(attempt.choices))
        res = bin_search_down(0, new.choices[i], n -> begin
            new.choices[i] = n
            consider(ts, new)
        end)
        new.choices[i] = @something res Some(new.choices[i])
    end

    if new.choices == attempt.choices
        nothing
    else
        Some(new)
    end
end

"""
    shrink_sort(::TestState, attempt::Attempt, k::UInt)

Try to shrink `attempt` by sorting `k` contiguous elements at a time.
"""
function shrink_sort(ts::TestState, attempt::Attempt, k::UInt)
    k >= length(attempt.choices) && return nothing

    valid = ( (j-k+1, j) for j in length(attempt.choices):-1:k)
    for (x,y) in valid
        head, middle, tail = windows(attempt.choices, x, y)
        issorted(middle) && continue
        newmid = sort(middle)
        new = Attempt([head; newmid; tail], attempt.generation, attempt.max_generation)
        consider(ts, new) && return Some(new)
    end
    nothing
end

"""
    shrink_swap(::TestState, attempt::Attempt, k::UInt)

Try to shrink `attempt` by swapping two elements length `k` apart.
"""
function shrink_swap(ts::TestState, attempt::Attempt, k::UInt)
    valid = ( (j-k+1, j) for j in (length(attempt.choices):-1:k))
    for (x,y) in valid
        attempt.choices[x] == attempt.choices[y] && continue
        new = Attempt(copy(attempt.choices), attempt.generation, attempt.max_generation)
        new.choices[y] = attempt.choices[x]

        res = bin_search_down(0, attempt.choices[y], n -> begin
            new.choices[x] = n
            consider(ts, new)
        end)
        if !isnothing(res)
            new.choices[x] = @something res
            return Some(new)
        end
    end
    nothing
end

"""
    shrink_redistribute(ts::TestState, attempt::Attempt, k::UInt)

Try to shrink `attempt` by redistributing value between two elements length `k` apart.
"""
function shrink_redistribute(ts::TestState, attempt::Attempt, k::UInt)
    length(attempt.choices) < k && return nothing
    new = Attempt(copy(attempt.choices), attempt.generation, attempt.max_generation)
    valid = ( (j,j+k) for j in 1:(length(attempt.choices)-k))
    for (x,y) in valid
        iszero(attempt.choices[x]) && continue
        res = bin_search_down(0, attempt.choices[x], n -> begin
            new.choices[x] = n
            new.choices[y] = attempt.choices[x] + attempt.choices[y] - n
            consider(ts, new)
        end)
        if !isnothing(res)
            v = @something res
            new.choices[x] = v
            new.choices[y] = attempt.choices[x] + attempt.choices[y] - v
        end
    end
    if new.choices == attempt.choices
        return nothing
    else
        return Some(new)
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
