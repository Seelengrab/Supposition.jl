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

max_exponent(::Type{T}) where {T<:Base.IEEEFloat} = uint(T)(1 << exposize(T) - 1)
bias(::Type{T}) where {T<:Base.IEEEFloat} = uint(T)(1 << (exposize(T) - 1) - 1)

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
