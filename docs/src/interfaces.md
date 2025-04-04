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

## API for controlling fuzzing

These functions are intended for usage while testing, having various effects
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
