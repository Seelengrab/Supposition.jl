# Benchmarks

Since Julia developers can sometimes go crazy for performance and because PropCheck.jl
already had a bunch of optimizations to (or try to, as we'll see) make it go fast, let's compare it to Supposition.jl
to see how the two stack up against each other. Since both packages have been written by the same author,
I think I'm in the clear and won't step on anyones feet :)

All benchmarks were run on the same machine, with the same Julia version:

```julia-repl
julia> versioninfo()
Julia Version 1.11.0-DEV.1610
Commit aecd8fd379 (2024-02-16 02:40 UTC)
Platform Info:
  OS: Linux (x86_64-pc-linux-gnu)
  CPU: 24 × AMD Ryzen 9 7900X 12-Core Processor
  WORD_SIZE: 64
  LLVM: libLLVM-16.0.6 (ORCJIT, znver4)
Threads: 23 default, 1 interactive, 11 GC (on 24 virtual cores)
Environment:
  JULIA_PKG_USE_CLI_GIT = true
```

## Integers

The task is simple - generating a single `Vector{Int}` with `1_000_000` elements, through the respective
interface of each package.

First, PropCheck.jl:

```julia-repl
julia> using BenchmarkTools

julia> using PropCheck

julia> intgen = PropCheck.vector(PropCheck.iconst(1_000_000), itype(Int));

julia> @benchmark root(PropCheck.generate(intgen))
BenchmarkTools.Trial: 1 sample with 1 evaluation.
 Single result which took 6.826 s (31.94% GC) to evaluate,
 with a memory estimate of 9.17 GiB, over 27284112 allocations.
```

And now, Supposition:

```julia-repl
julia> using BenchmarkTools

julia> using Supposition

julia> intgen = Data.Vectors(Data.Integers{Int}(); min_size=1_000_000, max_size=1_000_000);

julia> @benchmark example($intgen)
BenchmarkTools.Trial: 373 samples with 1 evaluation.
 Range (min … max):   7.840 ms … 46.349 ms  ┊ GC (min … max):  0.00% … 76.51%
 Time  (median):     10.796 ms              ┊ GC (median):     7.90%
 Time  (mean ± σ):   13.392 ms ±  6.737 ms  ┊ GC (mean ± σ):  25.16% ± 20.21%

    ▃▅█▅▅▅▃
  ▃▇███████▇██▆▄▂▃▃▁▁▁▁▁▂▁▁▁▂▁▁▂▁▁▁▁▁▁▁▂▃▂▃▂▃▄▂▄▃▃▃▄▄▃▃▂▃▂▂▂▃ ▃
  7.84 ms         Histogram: frequency by time          32 ms <

 Memory estimate: 52.94 MiB, allocs estimate: 52.
```

GC percentage is about the same, but the used memory and total number of allocations
are VASTLY in favor of Supposition.jl, by about a factor of 1000 timewise and a factor 200 memorywise.

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

## Floats

This is basically the same task as with `Int`, just producing `1_000_000` `Float64` instead.

We'll start with PropCheck.jl again:

```julia-repl
julia> floatgen = PropCheck.vector(PropCheck.iconst(1_000_000), PropCheck.ifloatinfnan(Float64));

julia> @benchmark root(PropCheck.generate(floatgen))
BenchmarkTools.Trial: 2 samples with 1 evaluation.
 Range (min … max):  4.881 s …   4.896 s  ┊ GC (min … max): 27.50% … 24.34%
 Time  (median):     4.889 s              ┊ GC (median):    25.92%
 Time  (mean ± σ):   4.889 s ± 10.866 ms  ┊ GC (mean ± σ):  25.92% ±  2.24%

  █                                                       █
  █▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█ ▁
  4.88 s         Histogram: frequency by time         4.9 s <

 Memory estimate: 4.58 GiB, allocs estimate: 16363584.
```

And again, with Supposition.jl:

```julia-repl
julia> floatgen = Data.Vectors(Data.Floats{Float64}(); min_size=1_000_000, max_size=1_000_000);

julia> @benchmark example($floatgen)
BenchmarkTools.Trial: 379 samples with 1 evaluation.
 Range (min … max):   8.112 ms … 49.929 ms  ┊ GC (min … max):  0.00% … 70.59%
 Time  (median):     10.721 ms              ┊ GC (median):     8.58%
 Time  (mean ± σ):   13.176 ms ±  6.559 ms  ┊ GC (mean ± σ):  24.73% ± 19.99%

   ▂▂▂█▇▆█▄
  ▆████████▇▇▆▄▃▁▂▁▂▁▁▁▁▁▁▁▁▂▁▁▁▁▁▁▃▁▁▁▁▁▃▁▁▂▁▃▃▃▃▄▃▄▄▃▅▃▂▂▁▃ ▃
  8.11 ms         Histogram: frequency by time        30.8 ms <

 Memory estimate: 52.94 MiB, allocs estimate: 52.
```

Once again, Supposition.jl beats PropCheck.jl by a factor of 500 in time and a factor of 100 in memory.

## Strings

