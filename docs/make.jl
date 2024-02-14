using Documenter

liveserver = "livesever" in ARGS

if liveserver
    using Revise
    Revise.revise()
end

using Supposition, Supposition.Data

DocMeta.setdocmeta!(Supposition, :DocTestSetup, :(using Supposition, Supposition.Data); recursive=true)

function builddocs(clear=false)
    clear && rm(joinpath(@__DIR__, "build"), force=true, recursive=true)
    makedocs(
        sitename="Supposition.jl Documentation",
        format = Documenter.HTML(
            prettyurls = get(ENV, "CI", nothing) == true,
            size_threshold_ignore = ["Examples/stateful.md"]
        ),
        remotes=nothing,
        pages = [
            "Main Page" => "index.md",
            "Introduction to PBT" => "intro.md",
            "Examples" => [
                "Basic Usage" => "Examples/basic.md",
                "Composing Generators" => "Examples/composition.md",
                "Alignment of Documentation" => "Examples/docalignment.md",
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
