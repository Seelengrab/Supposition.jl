# Benchmarks

Since Julia developers can sometimes go crazy for performance and because PropCheck.jl
already had a bunch of optimizations to (or try to, as we'll see) make it go fast, let's compare it to Supposition.jl
to see how the two stack up against each other. Since both packages have been written by the same author,
I think I'm in the clear and won't step on anyones feet :)

All benchmarks were run on the same machine, with the same Julia version:

```julia-repl
julia> versioninfo()
Julia Version 1.12.0-DEV.89
Commit 35cb8a556b (2024-02-27 06:12 UTC)
Platform Info:
  OS: Linux (x86_64-pc-linux-gnu)
  CPU: 24 × AMD Ryzen 9 7900X 12-Core Processor
  WORD_SIZE: 64
  LLVM: libLLVM-16.0.6 (ORCJIT, znver4)
Threads: 23 default, 1 interactive, 11 GC (on 24 virtual cores)
Environment:
  JULIA_PKG_USE_CLI_GIT = true
```

## Generation

### Integers

The task is simple - generating a single `Vector{Int}` with `1_000_000` elements, through the respective
interface of each package.

First, PropCheck.jl:

```julia-repl
julia> using BenchmarkTools

julia> using PropCheck

julia> intgen = PropCheck.vector(PropCheck.iconst(1_000_000), itype(Int));

julia> @benchmark root(PropCheck.generate(intgen))
BenchmarkTools.Trial: 1 sample with 1 evaluation.
 Single result which took 5.780 s (30.71% GC) to evaluate,
 with a memory estimate of 9.17 GiB, over 27285108 allocations.
```

And now, Supposition:

```julia-repl
julia> using BenchmarkTools

julia> using Supposition

julia> intgen = Data.Vectors(Data.Integers{Int}(); min_size=1_000_000, max_size=1_000_000);

julia> @benchmark example($intgen)
BenchmarkTools.Trial: 646 samples with 1 evaluation.
 Range (min … max):  5.556 ms … 24.662 ms  ┊ GC (min … max):  0.00% … 72.10%
 Time  (median):     6.344 ms              ┊ GC (median):     4.18%
 Time  (mean ± σ):   7.734 ms ±  4.033 ms  ┊ GC (mean ± σ):  19.81% ± 19.08%

  █▇▅▄▅▅▅▂
  █████████▆▅▄▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▄▅█▇▆█▆▄▁▁▁▄▅▁▆▆▆▆▆▄▄▆ ▇
  5.56 ms      Histogram: log(frequency) by time     22.7 ms <

 Memory estimate: 25.04 MiB, allocs estimate: 34.
```

GC percentage is about the same, but the used memory and total number of allocations
are VASTLY in favor of Supposition.jl, by about a factor of ~1000 timewise and a factor 300 memorywise.

To put this into perspective, here's a benchmark of just `1_000_000` `Int` randomly generated:

```julia-repl
julia> @benchmark rand(Int, 1_000_000)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  182.570 μs …  11.340 ms  ┊ GC (min … max):  0.00% … 96.50%
 Time  (median):     311.934 μs               ┊ GC (median):     0.00%
 Time  (mean ± σ):   391.653 μs ± 244.852 μs  ┊ GC (mean ± σ):  11.15% ± 15.24%

      ▆██▆▆▆▅▄▃▂▁▁▁▁            ▁▁▂▂▂▁▁                         ▂
  ▄▆▇████████████████████▇▇▇▇▆▅▇█████████▇▇▇█▇▇▆▅▅▄▄▄▄▃▄▅▄▃▄▄▄▅ █
  183 μs        Histogram: log(frequency) by time       1.33 ms <

 Memory estimate: 7.63 MiB, allocs estimate: 3.
```

So Supposition.jl is within 300x of just generating some random numbers, suggesting there's still room for improvement.

### Floats

This is basically the same task as with `Int`, just producing `1_000_000` `Float64` instead.

We'll start with PropCheck.jl again:

```julia-repl
julia> floatgen = PropCheck.vector(PropCheck.iconst(1_000_000), PropCheck.ifloatinfnan(Float64));

julia> @benchmark root(PropCheck.generate(floatgen))
BenchmarkTools.Trial: 2 samples with 1 evaluation.
 Range (min … max):  4.524 s …    4.677 s  ┊ GC (min … max): 24.68% … 25.56%
 Time  (median):     4.600 s               ┊ GC (median):    25.13%
 Time  (mean ± σ):   4.600 s ± 108.561 ms  ┊ GC (mean ± σ):  25.13% ±  0.63%

  █                                                        █
  █▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█ ▁
  4.52 s         Histogram: frequency by time         4.68 s <

 Memory estimate: 4.64 GiB, allocs estimate: 18364056.
```

And again, with Supposition.jl:

