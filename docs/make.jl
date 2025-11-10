import Pkg

cd(@__DIR__)
Pkg.activate(@__DIR__)
Pkg.develop(path="..")
Pkg.instantiate()

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
            size_threshold_ignore = ["Examples/stateful.md","Examples/docalignment.md"]
        ),
        repo=Remotes.GitHub("Seelengrab", "Supposition.jl"),
        pages = [
            "Main Page" => "index.md",
            "Introduction to PBT" => "intro.md",
            "Examples" => [
                "Basic Usage" => "Examples/basic.md",
                "Composing Generators" => "Examples/composition.md",
                "Recursive Generation" => "Examples/recursive.md",
                "Alignment of Documentation" => "Examples/docalignment.md",
                "Targeted Operation" => "Examples/target.md",
                "Stateful Testing" => "Examples/stateful.md",
                "Events & Oracle testing" => "Examples/events.md",
            ],
            "PBT Resources" => "resources.md",
            "FAQ" => "faq.md",
            "User-facing API" => "interfaces.md",
            "Benchmarks" => "benchmarks.md",
            "API Reference" => "api.md",
            "Glossary" => "glossary.md"
        ]
    )
end

builddocs()

!isinteractive() && !liveserver && deploydocs(
   repo = "github.com/Seelengrab/Supposition.jl.git",
   devbranch = "main",
   push_preview = true
)
