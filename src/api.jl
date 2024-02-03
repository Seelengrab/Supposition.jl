using Base: isexpr
using Test: @testset, @test

"""
    example(gen::Possibility)

Generate an example for the given `Possibility`.

```julia-repl
julia> using Supposition, Supposition.Data

julia> example(Data.Integers(0, 10))
7
```
"""
function example(gen::Data.Possibility)
    tc = for_choices(UInt[])
    tc.max_size = typemax(UInt)
    Data.produce(gen, tc)
end

function kw_to_produce(tc::Symbol, kwargs)
    res = Expr(:block)
    rettup = Expr(:tuple)

    for e in kwargs
        name, call = e.args
        ass = :($name = $Data.produce($call, $tc))
        push!(res.args, ass)
        push!(rettup.args, :($name = $name))
    end
    push!(res.args, rettup)

    return res
end

"""
    @check

The main way to declare & run a property based test. Called like so:

```julia-repl
julia> using Supposition, Supposition.Data

julia> Supposition.@check function foo(a = Data.Text(Data.Characters(); max_len=10))
          length(a) > 8
       end
```

The arguments to the given function are expected to be generator strategies. The names they are bound to
are the names the generated object will have in the test. It is possible to optionally give a custom RNG object
that will be used for random data generation. If none is given, `Xoshiro(rand(Random.RandomDevice(), UInt))` is used instead.

```julia-repl
julia> using Supposition, Supposition.Data, Random

julia> Supposition.@check function foo(a = Data.Text(Data.Characters(); max_len=10))
          length(a) > 8
       end Xoshiro(1234) # use a custom Xoshiro instance
```

!!! warning "Hardware RNG"
    Be aware that you _cannot_ pass a hardware RNG to `@check` directly. If you want to randomize
    based on hardware entropy, seed a copyable RNG like `Xoshiro` from your hardware RNG and pass
    that to `@check` instead. The RNG needs to be copyable for reproducibility.
"""
macro check(e::Expr, rng=nothing)
    isexpr(e, :function, 2) || throw(ArgumentError("Given expression is not a function expression!"))
    head, body = e.args
    isexpr(head, :call) || throw(ArgumentError("Given expression is not a function head expression!"))
    name = first(head.args)
    namestr = string(name)
    isone(length(head.args)) && throw(ArgumentError("Given function does not accept any arguments for fuzzing!"))
    kwargs = @view head.args[2:end]
    any(kw -> !isexpr(kw, :kw), kwargs) && throw(ArgumentError("An argument doesn't have a generator set!"))

    # choose the RNG
    testrng = isnothing(rng) ? :($Random.Xoshiro(rand($Random.RandomDevice(), UInt))) : rng

    tc = gensym()
    ts = gensym()
    gen_input = Symbol(name, :__geninput)
    run_input = Symbol(name, :__run)
    args = kw_to_produce(tc, kwargs)
    argnames = Expr(:tuple)
    argnames.args = [ e.args[1] for e in last(args.args).args ]

    # Build the actual testing function
    testfunc = Expr(:function)
    funchead = copy(argnames)
    funchead.head = :call
    pushfirst!(funchead.args, name)
    push!(testfunc.args, funchead)
    push!(testfunc.args, body)

    esc(quote
        function $gen_input($tc::$TestCase)
            $args
        end

        function $run_input($tc::$TestCase)
            return !$name($gen_input($tc)...)
        end

        $testfunc

        @testset $namestr begin
            initial_rng = $testrng
            rng_orig = try
                copy(initial_rng)
            catch e
                # we only care about this outermost `copy` call
                (e isa $MethodError && e.f == $copy && only(e.args) == initial_rng) || rethrow()
                rethrow(ArgumentError("Encountered a non-copyable RNG object. If you want to use a hardware RNG, seed a copyable RNG like `Xoshiro` and pass that instead."))
            end
            $ts = $TestState(copy(rng_orig), $run_input, 10_000)
            $Supposition.run($ts)
            got_res = !isnothing($ts.result)
            got_score = !isnothing($ts.best_scoring)
            if got_res
                res = @something $ts.result $ts.best_scoring
                obj = $gen_input($Supposition.for_choices(res, copy(rng_orig)))
                @test obj
            else
                @test true
            end
        end
    end)
end

function kw_to_let(tc, kwargs)
    head = Expr(:block)
    body = Expr(:tuple)

    for e in kwargs
        name, call = e.args
        ass = :($name = $Data.produce($call, $tc))
        push!(head.args, ass)
        push!(body.args, name)
    end
    push!(head.args, body)

    return head
end

"""
    @composed

A way to compose multiple `Possibility` into one, by applying a function.

The return type is inferred as a best-effort!

Used like so:

```julia-repl
julia> using Supposition, Supposition.Data

julia> gen = Supposition.@composed function foo(a = Data.Text(Data.AsciiCharacters(); max_len=10), num=Data.Integers(0, 10))
              lpad(num, 2) * ": " * a
       end

julia> example(gen)
" 8:  giR2YL\\rl"
```
"""
macro composed(e::Expr)
    isexpr(e, :function, 2) || throw(ArgumentError("Given expression is not a function expression!"))
    head, body = e.args
    isexpr(head, :call) || throw(ArgumentError("Given expression is not a function head expression!"))
    name = first(head.args)
    isone(length(head.args)) && throw(ArgumentError("Given function does not accept any arguments for fuzzing!"))
    kwargs = @view head.args[2:end]
    any(kw -> !isexpr(kw, :kw), kwargs) && throw(ArgumentError("An argument doesn't have a generator set!"))

    tc = gensym()
    strategy_let = kw_to_let(tc, kwargs)

    structproduce = Symbol(name, "__produce")

    structfunc = Expr(:function)
    funchead = copy(last(strategy_let.args))
    funchead.head = :call
    pushfirst!(funchead.args, structproduce)
    push!(structfunc.args, funchead)
    push!(structfunc.args, body)

    return esc(quote
        struct $name{T} <: $Data.Possibility{T}
            $name() = new{$Any}()
        end

        function $Data.produce(::$name, $tc::$TestCase)
            $structproduce($strategy_let...)
        end

        $structfunc

        $name()
    end)
end