```julia-repl
julia> floatgen = Data.Vectors(Data.Floats{Float64}(); min_size=1_000_000, max_size=1_000_000);

julia> @benchmark example($floatgen)
BenchmarkTools.Trial: 736 samples with 1 evaluation.
 Range (min … max):  5.547 ms …  22.696 ms  ┊ GC (min … max): 0.00% … 75.37%
 Time  (median):     6.720 ms               ┊ GC (median):    5.02%
 Time  (mean ± σ):   6.793 ms ± 993.344 μs  ┊ GC (mean ± σ):  6.67% ±  4.56%

                ▂▂▂▆▁▅▃▄▃▂▃█▄▂▂▅▂▇▄ ▆ ▁▃▃▂▁▃▁▁    ▁
  ▃▁▂▂▁▁▃▃▃▂▄▄▇▅██████████████████████████████▇▅▇▅██▇▄▃▃▃▃▂▂▃ ▅
  5.55 ms         Histogram: frequency by time        7.88 ms <

 Memory estimate: 25.04 MiB, allocs estimate: 34.
```

Once again, Supposition.jl beats PropCheck.jl by a factor of 500+ in time and a factor of 100 in memory.

### Strings

Both Supposition.jl and PropCheck.jl can generate the full spectrum of possible
`String`, by going through _all_ assigned unicode codepoints using specialized
generation methods. Let's compare them, starting again with PropCheck.jl:

```julia-repl
# the default uses all valid `Char`
julia> strgen = PropCheck.str(PropCheck.iconst(1_000_000));

julia> @benchmark root(PropCheck.generate(strgen))
BenchmarkTools.Trial: 9 samples with 1 evaluation.
 Range (min … max):  458.354 ms … 631.947 ms  ┊ GC (min … max): 24.95% … 46.11%
 Time  (median):     572.739 ms               ┊ GC (median):    39.24%
 Time  (mean ± σ):   559.611 ms ±  55.519 ms  ┊ GC (mean ± σ):  38.24% ±  6.11%

  █                   █   █ █             ██     █         █  █
  █▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█▁▁▁█▁█▁▁▁▁▁▁▁▁▁▁▁▁▁██▁▁▁▁▁█▁▁▁▁▁▁▁▁▁█▁▁█ ▁
  458 ms           Histogram: frequency by time          632 ms <

 Memory estimate: 1.01 GiB, allocs estimate: 4999798.
```

PropCheck.jl manages to go below 1s runtime for the first time! It still doesn't manage to
use less than 1GiB of memory though. Supposition.jl on the other hand..

```julia-repl
julia> strgen = Data.Text(Data.Characters(); min_len=1_000_000, max_len=1_000_000);

julia> @benchmark example($strgen)
BenchmarkTools.Trial: 163 samples with 1 evaluation.
 Range (min … max):  26.756 ms … 62.461 ms  ┊ GC (min … max): 0.00% … 48.46%
 Time  (median):     28.386 ms              ┊ GC (median):    1.95%
 Time  (mean ± σ):   30.679 ms ±  6.679 ms  ┊ GC (mean ± σ):  8.86% ± 12.41%

  ▄██▅▃
  █████▆█▆▃▁▂▁▁▁▁▁▁▁▁▁▁▁▁▁▂▁▃▁▄▂▃▂▂▁▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▄ ▂
  26.8 ms         Histogram: frequency by time        56.9 ms <

 Memory estimate: 30.22 MiB, allocs estimate: 66.
```

..completely obliterates PropCheck.jl yet again, being only barely slower than generating one million
`Int` or `Float64`. To put this into perspective, bare `randstring` is faster by a factor of only ~3:

```julia-repl
julia> using Random

julia> @benchmark randstring(typemin(Char):"\xf7\xbf\xbf\xbf"[1], 1_000_000)
BenchmarkTools.Trial: 675 samples with 1 evaluation.
 Range (min … max):  6.920 ms …   9.274 ms  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     7.055 ms               ┊ GC (median):    0.00%
 Time  (mean ± σ):   7.221 ms ± 366.592 μs  ┊ GC (mean ± σ):  2.22% ± 3.98%

   ▅█▅▃▁
  ▄█████▇▇▅▃▃▃▃▃▃▂▃▂▁▃▂▂▂▃▃▄▃▃▄▂▃▃▃▃▂▃▃▂▂▂▂▂▂▃▂▂▂▂▂▂▂▁▁▁▂▁▁▂▂ ▃
  6.92 ms         Histogram: frequency by time         8.5 ms <

 Memory estimate: 7.60 MiB, allocs estimate: 4.
```

Considering the amount of state that is being kept track of here, I'd say this is not too shabby.

### Map

Next, function mapping - which is one of the most basic tools to transform an input into something else.
Our mapped function is the humble "make even" function, `x -> 2x`. With PropCheck.jl:

