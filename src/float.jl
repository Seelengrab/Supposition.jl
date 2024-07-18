"""
    FloatEncoding

This module includes utilities for maniuplating floating point numbers in an IEEE 754 encoding:

Additionally, it implements an encoding for floating point numbers that has better shrinking properties, ported from hypothesis. See [`lex_to_float`](@ref) for more details.
"""
module FloatEncoding

"""
    uint(::Type{F})

Returns the unsigned integer type that can hold the bit pattern of a floating point number of type `F`.
"""
uint(::Type{Float16}) = UInt16
"""
    uint(::F)

Returns the zero value of the unsigned integer type that can hold the bit pattern of a floating point number of type `F`.
"""
uint(::Float16) = zero(UInt16)
uint(::Type{Float32}) = UInt32
uint(::Float32) = zero(UInt32)
uint(::Type{Float64}) = UInt64
uint(::Float64) = zero(UInt64)

"""
    fracsize(::Type{F})

Returns the number of bits in the fractional part of a floating point number of type `F`.
"""
fracsize(::Type{Float16}) = 10
fracsize(::Type{Float32}) = 23
fracsize(::Type{Float64}) = 52


"""
    exposize(::Type{F})

Returns the number of bits in the exponent part of a floating point number of type `F`.
"""
exposize(::Type{Float16}) = 5
exposize(::Type{Float32}) = 8
exposize(::Type{Float64}) = 11

"""
    max_exponent(::Type{F})

The maximum value of the exponent bits of a floating point number of type `F`.
"""
max_exponent(::Type{T}) where {T<:Base.IEEEFloat} = (1 << exposize(T) - 1) % uint(T)
"""
    bias(::Type{F})

The IEEE 754 bias of the exponent bits of a floating point number of type `F`.
"""
bias(::Type{T}) where {T<:Base.IEEEFloat} = uint(T)(1 << (exposize(T) - 1) - 1)

function masks(::Type{T}) where {T<:Base.IEEEFloat}
    ui = uint(T)
    signbitmask = one(ui) << (8 * sizeof(ui) - 1)
    fracbitmask = (-1 % ui) >> (8 * sizeof(ui) - fracsize(T))
    expobitmask = ((-1 % ui) >> (8 * sizeof(ui) - exposize(T))) << fracsize(T)
    signbitmask, expobitmask, fracbitmask
end

"""
    assemble(::T, sign::I, expo::I, frac::I) where {I, T <: Union{Float16, Float32, Float64}} -> T

Assembles `sign`, `expo` and `frac` arguments into the floating point number of type `T` it represents.
`sizeof(T)` must match `sizeof(I)`.
"""
function assemble(::Type{T}, sign::I, expo::I, frac::I) where {I,T<:Base.IEEEFloat}
    sizeof(T) == sizeof(I) || throw(ArgumentError("The bitwidth of  `$T` needs to match the other arguments of type `I`!"))
    signmask, expomask, fracmask = masks(T)
    sign = (sign << (exposize(T) + fracsize(T))) & signmask
    expo = (expo << fracsize(T)) & expomask
    frac = frac & fracmask
    ret = sign | expo | frac
    reinterpret(T, ret)
end

"""
    tear(x::T) where T <: Union{Float16, Float32, Float64} -> Tuple{I, I, I}

Returns the sign, exponent and fractional parts of a floating point number.
The returned tuple consists of three unsigned integer types `I` of the same bitwidth as `T`.
"""
function tear(x::T) where {T<:Base.IEEEFloat}
    signbitmask, expobitmask, fracbitmask = masks(T)
    ur = reinterpret(uint(T), x)
    s = (ur & signbitmask) >> (exposize(T) + fracsize(T))
    e = (ur & expobitmask) >> fracsize(T)
    f = (ur & fracbitmask) >> 0x0
    s, e, f
end

