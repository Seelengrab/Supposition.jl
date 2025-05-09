# Userfacing API

Supposition.jl provides a few main interfaces to hook into with your code,
as well as use during general usage of Supposition.jl. These
are pretty robust and very minimal.

The interfaces mentioned on this page are intended for user-extension & usage, in the manner described.
Overloading the functions in a different way or assuming more of an interface than is guaranteed
is not supported.

For the abstract-type based interfaces `ExampleDB` and `Possibility`, you can use
the API provided by [RequiredInterfaces.jl](https://github.com/Seelengrab/RequiredInterfaces.jl)
to check for basic compliance, if you want to provide a custom implementation.

## Macro-based API

These macros are the main entryway most people should use, for both entry-level and advanced
usage. [`@check`](@ref) is responsible for interfacing with the internals of Supposition.jl,
orchestrating the generation of examples & reporting back to the testing framework.

[`@composed`](@ref) is the one-stop-shop for composing a new generator from a number of existing ones.

```@docs
Supposition.@check
Supposition.@composed
Supposition.@event!
```

## `SuppositionReport` API

`@check` returns a [`Supposition.SuppositionReport`](@ref), an opaque object
summarizing the results of that invocation. While the fields of this object
are considered internal & unsupported, there are some functions available for
querying this report. This is useful for various statistics, or retrieving
the exact object that was found as a counterexample. This can be particularly
important when a specific `NaN` bitpattern is a counterexample, or in other
cases where the printing of a value is not sufficient to reconstruct it.

```@docs
Supposition.statistics(::Supposition.SuppositionReport)
Supposition.counterexample(::Supposition.SuppositionReport)
```

## Statistics

These functions are useful for learning more about the behavior of one specific
execution of a testcase, querying various collected statistics of a `SuppositionReport`.

```@docs
Supposition.attempts(::Supposition.Stats)
Supposition.acceptions(::Supposition.Stats)
Supposition.rejections(::Supposition.Stats)
Supposition.invocations(::Supposition.Stats)
Supposition.overruns(::Supposition.Stats)
Supposition.shrinks(::Supposition.Stats)
Supposition.improvements(::Supposition.Stats)
Supposition.runtime_mean(::Supposition.Stats)
Supposition.runtime_variance(::Supposition.Stats)
Supposition.gentime_mean(::Supposition.Stats)
Supposition.gentime_variance(::Supposition.Stats)
Supposition.total_time(::Supposition.Stats)
```

## API for controlling fuzzing

These items are intended for usage while testing, having various effects
on either the shrinking or fuzzing process. They are not intended to be part
of a codebase permanently or remain active while deployed in production.

The trailing exclamation mark serves as a reminder that this will, under
the hood, modify the currently running testcase.

```@docs
Supposition.target!(::Float64)
Supposition.assume!(::Bool)
Supposition.produce!(::Data.Possibility)
Supposition.reject!
Supposition.event!
Supposition.err_less
Supposition.DEFAULT_CONFIG
```

## Available `Possibility`

The `Data` module contains most everyday objects you're going to use when writing property
based tests with Supposition.jl. For example, the basic generators for integers, strings,
floating point values etc. are defined here. Everything listed in this section is considered
supported under semver.

```@index
Modules = [Data]
Order = [:function, :type]
```

### Functions

```@autodocs
Modules = [Data]
Order = [:function]
Filter = t -> begin
    t != Supposition.Data.produce!
end
```

```@docs
Supposition.example
```

### Types

```@autodocs
Modules = [Data]
Order = [:type]
Filter = t -> begin
    t != Supposition.Data.Possibility
end
```

```@docs
Supposition.CheckConfig
```

## Type-based hooks

These are hooks for users to provide custom implementations of certain parts
of Supposition.jl. Follow their contracts precisely if you implement your
own.

### `Possibility{T}`

```@docs
Supposition.Data.Possibility
```

### `ExampleDB`

```@docs
Supposition.ExampleDB
```
