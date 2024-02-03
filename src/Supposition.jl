module Supposition

using Base
export TestCase, TestState, forced_choice!, choice!, weighted!, assume!, target!, reject, example

import Random
using Logging

abstract type Error <: Exception end
struct Overrun <: Error end
struct Invalid <: Error end
const Option{T} = Union{Some{T}, Nothing}

include("testcase.jl")
include("util.jl")
include("data.jl")
include("teststate.jl")
include("shrink.jl")
include("api.jl")

end # Supposition module
