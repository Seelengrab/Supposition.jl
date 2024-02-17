import Pkg

using Mmap: mmap

"""
    NoRecordDB <: ExambleDB

An `ExampleDB` that doesn't record anything, and won't retrieve anything.
"""
struct NoRecordDB <: ExampleDB end

records(::NoRecordDB) = ()
record!(::NoRecordDB, _, _) = nothing
retrieve(::NoRecordDB) = nothing

"""
    DirectoryDB <: ExampleDB

An `ExampleDB` that records examples as files in a directory.
"""
struct DirectoryDB <: ExampleDB
    basepath::String
    records::Vector{String}
end

records(ddb::DirectoryDB) = ddb.records

function record!(ddb::DirectoryDB, name, choices)
    storage_path = joinpath(ddb.basepath, name)
    open(storage_path, "w") do io
        write(io, choices)
    end
    ddb
end

function retrieve(ddb::DirectoryDB, name)
    storage_path = joinpath(ddb.basepath, name)
    !isfile(storage_path) && return nothing
    io = open(storage_path, "r+")
    return Some(mmap(io, Vector{UInt}))
end

#####
# default config for DirectoryDB
#####

function default_directory_db()
    project_dir = dirname(Pkg.project().path)
    
    # Ensure a stable directory
    db_path = if !endswith(project_dir, "test")
        joinpath(project_dir, "test", "SuppositionDB")
    else
        project_dir
    end

    # The DB doesn't yet exist, so create it and return early
    if !ispath(db_path)
        mkpath(db_path)
        open(joinpath(db_path, "README.md"), "w") do io
            write(io, 
                """
                # Example Database

                This directory contains the example database for Supposition.jl. Each file
                represents a previously seen counterexample for one invocation of `@check`.
                The directory is managed entirely by Supposition.jl - any outside modifications
                may be deleted, reverted, changed, modified or undone at a moments notice.

                Feel free to add this directory to your `.gitignore` if you don't need past failures
                tracked or have too many or too big examples stored here.

                If you want to track these somehow/keep them persistent through CI, you can also
                pass a custom `DirectoryDB` with a different directory to `@check`.
                """
            )
        end
        return DirectoryDB(db_path, String[])
    end

    # the DB exists, so read it
    records = filter!(isfile, readdir(db_path; join=true))
    return DirectoryDB(db_path, records)
end

#####
# Mapping a SuppositionReport to a record & storing & retrieving it
#####

function record(sr::SuppositionReport)
    ts = @something sr.final_state
    choices = @something ts.result
    record!(sr.database, sr.record_name * "_" * sr.description, choices)
    true
end

retrieve(sr::SuppositionReport) = retrieve(sr.database, sr.record_name * "_" * sr.description)

