module Supposition

using Base
export TestCase, TestState, forced_choice!, choice!, weighted!, assume!, target!, reject

import Random
using Logging

abstract type Error <: Exception end
struct Overrun <: Error end
struct Invalid <: Error end
const Option{T} = Union{Some{T}, Nothing}

include("util.jl")
include("testcase.jl")
include("data.jl")
include("teststate.jl")
include("shrink.jl")

end # Supposition module
