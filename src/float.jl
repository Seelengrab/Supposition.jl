module FloatEncoding
using Supposition: uint, tear, bias, fracsize, exposize, max_exponent, assemble

"""
    exponent_key(T, e)

A lexographical ordering for floating point exponents. The encoding is taken
from hypothesis.
The ordering is
- non-negative exponents in increasing order
- negative exponents in decreasing order
- the maximum exponent
"""
function exponent_key(::Type{T}, e::iT) where {T<:Base.IEEEFloat,iT<:Unsigned}
    if e == max_exponent(T)
        return Inf
    end
    unbiased = float(e) - bias(T)
    if unbiased < 0
        10000 - unbiased
    else
        unbiased
    end
end

_make_encoding_table(T) = sort(
    zero(uint(T)):max_exponent(T),
    by=Base.Fix1(exponent_key, T))
const ENCODING_TABLE = Dict(
    UInt16 => _make_encoding_table(Float16),
    UInt32 => _make_encoding_table(Float32),
    UInt64 => _make_encoding_table(Float64))

encode_exponent(e::T) where {T<:Unsigned} = ENCODING_TABLE[T][e+1]

function _make_decoding_table(T)
    decoding_table = zeros(uint(T), max_exponent(T) + 1)
    for (i, e) in enumerate(ENCODING_TABLE[uint(T)])
        decoding_table[e+1] = i - 1
    end
    decoding_table
end
const DECODING_TABLE = Dict(
    UInt16 => _make_decoding_table(Float16),
    UInt32 => _make_decoding_table(Float32),
    UInt64 => _make_decoding_table(Float64))
decode_exponent(e::T) where {T<:Unsigned} = DECODING_TABLE[T][e+1]


"""
    update_mantissa(exponent, mantissa)

Encode the mantissa of a floating point number using an encoding with better shrinking.
"""
function update_mantissa(::Type{T}, exponent::iT, mantissa::iT)::iT where {T<:Base.IEEEFloat,iT<:Unsigned}
    @assert uint(T) == iT
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
This produces a non-negative floating point number, possibly including NaN or Inf.

The encoding is taken from hypothesis, and has the property that lexicographically smaller
bit patterns corespond to 'simpler' floats.

# Encoding

The encoding used is as follows:

If the sign bit is set: 

    - the remainder of the first byte is ignored
    - the remaining bytes are interpreted as an integer and converted to a float

If the sign bit is not set:

    - the exponent is decoded using `decode_exponent`
    - the mantissa is updated using `update_mantissa`
    - the float is reassembled using `assemble`

"""
function lex_to_float(::Type{T}, bits::I)::T where {I,T<:Base.IEEEFloat}
    sizeof(T) == sizeof(I) || throw(ArgumentError("The bitwidth of `$T` needs to match the bidwidth of `I`!"))
    iT = uint(T)
    sign, exponent, mantissa = tear(reinterpret(T, bits))
    if sign == 1
        exponent = encode_exponent(exponent)
        mantissa = update_mantissa(T, exponent, mantissa)
        assemble(T, zero(iT), exponent, mantissa)
    else
        integral_mask = iT((1 << (8 * (sizeof(T) - 1))) - 1)
        integral_part = bits & integral_mask
        T(integral_part)
    end
end

function float_to_lex(f::T) where {T<:Base.IEEEFloat}
    if is_simple_float(f)
        uint(T)(f)
    else
        base_float_to_lex(f)
    end
end

function is_simple_float(f::T) where {T<:Base.IEEEFloat}
    try
        if trunc(f) != f
            return false
        end
        ndigits(reinterpret(uint(T), f), base=2) <= 8 * (sizeof(T) - 1)
    catch e
        if isa(e, InexactError)
            return false
        end
        rethrow(e)
    end
end

function base_float_to_lex(f::T) where {T<:Base.IEEEFloat}
    _, exponent, mantissa = tear(f)
    mantissa = update_mantissa(T, exponent, mantissa)
    exponent = decode_exponent(exponent)

    reinterpret(uint(T), assemble(T, one(uint(T)), exponent, mantissa))
end
end