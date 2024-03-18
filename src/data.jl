"""
    Data

This module contains a collection of [`Possibility`](@ref) types, as well as some
useful utility functions for constructing them.

These currently include:

 * [`Integers{T}`](@ref), for producing integer types (except `BigInt`)
 * [`Floats{F}`](@ref), for producing floating point types (except `BigFloat`)
 * [`Booleans`](@ref), for producing booleans
 * [`Pairs`](@ref), for producing pairs of values `a => b`
 * [`Vectors`](@ref), for producing `Vector`s out of `Possibility`
 * [`Dicts`](@ref), for producing `Dict`s out of a `Possibility` for keys and one for values
 * [`AsciiCharacters`](@ref), for producing `Char`s that are `isascii`
 * [`Characters`](@ref), for producing all possible `Char`s, including all of Unicode
 * [`Text`](@ref), for producing `String`s from `Possibility{Char}`
 * [`SampledFrom`](@ref), for producing a value from a given collection
 * [`Satisfying`](@ref), for filtering the values a `Possibility` produces through a predicate
 * [`Map`](@ref), for mapping a function over the values a `Possibility` produces
 * [`OneOf`](@ref), for choosing one of a number of given `Possibility` to produce from
 * [`Bind`](@ref), for binding a function that produces `Possibility` to the output of another `Possibility`
 * [`Recursive`](@ref), for creating recursive data structures using a basecase `Possibility` and a function that layers more `Possibility` around it

as well as these utility functions:

 * `map` for creating a `Map`
 * `filter` for creating a `Satisfying`
 * `|` for creating a `OneOf`
 * `bind` for creating a `Bind`
 * `recursive` for creating a `Recursive`
 * `Floats()` for producing all of `Float16`, `Float32` and `Float64` from the same `Possibility` at once
 * `BitIntegers()` for producing all of `Base.BitIntegers` from the same `Possibility` at once
"""
module Data

using Supposition
using Supposition: smootherstep, lerp, TestCase, choice!, weighted!, forced_choice!
using RequiredInterfaces: @required

"""
    Possibility{T}

Abstract supertype for all generators.
The `T` type parameter describes the kinds of objects generated by this integrated shrinker.

Required methods:

  * `produce!(::TestCase, ::P) where P <: Possibility`

Fallback definitions:

  * `postype(::Possibility{T}) -> Type{T}`
  * `example(::Possibility{T}) -> T`
"""
abstract type Possibility{T} end

@required Possibility begin
    produce!(::TestCase, ::Possibility)
end

"""
    |(::Possibility{T}, ::Possibility{S}) where {T,S} -> OneOf{Union{T,S}}

Combine two `Possibility` into one, sampling uniformly from either.

If either of the two arguments is a `OneOf`, the resulting object acts
as if all original non-`OneOf` had be given to `OneOf` instead.
That is, e.g. `OneOf(a, b) | c` will act like `OneOf(a,b,c)`.

See also [`OneOf`](@ref).
"""
Base.:(|)(a::Possibility, b::Possibility) = OneOf(a, b)

"""
    produce!(tc::TestCase, pos::Possibility{T}) -> T

Produces a value from the given `Possibility`, recording the required choices in the `TestCase` `tc`.

This needs to be implemented for custom `Possibility` objects, passing the given `tc` to any inner
requirements directly.

See also [`Supposition.produce!`](@ref)

!!! tip "Examples"
    You should not call this function when you have a `Possibility` and want to inspect what an object
    produced by that `Possibility` looks like - use [`example`](@ref) for that instead.
"""
function produce! end

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

```julia-repl
julia> using Supposition

julia> makeeven(x) = (x ÷ 2) * 2

julia> pos = map(makeeven, Data.Integers{Int8}())

julia> all(iseven, example(pos, 10_000))
true
```
"""
struct Map{R, S <: Possibility, F} <: Possibility{R}
    source::S
    map::F
    Map(s::S, f::F) where {T, S <: Possibility{T}, F} = new{Base.promote_op(f, T), S, F}(s, f)
end

"""
    map(f, pos::Possibility)

Apply `f` to the result of calling `produce!` on `pos` (lazy mapping).

Equivalent to calling `Map(pos, f)`.

