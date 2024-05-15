# Stateful Testing

So far, we've only seem examples of very simple & trivial properties, doing little more than showcasing syntax.
However, what if we're operating on some more complicated datastructure and want to check whether
the operations we can perform on it uphold the invariants we expect? This too can, in a for now basic form,
be done with Supposition.jl.

## Juggling Jugs

Consider this example from the movie Die Hard With A Vengeance:

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

The problem John McClane & Zeus Carver have to solve is the well known 3L & 5L variation on the [water pouring puzzle](https://en.wikipedia.org/wiki/Water_pouring_puzzle). You have two jugs,
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

 * Filling a jug to the brim
   * No partial filling! That's not accurate enough.
 * Emptying a jug
   * No partial emptying! That's not accurate enough.
 * Pouring one jug into the other
   * Any leftover liquid stays in the jug we poured from - don't spill anything!

Defining them as functions returning a new `Jugs`, we get:

```@example jugs
# filling
fill_small(j::Jugs) = Jugs(3, j.large)
fill_large(j::Jugs) = Jugs(j.small, 5)

# emptying
empty_small(j::Jugs) = Jugs(0, j.large)
empty_large(j::Jugs) = Jugs(j.small, 0)

# pouring
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
emptying either jug, and finally pouring one into the other, taking care not to spill anything (i.e., any leftovers stay
in the jug we poured out of).

We can very easily now generate a sequence of operations:

```@example jugs
using Supposition

raw_ops = (fill_small, fill_large, empty_small, empty_large, pour_small_into_large, pour_large_into_small)
gen_ops = Data.Vectors(Data.SampledFrom(raw_ops))
gen_ops = Data.Vectors(Data.SampledFrom(raw_ops); min_size=5, max_size=10) # hide
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
# do a little dance so that this expected failure doesn't kill doc building # hide
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
```

This pattern is very extensible, and a good candidate for the next UX overhaul (getting a reported failure for the target we actually want to find is quite bad UX). Nevertheless, it already works right now!

## Balancing a heap

The previous example showed how we can check these kinds of operations based invariants on an immutable struct.
There is no reason why we can't do the same with a mutable struct (or at least, a struct containing a mutable
object) though, so let's look at another example: ensuring a heap observes its heap property. As a quick reminder,
the heap property for a binary heap is that each child of a node is `<=` than that node, resulting in what's called
a "Max-Heap" (due to the maximum being at the root). Similarly, if the property for children is `>=`, we get a
"Min-Heap". Here, we're going to implement a Min-Heap.

First, we need to define our datastructure:

```@example heap
struct Heap{T}
    data::Vector{T}
end
Heap{T}() where T = Heap{T}(T[])
```

as well as the usual operations (`isempty`, `push!`, `pop!`) on that heap:

 * `isempty`: Whether the heap has elements
 * `push!`: Put an element onto the heap
 * `pop!`: Retrieve the smallest element of the heap (i.e., remove the root)

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
    heap
end

Base.pop!(heap::Heap) = popfirst!(heap.data)
```

In this implementation, we're simply using an array as the backing store for our heap. The first element is the root,
followed by the left subtree, followed by the right subtree.
As implemented, `pop!` will return the correct element if the heap is currently balanced, but because `pop!` doesn't rebalance
the heap after removing the root, `pop!` may leave it in an invalid state. A subsequent `pop!` may then remove an element that is not the smallest
currently stored.

We can very easily test this manually:

```@example heap
using Supposition

intvec = Data.Vectors(Data.Integers{UInt8}())

try # hide
@check function test_pop_in_sorted_order(ls=intvec)
    h = Heap{eltype(ls)}()

    # push all items
    for l in ls
        push!(h, l)
    end

    # pop! all items
    r = eltype(ls)[]
    while !isempty(h)
        push!(r, pop!(h))
    end

    # the pop!ed items should be sorted
    r == sort(ls)
end
catch # hide
end # hide
```

And as expected, the minimal counterexample is `[0x0, 0x1, 0x0]`. We first `pop!` `0x0`, followed by `0x1` while it should be
`0x0` again, and only *then* `0x1`, resulting in `[0x0, 0x0, 0x1]` instead of `[0x0, 0x1, 0x0]`.

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
        broke = false
        for c in children
            if data[index+1] > data[c+1]
                data[index+1], data[c+1] = data[c+1], data[index+1]
                index = c
                broke = true
                break
            end
        end
        !broke && break
    end
    return result
end
```

Me telling you that this is correct though should only be taken as well-intentioned, but not necessarily as true.
There might be more bugs that have sneaked in after all, that aren't caught by our naive "pop in order and check
that it's sorted" test. There could be a nasty bug waiting for us that only happens when various `push!` and `pop!`
are interwoven in just the right way. Using stateful testing techniques and the insight that we can generate
sequences of operations on our `Heap` with Supposition.jl too! We're first going to try with the existing, known
broken `pop!`:

```@example heap
gen_push = map(Data.Integers{UInt}()) do i
    (push!, i)
end
gen_pop = Data.Just((pop!, nothing))
gen_ops = Data.Vectors(Data.OneOf(gen_push, gen_pop); max_size=10_000)
nothing # hide
```

We either `push!` an element, or we `pop!` from the heap. Using `(pop!, nothing)` here will make it
a bit easier to actually define our test. Note how the second element acts as the eventual argument
to `pop!`.

There's also an additional complication - because we don't
have the guarantee anymore that the `Heap` contains elements, we have to guard the use of `pop!`
behind a precondition check. In case the heap is empty, we can just consume the operation and treat it
as a no-op, continuing with the next operation:

```@example heap
# let's dance again, Documenter.jl! # hide
try # hide
@check function test_heap(ops = gen_ops)
    heap = Heap{UInt}()

    for (op, val) in ops
        if op === push!
            # we can always push
            heap = op(heap, val)
        else
            # check our precondition!
            isempty(heap) && continue

            # the popped minimum must always == the minimum
            # of the backing array, so retrieve the minimum
            # through alternative internals
            correct = minimum(heap.data)
            val = op(heap)

            # there's only one invariant this time around
            # and it only needs checking in this branch:
            val != correct && return false
        end
    end

    # by default, we pass the test!
    # this happens if our `ops` is empty or all operations
    # worked successfully
    return true
end
catch # hide
end # hide
```

Once again, we find our familiar example `UInt[0x0, 0x1, 0x0]`, though this time in the form of operations done on the heap:

```julia
ops = Union{Tuple{typeof(pop!), Nothing}, Tuple{typeof(push!), UInt64}}[
    (push!, 0x0000000000000001),
    (push!, 0x0000000000000000),
    (push!, 0x0000000000000000),
    (pop!, nothing),
    (pop!, nothing)
]
```

We push three elements (0x1, 0x0 and 0x0) and when popping two, the second doesn't match the expected minimum anymore!

Now let's try the same property with our (hopefully correct) `fixed_pop!`:

```@example heap
gen_fixed_pop = Data.Just((fixed_pop!, nothing))
gen_fixed_ops = Data.Vectors(Data.OneOf(gen_push, gen_fixed_pop); max_size=10_000)
# Documenter shenanigans require me to repeat this. # hide
function test_heap(ops) # hide
    heap = Heap{UInt}() # hide
 # hide
    for (op, val) in ops # hide
        if op === push! # hide
            # we can always push # hide
            heap = op(heap, val) # hide
        else # hide
            # check our precondition! # hide
            isempty(heap) && continue # hide
 # hide
            # the popped minimum must always == the minimum # hide
            # of the backing array, so retrieve the minimum # hide
            # through alternative internals # hide
            correct = minimum(heap.data) # hide
            val = op(heap) # hide
 # hide
            # there's only one invariant this time around # hide
            # and it only needs checking in this branch: # hide
            val != correct && return false # hide
        end # hide
    end # hide
 # hide
    # by default, we pass the test! # hide
    return true # hide
end # hide

@check test_heap(gen_fixed_ops)
```

Now this is much more thorough testing!
