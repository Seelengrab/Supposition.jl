# Supposition.jl Documentation

This is the documentation for *Supposition.jl*, a property based testing framework inspired by
[Hypothesis](https://hypothesis.readthedocs.io/en/latest/).

It features choice-sequence based generation & shrinking of examples, which can smartly shrink
initial failures to smaller example while preserving the invariants the original input was generated
under. It's also easy to combine generators into new generators.

Regular unit testing can be viewed as a sequence of

 1. First, set up some data
 2. Manipulate the data in some way
 3. Assert something about the result (e.g. equality with an expected output)

while Supposition.jl treats this flow like

 1. Generate a random (valid) input
 2. Manipulate that input in some way
 3. Assert something about the result and/or check that some property holds

This is often called property based testing (PBT). For more information about why you may want to
test your library in this way, have a look at [the introduction to PBT](@ref pbt_intro).

In addition to providing facilities for generating random input, Supposition.jl also tries
to simplify any found inputs to make them easier to handle when debugging the failure.

For specific useage example of Supposition.jl, give the `Examples` in the sidebar a look! They contain common
PBT patterns that can often generalize.

Here's also a sitemap for the rest of the documentation:

```@contents
Pages = [ "index.md", "intro.md", "faq.md", "interfaces.md", "api.md" ]
Depth = 3
```

## Goals

 * Good performance
   * A test framework should not be the bottleneck of the testsuite.
 * Composability
   * It should not be required to modify an existing codebase to accomodate Supposition.jl
   * However, for exploratory fuzzing it may be advantageous to insert small markers into a codebase
 * Reusability
   * It should be easily possible to reuse large parts of existing definitions (functions/structs) to
     build custom generators
 * Repeatability
   * It should be possible to replay previous (failing) examples and reproduce the sequence of steps taken
     *exactly*. The only cases where this isn't going to work is if your code relies on external state,
     such as querying a hardware RNG for random data or similar objects that are not under the control of
     the testing framework itself (such as the capacity of your harddrive, for example).
 * Discoverability (of API boundaries)
   * Supposition.jl should be easy to use to find the actual API boundaries of a given function, if that is
     not yet known or not sufficiently specified in the docstring of a function. It should be enough to
     know the argument types to start fuzzing a function (at least in the simplest sense of "does it error").
 * Ease of Use
   * It should be relatively straightforward to write custom generators.

## Limitations

 * Due to its nature as a fuzzing framework and the (usually) huge associated statespace, Supposition.jl
   cannot give a formal proof of correctness. It's only an indicator (but a pretty good one).