See also [`Map`](@ref).
"""
Base.map(f, p::Possibility) = Map(p, f)
produce!(tc::TestCase, m::Map) = m.map(produce!(tc, m.source))

"""
    Satisfying(source::Possibility, pred) <: Possibility

A `Possibility` representing values from `source` fulfilling `pred`.

Equivalent to calling `filter(f, source)`.

```julia-repl
julia> using Supposition

julia> pos = filter(iseven, Data.Integers{Int8}())

julia> all(iseven, example(pos, 10_000))
true
```
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

"""
    filter(f, pos::Possibility)

Filter the output of `produce!` on `pos` by applying the predicate
`f`.

!!! note "No stalling"
    In order not to stall generation of values, this will not
    try to produce a value from `pos` forever, but reject the
    testcase after some attempts.
"""
Base.filter(f, p::Possibility) = Satisfying(p, f)
satisfying(f, p::Possibility) = Satisfying(p, f)

function produce!(tc::TestCase, s::Satisfying)
    for _ in 1:3
        candidate = produce!(tc, s.source)
        if s.predicate(candidate)
            return candidate
        end
    end

    reject(tc)
end

"""
    Bind(source::Possibility, f)

Binds `f` to `source`, i.e., on `produce!(::Bind, ::TestCase)` this calls `produce!` on
`source`, the result of which is passed to `f`, the output of which will be used as input
to `produce!` again.

In other words, `f` takes a value `produce!`d by `source` and gives back a
`Possibility` that is then immediately `produce!`d from.

Equivalent to `bind(f, source)`.
"""
struct Bind{T, S <: Possibility{T}, M} <: Possibility{T}
    source::S
    map::M
end

"""
    bind(f, pos::Possibility)

Maps the output of `produce!` on `pos` through `f`, and calls `produce!` on
the result again. `f` is expected to take a value and return a `Possibility`.

Equivalent to calling `Bind(pos, f)`.

See also [`Bind`](@ref).
"""
bind(f, s::Possibility) = Bind(s, f)
function produce!(tc::TestCase, b::Bind)
    inner = produce!(tc, b.source)
    produce!(tc, b.map(inner))
end

## Possibilities of signed integers

"""
    Integers(minimum::T, maximum::T) <: Possibility{T <: Integer}
    Integers{T}() <: Possibility{T <: Integer}

A `Possibility` representing drawing integers from `[minimum, maximum]`.
The second constructors draws from the entirety of `T`.

Produced values are of type `T`.

```julia-repl
julia> using Supposition

julia> is = Data.Integers{Int}()

julia> example(is, 5)
5-element Vector{Int64}:
 -5854403925308846160
  4430062772779972974
    -9995351034504801
  2894734754389242339
 -6640496903289665416
```
"""
struct Integers{T<:Integer, U<:Unsigned} <: Possibility{T}
    minimum::T
    range::U
    function Integers(minimum::T, maximum::T) where T<:Integer
        minimum <= maximum || throw(ArgumentError("`minimum` must be `<= maximum`!"))
        new{T,unsigned(T)}(minimum, (maximum - minimum) % unsigned(T))
    end
    Integers{T}() where T <: Integer = new{T, unsigned(T)}(typemin(T), typemax(unsigned(T)))
end

const BITINT_TYPES = (UInt8, Int8, UInt16, Int16, UInt32, Int32, UInt64, Int64, UInt128, Int128, )

"""
    BitIntegers() <: Possibility{$(Base.BitInteger)}

A `Possibility` for generating all possible bitintegers with fixed size.
"""
BitIntegers() = OneOf((Integers{T}() for T in BITINT_TYPES)...)

function produce!(tc::TestCase, i::Integers{T}) where T
    offset = choice!(tc, i.range % UInt) % T
    return (i.minimum + offset) % T
end

function produce!(tc::TestCase, i::Integers{T}) where T <: Union{Int128, UInt128}
    # FIXME: this assumes a 64-bit architecture!
    upperbound = (i.range >> 64) % UInt
    lowerbound = i.range % UInt
    upper = choice!(tc, upperbound) % T
    lower = choice!(tc, lowerbound) % T
    offset = (upper << 64) | lower
    return (i.minimum + offset) % T
