import Random
using DataStructures: BinaryMinHeap

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
    BiasedNumbers(weights::Vector{Float64})

Sample the numbers from `1:length(weights)`, each with a weight of `weights[i]`.

The weights may be any positive number.
"""
struct BiasedNumbers
    table::Matrix{Union{Int,Float64,Nothing}}
    function BiasedNumbers(weights::Vector{Float64})
        n = length(weights)
        iszero(n) && throw(ArgumentError("Weights must not be empty!"))
        total = sum(weights)
        probabilities = weights ./ total

        table = [ (i, nothing, nothing) for i in 1:n ]

        small = BinaryMinHeap{Int}()
        large = BinaryMinHeap{Int}()
        sizehint!(small, n)
        sizehint!(large, n)

        scaled_probabilities = Vector{Float64}(undef, n)

        for (i,pi) in enumerate(probabilities)
            scaled = pi*n
            scaled_probabilities[i] = scaled
            if isone(scaled)
                table[i, 3] = 0.0
            elseif pi < 1.0
                push!(small, i)
            else
                push!(large, i)
            end
        end

        while !isempty(small) && !isempty(large)
            lo = pop!(small)
            hi = pop!(large)
            @assert lo != hi
            @assert scaled_probabilities[hi] > 1.0
            @assert table[lo][2] == -1
            table[lo, 2] = hi
            table[hi, 3] = 1.0 - scaled_probabilities[lo]
            scaled_probabilities[hi] = (scaled_probabilities[hi] + scaled_probabilities[lo]) - 1.0

            if scaled_probabilities[hi] < 1.0
                push!(small, hi)
            elseif isone(scaled_probabilities[hi])
                table[hi, 3] = 0.0
            else
                push!(large, hi)
            end
        end

        while !isempty(large)
            g = pop!(large)
            table[g, 3] = 0.0
        end

        while !isempty(small)
            l = pop!(small)
            table[l, 3] = 0.0
        end

        res = Vector{Tuple{Int,Int,Float64}}(undef, n)
        for (base, alternate, alternate_chance) in eachrow(table)
            @assert base isa Int
            @assert alternate isa Int | alternate isa Nothing
            if alternate isa Nothing
                res[base] = (base, base, alternate_chance)
            elseif alternate < base
                res[base] = (alternate, base, 1.0 - alternate_chance)
            else
                res[base] = (base, alternate, alternate_chance)
            end
        end

        new(res)
    end
end

function sample(bn::BiasedNumbers, tc::TestCase)
    base, alternate, alternate_chance = choice!(tc, eachrow(bn.table))
    use_alternate = weighted!(tc, alternate_chance)
    use_alternate ? alternate : base
end
