# Documentation Reference

This section contains a complete reference of everything Supposition.jl contains,
on one page. This is not a devdocs section, but a _reference_, for quick lookups
of what something does, without having to hunt for the exact definition in the
source code. A proper devdocs section with a high level introduction will
be added at a later date.

!!! warning "Stability"
    The entries written on this page are automatically generated and DO NOT represent
    the currently supported API surface. Feel free to use anything you can find here,
    but be aware that just because it's listed here, does not mean it's covered under
    semver (though it may be - check [Userfacing API](@ref) if you're unsure).

## Data reference

The `Data` module contains most everyday objects you're going to use when writing property
based tests with Supposition.jl. For example, the basic generators for integers, strings,
floating point values etc. are defined here. Everything listed in this section is considered
supported under semver.

```@index
Modules = [Data]
Order = [:function, :type]
```

### Functions

```@autodocs; canonical=false
Modules = [Data]
Order = [:function]
```

```@autodocs; canonical=false
Modules = [Data]
Order = [:type]
Filter = t -> begin
    t != Supposition.Data.Possibility
end
```

## Supposition reference

```@index
Modules = [Supposition]
Order = [:macro, :function, :type, :constant]
```

```@autodocs; canonical=false
Modules = [Supposition]
Order = [:macro, :function, :type, :constant]
Filter = t -> begin
    t != Supposition.ExampleDB
end
```