end

## Possibilities of vectors

"""
    Vectors(elements::Possibility{T}; min_size=0, max_size=10_000) <: Possibility{Vector{T}}

A `Possibility` representing drawing vectors with length `l` in `min_size <= l <= max_size`,
holding elements of type `T`.

`min_size` and `max_size` must be positive numbers, with `min_size <= max_size`.

```julia-repl
julia> using Supposition

julia> vs = Data.Vectors(Data.Floats{Float16}(); max_size=5)

julia> example(vs, 3)
3-element Vector{Vector{Float16}}:
 [9.64e-5, 9.03e3, 0.04172, -0.0003352]
 [9.793e-5, -2.893, 62.62, 0.0001961]
 [-0.007023, NaN, 3.805, 0.1943]
```
"""
struct Vectors{T, P <: Possibility{T}} <: Possibility{Vector{T}}
    elements::P
    min_size::UInt
    max_size::UInt

    function Vectors(elements::Possibility{T}; min_size=0, max_size=10_000) where T
        min_size <= max_size || throw(ArgumentError("`min_size` must be `<= max_size`!"))

        low = UInt(min_size)
        high = UInt(max_size)

        new{T,typeof(elements)}(elements, low, high)
    end
end

function produce!(tc::TestCase, v::Vectors{T}) where T
    result = T[]

    # it's VERY important to let the shrinker shrink this!
    # if we don't we get Invalids even when we shouldn't
    max_offset = choice!(tc, v.max_size - v.min_size)

    if tc.generation == tc.max_generation
        # if we're on the last try (should that exist)
        # guarantee that we're able to draw the maximum permissible size
        average_offset = (v.max_size÷2 + v.min_size÷2) - v.min_size
    else
        # otherwise, get an average according to a beta distribution
        raw_step = smootherstep(0.0, float(max(tc.max_generation÷2, 5_000)), tc.generation)
        beta_param = lerp(0.5, 5.0, raw_step)
        average_offset = floor(UInt, max_offset*(beta_param/(beta_param+1.0)))
    end

    # give some hint to the amount of data we're going to need
    sizehint!(result, v.min_size+average_offset)

    # first, make sure we hit the minimum size
    for _ in 1:v.min_size
        push!(result, produce!(tc, v.elements))
    end

    # now for the fiddly bit to reaching `v.max_size`
    # the `min` here is important, otherwise we may _oversample_ if the
    # beta distribution drew too high after `max_offset` shrank!
    p_continue = _calc_p_continue(min(average_offset, max_offset), max_offset)

    # finally, draw with our targeted average until we're done
    for _ in 1:max_offset
        if weighted!(tc, p_continue)
            push!(result, produce!(tc, v.elements))
        else
            break
        end
    end

    return result
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

## Possibilities of pairs

"""
    Pairs(first::Possibility{T}, second::Possibility{S}) where {T,S} <: Possibility{Pair{T,S}}

A `Possibility` for producing `a => b` pairs. `a` is produced by `first`, `b` is produced by `second`.

```
julia> p = Data.Pairs(Data.Integers{UInt8}(), Data.Floats{Float64}());

julia> example(p, 4)
4-element Vector{Pair{UInt8, Float64}}:
 0x41 => 4.1183566661848205e-230
 0x48 => -2.2653631095108555e-119
 0x2a => -6.564396855333643e224
 0xec => 1.9330751262581671e-53
```
"""
struct Pairs{T,S} <: Possibility{Pair{T,S}}
    first::Possibility{T}
    second::Possibility{S}
end

pairs(a::Possibility, b::Possibility) = Pairs(a,b)
produce!(tc::TestCase, p::Pairs) = produce!(tc, p.first) => produce!(tc, p.second)

## Possibility of Just a value

"""
    Just(value::T) <: Possibility{T}

A `Possibility` that always produces `value`.

!!! warning "Mutable Data"
    The source object given to this `Just` is not copied when `produce!` is called.
    Be careful with mutable data!

```julia-repl
julia> using Supposition

julia> three = Data.Just(3)

julia> example(three, 3)
3-element Vector{Int64}:
 3
 3
 3
```
"""
struct Just{T} <: Possibility{T}
    value::T
end

