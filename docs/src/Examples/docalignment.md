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

TODO: Insert example!

At the end of this process, a developer should have

 * a clear understanding of when the tested function errors,
 * knowledge about the requirements a function has so that it can be called without error,
    ready to be added to the documentation of the function, 
 * ready-made tests that can be integrated into a testsuite running in CI,
 * potentially found & fixed (or tracked on an issue tracker) a few bugs that were found during testing.

## Docstring guarantees of single functions

The next level up from error checks is checking requirements & guarantees on valid input, i.e. the input that
is not expected to error but must nonetheless conform to some specification. Once we can generate such a
valid input, we can check that the output of the function actually behaves as we expect it to.

Take for example this function and its associated docstring:

TODO: Insert example!

At the end of  this process, a developer should have

 * a clear understanding of the guarantees a function

## Interactions between functions

Once the general knowledge about single functions has been expanded and appropriately documented,
it's time to ask the bigger question - how do these functions interact, and do they interact in
a way that a developer would expect them to? Since this is more involved, I've dedicated an entire
section to this: [Stateful Testing](@ref).

These three sections present a natural progression from writing your first test with Supposition.jl,
over documenting guarantees of single functions to finally investigating interactions between functions
and the effect they have on the datastructures of day-to-day use.
