using MiniThesis
using Test
using Aqua

@testset "MiniThesis.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(MiniThesis; ambiguities = false,)
    end
    # Write your tests here.
end