just(t) = Just(t)
produce!(_::TestCase, j::Just) = j.value

## Possibility of Nothing

produce!(tc::TestCase, ::Nothing) = reject(tc)

## Sampling one of N

"""
    OneOf(pos::Possibility...) <: Possibility

A `Possibility` able to generate any of the examples one of the given
`Possibility` can produce. The given `Possibility` are sampled from
uniformly.

At least one `Possibility` needs to be given to `OneOf`.

`postype(::OneOf)` is inferred as a _best effort_, and may be wider than necessary.

`OneOf` can also be constructed through use of `a | b` on `Possibility`. Constructed
in this way, if either `a` or `b` is already a `OneOf`, the resulting `OneOf`
acts as if it had been given the original `Possibility` objects in the first place.
That is, `OneOf(a, b) | c` acts like `OneOf(a, b, c)`.

```julia-repl
julia> of = Data.OneOf(Data.Integers{Int8}(), Data.Integers{UInt8}());

julia> Data.postype(of)
Union{Int8, UInt8}

julia> ex = map(of) do i
           (i, typeof(i))
       end;

julia> example(ex)
(-83, Int8)

julia> example(ex)
(0x9f, UInt8)
```
"""
struct OneOf{X, N} <: Possibility{X}
    strats::NTuple{N, Possibility}
    function OneOf(pos::Possibility...)
        isempty(pos) && throw(ArgumentError("Need at least one `Possibility` to draw from!"))
        new{Union{postype.(pos)...}, length(pos)}(pos)
    end
end

function produce!(tc::TestCase, @nospecialize(of::OneOf))
    strategy = produce!(tc, SampledFrom(of.strats))
    produce!(tc, strategy)::postype(of)
end

Base.:(|)(of::OneOf, b::Possibility) = OneOf(of.strats..., b)
Base.:(|)(a::Possibility, of::OneOf) = OneOf(a, of.strats...)
Base.:(|)(a::OneOf, b::OneOf) = OneOf(a.strats..., b.strats...)

## Recursion

"""
    Recursive(base::Possibility, extend; max_layers::Int=5) <: Possibility{T}

A `Possibility` for generating recursive data structures.
`base` is the basecase of the recursion. `extend` is a function returning a
new `Possibility` when given a `Possibility`, called to recursively
expand a tree starting from `base`. The returned `Possibility` is fed
back into `extend` again, expanding the recursion by one layer.

`max_layers` designates the maximum layers `Recursive` should
keep track of. This must be at least `1`, so that at least
the base case can always be generated. Note that this implies `extend`
will be used at most `max_layers-1` times, since the base case of
the recursion will not be wrapped.

Equivalent to calling `recursive(extend, base)`.

## Examples

```julia-repl
julia> base = Data.Integers{UInt8}()

julia> wrap(pos) = Data.Vectors(pos; min_size=2, max_size=3)

julia> rec = Data.recursive(wrap, base; max_layers=3);

julia> Data.postype(rec) # the result is formatted here for legibility
Union{UInt8,
      Vector{UInt8},
      Vector{Union{UInt8, Vector{UInt8}}}
}

julia> example(rec)
0x31

julia> example(rec)
2-element Vector{Union{UInt8, Vector{UInt8}}}:
     UInt8[0xa9, 0xb4]
 0x9b

julia> example(rec)
2-element Vector{UInt8}:
 0xbd
 0x25
```
"""
struct Recursive{T,F} <: Possibility{T}
    base::Possibility
    extend::F
    inner::Possibility{T}
    function Recursive(base::Possibility, extend; max_layers::Int=5)
        max_layers < 1 && throw(ArgumentError("Must be able to produce at least the base layer!"))
        strategies = Vector{Possibility}(undef, max_layers)
        strategies[1] = base
        for layer in 2:max_layers
            prev_layers = @view strategies[1:layer-1]
            strategies[layer] = extend(OneOf(prev_layers...))
        end
        inner = OneOf(strategies...)
        new{postype(inner), typeof(extend)}(base, extend, inner)
    end
end

