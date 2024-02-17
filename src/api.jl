using Base: isexpr
using Test: Test, @testset, @test
using Logging: @debug

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
    tries = 100_000
    # by chance, the TestCase may be rejected by `gen`
    # so we have to try again and again until it works out
    for i in 1:tries
        tc = for_choices(UInt[])
        tc.max_size = typemax(UInt)
        try
            res = Data.produce(gen, tc)
            return res
        catch e
            e isa TestException && continue
            rethrow()
        end
    end
    error("Tried sampling $tries times, without getting a result. Perhaps you're filtering out too many examples?")
end

"""
    example(gen::Possibility, n::Integer)

Generate `n` examples for the given `Possibility`.

```julia-repl
julia> using Supposition, Supposition.Data

julia> is = Data.Integers(0, 10);

julia> example(is, 10)
10-element Vector{Int64}:
  9
  1
  4
  4
  7
  4
  6
 10
  1
  8
```
"""
function example(gen::Data.Possibility{T}, n::Integer) where {T}
    res = Vector{T}(undef, n)
    res .= example.(Ref(gen))
    res
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

julia> Supposition.@check [options...] function foo(a = Data.Text(Data.Characters(); max_len=10))
          length(a) > 8
       end
```

Supported options, passed as `key=value`:

 * `rng::Random.AbstractRNG`: Pass an RNG to use. Defaults to `Random.Xoshiro(rand(Random.RandomDevice(), UInt))`.
 * `max_examples::Int`: The maximum number of generated examples that are passed to the property.
 * `broken::Bool`: Mark a property that should pass but doesn't as broken, so that failures are not counted.
 * `record::Bool`: Whether the result of the invocation should be recorded with any parent testsets.

The arguments to the given function are expected to be generator strategies. The names they are bound to
are the names the generated object will have in the test.

# Extended help

## Reusing existing properties

If you already have a predicate defined, you can also use the calling syntax in `@check`. Here, the
generator is passed purely positionally to the given function.

```julia-repl
julia> using Supposition, Supposition.Data

julia> isuint8(x) = x isa UInt8

julia> intgen = Data.Integers{UInt8}()

julia> Supposition.@check isuint8(intgen)
```

## Passing a custom RNG

It is possible to optionally give a custom RNG object that will be used for random data generation.
If none is given, `Xoshiro(rand(Random.RandomDevice(), UInt))` is used instead.

```julia-repl
julia> using Supposition, Supposition.Data, Random

# use a custom Xoshiro instance
julia> Supposition.@check rng=Xoshiro(1234) function foo(a = Data.Text(Data.Characters(); max_len=10))
          length(a) > 8
       end