"""
    exponent_key(T, e)

A lexicographical ordering for floating point exponents. The encoding is ported
from Hypothesis.

The ordering is

    * non-negative exponents in increasing order
    * negative exponents in decreasing order
    * the maximum exponent

# Extended Help

The [reference implementation](https://github.com/HypothesisWorks/hypothesis/blob/aad70fb2d9dec2cef9719cdf5369eec9fae0d2a4/hypothesis-python/src/hypothesis/internal/conjecture/floats.py#L82) in Hypothesis.
"""
function exponent_key(::Type{T}, e::iT) where {T<:Base.IEEEFloat,iT<:Unsigned}
    if e == max_exponent(T)
        return Inf
    end
    unbiased = float(e) - bias(T)
    if unbiased < 0
        # order all negative exponents after the positive ones
        # in reverse order
        # max_exponent(T) - 1 maps to the key bias(T)
        # so the first negative exponent maps to bias(T) + 1
        bias(T) - unbiased
    else
        unbiased
    end
end

""" 
    _make_encoding_table(T)

Build a look up table for encoding exponents of floating point numbers of type `T`.
For a floating point type `T`, the lookup table is a permutation of the unsigned integers of type [`uint`](@ref) from `0` to `max_exponent(T)`.

This allows the reordering of the exponent bits of a floating point number according to the encoding described in [`exponent_key`](@ref).
"""
_make_encoding_table(T) = sort(zero(uint(T)):max_exponent(T);
                               by = Base.Fix1(exponent_key, T))
"""
    ENCODING_TABLE

A dictionary mapping `Unsigned` types to encoding tables for exponents.
The encoding is described in [`exponent_key`](@ref) and is ported from Hypothesis.

# See Also

[`encode_exponent`](@ref)
[`DECODING_TABLE`](@ref)
"""
const ENCODING_TABLE = Dict(
    UInt16 => _make_encoding_table(Float16),
    UInt32 => _make_encoding_table(Float32),
    UInt64 => _make_encoding_table(Float64))

"""
    encode_exponent(e)

Encode the exponent of a floating point number using an encoding with better shrinking.
The exponent can be extracted from a floating point number `f` using [`tear`](@ref).

# See Also

[`ENCODING_TABLE`](@ref)
[`exponent_key`](@ref)
[`tear`](@ref)
"""
encode_exponent(e::T) where {T<:Unsigned} = ENCODING_TABLE[T][e+1]

"""
    _make_decoding_table(T)

Build a look up table for decoding exponents of floating point numbers of type `T` which is the inverse of the table built by [`_make_encoding_table`](@ref).
"""
function _make_decoding_table(T)
    decoding_table = zeros(uint(T), max_exponent(T) + 1)
    for (i, e) in enumerate(ENCODING_TABLE[uint(T)])
        decoding_table[e+1] = i - 1
    end
    decoding_table
end

"""
    DECODING_TABLE

A dictionary mapping `Unsigned` types to decoding tables for exponents.
The encoding is described in [`exponent_key`](@ref) and is ported from Hypothesis.

# See Also

[`decode_exponent`](@ref)
[`ENCODING_TABLE`](@ref)
"""
const DECODING_TABLE = Dict(
    UInt16 => _make_decoding_table(Float16),
    UInt32 => _make_decoding_table(Float32),
    UInt64 => _make_decoding_table(Float64))

"""
    decode_exponent(e)

Undoes the encoding of the exponent of a floating point number used by [`encode_exponent`](@ref).
"""
decode_exponent(e::T) where {T<:Unsigned} = DECODING_TABLE[T][e+1]


"""
    update_mantissa(exponent, mantissa)

Encode the mantissa of a floating point number using an encoding with better shrinking.
The encoding is ported from Hypothesis.

The encoding is as follows:

    * If the unbiased exponent is <= 0, reverse the bits of the mantissa
    * If the unbiased exponent is >= fracsize(T) + bias(T), do nothing
    * Otherwise, reverse the low bits of the fractional part

# Extended help

See the [reference implementation](https://github.com/HypothesisWorks/hypothesis/blob/aad70fb2d9dec2cef9719cdf5369eec9fae0d2a4/hypothesis-python/src/hypothesis/internal/conjecture/floats.py#L165) in hypothesis
"""
function update_mantissa(::Type{T}, exponent::iT, mantissa::iT)::iT where {T<:Base.IEEEFloat,iT<:Unsigned}
    exponent = convert(uint(T), exponent)
    mantissa = convert(uint(T), mantissa)
    # The unbiased exponent is <= 0
    if exponent <= bias(T)
        # reverse the bits of the mantissa in place
        bitreverse(mantissa) >> (exposize(T) + 1)
    elseif exponent >= fracsize(T) + bias(T)
        mantissa
    else
        # reverse the low bits of the fractional part
        # as determined by the exponent
        n_reverse_bits = fracsize(T) + bias(T) - exponent
        # isolate the bits to be reversed
        to_reverse = mantissa & iT((1 << n_reverse_bits) - 1)
        # zero them out
        mantissa = mantissa ⊻ to_reverse
        # reverse them and put them back in place
        mantissa |= bitreverse(to_reverse) >> (8 * sizeof(T) - n_reverse_bits)
    end