Both Supposition.jl and PropCheck.jl can generate the full spectrum of possible
`String`, by going through _all_ assigned unicode codepoints using specialized
generation methods. Let's compare them, starting again with PropCheck.jl:

```julia-repl
# the default uses all valid `Char`
julia> strgen = PropCheck.str(PropCheck.iconst(1_000_000));

julia> @benchmark root(PropCheck.generate(strgen))
BenchmarkTools.Trial: 8 samples with 1 evaluation.
 Range (min … max):  562.946 ms … 818.003 ms  ┊ GC (min … max): 29.31% … 53.26%
 Time  (median):     662.959 ms               ┊ GC (median):    42.11%
 Time  (mean ± σ):   670.489 ms ±  78.934 ms  ┊ GC (mean ± σ):  42.58% ±  7.18%

  █          █ █    █          █    █ █                       █
  █▁▁▁▁▁▁▁▁▁▁█▁█▁▁▁▁█▁▁▁▁▁▁▁▁▁▁█▁▁▁▁█▁█▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█ ▁
  563 ms           Histogram: frequency by time          818 ms <

 Memory estimate: 1.01 GiB, allocs estimate: 4999791.
```

PropCheck.jl manages to go below 1s runtime for the first time! It still doesn't manage to
use less than 1GiB of memory though. Supposition.jl on the other hand..

```julia-repl
julia> strgen = Data.Text(Data.Characters(); min_len=1_000_000, max_len=1_000_000);

julia> @benchmark example($strgen)
BenchmarkTools.Trial: 156 samples with 1 evaluation.
 Range (min … max):  29.273 ms … 51.403 ms  ┊ GC (min … max): 0.00% … 40.30%
 Time  (median):     31.196 ms              ┊ GC (median):    2.21%
 Time  (mean ± σ):   32.035 ms ±  3.192 ms  ┊ GC (mean ± σ):  2.34% ±  3.45%

     ▁▁▅▆▂█▆▃▂
  ▄▆▅█████████▆▇▆▃▄▄▁▁▁▁▁▁▁▁▁▃▁▁▃▁▁▄▁▁▁▁▁▁▁▁▁▁▁▁▁▃▁▄▄▁▁▁▃▁▁▃▃ ▃
  29.3 ms         Histogram: frequency by time        42.5 ms <

 Memory estimate: 53.22 MiB, allocs estimate: 84.
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

## Map

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

julia> @benchmark example($evengen)
BenchmarkTools.Trial: 491 samples with 1 evaluation.
 Range (min … max):   7.926 ms … 24.521 ms  ┊ GC (min … max): 0.00% … 3.01%
 Time  (median):     10.146 ms              ┊ GC (median):    7.19%
 Time  (mean ± σ):   10.176 ms ±  1.696 ms  ┊ GC (mean ± σ):  6.75% ± 5.07%

    ▁ ▃▁     ▃██▇▇▁▂
  ▃▅█▆██▆▆▇▅▇████████▅▃▅▃▂▁▁▁▃▂▁▂▁▁▁▁▁▁▁▁▁▂▁▁▁▁▁▂▂▁▁▁▁▁▁▁▁▃▂▂ ▃
  7.93 ms         Histogram: frequency by time        18.1 ms <

 Memory estimate: 52.94 MiB, allocs estimate: 52.
```

And once again, Supposition.jl is victorious on all accounts.

## Filtering

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
 Single result which took 9.294 s (25.00% GC) to evaluate,
 with a memory estimate of 9.64 GiB, over 45284893 allocations.
```

Almost 10s - what a monster, and that's just for a single example! As for Supposition.jl..

```julia-repl
julia> evengen = Data.Vectors(filter(iseven, map(x -> 2x, Data.Integers{Int}())); min_size=1_000_000, max_size=1_000_000);

julia> @benchmark example($evengen)
BenchmarkTools.Trial: 488 samples with 1 evaluation.
 Range (min … max):   7.932 ms … 41.305 ms  ┊ GC (min … max): 0.00% … 14.49%
 Time  (median):     10.062 ms              ┊ GC (median):    7.04%
 Time  (mean ± σ):   10.244 ms ±  2.431 ms  ┊ GC (mean ± σ):  6.91% ±  5.33%

    ▁     ▃█▅▃
  ▄▅███▆▆▆█████▇▇▅▂▃▃▁▂▂▁▁▁▂▁▁▁▂▂▁▁▁▁▁▁▁▁▂▁▁▁▂▂▁▁▁▂▁▁▁▁▂▁▁▁▂▂ ▃
  7.93 ms         Histogram: frequency by time        21.1 ms <

 Memory estimate: 52.94 MiB, allocs estimate: 52.
```

Another factor 1000 timewise, and factor 200 memory wise!

## Conclusion

If you've read down to here, I think I don't even have to write it out - Supposition.jl is _fast_!
I feel pretty confident saying that it's unlikely to be the bottleneck of a testsuite. All of that
without even explicitly looking for places to optimize the package yet.

So go and incorporate fuzzing into your testsuite ;)
