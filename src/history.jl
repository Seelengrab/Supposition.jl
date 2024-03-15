import Pkg

"""
    UnsetDB

An `ExampleDB` that is only used by the default `CheckConfig`, to mark as
"no config has been set". If this is the database given in a config
to `@check` and no other explicit database has been given,
`@check` will choose the `default_directory_db()` instead.

Cannot be used during testing.
"""
struct UnsetDB <: ExampleDB end

records(::UnsetDB) = ()
record!(::UnsetDB, _, _) = nothing
retrieve(::UnsetDB, _) = nothing

"""
    NoRecordDB <: ExambleDB

An `ExampleDB` that doesn't record anything, and won't retrieve anything.

!!! note "Doing nothing"
    If you're wondering why this exists, I can recommend
    ["If you're just going to sit there doing nothing, at least do nothing correctly"](https://devblogs.microsoft.com/oldnewthing/20240216-00/?p=109409)
    by the ever insightful Raymond Chen!
"""
struct NoRecordDB <: ExampleDB end

records(::NoRecordDB) = ()
record!(::NoRecordDB, _, _) = nothing
retrieve(::NoRecordDB, _) = nothing

"""
    DirectoryDB <: ExampleDB

An `ExampleDB` that records examples as files in a directory.
"""
struct DirectoryDB <: ExampleDB
    basepath::String
end

records(ddb::DirectoryDB) = filter!(!isdir, readdir(ddb.basepath; join=true))

function record!(ddb::DirectoryDB, name, choices)
    !ispath(ddb.basepath) && mkpath(ddb.basepath)
    storage_path = joinpath(ddb.basepath, name)
    serialize(storage_path, choices)
    ddb
end

function retrieve(ddb::DirectoryDB, name)
    storage_path = joinpath(ddb.basepath, name)
    !isfile(storage_path) && return nothing
    return Some(deserialize(storage_path))
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
        return DirectoryDB(db_path)
    end

    # the DB exists, so read it
    records = filter!(isfile, readdir(db_path; join=true))
    return DirectoryDB(db_path)
end

#####
# Mapping a SuppositionReport to a record & storing & retrieving it
#####

function record(sr::SuppositionReport)
    ts = @something sr.final_state
    choices = @something ts.result
    record!(sr.config.db, record_name(sr), choices)
    true
end

retrieve(sr::SuppositionReport) = retrieve(sr.config.db, record_name(sr))

