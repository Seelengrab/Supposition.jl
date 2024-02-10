module Supposition

using Base
export TestCase, TestState, forced_choice!, choice!, weighted!, assume!, target!, reject, example
export Data, @composed, @check

import Random
using Logging

@static if VERSION < v"1.11"
    using ScopedValues
end

abstract type TestException <: Exception end
struct Overrun <: TestException end
struct Invalid <: TestException end
const Option{T} = Union{Some{T}, Nothing}

include("testcase.jl")
include("util.jl")
include("data.jl")
include("teststate.jl")
include("shrink.jl")
include("api.jl")
include("testset.jl")

end # Supposition module
