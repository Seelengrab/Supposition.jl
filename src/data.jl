module Data

using Supposition

abstract type Possibility{T} end

"""
    postype(::Type{P<:Possibility})

Gives the type of objects this `Possibility` type will generate.
"""
postype(::Type{_P}) where {T, _P <: Possibility{T}} = T

"""
    postype(::P) where P <: Possibility

Gives the type of objects this `Possibility` object will generate.
"""
postype(::P) where P <: Possibility = postype(P)

"""
    Map(source::Possibility, f) <: Possibility

A `Possibility` representing mapping values from `source` through `f`.

Equivalent to calling `map(f, source)`.

The pre-calculated return type of `Map` is a *best effort* and may be wider than
necessary.
"""
struct Map{R, S <: Possibility, F} <: Possibility{R}
    source::S
    map::F
    Map(s::S, f::F) where {T, S <: Possibility{T}, F} = new{Base.promote_op(f, T), S, F}(s, f)
end

Base.map(f, p::Possibility) = Map(p, f)
produce(m::Map, tc::TestCase) = m.map(produce(m.source, tc))

"""
    Satisfying(source::Possibility, pred) <: Possibility

A `Possibility` representing values from `source` fulfilling `pred`.

Equivalent to calling `filter(f, source)`.
"""
struct Satisfying{T, S <: Possibility{T}, P} <: Possibility{T}
    source::S
    predicate::P
    # flatten chained calls to `filter`
    Satisfying(s::Satisfying, pred) = Satisfying(s.source, pred ∘ s.predicate)
    function Satisfying(s::S, pred::P) where {T, S <: Possibility{T}, P}
        new{T,S,P}(s, pred)
    end
end

Base.filter(f, p::Possibility) = Satisfying(p, f)
satisfying(f, p::Possibility) = Satisfying(p, f)

function produce(s::Satisfying, tc::TestCase)
    for _ in 1:3
        candidate = produce(s.source, tc)
        if s.predicate(candidate)
            return candidate
        end
    end

    reject(tc)
end

"""
    Bind(source::Possibility, map)

Binds `map` to `source`, i.e., on `produce(::Bind)` this calls `produce` on
`source`, the result of which is passed to `map` which will be used as input
to `produce` again.

In other words, `map` takes a value `produce`d by `source` and gives back a
`Possibility` that is then immediately `produce`d from.
"""
struct Bind{T, S <: Possibility{T}, M} <: Possibility{T}
    source::S
    map::M
end

bind(f, s::Possibility) = Bind(s, f)
function produce(b::Bind, tc::TestCase)
    inner = produce(b.source, tc)
    produce(b.map(inner), tc)
end

## Possibilities of signed integers

"""
    Integers(minimum::T, maximum::T) <: Possibility{T}

A `Possibility` representing drawing integers from `[minimum, maximum]`.

Produced values are of type `T`.
"""
struct Integers{T<:Integer, U<:Unsigned} <: Possibility{T}
    minimum::T
    range::U
    Integers(minimum::T, maximum::T) where T<:Integer = new{T,unsigned(T)}(minimum, (maximum - minimum) % unsigned(T))
end

function produce(i::Integers{T}, tc::TestCase) where T
    offset = choice!(tc, i.range)
    return (i.minimum + offset) % T
end

## Possibilities of vectors

"""
    Vectors(elements::Possibility{T}; min_size=0, max_size=10_000) <: Possibility{Vector{T}}

A `Possibility` representing drawing vectors with length `l` in `min_size <= l <= max_size`,
holding elements of type `T`.

`min_size` and `max_size` must be positive numbers, with `min_size <= `max_size`.
"""
struct Vectors{T} <: Possibility{Vector{T}}
    elements::Possibility{T}
    min_size::UInt
    max_size::UInt

    function Vectors(elements::Possibility{T}; min_size=0, max_size=10_000) where T
        min_size <= max_size || throw(ArgumentError("`min_size` must be `<= max_size`!"))

        low = UInt(min_size)
        high = UInt(max_size)

        new{T}(elements, low, high)
    end
end

