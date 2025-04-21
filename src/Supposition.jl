"""
    Supposition.jl

Supposition.jl is a fuzzing & property based testing (PBT) framework,
integrating nicely with `Test.@testset`. Under the hood it's similar
to the Python fuzzing framework Hypothesis.

The package features:

 * Generation of (almost) arbitrary instances of types
 * Minimization of failure cases
 * Testing of statemachines
 * Deterministic replaying of failures cases

..and a bunch more! Please check out [the documentation](https://seelengrab.github.io/Supposition.jl/stable/) for more information.
"""
module Supposition

export assume!, target!, event!, reject!, example
export Data, @composed, @check, @event!

using Base
using Base: stacktrace, StackFrame
using Test: AbstractTestSet

import Random
using Dates
using Logging
using Serialization

using RequiredInterfaces: @required

using ScopedValues
using StyledStrings

include("types.jl")
include("testcase.jl")
include("util.jl")
include("data.jl")
include("teststate.jl")
include("shrink.jl")
include("statistics.jl")
include("api.jl")
include("history.jl")
include("testset.jl")

using .Data: produce!
export produce!

"""
    DEFAULT_CONFIG

A `ScopedValue` holding the [`CheckConfig`](@ref) that will be used by default & as a fallback.

Currently uses these values:

 * `rng`: `Random.Xoshiro(rand(Random.RandomDevice(), UInt))`
 * `max_examples`: `10_000`
 * `record`: `true`
 * `verbose`: `false`
 * `broken`: `false`
 * `db`: `UnsetDB()`
 * `buffer_size`: `100_000`

[`@check`](@ref) will use a _new_ instance of `Random.Xoshiro` by itself.
"""
const DEFAULT_CONFIG = ScopedValue{CheckConfig}(CheckConfig(;
    rng=Random.Xoshiro(rand(Random.RandomDevice(), UInt)),
    max_examples=10_000,
    record=true,
    verbose=false,
    broken=false,
    db=UnsetDB(),
    buffer_size=100_00
))

include("precompile.jl")

end # Supposition module
