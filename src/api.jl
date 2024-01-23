using Base: isexpr
using Test: @testset, @test

function kw_to_produce(tc::Symbol, kwargs)
    res = Expr(:block)
    rettup = Expr(:tuple)

    for e in kwargs
        name, call = e.args
        escname = esc(name)
        c = esc(call)
        ass = :($escname = $Data.produce($c, $tc))
        push!(res.args, ass)
        push!(rettup.args, :($name = $escname))
    end
    push!(res.args, rettup)

    return res
end

"""
    @check

The main way to declare a property based test. Called like so:

```julia-repl
julia> using Supposition, Supposition.Data

julia> Supposition.@check function foo(a = Data.Text(Data.Characters(); max_len=10))
          length(a) > 8
       end
```

The arguments to the given function are expected to be generator strategies. The names they are bound to
are the names the generated object will have in the test. It is possible to optionally give a custom RNG object
that will be used for random data generation. If none is given, `Random.default_rng()` is used instead.

```julia-repl
julia> using Supposition, Supposition.Data, Random

julia> Supposition.@check function foo(a = Data.Text(Data.Characters(); max_len=10))
          length(a) > 8
       end Xoshiro(1234) # use a custom Xoshiro instance
```
"""
macro check(e::Expr, rng=nothing)
    isexpr(e, :function, 2) || throw(ArgumentError("Given expression is not a function expression!"))
    head, body = e.args
    isexpr(head, :call) || throw(ArgumentError("Given expression is not a function head expression!"))
    name = first(head.args)
    namestr = string(name)
    escname = esc(name)
    isone(length(head.args)) && throw(ArgumentError("Given function does not accept any arguments for fuzzing!"))
    kwargs = @view head.args[2:end]
    any(kw -> !isexpr(kw, :kw), kwargs) && throw(ArgumentError("An argument doesn't have a generator set!"))

    # choose the RNG
    testrng = esc(isnothing(rng) ? :($Random.default_rng()) : rng)

    tc = gensym()
    ts = gensym()
    gen_input = esc(Symbol(name, :__geninput))
    run_input = esc(Symbol(name, :__run))
    args = kw_to_produce(tc, kwargs)
    argnames = Expr(:tuple)
    argnames.args = [ e.args[1] for e in last(args.args).args ]

    # Build the actual testing function
    testfunc = Expr(:function)
    funchead = copy(argnames)
    funchead.head = :call
    pushfirst!(funchead.args, escname)
    push!(testfunc.args, funchead)
    push!(testfunc.args, body)

    quote
        function $gen_input($tc::$TestCase)
            $args
        end

        function $run_input($tc::$TestCase)
            return !$escname($gen_input($tc)...)
        end

        $testfunc

        @testset $namestr begin
            rng_orig = copy($testrng)
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
    end
end