```julia-repl
julia> evengen = PropCheck.vector(PropCheck.iconst(1_000_000), PropCheck.map(x -> 2x, PropCheck.itype(Int)));

julia> @benchmark root(PropCheck.generate(evengen))
BenchmarkTools.Trial: 1 sample with 1 evaluation.
 Single result which took 7.554 s (26.22% GC) to evaluate,
 with a memory estimate of 9.32 GiB, over 32284641 allocations.
```

and Supposition.jl:

```julia-repl
julia> evengen = Data.Vectors(map(x -> 2x, Data.Integers{Int}()); min_size=1_000_000, max_size=1_000_000);

julia> @benchmark example($evengen, 1)
BenchmarkTools.Trial: 724 samples with 1 evaluation.
 Range (min … max):  5.444 ms … 34.544 ms  ┊ GC (min … max):  0.00% … 82.94%
 Time  (median):     5.900 ms              ┊ GC (median):     3.80%
 Time  (mean ± σ):   6.905 ms ±  3.775 ms  ┊ GC (mean ± σ):  16.51% ± 16.42%

  ▅█▅▄▁
  █████▄▅▅▅▄▅▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▄▅▆▅▆▅▄▅▁▅▁▅▅▆▆▅ ▇
  5.44 ms      Histogram: log(frequency) by time     21.7 ms <

 Memory estimate: 25.04 MiB, allocs estimate: 36.
```

And once again, Supposition.jl is victorious on all accounts.

### Filtering

Benchmarking `filter` is a bit special now - Supposition.jl tries to protect you from too-long sampling sessions,
which PropCheck.jl just doesn't even try. As a result, if we naively try to filter for even numbers
with PropCheck, we get a monstrosity:

```julia-repl
julia> evengen = PropCheck.vector(PropCheck.iconst(1_000_000), PropCheck.filter(iseven, PropCheck.itype(Int)));

julia> @benchmark root(PropCheck.generate(evengen))
BenchmarkTools.Trial: 1 sample with 1 evaluation.
 Single result which took 37.428 s (24.58% GC) to evaluate,
 with a memory estimate of 50.67 GiB, over 220777721 allocations.
```

37s and 50GiB memory used is a very tall order (especially for just a single vector!), and should rightly be
kindly asked to leave the venue. Supposition.jl on the other hand stops you in your tracks:

```julia-repl
julia> evengen = Data.Vectors(filter(iseven, Data.Integers{Int}()); min_size=1_000_000, max_size=1_000_000);

julia> @benchmark example($evengen)
ERROR: Tried sampling 100000 times, without getting a result. Perhaps you're filtering out too many examples?
```

and asks you what you're even doing. After all, make `1_000_000` coin flips and you're vanishingly unlikely
to actually get a full vector with `1_000_000` elements that are all even (somewhere on the order of 1e-301030,
to be precise).

So to test this properly, we're going to make sure that the filtering step is not the bottleneck, by
first using our trusty `x -> 2x` again and then "filtering" for only even numbers. This adds
the additional filtering step, but doesn't let it fail, so the probability of getting an even number
doesn't come into play and we can purely focus on the relative overhead to just `map`.

With PropCheck.jl, that leads to:

```julia-repl
julia> evengen = PropCheck.vector(PropCheck.iconst(1_000_000), PropCheck.filter(iseven, PropCheck.map(x -> 2x, PropCheck.itype(Int))));

julia> @benchmark root(PropCheck.generate(evengen))
BenchmarkTools.Trial: 1 sample with 1 evaluation.
 Single result which took 8.756 s (21.85% GC) to evaluate,
 with a memory estimate of 9.63 GiB, over 45284301 allocations.
```

Almost 9s - what a monster, and that's just for a single example! As for Supposition.jl..

```julia-repl
julia> evengen = Data.Vectors(filter(iseven, map(x -> 2x, Data.Integers{Int}())); min_size=1_000_000, max_size=1_000_000);

julia> @benchmark example($evengen)
BenchmarkTools.Trial: 712 samples with 1 evaluation.
 Range (min … max):  5.594 ms … 29.914 ms  ┊ GC (min … max): 5.10% … 68.75%
 Time  (median):     6.672 ms              ┊ GC (median):    4.67%
 Time  (mean ± σ):   7.019 ms ±  2.362 ms  ┊ GC (mean ± σ):  9.82% ±  9.84%

   ▃█▄▅▅▃
  ███████▅▃▂▂▂▂▁▁▁▁▁▁▁▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▂▁▁▁▂▁▂▂▂▂ ▃
  5.59 ms        Histogram: frequency by time        21.2 ms <

 Memory estimate: 25.04 MiB, allocs estimate: 34.
```

Another factor 1000 timewise, and factor 200 memory wise!

## Shrinking

