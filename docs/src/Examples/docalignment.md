# Aligning Behavior & Documentation

When it comes to property based testing, the question "but how/what should I start testing?" quickly arises.
After all, a documented & tested code base should already have matching documentation & implementation!

In reality, this is often not the case. Docstrings can bitrot when performance optimizations or bugfixes
subtly change the semantics of a function, generic functions often can't easily write out all
conditions a passed-in function must follow and large code bases are often so overwhelmingly full of
possible invocations that the task to check for conformance with each and every single docstring
can be much too daunting, to say the least.

There is a silver lining though - there are a number of simple checks a developer can use
to directly & measurably improve not only the docstring of a function, but code coverage of a testsuite.

## Does it error?

The simplest property one can test is very straightforward: On any given input, does the function error?
In theory, this is something that any docstring should be able to precisely answer - under which conditions is
the function expected to error? The use of Supposition.jl helps in confirming that the function _only_ errors under
those conditions.

Take for example this function and its associated docstring:

```
"""
    sincosd(x)

Simultaneously compute the sine and cosine of x, where x is in degrees.

!!! compat "Julia 1.3"
    This function requires at least Julia 1.3.
"""
sincosd
```

`sincosd` is a function from Base Julia - I don't mean to pick on it, but it serves as a good example (and I also
have [an open PR](https://github.com/JuliaLang/julia/pull/50855) to improve this very docstring!).

As written, we don't really know a whole lot about `sincosd`, other than that it computes both `sin` and `cosin`
in some simultaneous fashion and interprets whatever we give it in degrees. In particular, there is no mention
of what types and instances of those types are expected to work at all, and no indication of when or even if
the function can throw an error. Nevertheless, it does:

```julia-repl
julia> sincosd(Inf)
ERROR: DomainError with Inf:
`x` cannot be infinite.
Stacktrace:
 [1] sind(x::Float64)
   @ Base.Math ./special/trig.jl:1185
 [2] sincosd(x::Float64)
   @ Base.Math ./special/trig.jl:1250
 [3] top-level scope
   @ REPL[3]:1

julia> sincosd("Inf")
ERROR: MethodError: no method matching deg2rad(::String)

Closest candidates are:
  deg2rad(::AbstractFloat)
   @ Base math.jl:346
  deg2rad(::Real)
   @ Base math.jl:348
  deg2rad(::Number)
   @ Base math.jl:350

Stacktrace:
  [...]
```

So at the very least, due to its dependence on `deg2rad`, `sincosd` expects a "number-like" object, not a `String`.
At the same time, not all "number-like" objects are accepted either. It may be obvious to a mathematician or to
a developer who regularly uses `sin` that `Inf` can't possibly be a valid input, but that is not necessarily obvious
to someone just starting out with using trigonometric functions. It may be entirely reasonable that `sin`
returns `NaN` on an `Inf` input, to signal to a user that there is no number that can represent the result of that
call! For a developer, that is a huge difference in error checking behavior - one case can be a quick `if isnan(sin(z))`
check, while the other requires a costly `try`/`catch`. For this reason, it's very important to be accurate in documentation
about what kinds of inputs are valid and clearly specify what happens when & why things go wrong, and not just think of the "happy path".

So an improved version of this docstring might look like so:

```patch
  """
      sincosd(x::Number)

  Simultaneously compute the sine and cosine of x, where x is in degrees.
+
+ Throws a `DomainError` if `isinf(x)` is `true`.

  !!! compat "Julia 1.3"
      This function requires at least Julia 1.3.
  """
  sincosd
```

By adding the `::Number` type restriction to the argument `x`, we clearly communicate what kind of object we expect to work
on `sincosd`. If other user-defined types have their own implementation of `sincosd`, they should have their own docstrings
specifying the peculiarities of their implementation on their own types.

We've checked some simple examples through knowing special values of `Float64`, but are there any other special values we should
know about? Let's use Supposition.jl to define the simplest possible test that tries all kinds of different `Float64` inputs:

```@example sincosd
using Supposition

@check function sincosd_float64(f=Data.Floats{Float64}())
   try
       return sincosd(f) isa Tuple{Float64, Float64}
   catch e
       e isa DomainError && isinf(f) && return true
       rethrow()
   end
end
```

We first define our data generator, in this case sampling from all possible `Float64` values (including all `NaN`s and `Inf`s!).
For each value, we try to call `sincosd` and check whether it returns two `Float64` values.
In case an error occurs, we can check whether the error is a `DomainError` and the input was an infinity. If so, the property holds;
if not, we simply rethrow the error. Supposition.jl will take the thrown error as a signal that something has gone wrong, and try
to shrink the input to the minimal example that reproduces the same error.

Looking at that test, there's another assumption that we should document: `sincosd` returns a tuple! The companion function
`sincos` (differing from `sincosd` insofar as it takes its argument in radians, not degrees) does document this,
so we should match that documentation here too:

```patch
  """
      sincosd(x::Number)

- Simultaneously compute the sine and cosine of x, where x is in degrees.
+ Simultaneously compute the sine and cosine of x, where x is in degrees,
+ returning a tuple (sine, cosine).

  Throws a `DomainError` if `isinf(x)` is `true`.

  !!! compat "Julia 1.3"
      This function requires at least Julia 1.3.
  """
  sincosd
```

This is especially important because of the order the sine and cosine are returned in. If this isn't documented,
users can only assume which returned number is which trigonometric result, and without actually checking, they have no
way to confirm that behavior, which we will get to in the next subchapter.

Now that we've followed an example, let's reflect on what even simple "does it error?" style tests can do.
At the end of this process, a developer should now have

 * a clear understanding of when the tested function errors,
 * knowledge about the requirements a function has so that it can be called without error,
    ready to be added to the documentation of the function,
 * ready-made tests that can be integrated into a testsuite running in CI,
 * potentially found & fixed (or tracked on an issue tracker) a few bugs that were found during testing.

all of which should help a user make an informed choice in how they use e.g. `sincosd`, as well as inform
a developer about a deviation in expected behavior.

## Docstring guarantees of single functions

The next level up from error checks is checking requirements & guarantees on valid input, i.e. the input that
is not expected to error but must nonetheless conform to some specification. Once we can generate such a
valid input, we can check that the output of the function actually behaves as we expect it to.

Continuing on from the `sincosd` example from above, let's start out with a generator for all non-throwing `Float64`.
Since there are just a few of these, we can `filter` them out easily, without having to worry about rejecting too many
samples:

```@example guarantees
using Supposition

non_throw_sincos = filter(!isinf, Data.Floats{Float64}())
print(non_throw_sincos) # hide
non_throw_sincos = Data.Just(NaN) # hide
nothing # hide
```

Now let's think about what we'd like `sin` and `cos` to obey. For starters, we could use some mathematical
identities:

```@example guarantees
@check function pythagorean_identity(degrees=non_throw_sincos)
  s, c = sincosd(degrees)
  (s^2 + c^2) == one(s)
end
nothing # hide
```

Right away, we can find a very easy counterexample - `NaN`! Not to worry, we can simply amend the docstring to mention this too:

```patch
  """
      sincosd(x::Number)

  Simultaneously compute the sine and cosine of x, where x is in degrees,
  returning a tuple (sine, cosine).

  Throws a `DomainError` if `isinf(x)` is `true`.
+
+ If `isnan(x)`, return a 2-tuple of `NaN` of type `typeof(x)`.

  !!! compat "Julia 1.3"
      This function requires at least Julia 1.3.
  """
  sincosd
```

and try again, this time with `NaN` values filtered out too:

```@example guarantees
pure_float = filter(Data.Floats{Float64}()) do f
    !(isinf(f) || isnan(f))
end
function pythagorean_identity(degrees) # hide
    s, c = sincosd(degrees) # hide
    (s^2 + c^2) ≈ one(s) # hide
end # hide
@check pythagorean_identity(pure_float)
nothing # hide
```

The property holds! Very nice. What other properties do we have? Wikipedia [maintains a list](https://en.wikipedia.org/wiki/List_of_trigonometric_identities),
so we just have to pick and choose some that are to our liking.

For example, there's these:

```math
sin(\alpha \pm \beta) = sin(\alpha)cos(\beta) \pm cos(\alpha)sin(\beta) \\
cos(\alpha \pm \beta) = cos(\alpha)cos(\beta) \pm sin(\alpha)sin(\beta) \\
sin(2\theta) = 2sin(\theta)cos(\theta) = (sin(\theta) + cos(\theta))^2 \\
cos(2\theta) = cos^2(\theta) - sin^2(\theta) = 2cos^2(\theta)-1 = 1-2sin^2(\theta)
```

and lots more - there's just one problem: due to floating point addition not being associative,
almost none of these are numerically stable:

```@example guarantees
using Test

try # hide
@testset "offset identity" begin
    @check function sin_offset(a=pure_float, b=pure_float)
        sin_a, cos_a = sincosd(a)
        sin_b, cos_b = sincosd(b)
        sind(a+b) == sin_a*cos_b + cos_a*sin_b
    end
end
catch # hide
end # hide
nothing # hide
```

We have to make do with a subset of all properties then, such as "the output of `sincos` should `==`
the outputs of `sin` and `cos` on their own", or properties that avoid addition & subtraction.

```@example guarantees
@testset "sincos properties" begin
@check function sincos_same(theta=pure_float)
    s, c = sincosd(theta)
    s == sind(theta) && c == cosd(theta)
end
@check function twice_sin(theta=pure_float)
    s, c = sincosd(theta)
    twice_theta = 2*theta
    assume!(!isinf(twice_theta))
    isapprox(sind(twice_theta), 2*s*c)
end
end
nothing # hide
```

These somewhat milder properties seem to pass, nice!

Note how we have to make use of [`assume!`](@ref) to not have `sin` error out with a `DomainError` too!
This indicates that there are situations where `sincos` & the longer form of `sin` is preferable to the real
thing. I'm unsure whether that should be noted in a docstring of `sincos` (this seems more appropriate for
a computer numerics course), but it's a good example of how a developer can learn about the properties
& tradeoffs a function can have compared to its counterparts. Perhaps a warning like the following would be best:

```patch
  """
      sincosd(x::Number)

  Simultaneously compute the sine and cosine of x, where x is in degrees,
  returning a tuple (sine, cosine).

  Throws a `DomainError` if `isinf(x)` is `true`.

  If `isnan(x)`, return a 2-tuple of `NaN` of type `typeof(x)`.
+
+ !!! warning "Numerical Stability"
+     Due to floating point addition not being associative, not all
+     trigonometric identies can hold for all inputs. Choose carefully
+     and consider the operation you're doing when using trigonometric
+     identities to transform your code.

  !!! compat "Julia 1.3"
      This function requires at least Julia 1.3.
  """
  sincosd
```

We've now not only documented the erroring behavior of `sincosd`, but also special values and their
special behavior. In the process we've also found that for this particular function, not everything
we might expect actually can hold true in general - and documenting that has good chances to be
a helpful improvement for anyone stumbling over trigonometric functions for the first time (in the long
run, most developers are newbies; experts are rare!)

At the end of this process, a developer should now have

 * a better understanding of the guarantees a function gives,
 * some behavioral tests of a function, ready to be integrated into a testsuite running in CI,
 * a clear understanding that care must be taken when talking about what a computer ought to compute "correctly".

Of course, there could be numerous other properties we'd like to test. For example, we may want to confirm
that the output of `sincos` is always a 2-Tuple, or that if the input was non-`NaN`, the output values
are in the closed interval `[-1, 1]`, or that the output values are evenly distributed in that interval (up
to a point - this is surprisingly difficult to do for large inputs!)

## Interactions between functions

Once the general knowledge about single functions has been expanded and appropriately documented,
it's time to ask the bigger question - how do these functions interact, and do they interact in
a way that a developer would expect them to? Since this is more involved, I've dedicated an entire
section to this: [Stateful Testing](@ref).

These three sections present a natural progression from writing your first test with Supposition.jl,
over documenting guarantees of single functions to finally investigating interactions between functions
and the effect they have on the datastructures of day-to-day use.
