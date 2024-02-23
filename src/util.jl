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

uint(::Type{Float16}) =      UInt16
uint(::     Float16)  = zero(UInt16)
uint(::Type{Float32}) =      UInt32
uint(::     Float32)  = zero(UInt32)
uint(::Type{Float64}) =      UInt64
uint(::     Float64)  = zero(UInt64)
fracsize(::Type{Float16}) = 10
fracsize(::Type{Float32}) = 23
fracsize(::Type{Float64}) = 52
exposize(::Type{Float16}) = 5
exposize(::Type{Float32}) = 8
exposize(::Type{Float64}) = 11

function masks(::Type{T}) where T <: Base.IEEEFloat
    ui = uint(T)
    signbitmask = one(ui) << (8*sizeof(ui)-1)
    fracbitmask =  (-1 % ui) >> (8*sizeof(ui)-fracsize(T))
    expobitmask = ((-1 % ui) >> (8*sizeof(ui)-exposize(T))) << fracsize(T)
    signbitmask, expobitmask, fracbitmask
end

"""
    assemble(::T, sign::I, expo::I, frac::I) where {I, T <: Union{Float16, Float32, Float64}} -> T

Assembles `sign`, `expo` and `frac` arguments into the floating point number of type `T` it represents.
`sizeof(T)` must match `sizeof(I)`.
"""
function assemble(::Type{T}, sign::I, expo::I, frac::I) where {I, T <: Base.IEEEFloat}
    sizeof(T) == sizeof(I) || throw(ArgumentError("The bitwidth of  `$T` needs to match the other arguments of type `I`!"))
    signmask, expomask, fracmask = masks(T)
    sign = (sign << (exposize(T) + fracsize(T))) & signmask
    expo = (expo <<                fracsize(T))  & expomask
    frac =  frac                                 & fracmask
    ret =  sign | expo | frac
    return reinterpret(T, ret)
end

"""
    tear(x::T) where T <: Union{Float16, Float32, Float64} -> Tuple{I, I, I}

Returns the sign, exponent and fractional parts of a floating point number.
The returned tuple consists of three unsigned integer types `I` of the same bitwidth as `T`.
"""
function tear(x::T) where T <: Base.IEEEFloat
    signbitmask, expobitmask, fracbitmask = masks(T)
    ur = reinterpret(uint(T), x)
    s = (ur & signbitmask) >> (exposize(T) + fracsize(T))
    e = (ur & expobitmask) >>                fracsize(T)
    f = (ur & fracbitmask) >>                        0x0
    return (s, e, f)
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
