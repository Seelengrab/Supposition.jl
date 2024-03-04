module Supposition

export TestCase, TestState, forced_choice!, choice!, weighted!, assume!, target!, reject, example
export Data, @composed, @check

using Base
using Base: stacktrace, StackFrame
using Test: AbstractTestSet

import Random
using Logging
using Serialization

using RequiredInterfaces: @required

using ScopedValues

include("types.jl")
include("testcase.jl")
include("util.jl")
include("data.jl")
include("teststate.jl")
include("shrink.jl")
include("api.jl")
include("history.jl")
include("testset.jl")

"""
    DEFAULT_CONFIG

A `ScopedValue` holding the `CheckConfig` that will be used by default & as a fallback.

Currently uses these values:

 * `rng`: `Random.Xoshiro(rand(Random.RandomDevice(), UInt))`
 * `max_examples`: `10_000`
 * `record`: `true`
 * `verbose`: `false`
 * `broken`: `false`
 * `buffer_size`: `100_000`

`@check` will use a _new_ instance of `Random.Xoshiro` by itself.
"""
const DEFAULT_CONFIG = ScopedValue{CheckConfig}(CheckConfig(;
    rng=Random.Xoshiro(rand(Random.RandomDevice(), UInt)),
    max_examples=10_000,
    record=true,
    verbose=false,
    broken=false,
    buffer_size=100_00
))

include("precompile.jl")

end # Supposition module
