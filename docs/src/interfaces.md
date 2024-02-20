# Interfaces

Supposition.jl provides a few main interfaces to hook into with your code. These
are pretty robust and very minimal.

The interfaces mentioned on this page are intended for user-extension, in the manner described.
Overloading the functions in a different way or assuming more of an interface than is guaranteed
is not supported.

For the abstract-type based interfaces `ExampleDB` and `Possibility`, you can use
the API provided by [RequiredInterfaces.jl](https://github.com/Seelengrab/RequiredInterfaces.jl)
to check for basic compliance, if you want to provide a custom implementation.

## Macros

These macros are the main entryway most people should use, for both entry-level and advanced
usage. [`@check`](@ref) is responsible for interfacing with the internals of Supposition.jl,
orchestrating the generation of examples & reporting back to the testing framework.

[`@composed`](@ref) is the one-stop-shop for composing a new generator from a number of existing ones.

```@docs
Supposition.@check
Supposition.@composed
```

## Type-based hooks

### `Possibility{T}`

```@docs
Supposition.Data.Possibility
```

### `ExampleDB`

```@docs
Supposition.ExampleDB
```
