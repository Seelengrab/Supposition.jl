# Supposition.jl

[![CI Stable](https://github.com/Seelengrab/Supposition.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/Seelengrab/Supposition.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![CI Nightly](https://github.com/Seelengrab/Supposition.jl/actions/workflows/nightly.yml/badge.svg)](https://github.com/Seelengrab/Supposition.jl/actions/workflows/nightly.yml?query=branch%3Amain)
[![docs-stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://seelengrab.github.io/Supposition.jl/stable)
[![docs-dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://seelengrab.github.io/Supposition.jl/dev)
[![codecov](https://codecov.io/gh/Seelengrab/Supposition.jl/graph/badge.svg?token=BMO2XHN5JX)](https://codecov.io/gh/Seelengrab/Supposition.jl)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

This is a Julia implementation of property based testing using choice sequences.
It's been heavily inspired by the testing framework [Hypothesis](https://hypothesis.readthedocs.io/en/latest/).

Supposition.jl features the following capabilities:

 * Shrinking of generated examples
   * targeted shrinking, counterexample shrinking and error-based shrinking are all supported
 * Combination of generators into new ones
 * Basic stateful testing
 * Deterministic replaying of previously recorded counterexamples
 * Integration into existing frameworks through `Test.AbstractTestset`

Please check out the [documentation](https://seelengrab.github.io/Supposition.jl/stable) for more information!

If you have specific usage questions, ideas for new features or want to show off
your fuzzing skills, please share it on the [Discussions Tab](https://github.com/Seelengrab/Supposition.jl/discussions)!

Here's a small usage example:

```julia
julia> using Test, Supposition

julia> @testset "Examples" begin

           # Get a generator for `Int8`
           intgen = Data.Integers{Int8}()

           # Define a property `foo` and feed it `Int8` from that generator
           @check function foo(i=intgen)
               i isa Int
           end

           # Define & run another property, reusing the generator
           @check function bar(i=intgen)
               i isa Int8
           end

           # Define a property that can error
           @check function baba(i=intgen)
               i < -5 || error()
           end

           # Feed a new generator to an existing property
           @check bar(Data.Floats{Float16}())

           # Mark properties as broken
           @check broken=true function broke(b=Data.Booleans())
               b isa String
           end

           # ...and lots more, so check out the docs!
       end
```

Which will (on 1.11+ - in older versions, the testset printing can't be as pretty :/) produce this output:

```
┌ Error: Property doesn't hold!
│   Description = "foo"
│   Example = (i = -128,)
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:255
┌ Error: Property errored!
│   Description = "baba"
│   Example = (i = -5,)
│   exception =
│
│    Stacktrace:
│     [1] error()
│       @ Base ./error.jl:44
│     [2] (::var"#baba#11")(i::Int8)
│       @ Main ./REPL[2]:18
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:250
┌ Error: Property doesn't hold!
│   Description = "bar"
│   Example = (Float16(0.0),)
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:255
Test Summary: | Pass  Fail  Error  Broken  Total  Time
Examples      |    1     2      1       1      5  1.2s
  foo         |          1                     1  0.0s
  bar         |    1                           1  0.0s
  baba        |                 1              1  0.2s
  bar         |          1                     1  0.0s
  broke       |                         1      1  0.0s
ERROR: Some tests did not pass: 1 passed, 2 failed, 1 errored, 1 broken.
```
