# Basic Usage

At its core, property based testing (PBT) is about having a function (or set of functions) to test and a set of 
properties that should on on that function. If you're already familiar with PBT, this basic example
will be familiar to you already. 

Consider this `add` function, which simply forwards to `+`:

```@example example_add; output=false
function add(a,b)
    a + b
end
```

How can we test that this function truly is the same as `+`? First, we have to decide what input we
want to test with. In Supposition.jl, this is done through the use of `Possibilitiy` objects, which represent
an entire set of objects of a shared type. In other frameworks like Hypothesis, this is known as a strategy.
In our case, we are mostly interested in integers, so the generator [`Data.Integers{UInt}`](@ref)
is what we're going to use:

```@example example_add; output = false
using Supposition, Supposition.Data

intgen = Data.Integers{UInt}()
```

Now that we have our input generator, we have to decide on the properties we want to enforce. Here, we simply
want to check the mathematical properties of addition, so let's start with commutativity:

```@example example_add; output = false
Supposition.@check function commutative(a=intgen, b=intgen)
    add(a,b) == add(b,a)
end
nothing # hide
```

[`@check`](@ref) takes a function definition where each argument is given a `Possibility`, runs those generators, feeds
the generated values into the given function and shrinks any failing examples. Note that the name given in the
arguments is the same as used in the function.

Here's an example for a failing property:

```@example example_add; output = false
try # hide
Supposition.@check function failprop(x=intgen)
    add(x, one(x)) < x
end
catch # hide
end # hide
nothing # hide
```

Supposition.jl successfully found a counterexample and reduced it to a more minimal counterexample, in this
case just `UInt(0)`.

!!! note "Overflow"
    There is a subtle bug here - if `x+1` overflows when `x == typemax(UInt)`, the resulting comparison is
    `true`: `typemin(UInt) < typemax(UInt)` after all. It's important to keep these kinds of subtleties, as
    well as the invariants the datatype guarantees, in mind when choosing a generator and writing properties
    to check the datatype and its functions for.

We've still got three more properties to test, taking two or three arguments each. Since these properties
are fairly universal, we can also write them out like so, passing a function of interest:

```@example example_add; output = false
associative(f, a, b, c) = f(f(a,b), c) == f(a, f(b,c))
identity_add(f, a) = f(a,zero(a)) == a
function successor(a, b)
    a,b = minmax(a,b)
    sumres = a
    for _ in one(b):b
        sumres = add(sumres, one(b))
    end

    sumres == add(a, b)
end
```

And check that they hold like so. Of course, we can also test the property implicitly defined by `@check` earlier: 

```@example example_add; output = false, filter = r"\d+\.\d+s"
using Test

Supposition.@check associative(Data.Just(add), intgen, intgen, intgen)
Supposition.@check identity_add(Data.Just(add), intgen)
Supposition.@check successor(intgen, intgen)
Supposition.@check commutative(intgen, intgen)
nothing # hide
```

In this way, we can even reuse properties from other invocations of `@check` with new, perhaps more specialized, inputs.
For generalization, we can use [`Data.Just`](@ref) to pass our `add` function to the generalized properties.

!!! note "Nesting @testset"
    From Julia 1.11 onwards, `@check` can also report its own results as part of a parent `@testset`.
    This is unfortunately unsupported on 1.10 and earlier.

Be aware that while all checks pass, we _do not have a guarantee that our code is correct for all cases_.
Sampling elements to test is a statistical process and as such we can only gain _confidence_ that our code
is correct. You may view this in the light of Bayesian statistics, where we update our prior that the code
is correct as we run our testsuite more often. This is also true were we not using property based testing
or Supposition.jl at all - with traditional testing approaches, only the values we've actually run the code with
can be said to be tested.