end


"""
    lex_to_float(T, bits)

Reinterpret the bits of a floating point number using an encoding with better shrinking
properties.
This produces a non-negative floating point number, possibly including `NaN` or `Inf`.

The encoding is ported from Hypothesis, and has the property that lexicographically smaller
bit patterns correspond to 'simpler' floats.

# Encoding

The encoding used is as follows:

If the sign bit is set: 

    - the remainder of the first byte is ignored
    - the remaining bytes are interpreted as an integer and converted to a float

If the sign bit is not set:

    - the exponent is encoded using [`encoded_exponent`](@ref)
    - the mantissa is updated using [`update_mantissa`](@ref)
    - the float is reassembled using [`assemble`](@ref)

## Extended Help

See the [reference implementation](https://github.com/HypothesisWorks/hypothesis/blob/aad70fb2d9dec2cef9719cdf5369eec9fae0d2a4/hypothesis-python/src/hypothesis/internal/conjecture/floats.py#L176) in Hypothesis.

"""
function lex_to_float(::Type{T}, bits::I)::T where {I,T<:Base.IEEEFloat}
    sizeof(T) == sizeof(I) || throw(ArgumentError("The bitwidth of `$T` needs to match the bitwidth of the given bits!"))
    iT = uint(T)
    sign, exponent, mantissa = tear(reinterpret(T, bits))
    if isone(sign)
        exponent = encode_exponent(exponent)
        mantissa = update_mantissa(T, exponent, mantissa)
        assemble(T, zero(iT), exponent, mantissa)
    else
        integral_mask = signed(iT)(-1) >>> 0x8
        integral_part = bits & integral_mask
        T(integral_part)
    end
end

"""
    float_to_lex(f)

Encoding a floating point number as a bit pattern.

This is essentially the inverse of [`lex_to_float`](@ref) and produces a bit pattern that is lexicographically
smaller for 'simpler' floats.

Note that while `lex_to_float` can produce any valid positive floating point number, it is not injective. So combined with the fact that positive and negative floats map to the same bit pattern,
`float_to_lex` is not an exact inverse of `lex_to_float`.
"""
function float_to_lex(f::T) where {T<:Base.IEEEFloat}
    # If the float is simple, we can just reinterpret it as an integer
    # This corresponds to the latter branch of lex_to_float
    if is_simple_float(f)
        uint(T)(f)
    else
        nonsimple_float_to_lex(f)
    end
end

"""
    is_simple_float(f)

`f` is simple if it is integral and the first byte is all zeros.
"""
function is_simple_float(f::T) where {T<:Base.IEEEFloat}
    if trunc(f) != f
        return false
    end
    # In the encoding, the float is simple if the first byte is all zeros
    leading_zeros(reinterpret(uint(T), f)) >= 8
end

"""
    nonsimple_float_to_lex(f)

Encode a floating point number as a bit pattern, when the float is not simple.

This is the inverse of [`lex_to_float`](@ref) for bit patterns with the signbit set i.e.,

```jldoctest
julia> using Supposition.FloatEncoding: lex_to_float, nonsimple_float_to_lex

julia> bits = 0xff00
0xff00

julia> signbit(reinterpret(Float16, bits))
true

julia> nonsimple_float_to_lex(lex_to_float(Float16, bits)) == bits
true
```
"""
function nonsimple_float_to_lex(f::T) where {T<:Base.IEEEFloat}
    _, exponent, mantissa = tear(f)
    mantissa = update_mantissa(T, exponent, mantissa)
    exponent = decode_exponent(exponent)

    reinterpret(uint(T), assemble(T, one(uint(T)), exponent, mantissa))
end
end