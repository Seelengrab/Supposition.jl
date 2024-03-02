# Composing generators

## `@composed`

While Supposition.jl provides basic generators for a number of objects from Base, quite a lot of Julia code relies on the use of custom structs. At the innermost level,
all Julia structs are composed of one or more of these basic types, like `Int`, `String`, `Vector` etc. Of course, we want to be able to generate & correctly shrink
these custom structs as well, so how can this be done? Enter [`@composed`](@ref), which can do exactly that. Here's how it's used:

```@example example_composed
using Supposition

const intgen = Data.Integers{Int}()

makeeven(x) = (x÷0x2)*0x2

even_complex = @composed function complex_even(a=intgen, b=intgen)
    a = makeeven(a)
    b = makeeven(b)
    a + b*im
end
example(even_complex, 5)
```

In essence, `@composed` takes a function that is given some generators, and ultimately returns a generator that runs the function on those given generators.
As a full-fledged `Possibility`, you can of course do everything you'd expect to do with other `Possibility` objects from Supposition.jl, including
using them as input to other `@composed`! This makes them a powerful tool for composing custom generators.

```@example example_composed
@check function all_complex_even(c=even_complex)
    iseven(real(c)) && iseven(imag(c))
end
nothing # hide
```

!!! warning "Type stability"
    The inferred type of objects created by a generator from `@composed` is a _best effort_ and may be wider
    than expected. E.g. if the input generators are non-`const` globals, it can easily happen that type inference
    falls back to `Any`. The same goes for other type instabilities and the usual best-practices surrounding type
    stability.

In addition, `@composed` defines the function given to it as well as a regular function, which means that you can call & reuse it however you like:

```@example example_composed
complex_even(1.0,2.0)
```

## Filtering, mapping, and other combinators

### `filter`

Of course, manually marking, mapping or filtering inside of `@composed` is sometimes a bit too much. For these cases,
all `Possibility` support `filter` and `map`, returning a new [`Data.Satisfying`](@ref) or [`Data.Map`](@ref) `Possibility` respectively:

```@example filter
using Supposition

intgen = Data.Integers{UInt8}()

f = filter(iseven, intgen)

example(f, 10)
```

Note that filtering is, in almost all cases, strictly worse than constructing the desired objects directly. For example, if the filtering predicate
rejects too many examples from the input space, it can easily happen that no suitable examples can be found:

```@example filter
g = filter(>(typemax(UInt8)), intgen)
try # hide
example(g, 10)
catch e # hide
Base.display_error(e) # hide
end # hide
nothing # hide
```

It is best to only filter when you're certain that the part of the state space you're filtering out is not substantial.

### `map`

In order to make it easier to directly construct conforming instances, you can use `map`, transforming the output of one `Possibility` into a different object:

```@example mapping
using Supposition

intgen = Data.Integers{UInt8}()
makeeven(x) = (x÷0x2)*0x2
m = map(makeeven, intgen)

example(m, 10)
```

!!! warning "Type stability"
    The inferred type of objects created by a generator from `map` is a _best effort_ and may be wider
    than expected. Ensure your function `f` is easily inferrable to have good chances for `map`ping it
    to be inferable as well.
