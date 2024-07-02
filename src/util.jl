import Random

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

lerp(x,y,t) = y*t + x*(1-t)
function smootherstep(a, b, t)
    x = clamp((t - a)/(b-a), 0.0, 1.0)
    return x*x*x*(x*(6.0*x - 15.00) + 10.0)
end

struct BiasedAverage
    tc::TestCase
    prob::Float64
    target_offset::UInt
    cnt::Base.RefValue{Int}
    mincnt::Int
    maxcnt::Int
    function BiasedAverage(tc::TestCase, min_data, max_data, alpha_min, alpha_max, beta=1.0)
        # it's VERY important to let the shrinker shrink this!
        # if we don't we get Invalids even when we shouldn't
        max_offset = choice!(tc, max_data - min_data)

        if tc.attempt.generation == tc.attempt.max_generation
            # if we're on the last try (should that exist)
            # guarantee that we're able to draw the maximum permissible size
            average_offset = (max_data÷2 + min_data÷2) - min_data
        else
            # otherwise, get an average according to a beta distribution
            raw_step = smootherstep(0.0, div(tc.attempt.max_generation, 2), tc.attempt.generation)
            alpha_param = lerp(alpha_min, alpha_max, raw_step)
            average_offset = floor(UInt, max_offset*(alpha_param/(alpha_param+beta)))
        end

        # now for the fiddly bit to reaching `v.max_size`
        # the `min` here is important, otherwise we may _oversample_ if the
        # beta distribution drew too high after `max_offset` shrank!
        target_offset = min(average_offset, max_offset)
        p_continue = _calc_p_continue(target_offset, max_offset)

        new(tc, p_continue, target_offset, Ref(0), min_data, max_data)
    end
end

function _calc_p_continue(desired_avg, max_size)
    @assert desired_avg <= max_size "Require target <= max_size, not $desired_avg > $max_size"
    if desired_avg == max_size
        return 1.0
    end
    p_continue = 1.0 - 1.0/(1+desired_avg)
    if iszero(p_continue)
        @assert 0 <= p_continue < 1
        return p_continue
    end

    while _p_continue_to_avg(p_continue, max_size) > desired_avg
        p_continue -= 0.0001
        smallest_positive = nextfloat(0.0)
        if p_continue < smallest_positive
            p_continue = smallest_positive
            break
        end
    end

    hi = 1.0
    while desired_avg - _p_continue_to_avg(p_continue, max_size) > 0.01
        @assert 0 < p_continue < hi "Binary search failed: $p_continue, $hi"
        # this can't overflow, since the numbers are all in [0,1]
        mid = (p_continue + hi) / 2
        if _p_continue_to_avg(mid, max_size) <= desired_avg
            p_continue = mid
        else
            hi = mid
        end
    end
    @assert 0 < p_continue < 1 "Binary search faileD: $p_continue, $hi"
    @assert _p_continue_to_avg(p_continue, max_size) <= desired_avg "Found probability leads to higher-than-requested average"
    return p_continue
end

function _p_continue_to_avg(p_continue, max_size)
    p_continue >= 1 && return max_size
    return (1.0 / (1 - p_continue) - 1.0) * (1 - p_continue^max_size)
end

function should_continue(bb::BiasedAverage)
    bb.cnt[] >= bb.maxcnt && return false
    if bb.mincnt > bb.cnt[] || weighted!(bb.tc, bb.prob)
        bb.cnt[] += 1
        true
    else
        bb.cnt[] = bb.maxcnt
        false
    end
end