function produce(v::Vectors{T}, tc::TestCase) where T
    result = T[]

    # this does an exponential backoff - longer vectors
    # are more and more unlikely to occur
    # so results are biased towards min_size
    while true
        if length(result) < v.min_size
            forced_choice!(tc, UInt(1))
        elseif (length(result)+1) >= v.max_size
            forced_choice!(tc, UInt(0))
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

pairs(a::Possibility, b::Possibility) = Pairs(a,b)
produce(p::Pairs, tc::TestCase) = produce(p.first, tc) => produce(p.second, tc)

## Possibility of Just a value

"""
    Just(value::T) <: Possibility{T}

A `Possibility` that always produces `value`, which is not copied.

Be careful with mutable data!
"""
struct Just{T} <: Possibility{T}
    value::T
end

just(t) = Just(t)
produce(j::Just, _::TestCase) = j.value

## Possibility of Nothing

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

## Possibility of Characters

"""
    Characters(;valid::Bool = false)

A `Possibility` of producing arbitrary `Char` instances.

!!! warn "Unicode"
    This will `produce` ANY possible `Char` by default, not just valid unicode codepoints!
    To only produce valid unicode codepoints, pass `valid=true` as a keyword argument.
"""
struct Characters <: Possibility{Char}
    valid::Bool
    Characters(; valid=false) = new(valid)
end

function produce(c::Characters, tc::TestCase)
    # Ref. https://github.com/JuliaLang/julia/issues/44741#issuecomment-1079083216
    if c.valid
        sample = SampledFrom(typemin(Char):'\U0010ffff')
        s = filter(isvalid, sample)
    else
        s = SampledFrom(typemin(Char):"\xf7\xbf\xbf\xbf"[1])
    end
    produce(s, tc)
end

"""
    AsciiCharacters()


A `Possibility` of producing arbitrary `Char` instances that are `isascii`.
More efficient than filtering [`Characters`](@ref).
"""
struct AsciiCharacters <: Possibility{Char} end

function produce(::AsciiCharacters, tc::TestCase)
    s = SampledFrom(Char(0x0):Char(0x7f))
    produce(s, tc)
end

## Possibility of Strings

"""
    Text(alphabet::Possibility{Char}; min_len=0, max_len=10_000)

A `Possibility` for generating text containing characters of a given alphabet.
"""
struct Text <: Possibility{String}
    vectors::Possibility{Vector{Char}}
    function Text(alphabet::A; min_len=0, max_len=10_000) where A <: Possibility{Char}
        vectors = Vectors(alphabet; min_size=min_len, max_size=max_len)
        new(vectors)
    end
end

produce(s::Text, tc::TestCase) = join(produce(s.vectors, tc))

## Possibility of values from a collection

"""
    SampledFrom(collection) <: Possibility{eltype(collection)}

A `Possibility` for sampling uniformly from `collection`.

`collection`, as well as its `eachindex`, is assumed to be indexable.

The produced object is _not_ copied, be careful with mutable data!
"""
struct SampledFrom{T, C} <: Possibility{T}
    collection::C
    SampledFrom(col) = new{eltype(col), typeof(col)}(col)
end

function produce(sf::SampledFrom, tc::TestCase)
    pos_indices = eachindex(sf.collection)
    idx = produce(Integers(firstindex(pos_indices), lastindex(pos_indices)), tc)
    return sf.collection[pos_indices[idx]]
end

## Possibility of booleans

"""
    Booleans() <: Possibility{Bool}

A `Possibility` for sampling boolean values.
"""
struct Booleans <: Possibility{Bool} end

produce(::Booleans, tc::TestCase) = weighted!(tc, 0.5)

## Possibility of floating point values

"""
    Floats{T <: Union{Float16,Float32,Float64}} <: Possibility{T}

A `Possibility` for sampling floating point values.

!!! warn "Inf, Nan"
    This possibility will generate *any* valid instance, including positive
    and negative infinities, signaling and quiet NaNs and every possible float.
"""
struct Floats{T <: Base.IEEEFloat} <: Possibility{T} end

uint(::Type{Float16}) = UInt16
uint(::Type{Float32}) = UInt32
uint(::Type{Float64}) = UInt64

function produce(::Floats{T}, tc::TestCase) where {T}
    iT = uint(T)
    i = Integers(typemin(iT), typemax(iT))
    reinterpret(T, produce(i, tc))
end

end # data module
