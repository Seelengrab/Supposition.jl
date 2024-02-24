# FAQ

## Why write a new package? What about PropCheck.jl?

PropCheck.jl is based on the Haskell library Hedgehog, while Supposition.jl is based on Hypothesis.
For a detailed look into the differences between these (as well as QuickCheck), I've written up
a small comparison [on my blog](https://seelengrab.github.io/articles/The%20properties%20of%20QuickCheck,%20Hedgehog%20and%20Hypothesis/).
Some understanding of property based testing is required, but the TL;DR is that the approaches
taken by these two frameworks are fundamentally different. 

Originally, I was planning on only investigating what Hypothesis did differently from Hedgehog and
incorporating the results of that investigation into PropCheck.jl, but once I learned how different
the approaches truly are, I quickly realized that marrying the two would be more work and likely less
fruitful than just porting Hypothesis directly. My resolve in that regard had only grown stronger
after [porting MiniThesis to Julia](https://github.com/DRMacIver/minithesis), which this package is ultimately also based on. So far, I have
found the core of the package to be extremely solid, and I don't expect that to change.

Some of the upsides I've noticed while using Supposition.jl so far is that it's much, MUCH easier to
wrap your head around than PropCheck.jl ever was. Even after working on & thinking about Hedgehog & PropCheck.jl
for more than 4 years, I still get lost in its internals. I don't see that happening with Supposition.jl;
I can confidently say that I am (for the moment) able to keep the entire package in my head. 
Another big upside is that, as far as I can tell, Supposition.jl is much faster than PropCheck.jl, even
after the latter received extensive type stability analysis and performance improvements out of necessity.
I haven't done the same for Supposition.jl so far - be sure to check out the [Benchmarks](@ref) section for a direct
comparison. Of course, only part of this is due to the underlying approach of Hypothesis vs. Hedgehog.
Sticking to a much more functional & function-based implementation with PropCheck.jl is sure to hold
the package back, and perhaps the situation would be different with a more data-oriented approach.

## What can Supposition.jl do that PropCheck.jl can't?

While there is a big overlap in capabilities between the two, there are a number of things that
Supposition.jl can very easily do that would require a major rework of the internals of PropCheck.jl.
Here's a small (incomplete) list:

 * Shrink examples that lead to an error
 * Easily use temporal & stateful property tests
 * Reproducibly replay previously found counterexamples (with caveats regarding external state)
 * Generate values based on the values that were put into a test, and have those values in turn
   shrink just as well as the values that were put in while preserving the invariants they were
   generated under.

