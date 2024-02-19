#!/usr/bin/env julia

# Root of the repository
const repo_root = dirname(@__DIR__)

# Make sure docs environment is active and instantiated
import Pkg
Pkg.activate(expanduser("~/.julia/environments/liveserver"))
Pkg.instantiate()

# Run LiveServer.servedocs(...)
import LiveServer

LiveServer.serve(;
    dir = joinpath(repo_root, "docs", "build")
)
