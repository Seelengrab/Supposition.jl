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

## What feature X of PropCheck.jl corresponds to feature Y of Supposition.jl?

The following is a short overview/feature comparison between PropCheck.jl and Supposition.jl. It may not be a perfect match for all functionality -
be sure to check the documentation of each respective feature to learn about their minute differences!

| Feature                            | PropCheck.jl                                                        | Supposition.jl                                                                                                                   |
|------------------------------------|---------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| Checking Interface                 | `check(<prop>, <AbstractIntegrated>)`                                 | `@check prop(<Data.Possibility>)`  or  `@check function prop(arg=<Data.Possibility>, ...)    # ...use args... end`             |
| `map`                              | `map(<func>, <AbstractIntegrated>)`                                   | `map(<func>, <Data.Possibility>)`                                                                                              |
| `filter`                           | `filter(<pred>, <AbstractIntegrated>)`                                | `filter(<pred>, <Data.Possibility>)`                                                                                           |
| composition through combination    | `interleave(integ::AbstractIntegrated...)`                            | `@composed function comp(a=<Data.Possibility>, ...)    # ...use args... end`                                                   |
| Vectors                            | `PropCheck.vector(len::AbstractIntegrated, objs::AbstractIntegrated)` | `Data.Vectors(objs::Data.Possibility; min_size=0, max_size=...)                                                                |
| Tuples                             | `PropCheck.tuple(len::AbstractIntegrated, objs::AbstractIntegrated)`  | Currently unsupported, but could be added in a PR                                                                              |
| Integers                           | `PropCheck.inegint`/`PropCheck.iposint`                               | `Data.Integers(min, max)`                                                                                                      |
| Floating point                     | `PropCheck.ifloat(T)` and its variants                                | `Data.Floats{T}(; infs=<Bool>, nans=<Bool>)`                                                     |
| Strings                            | `PropCheck.str(len::AbstractIntegrated, alphabet::AbstractIntegrated)` | `Data.Text(::Possibility{Char}; min_len=0, max_len=...)`                                                                      |
| Stateful generation                | `IntegratedOnce`                                                      | Unsupported due to deterministic replaying of finite generators being tricky                                                   |
|                                    | `IntegratedFiniteIterator`                                            | Unsupported due to deterministic replaying of finite generators being tricky                                                   |
|                                    | `IntegratedLengthBounded`                                             | Unsupported due to deterministic replaying of finite generators being tricky                                                   |
|                                    | `IntegratedChain`                                                     | Unsupported due to deterministic replaying of finite generators being tricky                                                   |
|                                    | `PropCheck.iunique`                                                   | Unsupported due to deterministic replaying of finite generators being tricky                                                   |
| Generation of constant data        | `PropCheck.iconst(x)`                                                 | `Data.Just(x)`                                                                                                                 |
| Generation from Collections        | `IntegratedRange(x)`/`PropCheck.isample`                              | `Data.SampledFrom(x)`                                                                                                          |
| Generation of shrinkable constants | `IntegratedVal(x)`                                                    | Unsupported until custom shrinking functions are added, see [#25](https://github.com/Seelengrab/Supposition.jl/discussions/25) |
| Type-based generation              | `PropCheck.itype`                                                     | Unsupported for now, see [#21](https://github.com/Seelengrab/Supposition.jl/discussions/21) for more information (it's coming though! And smarter than PropCheck.jl too ;) ). |

## Can I use Supposition.jl to test an MIT/proprietary/other licensed project?

Yes!

Supposition.jl is licensed under the [EUPLv1.2](https://joinup.ec.europa.eu/collection/eupl), which means that modifications
to Supposition.jl also need to be licensed under the EUPLv1.2 (and various other obligations).
However, simply _using_ Supposition.jl in a testsuite of any project has no
influence on the license of that project (or even the testsuite), because the EUPLv1.2 [is not a "viral"
copyleft license](https://joinup.ec.europa.eu/collection/eupl/news/eupl-and-proprietary-commer). There is no risk of having to license your MIT/proprietary/other
licensed project under the EUPLv1.2, because under European law (which the EUPLv1.2 defaults
to, even if you're outside of the EU as either licensor or licensee) linking computer
programs for the purposes of interoperability is [exempt from copyright](https://joinup.ec.europa.eu/collection/eupl/news/why-viral-licensing-ghost),
which is the cause of "virality" in other licenses.

For more information about using Supposition.jl in a commercial setting, see [EUPL and Proprietary / Commercial use](https://joinup.ec.europa.eu/collection/eupl/news/eupl-and-proprietary-commer), written by [Patrice-Emmanuel Schmitz](https://joinup.ec.europa.eu/user/9079),
who has written [extensive analysis](https://www.jolts.world/index.php/jolts/article/view/91/164) of the EUPL under EU law.
For more information about copyright in the EU in general, see [Directive 2009/24/EC](https://eur-lex.europa.eu/legal-content/en/TXT/?uri=CELEX:32009L0024).
