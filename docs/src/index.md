# Supposition.jl Documentation

This is the documentation for *Supposition.jl*, a property based testing framework inspired by
[Hypothesis]().

It features choice-sequence based generation & shrinking of examples, which can smartly shrink
initial failures to smaller example while preserving the invariants the original input was generated
under. It's also easy to combine generators into new generators.

Check out the Examples in the sidebar to get an introduction to property based testing and to learn how to write your own tests!

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
