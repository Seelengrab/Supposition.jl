# API

## Function Index

!!! warning "Stability"
    The entries written on this page are automatically generated and DO NOT represent
    the currently supported API surface. Feel free to use anything you can find here,
    but know that (for now) only symbols that are exported are expected to stick around
    (they too may change, but I don't expect the underlying functionality to vanish entirely).

```@index
```

## Data reference 

### Functions

```@autodocs
Modules = [Data]
Order = [:function]
```

### Generators

```@autodocs
Modules = [Data]
Order = [:type]
Filter = t -> begin
    t != Supposition.Data.Possibility
end
```

## Supposition reference

```@autodocs
Modules = [Supposition]
Order = [:macro, :function, :type]
Filter = t -> begin
    t != Supposition.ExampleDB
end
```