Generating values is only half the effort though; what about shrinking values to find a
counterexample?

We're again going to use vectors of things as inputs, though we're going to use
a slight modification. Shrinking is already pretty complicated, so we're going to
look at much shorter inputs (only 1000 elements long), as well as hold their size
constant. This way, only the elements of each collection will shrink, and neither
framework can get "lucky" by only having to shrink short collections.

In order to prevent clobbering the output with unnecessary text, both PropCheck.jl
and Supposition.jl are silenced through `redirect_*` and/or any switches they
may provide themselves. This way, the resulting measurement should mostly be related
to the shrinking itself, rather than any printing badness creeping in.

### Integers

Without further ado, here's PropCheck.jl:

```julia-repl
julia> intgen = PropCheck.vector(PropCheck.iconst(1000), itype(Int));

julia> @time check(isempty, intgen; show_initial=false)
[ Info: Found counterexample for 'isempty', beginning shrinking...
Internal error: during type inference of
iterate(Base.Iterators.ProductIterator{Tuple{Base.Generator{Array{Int64, 1}, Base.Fix1{typeof(PropCheck.unfold), Base.ComposedFunction{Type{PropCheck.Shuffle{T} where T}, typeof(PropCheck.shrink)}}}, Vararg{Array{PropCheck.Tree{Int64}, 1}, 999}}})
Encountered stack overflow.
This might be caused by recursion over very long tuples or argument lists.
```

You'll notice that I'm using `@time` here instead of `@benchmark`. The reason
for this is pragmatic - I don't want to wait all day on PropCheck.jl. In this
case though, the worry was completely unfounded, as the compiler can't handle the
huge amount of nested functions this ends up generating. This result is, unfortunately,
consistent for the following experiments. As such, I'll only show Supposition.jl.

Supposition.jl not only delivers a result, but does so in record time:

```julia-repl
julia> intgen = Data.Vectors(Data.Integers{Int}(); min_size=1000, max_size=1000);

julia> @time @check db=false isempty(intgen)
  0.429625 seconds (567.42 k allocations: 657.697 MiB, 8.21% gc time, 1.27% compilation time: 5% of which was recompilation)
Found counterexample
  Context: isempty

  Arguments:
      arg_1::Vector{Int64} = [-9223372036854775808, -9223372036854775808, ...
```

### Floats

Supposition.jl:

```julia-repl
julia> floatgen = Data.Vectors(Data.Floats{Float64}(); min_size=1000, max_size=1000);

julia> @time @check db=false isempty(floatgen)
  0.442064 seconds (567.42 k allocations: 657.697 MiB, 7.51% gc time, 1.25% compilation time: 5% of which was recompilation)
Found counterexample
  Context: isempty

  Arguments:
      arg_1::Vector{Float64} = [0.0, 0.0, 0.0, 0.0, ...
```

### Strings

Supposition.jl:

```julia-repl
julia> strgen = Data.Text(Data.Characters(); min_len=1000, max_len=1000);

julia> @time @check db=false isempty(strgen)
  0.687378 seconds (647.30 k allocations: 596.830 MiB, 4.61% gc time, 7.56% compilation time: 8% of which was recompilation)
Found counterexample
  Context: isempty

  Arguments:
      arg_1::String = "\0\0\0\0\0\0\0\0\0...
```

### Map

Supposition.jl:

```julia-repl
julia> mapgen = Data.Vectors(map(x -> 2x, Data.Integers{Int}()); min_size=1000, max_size=1000);

julia> @time @check db=false isempty(mapgen)
  0.427833 seconds (587.02 k allocations: 658.673 MiB, 7.52% gc time, 3.96% compilation time: 2% of which was recompilation)
Found counterexample
  Context: isempty

  Arguments:
      arg_1::Vector{Int64} = [0, 0, 0, 0, ...
```

### Filter

Supposition.jl:

```julia-repl
julia> oddgen = Data.Vectors(filter(isodd, map(x -> 2x+1, Data.Integers{Int}())); min_size=1000, max_size=1000);

julia> @time @check db=false isempty(oddgen)
  0.437623 seconds (591.93 k allocations: 658.920 MiB, 7.50% gc time, 4.13% compilation time: 2% of which was recompilation)
Found counterexample
  Context: isempty

  Arguments:
      arg_1::Vector{Int64} = [1, 1, 1, 1, 1, ...
```

## Conclusion

If you've read down to here, I don't think I even have to write it out - Supposition.jl is _fast_!
I feel pretty confident saying that it's unlikely to be the bottleneck of a testsuite. All of that
without even explicitly looking for places to optimize the package yet. Of course, this doesn't even touch cranking up the
number of samples Supposition.jl tries, or any form of memoization on the property
you could quite easily add. So there is potential for going faster in the future.

Go and incorporate fuzzing into your testsuite ;)
