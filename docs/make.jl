using Documenter
using Supposition, Supposition.Data

liveserver = "livesever" in ARGS

if liveserver
    using Revise
    Revise.revise()
end

DocMeta.setdocmeta!(Supposition, :DocTestSetup, :(using Supposition, Supposition.Data); recursive=true)

function builddocs(clear=false)
    clear && rm(joinpath(@__DIR__, "build"), force=true, recursive=true)
    makedocs(
        sitename="Supposition.jl Documentation",
        format = Documenter.HTML(
            prettyurls = get(ENV, "CI", nothing) == true
        ),
        remotes=nothing,
        pages = [
            "Main Page" => "index.md",
            "Introduction to PBT" => "intro.md",
            "Examples" => [
                "Basic Usage" => "Examples/basic.md",
                "Composing Generators" => "Examples/composition.md",
                "Stateful Testing" => "Examples/stateful.md",
            ],
            "FAQ" => "faq.md",
            "Interfaces" => "interfaces.md",
            "Benchmarks" => "benchmarks.md",
            "API Reference" => "api.md"
        ]
    )
end

builddocs()

!isinteractive() && !liveserver && deploydocs(
   repo = "github.com/Seelengrab/Supposition.jl.git",
   devbranch = "main",
   push_preview = true
)