"""
    recursive(f, pos::Possibility; max_layers=5)

Recursively expand `pos` into deeper nested `Possibility` by repeatedly
passing `pos` itself to `f`. `f` returns a new `Possibility`, which is then
passed into `f` again until the maximum depth is achieved.

Equivalent to calling `Recursive(pos, f)`.

See also [`Recursive`](@ref).
"""
recursive(f, pos::Possibility; max_layers=5) = Recursive(pos, f; max_layers)

produce!(tc::TestCase, r::Recursive) = produce!(tc, r.inner)

## Possibility of Characters

"""
    Characters(;valid::Bool = false) <: Possibility{Char}

A `Possibility` of producing arbitrary `Char` instances.

!!! warning "Unicode"
    This will `produce!` ANY possible `Char` by default, not just valid unicode codepoints!
    To only produce valid unicode codepoints, pass `valid=true` as a keyword argument.

```julia-repl
julia> using Supposition

julia> chars = Data.Characters()

julia> example(chars, 5)
5-element Vector{Char}:
 '⠺': Unicode U+283A (category So: Symbol, other)
 '𰳍': Unicode U+30CCD (category Lo: Letter, other)
 '\\U6ec9c': Unicode U+6EC9C (category Cn: Other, not assigned)
 '\\U1a05c5': Unicode U+1A05C5 (category In: Invalid, too high)
 '𓂫': Unicode U+130AB (category Lo: Letter, other)
```
"""
struct Characters <: Possibility{Char}
    valid::Bool
    Characters(; valid=false) = new(valid)
end

function produce!(tc::TestCase, c::Characters)
    # Ref. https://github.com/JuliaLang/julia/issues/44741#issuecomment-1079083216
    if c.valid
        sample = SampledFrom(typemin(Char):'\U0010ffff')
        s = filter(isvalid, sample)
    else
        s = SampledFrom(typemin(Char):"\xf7\xbf\xbf\xbf"[1])
    end
    produce!(tc, s)
end

"""
    AsciiCharacters() <: Possibility{Char}

A `Possibility` of producing arbitrary `Char` instances that are `isascii`.
More efficient than filtering [`Characters`](@ref).

```julia-repl
julia> using Supposition

julia> ascii = Data.AsciiCharacters()

julia> example(ascii, 5)
5-element Vector{Char}:
 '8': ASCII/Unicode U+0038 (category Nd: Number, decimal digit)
 'i': ASCII/Unicode U+0069 (category Ll: Letter, lowercase)
 'R': ASCII/Unicode U+0052 (category Lu: Letter, uppercase)
 '\\f': ASCII/Unicode U+000C (category Cc: Other, control)
 '>': ASCII/Unicode U+003E (category Sm: Symbol, math)
```
"""
struct AsciiCharacters <: Possibility{Char} end

function produce!(tc::TestCase, ::AsciiCharacters)
    s = SampledFrom(Char(0x0):Char(0x7f))
    produce!(tc, s)
end

## Possibility of Strings

"""
    Text(alphabet::Possibility{Char}; min_len=0, max_len=10_000) <: Possibility{String}

A `Possibility` for producing `String`s containing `Char`s of a given alphabet.

```julia-repl
julia> using Supposition

julia> text = Data.Text(Data.AsciiCharacters(); max_len=15)

julia> example(text, 5)
5-element Vector{String}:
 "U\\x127lxf"
 "hm\\x172SJ-("
 "h`\\x03\\0\\x01[[il"
 "\\x0ep4"
 "9+Hk3 ii\\x1eT"
```
"""
struct Text <: Possibility{String}
    vectors::Vectors{Char}
    function Text(alphabet::A; min_len=0, max_len=10_000) where A <: Possibility{Char}
        vectors = Vectors(alphabet; min_size=min_len, max_size=max_len)
        new(vectors)
    end
end

produce!(tc::TestCase, s::Text) = join(produce!(tc, s.vectors))

## Dictionaries

