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
