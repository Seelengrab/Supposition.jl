# Supposition.jl

[![CI Stable](https://github.com/Sukera/Supposition.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Sukera/Supposition.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![CI Nightly](https://github.com/Sukera/Supposition.jl/actions/workflows/nightly.yml/badge.svg?branch=main)](https://github.com/Sukera/Supposition.jl/actions/workflows/nightly.yml)
[![docs-stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://seelengrab.github.io/Supposition.jl/stable)
[![docs-dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://seelengrab.github.io/Supposition.jl/dev)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

This is a Julia port of the property based testing framework [Hypothesis](https://hypothesis.readthedocs.io/en/latest/).

Supposition.jl features the following capabilities:

 * Shrinking of generated examples
   * targeted shrinking, counterexample shrinking and error-based shrinking are all supported
 * Combination of generators into new ones
 * Basic stateful testing
 * Integration into existing frameworks

Please check out the [documentation](https://seelengrab.github.io/Supposition.jl/stable) for more information!

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
       end
```

Which will produce this output:

```
┌ Error: Property doesn't hold!
│   Description = "foo"
│   Example = (i = -128,)
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:150
┌ Error: Property errored!
│   Description = "baba"
│   Example = (i = -5,)
│   exception =
│
│    Stacktrace:
│     [1] error()
│       @ Base ./error.jl:44
│     [2] (::var"#baba#27")(i::Int8)
│       @ Main ./REPL[3]:18
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:145
┌ Error: Property doesn't hold!
│   Description = "bar"
│   Example = (Float16(0.0),)
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:150
Test Summary: | Pass  Fail  Error  Total  Time
Examples      |    1     2      1      4  0.2s
  foo         |          1             1  0.0s
  bar         |    1                   1  0.0s
  baba        |                 1      1  0.1s
  bar         |          1             1  0.0s
ERROR: Some tests did not pass: 1 passed, 2 failed, 1 errored, 0 broken.
```
