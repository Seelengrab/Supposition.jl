module Supposition

export TestCase, TestState, forced_choice!, choice!, weighted!, assume!, target!, reject, example
export Data, @composed, @check

using Base
using Base: stacktrace, StackFrame
using Test: AbstractTestSet

import Random
using Logging

using RequiredInterfaces: @required

@static if VERSION < v"1.11"
    using ScopedValues
end

include("types.jl")
include("testcase.jl")
include("util.jl")
include("data.jl")
include("teststate.jl")
include("shrink.jl")
include("api.jl")
include("history.jl")
include("testset.jl")

end # Supposition module