```

!!! warning "Hardware RNG"
    Be aware that you _cannot_ pass a hardware RNG to `@check` directly. If you want to randomize
    based on hardware entropy, seed a copyable RNG like `Xoshiro` from your hardware RNG and pass
    that to `@check` instead. The RNG needs to be copyable for reproducibility.
"""
macro check(args...)
    isempty(args) && throw(ArgumentError("No arguments supplied to `@check`! Please refer to the documentation for usage information."))
    func = last(args)
    kw_args = collect(args[begin:end-1])
    args = similar(kw_args, Any)
    args .= kw_args
    if isexpr(func, :function, 2)
        check_func(func, args)
    elseif isexpr(func, :call)
        check_call(func, args)
    else
        throw(ArgumentError("Given expression is not a function call or definition!"))
    end
end

function check_func(e::Expr, tsargs)
    isexpr(e, :function, 2) || throw(ArgumentError("Given expression is not a function expression!"))
    head, body = e.args
    isexpr(head, :call) || throw(ArgumentError("Given expression is not a function head expression!"))
    name = first(head.args)
    namestr = string(name)
    isone(length(head.args)) && throw(ArgumentError("Given function does not accept any arguments for fuzzing!"))
    kwargs = @view head.args[2:end]
    any(kw -> !isexpr(kw, :kw), kwargs) && throw(ArgumentError("An argument doesn't have a generator set!"))

    tc = gensym()
    gen_input = gensym(Symbol(name, :__geninput))
    run_input = gensym(Symbol(name, :__run))
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

    pushfirst!(tsargs, :(record_name = string($namestr, "(", Base.promote_op($gen_input, $TestCase), ")")))
    final_block = final_check_block(namestr, run_input, gen_input, tsargs)

    esc(quote
        function $gen_input($tc::$TestCase)
            $args
        end

        function $run_input($tc::$TestCase)
            return !$name($gen_input($tc)...)
        end

        $testfunc

        $final_block
    end)
end

function check_call(e::Expr, tsargs)
    isexpr(e, :call) || throw(ArgumentError("Given expression is not a function call!"))
    any(kw -> isexpr(kw, :kw), e.args) && throw(ArgumentError("Can't pass a generator using keyword syntax to `@check` when reusing a property!"))
    name, kwargs... = e.args
    namestr = string(name)

    tc = gensym()
    gen_input = gensym(Symbol(name, :__geninput))
    run_input = gensym(Symbol(name, :__run))

    args = Expr(:tuple)
    for e in kwargs
        push!(args.args, :($Data.produce($e, $tc)))
    end

    pushfirst!(tsargs, :(record_name = string($namestr, "(", Base.promote_op($gen_input, $TestCase), ")")))
    final_block = final_check_block(namestr, run_input, gen_input, tsargs)

    esc(quote
        function $gen_input($tc::$TestCase)
            $args
        end

        function $run_input($tc::$TestCase)
            return !$name($gen_input($tc)...)
        end

        $final_block
    end)
end

function final_check_block(namestr, run_input, gen_input, tsargs)
    ts = gensym()
    sr = gensym()

    return quote
        # need this for backwards compatibility
        $sr = $SuppositionReport
        $Test.@testset $sr $(tsargs...) $namestr begin
            report = $Test.get_testset()
            previous_failure = $retrieve(report.database, report.record_name)
            $ts = $TestState(report.config, $run_input, previous_failure)
            $Supposition.run($ts)
            $Test.record(report, $ts)
            got_res = !isnothing($ts.result)
            got_err = !isnothing($ts.target_err)
            got_score = !isnothing($ts.best_scoring)
            if got_res | got_err | got_score
                res = @something $ts.target_err $ts.best_scoring $ts.result
                choices = if got_err | got_score
                    last(res)
                else
                    res
                end
                obj = $gen_input($Supposition.for_choices(choices, copy($ts.rng)))
                if got_err
                    # This is an unexpected error, report as `Error`
                    exc, trace, len = res
                    err = $Error(obj, exc, trace[begin:len-2])
                    $Test.record(report, err)
                elseif got_res # res
                    # This is an unexpected failure, report as `Fail`
                    fail = $Fail(obj, nothing)
                    $Test.record(report, fail)
                elseif got_score
                    # This means we didn't actually get a result, so report as `Pass`
                    # Also mark this, so we can display this correctly during `finish`
                    score = first(res)
                    pass = $Pass(Some(obj), Some(score))
                    $Test.record(report, pass)
                end
            else
                pass = $Supposition.Pass(nothing, nothing)
                $Test.record(report, pass)
            end
        end
	end
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

julia> text = Data.Text(Data.AsciiCharacters(); max_len=10)

julia> gen = Supposition.@composed function foo(a = text, num=Data.Integers(0, 10))
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
            function $name()
                new{$Base.promote_op($Data.produce, $name, $TestCase)}()
            end
        end

        function $Data.produce(::$name, $tc::$TestCase)
            $structproduce($strategy_let...)
        end

        $structfunc

        $name()
    end)
end

"""
    target!(score::Float64)

Update the currently running testcase to track the given score as its target.

`score` must be `convert`ible to a `Float64`.
"""
function target!(score::Float64)
    # CURRENT_TESTCASE is a ScopedValue that's being managed by the testing framework
    target!(CURRENT_TESTCASE[], score)
end
target!(score) = target!(convert(Float64, score))

"""
    assume!(precondition::Bool)

If this precondition is not met, abort the test and mark the currently running testcase as invalid.
"""
assume!(precondition::Bool) = precondition || reject!()

"""
    reject!()

Reject the current testcase as invalid, meaning the generated example should not be considered as producing a
valid counterexample.
"""
reject!() = reject(CURRENT_TESTCASE[])
