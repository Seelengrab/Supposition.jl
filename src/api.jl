using Base: isexpr
using Test: @testset, @test

function kw_to_produce(tc::Symbol, kwargs::Expr)
    res = Expr(:tuple)

    for (name, call) in Iterators.partition(kwargs.args, 2)
        c = esc(call)
        ass = :($name = $Data.produce($c, $tc))
        push!(res.args, ass)
    end

    return res
end

function esc_body(names, body::Expr)
    # TODO: make sure the `names` in `body` are not escaped, but everything else is
    body
end

macro check(e::Expr, rng=nothing)
    isexpr(e, :function, 2) || throw(ArgumentError("Given expression is not a function expression!"))
    head, body = e.args
    isexpr(head, :call, 2) || throw(ArgumentError("Given expression is not a function head expression!"))
    name = first(head.args)
    namestr = string(name)
    kwargs = last(head.args)
    isexpr(kwargs, :kw) || throw(ArgumentError("Given function does not accept any arguments for fuzzing!"))
    tc = gensym()
    ts = gensym()
    gen_input = Symbol(:geninput_, name)
    args = kw_to_produce(tc, kwargs)
    argnames = Expr(:tuple)
    argnames.args = [ e.args[1] for e in args.args ]
    produces = Expr(Symbol("="), argnames, :($gen_input($tc)))
    testrng = isnothing(rng) ? :($Random.default_rng()) : rng

    b = esc_body(argnames, body)

    quote
        @testset $namestr begin
            function $gen_input($tc::TestCase)
                $args
            end
            
            function $name($tc::$TestCase)
                $produces
                res = $b
                return !res
            end

            rng_orig = copy($testrng)
            $ts = $TestState(copy(rng_orig), $name, 10_000)
            $Supposition.run($ts)
            got_res = !isnothing($ts.result)
            got_score = !isnothing($ts.best_scoring)
            if got_res
                res = @something $ts.result $ts.best_scoring
                obj = if got_score
                    last(res)
                else
                    res
                end
                obj = $gen_input($Supposition.for_choices(res, copy(rng_orig)))
                @test obj
            else
                @test true
            end
        end
    end
end
