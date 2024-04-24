# [Introduction](@id pbt_intro)

What follows is a short introduction to what Property Based Testing (PBT) is from my POV. This may not be exhaustive - if you want a more formal
or deeper dive into this topic, I can greatly recommend [this](https://hypothesis.works/articles/what-is-property-based-testing/) article
by one of the authors of Hypothesis, the property based testing framework Supposition.jl is based on. For more formal methods, check out the [blog of Hillel Wayne](https://hillelwayne.com/post/).

If you're fine with the (short) introduction I'm giving, but want some sort of motivation about WHY you should care, here's a quote from him,
itself referencing other people:

> In 2010 Carmen Reinhart and Kenneth Rogoff published [Growth in a Time of Debt](http://scholar.harvard.edu/files/rogoff/files/growth_in_time_debt_aer.pdf). It’s arguably one of the most influential economics papers of the decade, convincing the IMF to push austerity measures in the European debt crisis. It was a very, very big deal.
>
> In 2013 they shared their code with another team, [who quickly found a bug](http://www.nytimes.com/2013/04/19/opinion/krugman-the-excel-depression.html). Once corrected, the results disappeared.
>
> Greece took on austerity because of a software bug. That’s pretty fucked up.

This is just a soundbite, the full article [How Do We Trust Science Code](https://hillelwayne.com/how-do-we-trust-science-code/) has
a number of other great examples for why the problem of correct software is not just something esoteric for software engineers, but
is of practical interest to scientific coders too.

Now that I have your attention, let's get started:

## What is Property Based Testing?

Property Based Testing is the idea of checking the correctness of a function, algorithm or calculation against a number of desired properties that function
should observe. Consider this example of a property, a function that returns a `Bool`:

```julia
function foo(a::Int, b::Int)
    a < 5 && return false
    b < 5 && return false
    return true
end
```

This is also called a [predicate function](https://stackoverflow.com/questions/3230944/what-does-predicate-mean-in-the-context-of-computer-science).
From reading the source code as a user, we can see that

  1) `a` and `b` must be of type `Int`
  2) if either `a` or `b` is smaller than `5`, the function returns `false`, otherwise it returns `true`.

So the property that should hold for this function is that if we supply two `Int` arguments, the function will always tell us whether they
are both at least `5`. We might define this property for testing purposes like so:

```julia
function foo_prop()
    a = rand(Int)
    b = rand(Int)
    if a < 5 || b < 5
        return foo(a,b) == false
    else
        return foo(a,b) == true
    end
end
```

Every time we run `foo_prop`, we generate a random input for `foo` and check whether its output behaves as expected. Written like this, it has
a few major drawbacks:

 1) Being somewhat certain that we cover the function completely quickly becomes infeasible
 2) We have no control over the numbers being generated
 3) We can't reuse the way we generate these numbers; expanding a testsuite like this leads to a lot of boilerplate and repetition

On its own, just `foo_prop` is already property based testing - we take some expected input and check it against the expected output/behavior.
However, on 64-bit systems, `Int` has a value in the interval `[-9223372036854775808, 9223372036854775807]`, which is one of $$2^{64}$$ different
values. Considering that our function takes two of those, our input space has $$2^{2 \times 64}$$ distinct pairs of elements! Looping through all of them
would take much too long. Worse, we may then need to record the result for each of them to prove later that we actually checked it.
With more complex data types, this only grows worse as more different types and combinations of them are involved.

This is where a related approach called fuzzing comes in - instead of checking ALL values and giving a 100% guarantee that it works as expected,
we only check a sampled subset of all possible values and therefore only receive a probabilistic result. However, this comes with the distinct
advantage of being _much, much faster_ than checking all possible values. We trade accuracy for performance (much like we do with floating point
values). If our sampling is good enough & representative of the actual data we'd usually expect, this can be a very good indicator for
correctness on our input. The difficulty comes from the second point above - controlling the values we put in to a satisfying degree,
as well as, once a failure is found, reducing it to something we humans can more easily use to pinpoint the uncovered bug, through a process
called "shrinking". You can find the introductory explanations for how this is done in the context of Supposition.jl in the [Basic Usage](@ref)
section of the examples.

For more information about shrinking, see [What exactly is "shrinking"?](@ref faq_shrinking).

## Julia specific nuances

Consider this (seemingly!) very trivial function:

```julia
function add(a,b)
    a + b
end
```

Obviously, this function does nothing more than forward its arguments to `+`. From reading the source code above, we'd expect this to always
behave the same as addition - and we'd probably be right! In julia though, a few subtleties come into play:

 * We don't know the type of the input arguments
 * We don't know how many different values each argument can take on
 * We don't know whether `+` is implemented on whatever we get in the first place
   * If it is, we don't know its implementation and we don't know whether it's correct/as we expect

So in reality, purely from reading the source code, we know nothing more about `add` other than "passes its argument to `+`". This sort of
genericity is both a blessing and a curse, in that it allows anyone that has `+` defined on two types to call our function, while also making
it devilishly difficult for us as developers to anticipate all possible behaviors that can occur.

With property based testing, we should in theory be able to define a set of properties we'd like to hold on our code, for any object that can be
passed into our `add` function. Users of our code who define a new type should be able to take those properties and check the behavior of
their type & implementation in our function against the expected properties and find out (at least probabilistically) whether they've implemented
the required functions correctly.
