# Stateful testing

So far, we've only seem examples of very simple & trivial properties, doing little more than showcasing syntax.
However, what if we're operating on some more complicated datastructure and want to check whether
the operations we can perform on it uphold the invariants we expect? This too can, in a for now basic form,
be done with Supposition.jl.

## Juggling Jugs

Consider this example from the classic christmas movie Die Hard:

```@raw html
<p style="display: flex; justify-content: center;">
<iframe
  src="https://www.youtube-nocookie.com/embed/6cAbgAaEOVE"
  title="YouTube video player"
  frameborder="0"
  allow="picture-in-picture" allowfullscreen>
</iframe>
</p>
```

The problem John McClane & Zeus Carver have to solve is the well known 3L & 5L jug problem. You have two jugs,
one that can hold 3L of liquid and one that can hold 5L. The task is to measure out _precisely_ 4L of liquid, using
nothing but those two jugs. Let's model the problem and have Supposition.jl solve it for us:

```@example jugs
struct Jugs
    small::Int
    large::Int
end
Jugs() = Jugs(0,0)
```

We start out with a struct holding our two jugs; one `Int` for the small jug and one `Int` for the large jug.
Next, we need the operations we can perform on these jugs. These are

 * Filling a jug
 * Emptying a jug
 * Pouring one jug into the other

Defining them as functions returning a new `Jugs`, we get:

```@example jugs
fill_small(j::Jugs) = Jugs(3, j.large)
fill_large(j::Jugs) = Jugs(j.small, 5)

empty_small(j::Jugs) = Jugs(0, j.large)
empty_large(j::Jugs) = Jugs(j.small, 0)

function pour_small_into_large(j::Jugs)
    nlarge = min(5, j.large + j.small)
    nsmall = j.small - (nlarge - j.large)
    Jugs(nsmall, nlarge)
end

function pour_large_into_small(j::Jugs)
    nsmall = min(3, j.small + j.large)
    nlarge = j.large - (nsmall - j.small)
    Jugs(nsmall, nlarge)
end
nothing # hide
```

From the top, we have filling either jug (note that we can only fill the small jug up to 3L, and the large up to 5L),
emptying either jugo, and finally pouring one into the other, taking care not to spill anything (i.e., any leftovers stay
in the jug we poured out of).

We can very easily now generate a sequence of operations:

```@example jugs
using Supposition

raw_ops = (fill_small, fill_large, empty_small, empty_large, pour_small_into_large, pour_large_into_small)
gen_ops = Data.Vectors(Data.SampledFrom(raw_ops))
gen_ops = Data.Vectors(Data.SampledFrom(raw_ops); max_size=10) # hide
example(gen_ops)
```

Generating a sequence of operations is simply generating a vector from all possible ones! This is the input to
our property. We declare that for all sequences of operations we can do with a `Jug`, all invariants we expect
must hold true.

Speaking of invariants, we need three of them that must be preserved at all times:

  1) The small jug must ALWAYS have a fill level between 0 and 3 (inclusive).
  2) The large jug must ALWAYS have a fill level between 0 and 5 (inclusive).
  3) The large just must NEVER have a fill level of exactly 4.

The last invariant may look a bit odd, but remember that Supposition.jl is trying to find a _falsifying_ example.
The first two invariants are sanity checks to make sure that our pouring functions are well behaved; the last
invariant is the solution we want to find, by combining the operations above in an arbitrary order. Let's translate these into
functions as well:

```@example jugs
small_jug_invariant(j::Jugs) = 0 <= j.small <= 3
large_jug_invariant(j::Jugs) = 0 <= j.large <= 5
level_invariant(j::Jugs) = j.large != 4
invariants = (small_jug_invariant, large_jug_invariant, level_invariant)
nothing # hide
```

And now, to finally combine all of these:

```@example jugs
gen_ops = Data.Vectors(Data.SampledFrom(raw_ops)) # hide
# do a little dance so that this expected failure doesn't kill doc building
try # hide
@check function solve_die_hard(ops = gen_ops)
    jugs = Jugs()

    for op in ops
        # apply the rule
        jugs = op(jugs)

        # check invariants
        for f in invariants
            f(jugs) || return false
        end
    end

    return true
end
catch # hide
end # hide
nothing # hide
```

This pattern is very extensible, and a good candidate for the next UX overhaul. Nevertheless, it already works right now!

## Balancing a heap

The previous example showed how we can check these kinds of operations based invariants on an immutable struct.
There is no reason why we can't do the same with a mutable struct (or at least, a struct containing a mutable
object) though, so let's look at another example: ensuring a heap observes its heap property. As a quick reminder,
the heap property for a binary heap is that each element in the left child of a node is less than that node,
and each element on the right child of a node is greater (or equal) than that node.

First, we need to define our `Heap`:

```@example heap
struct Heap{T}
    data::Vector{T}
end
Heap{T}() where T = Heap{T}(T[])
```

as well as the usual operations (`isempty`, `push!`, `pop!`) on that heap:

 * `isempty`: Whether the heap has elements
 * `push!`: Put an element onto the heap
 * `pop!`: Retrieve the smallest element of the heap

Written in code, this might look like this:

```@example heap
Base.isempty(heap::Heap) = isempty(heap.data)

function Base.push!(heap::Heap{T}, value::T) where T
    data = heap.data
    push!(data, value)
    index = lastindex(data)
    while index > firstindex(data)
        parent = index >> 1
        if data[parent] > data[index]
            data[parent], data[index] = data[index], data[parent]
            index = parent
        else
            break
        end
    end
end

Base.pop!(heap::Heap) = popfirst!(heap.data)
```

In this implementation, we're simply using an array as the backing store for our heap. The first half of the vector
is always smaller than the element in the middle, which itself is always smaller than all elements in the latter half.
As implemented, `pop!` will return the correct element if the heap is currently balanced, but because it doesn't rebalance
the heap, it may leave it in an invalid state. A subsequent `pop!` may then remove an element that is not the smallest
currently stored.

We can very easily test this manually:

```@example heap
using Supposition

intvec = Data.Vectors(Data.Integers{UInt8}())

try # hide
@check function test_pop_in_sorted_order(ls=intvec)
    h = Heap{eltype(ls)}()
    for l in ls
        push!(h, l)
    end
    r = eltype(ls)[]
    while !isempty(h)
        push!(r, pop!(h))
    end
    r == sort(ls)
end
catch # hide
end # hide
nothing # hide
```

And as expected, a counterexample is `[0x0, 0x2, 0x1]`. We first `pop!` `0x0`, followed by `0x2` while it should be
`0x1`, and only *then* `0x2`.

Replacing this with a (presumably) correct implementation looks like this:

```@example heap
function fixed_pop!(h::Heap)
    isempty(h) && throw(ArgumentError("Heap is empty!"))
    data = h.data
    isone(length(data)) && return popfirst!(data)
    result = first(data)
    data[1] = pop!(data)
    index = 0
    while (index * 2 + 1) < length(data)
        children = [ index*2+1, index*2+2 ]
        children = [ i for i in children if i < length(data) ]
        @assert !isempty(children)
        sort!(children; by=x -> data[x+1])
        isempty(children) && break
        for c in children
            if data[index+1] > data[c+1]
                data[index+1], data[c+1] = data[c+1], data[index+1]
                index = c
                break
            end
        end
    end
    return result
end
```

Me telling you that this is correct though should only be taken as well-intentioned, but not necessarily as true.
There might be more bugs that have sneaked in after all. So let's use stateful testing techniques, similar
to how we tested the `Jugs` example above, to fuzz better!
