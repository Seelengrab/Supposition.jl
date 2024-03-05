# Ways to contribute

First and foremost, thank you for wanting to contribute to Supposition.jl!

## Contributing bug/doc/UX fixes

The general philosophy surrounding contributions is "reply quickly, fix correctly".
What does that mean? In essence, the goal is to first and foremost make users
feel heard about the particular pain point/bug/documentation or UX problem they're
encountering. However, not everything is a quick fix, and especially more tricky
fixes can take a while to develop. It's good to give an early sign of interaction
(just something along the lines of "Hey, thanks for reporting this! I can see how that would
be a problem, perhaps XYZ can work?"), but it's important to be sure that
any proposed fix in a PR is _correct_, i.e. if it's a bug that the fix comes with tests
covering to prevent regressions, if it's a pain point/UX/doc problem that it
comes with a justification of some form of why the proposed fix is good. If it takes some
time to actually arrive at that fix, that is fine - coding is complicated work.

Always keep in mind; we're writing things down so we don't forget, as well
as making it easier for new people to learn about the codebase and its history.

## Other contributions

The package is not too large yet, coming in at just under 3000LOC at the
time of writing, docstrings, whitespace & all. The largest part by far are
the definitions of the actual generators in `src/data.jl`:

```
[sukera@tower Supposition.jl]$ wc -l src/* | sort -h
   29 src/precompile.jl
   58 src/Supposition.jl
   97 src/history.jl
  124 src/testcase.jl
  161 src/util.jl
  206 src/types.jl
  238 src/shrink.jl
  288 src/testset.jl
  301 src/teststate.jl
  466 src/api.jl
  862 src/data.jl
 2830 total
```

At the same time, this is also the place where contributions are (currently)
most appreciated; it's always helpful to support more basic data types
out of the box, as well as test the existing ones better.

### Contributing tests

While coverage is already reasonably high for the core functionality of
the package, it can nevertheless happen that some edge cases are, as of yet,
not covered by tests. If possible, adding a test for that using `@check` is
preferred (after all, [dogfooding](https://en.wikipedia.org/wiki/Eating_your_own_dog_food) the package is one of the best ways
to find subtle bugs!). Keep these tests lean - we want to test the maximum
of guaranteed functionality with the minimum of required input, to ensure
that any failure not only shrinks fast, but also leads directly to an easy
to understand counterexample to reproduce with. Once a counterexample has been found,
it's ok to add that counterexample as a standalone regular unittest (without `@check`)
to the testsuite.

### Contributing documentation

More documentation is always welcome! In particular, examples on how to use
`@check` in more complex situations or how to combine various `Possibility`
in a specific way are well sought after. If you have an example of a new
technique for practicing property based testing and have ported it to
Supposition.jl, please don't hesitate to open a PR so that it can either
be added as an example to the documentation, or linked as a more advanced resource.

### Contributing a `Possibility`

Generally, if it's in Base it can go into `src/data.jl`. Take a look at
the existing implementations for inspiration. The general approach
is to define a struct with supertype `Possibility{T}` for some precise
`T`, taking any required `Possibility` as positional arguments. Some generators can
support additional configuration, such as `Vectors` taking `min_size` & `max_size`
for controlling the size of the generated vector or `Floats` taking `infs` & `nans`
for including/excluding `Inf` and `NaN` respectively. For these, provide an
_inner_ constructor that takes these additional arguments as keywords, checking
their validity before returning a new instance. For example, `Dicts` and `Vectors` check
that `min_size <= max_size`, `Recursive` checks that at least one element
can be produced without wrapping.

Once you have a `MyPossibility <: Possibility` defined, you need to define `produce!(::MyPossiblity, ::TestCase)`,
which generates all necessary information to construct an instance of your desired
object. There are some general tricks to use here so that the resulting objects
shrink well:

DO:

 * Reuse existing `Possibility`. They are already tested & investigated to
   work well, so reusing them is a boon.
 * Document the design decisions for complicated `produce!` functions extensively.
   The next person coming after you should be able to pick the code up where you left off,
   without having to do too much guess work about WHY something is written the way it is.
 * Keep the `Possibility` as generic as possible, while being as specific as necessary.
   If it's possible to generalize the `Possibility` a bit without compromising the
   intent too much, it's generally a good choice to do so. This doesn't always
   apply; for example, `AsciiCharacters` doesn't use `Characters` under the hood
   because it's more efficient to sample only ASCII `Char` directly rather than
   filtering out invalid characters from the full Unicode set of `Char`. Still,
   both options are provided for convenience.

AVOID:

 * Adding dependencies to support specific types either from the ecosystem or
   an stdlib. These should live in a Pkg extension instead. If the type in
   question is from an stdlib, it's fine to have that extension live in
   Supposition.jl, but if it's for an external package, please maintain that
   extension & `Possibility` upstream. Supposition.jl is intended to be as
   lightweight as possible; new dependencies should only be added if they
   vastly simplify an implementation (e.g., PrecompileTools.jl is a dependency
   because rolling this ourselves is not the purpose of this package).
 * Explicit calls to `rand`. While Supposition.jl can make these calls
   deterministic (in the sense that it can replay the randomness), it
   _cannot_ shrink values produced this way properly. This is because
   (barring any bugs in the `Random` stdlib), the PRNG used is by definition
   not predictable/steerable. `rand` thus cannot be used as a source of
   shrinkable randomness, and various combinations of `OneOf`, `SampledFrom` etc.
   should be used instead. There may be some situations where `rand` seems
   unavoidable, but often these are possible to "turn inside out" and make shrinkable
   by mapping the use of `rand` to `SampledFrom` of an explicit collection.

### Contributing new features

The discussion tab already has a number of [planned features](https://github.com/Seelengrab/Supposition.jl/discussions?discussions_q=is%3Aopen+label%3Afeature).
I have some idea on how to implement all of these, so I can definitely give some
guidance if you want to tackle a feature to learn about the inner workings
of Supposition.jl. These "design docs" also have a list of things that
each feature should do, sometimes with a "nice to have, but not required".

If you want to implement a planned feature, please comment in its thread,
either asking for guidance or (if you've already read a bit about the internals)
lay out a rough sketch of how you want to implement the feature. 

If you want to contribute a new feature that hasn't yet been brought up, please post a descriptive summary
of what the feature does, how users are expected to interact with it
as well as a very rough sketch of a possible implementation to the 
[Design & Ideas](https://github.com/Seelengrab/Supposition.jl/discussions/categories/design-ideas?discussions_q=is%3Aopen+label%3Afeature+category%3A%22Design+%26+Ideas%22)
section of the discussion board. This may sound like a lot, but a few
sentences is usually enough for all of these. For example, for a new `Possibility`
the main questions that would be asked are "how will this shrink?" or "what
can I configure about this?", and having some succinct answers to this communicates
more precisely what the feature is for. Similarly, the "rough sketch" for an implementation
can be as simple as "I'd add XY here (linking), which allows FOO."

If you're unsure about how exactly a feature would be implemented, it's totally fine to omit that part! For this case,
please mention that you'd like some guidance on how/where your feature can be added (or, if you only want to suggest
an idea, omitting it entirely - please mention this though, so others know that the feature is up for grabs).

The reasoning for this approach is simple:

 * Clearly laying out what the vision behind the feature is makes room for discussion; perhaps there's a particularly
   good way to add the feature?
 * Having a good idea of what a feature is supposed to do aids in writing tests & docs for the feature
 * Discussing a feature before its implemented helps prevent contribution burnout; noone likes writing a bunch
   of code, only to have it shot down in PR review.
 * Documenting the history of how a feature came to be makes it easier for future contributors & maintainers follow
   the reasoning/assumptions that were made.
 * It can happen that some feature may sound great on paper, but falls apart at the implementation stage for various reasons, so to speak; for these
   cases, it's especially useful to have an outline to come back to in the future, should the feature in principle still be viable for inclusion.
