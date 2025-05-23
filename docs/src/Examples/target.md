# Targeting

As fuzzing targets become larger and the total state space of possible inputs
becomes sparser in the number of possible counterexamples, it can become rarer
to encounter randomized test failures. It can be challenging to design
fuzzing inputs in just the right way to still get good results; Supposition.jl
however has a tool that can make the process of finding inputs that are more
likely to be useful for the property at hand easier.

Consider this example, where we assert that no matter what number we generate,
it won't be equal to some other number we picked at random:

```@example singulartarget
using Supposition, Random, Logging

rand_goal = rand()

@info "Our random goal is:" Goal=rand_goal

# The RNG is fixed for doc-building purposes - you can try to reproduce
# this example with any RNG you'd like!
show(stdout, MIME"text/plain"(), # hide
@check rng=Xoshiro(1) function israndgoal(f=Data.Floats{Float64}())
    f != rand_goal
end
) # hide
nothing # hide
```

The default for the number of attempts `@check` tries to feed to `israndgoal`
is `10_000`; the test still passes, which means Supposition.jl was unable to
find the number we claim can't be generated. We can increase this by an almost arbitrary
amount, without having the test fail:

```@example singulartarget
@check max_examples=1_000_000 rng=Xoshiro(1) israndgoal(Data.Floats{Float64}())
```

Clearly, there needs to be something done so that we can hint to Supposition.jl
what we consider to be "better" inputs, so that Supposition.jl can focus on them.
This functionality is [`target!`](@ref). `target!` takes a number and records
it as the score for the given generated inputs. During the generation phase,
Supposition.jl tracks which example was considered "the best", i.e. which had
the highest score, and subsequently attempts to find further examples that
further increase this score, hopefully finding a maximum. For our example here,
we can simply use the absolute distance from our input to the artificial goal
as a score:

```@example singulartarget
sr = @check rng=Xoshiro(1) function israndgoal(f=Data.Floats{Float64}())
    # negative absolute distance, because we want to _minimize_ the distance
    target!(-abs(rand_goal - f))
    f != rand_goal
end
```

which results in Supposition.jl finding the _sole_ counterexample in (compared to all 2^64
bitpatterns of `Float64`) very few attempts:

```@example singulartarget
Supposition.statistics(sr)
```

In more complex situations where you don't have a very clear goal to minimize or
maximize, `target!` can be very useful as a guiding force, as long as the
metric you're using is good. I don't have a proof for it, but in general,
you'll probably want the metric to be [admissible](https://en.wikipedia.org/wiki/Admissible_heuristic).
