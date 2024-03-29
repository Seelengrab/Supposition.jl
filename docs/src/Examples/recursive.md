# Recursive Generation

In some situations, it is required to generate objects that can nest recursively.
For example, JSON is an often used data exchange format that consists
of various layers of dictionaries (with string keys) and one dimensional arrays,
as well as strings, numbers, booleans an `Nothing`.

In Supposition.jl, we can generate these kinds of recursively nested objects
using the [`Data.Recursive`](@ref) `Possibility`. For this, we need a generator of
a basecase, as well as a function that wraps one generated example
in a new layer by returning a new `Possibility`.

We can construct the `Possibility` that generates the basecase like so:

```@example recjson
using Supposition

strings = Data.Text(Data.AsciiCharacters())
strings = Data.Text(Data.AsciiCharacters(); max_len=10) # hide
bools = Data.Booleans()
none = Data.Just(nothing)
numbers = Data.Floats{Float64}()
basecase = strings | numbers | bools | none
```

which gives us a [`Data.OneOf`](@ref), a `Possibility` that can generate any
one of the objects generated by the given `Possibility`.

For wrapping into new layers, we need a function that wraps our
basecase `Possibility` and gives us a new `Possibility` generating the
wrapped objects. For the JSON example, this means we can wrap an object
either in a `Vector`, or a `Dict`, where the latter has `String` keys.

!!! note "Wrapping order"
    `Recursive` expects a function that takes a `Possibility` for generating
    the children of the wrapper object, which you should pass into a
    generator. The generator for the wrapper can be any arbitrary `Possibility`.

Defining that function like so:

```@example recjson
function jsonwrap(child)
    vecs = Data.Vectors(child)
    dicts = Data.Dicts(strings, child)
    vecs = Data.Vectors(child; max_size=5) # hide
    dicts = Data.Dicts(strings, child; max_size=5) # hide
    vecs | dicts
end
```

allows us to construct the `Possibility` for generating nested JSON-like objects:

```@example recjson
json = Data.Recursive(basecase, jsonwrap; max_layers=3)
example(json)
# a little bit of trickery, to show a nice example # hide
println( # hide
"Dict{String, Union{Nothing, Bool, Float64, Dict{String, Union{Nothing, Bool, Float64, String}}, String, Vector{Union{Nothing, Bool, Float64, String}}}} with 5 entries:" * # hide
"\n  \"!\"                 => -1.58772e111" * # hide
"\n  \"\\e^Y\\x1cq\\bEj8\"    => -4.31286e-135" * # hide
"\n  \"^\"                 => Union{Nothing, Bool, Float64, String}[false]" * # hide
"\n  \"\\x0f \\t;lgC\\e\\x15\" => nothing" * # hide
"\n  \"Y266uYkn6\"         => -5.68895e-145" # hide
) # hide
nothing # hide
```

