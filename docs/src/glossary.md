# Glossary

Property Based Testing has a lot of jargon associated with it, so this page contains
a small glossary explaining the most commonly used terms. Their definitions are written
down in the context of Supposition.jl, and may deviate slightly from their use in other
frameworks.

### Generator

A generator in the context of Supposition.jl is any object capable of producing objects
by following the interface required by [`Data.Possibility`](@ref).

### Choice Sequence

Supposition.jl records any decision taken while generating a counterexample to a choice sequence.
For example, in order to generate an `Int64`, 64 individual choices (one for each bit) need to
be made. For an `Int32`, it's 32 individual choices and so on for other number types.
For composite types, the recorded choices are an aggregate of the choices required for composition,
as well as the choices of each individual object the composite type will be created out of.

Some [`Data.Possibility`](@ref), such as [`Data.Just`](@ref), don't require any choices to be made, since
they always produce the same value.

As an example, generating a value from `Data.Integers(0x0, 0xf)` may lead to this choice sequence:

```
UInt[ 0x5 ]
```

I.e. it records that the produced value was `0x5` (internally, the choice sequence
is currently modelled as a `Vector{UInt64}`, though this is an implementation detail).

Another possible choice sequence is is `[ 0x4 ]`, another is `[ 0x1 ]`, another (and minimal) is `[ 0x0 ]`.
The bitstring representations of these are `00000100`, `00000001` and `00000000`
respectively.

How exactly this choice sequence is mapped to producing a value depends on
the `Possibility` in use - for this `Data.Integers` example, the value is given
directly. For others, like `Float64`, the mapping is more complicated.

### Fuzzing

"Fuzzing" refers to the process of generating random input to a function or program and executing
that function with that randomly generated input. A program that generates such random input is
called a "fuzzer".

There are various complexity grades of fuzzers. Some rely on purely random generation and some take
additional information into account to guide the random generation into more desirable directions.
The general goal of any fuzzer is to explore the entire codebase through its random input,
trying to find some failure condition (traditionally: segmentation faults).

### Unstructured Fuzzing 

There is also a distinction to be made between structured and unstructured fuzzing. Traditional
fuzzers like [American Fuzzy Lop (AFL)](https://github.com/google/AFL) started out as treating the input as a pure stream
of bytes, leaving the fuzzer to discover any additional requirements on the input by itself. This
stream of random bytes is fed to the program under test, which then either accepts or rejects the
input in some manner. Traditionally, this is detected with either return codes of the executed
program, analysis of the output stream or detected segmentation faults.

### Structured Fuzzing

Most programs operate on more than just random streams of bytes and require some structure to their input.
In the context of Supposition.jl this means composing various [`Data.Possibility`](@ref) into more complex
generators, which "stacks" the guarantees provided on the produced output. By producing more complex
objects, the "stream of random bytes" effectively gains more structure, reducing the number of rejections
due to trivially rejectable input.

This has the effect of requiring less work of the fuzzer to find "well formed" inputs that the program
accepts, making it easier to explore a larger portion of the codebase.

In addition to giving more structure to the generated examples, by creating actual objects directly it becomes possible to
not just give an input through the standard input stream, but also through calling various functions directly.
This allows to check more program/function specific failure cases, not just exit codes or segmentation faults.

### Property Based Testing

Property Based Testing (PBT) refers to a testing technique where a program is tested not just with small hardcoded
inputs, but with randomly generated input. Because the random input can make it impossible to make an exact comparison
with an expected value, what is usually tested instead of the exact output is a _property_ that the output (or the program!)
should have after the function currently being tested is called on the generated input.

For instance, after calling `lowercase` on a string, every individual character of the output should be in lower case.
Or after calling lowercase once, repeated calls of `lowercase` should not result in different strings.

### Property

A property is a boolean predicate that an object can have. For example, some `UInt8` have the property `iseven` (they are even numbers).
As another example, some `String` have the property `isascii` (they consist of only ASCII characters).

In the context of `@check`, a property is a predicate that the programmer wants a given transform/function call to have.
Here, `@check` tries to check that the desired property actually holds.

### Invariant

An invariant is a boolean predicate that holds for _all_ objects of a given type. For example, `x -> 0 <= x <= 255` is
true for all `UInt8`, thus the property is an invariant for `UInt8`. In contrast, this property is NOT an invariant
for `UInt16`, because there are values in `UInt16` that are larger than `255`.

A generator such as `ints = Data.Integers{UInt8}()` guarantees to _always_ produce `UInt8`; this is an invariant of the generator.
Similarly, a generator such as `map(x -> 0x2 * x, ints)` guarantees to _always_ produce `UInt8` that are even numbers, because
`x -> 0x2 * x` makes any number even by multiplying it with `0x2`.
Composing generators composes the invariants the input generator provides, with the invariants the composed function
provides. Through this, it is possible to create generators than can guarantee quite a lot of interesting & useful properties.

### Shrinking

Shrinking refers to the process of removing choices in the choice sequence in order to produce a "smaller" example
that makes a property fail in the same way as the original example (built from the original choice sequence) did.
Additionally, Supposition.jl considers shorter choice sequences better than longer ones, because that means that
fewer choices were necessary to produce a failing input.

How a given produce _value_ shrinks depends on how the mapping from the choice sequence to that value is implemented.
Generally though, numbers tend to shrink towards smaller values (e.g. `UInt` and `Float64` shrink towards zero),
collections shrink towards empty collections (`Vector`s shrink to empty vectors, `Dict`s to empty dicts with minimal keys & values)
etc.