"""
    Dicts(keys::Possibility, values::Possibility; min_size=0, max_size=10_000)

A `Possibility` for generating `Dict` objects. The keys are drawn from `keys`,
    while the values are drawn from `values`. `min_size`/`max_size` control
    the number of objects placed into the resulting `Dict`, respectively.

```julia-repl
julia> dicts = Data.Dicts(Data.Integers{UInt8}(), Data.Integers{Int8}(); max_size=3);

julia> example(dicts)
Dict{UInt8, Int8} with 2 entries:
  0x54 => -29
  0x1f => -28
```
"""
struct Dicts{K,V} <: Possibility{Dict{K,V}}
    keys::Possibility{K}
    values::Possibility{V}
    min_size::Int
    max_size::Int
    function Dicts(keys::Possibility{K}, values::Possibility{V}; min_size=0, max_size=10_000) where {K,V}
        min_size <= max_size || throw(ArgumentError("`min_size` must be `<= max_size`!"))
        new{K,V}(keys, values, min_size, max_size)
    end
end

function produce!(tc::TestCase, d::Dicts{K,V}) where {K,V}
    dict = Dict{K,V}()

    while true
        if length(dict) < d.min_size
            forced_choice!(tc, UInt(1))
        elseif (length(dict)+1) >= d.max_size
            forced_choice!(tc, UInt(0))
            break
        elseif !weighted!(tc, 0.9)
            break
        end
        k = produce!(tc, d.keys)
        v = produce!(tc, d.values)
        dict[k] = v
    end

    return dict
end

## Possibility of values from a collection

"""
    SampledFrom(collection) <: Possibility{eltype(collection)}

A `Possibility` for sampling uniformly from `collection`.

`collection`, as well as its `eachindex`, is assumed to be indexable.

!!! warning "Mutable Data"
    The source objects from the collection given to this `SampledFrom`
    is not copied when `produce!` is called. Be careful with mutable data!

```julia-repl
julia> using Supposition

julia> sampler = Data.SampledFrom([1, 1, 1, 2])

julia> example(sampler, 4)
4-element Vector{Int64}:
 1
 1
 2
 1
```
"""
struct SampledFrom{T, C} <: Possibility{T}
    collection::C
    SampledFrom(col) = new{eltype(col), typeof(col)}(col)
end

function produce!(tc::TestCase, sf::SampledFrom)
    pos_indices = eachindex(sf.collection)
    idx = produce!(tc, Integers(firstindex(pos_indices), lastindex(pos_indices)))
    return sf.collection[pos_indices[idx]]
end

## Possibility of booleans

"""
    Booleans() <: Possibility{Bool}

A `Possibility` for sampling boolean values.

```julia-repl
julia> using Supposition

julia> bools = Data.Booleans()

julia> example(bools, 4)
4-element Vector{Bool}:
 0
 1
 0
 1
```
"""
struct Booleans <: Possibility{Bool} end

produce!(tc::TestCase, ::Booleans) = weighted!(tc, 0.5)

## Possibility of floating point values

"""
    Floats{T <: Union{Float16,Float32,Float64}}(;infs=true, nans=true) <: Possibility{T}

A `Possibility` for sampling floating point values.

The keyword `infs` controls whether infinities can be generated. `nans` controls whether
    any `NaN` (signaling & quiet) will be generated.

!!! warning "Inf, Nan"
    This possibility will generate *any* valid instance, including positive
    and negative infinities, signaling and quiet NaNs and every possible float.

```julia-repl
julia> using Supposition

julia> floats = Data.Floats{Float16}()

julia> example(floats, 5)
5-element Vector{Float16}:
  -8.3e-6
   1.459e4
   3.277
 NaN
  -0.0001688
```
"""
struct Floats{T <: Base.IEEEFloat} <: Possibility{T}
    nans::Bool
    infs::Bool
    function Floats{T}(; nans=true, infs=true) where T <: Base.IEEEFloat
        new{T}(nans, infs)
    end
end

"""
    Floats(;nans=true, infs=true) <: Possibility{Union{Float64,Float32,Float16}}

A catch-all for generating instances of all three IEEE floating point types.
"""
Floats(;nans=true, infs=true) = OneOf(
    Floats{Float16}(;nans,infs),
    Floats{Float32}(;nans,infs),
    Floats{Float64}(;nans,infs))

function produce!(tc::TestCase, f::Floats{T}) where {T}
    iT = Supposition.uint(T)
    res = reinterpret(T, produce!(tc, Integers{iT}()))
    !f.infs && isinf(res) && reject(tc)
    !f.nans && isnan(res) && reject(tc)
    return res
end

end # data module
