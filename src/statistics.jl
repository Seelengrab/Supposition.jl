####
# Statistics
###

function Base.show(io::IO, ::MIME"text/plain", s::Stats)
    runmean = round(runtime_mean(s); sigdigits=3)
    runvar  = round(runtime_variance(s); sigdigits=3)
    genmean = round(gentime_mean(s); sigdigits=3)
    genvar  = round(gentime_variance(s); sigdigits=3)
    print(io, styled"""
    {code,underline:$Stats}:

        Attempted choice sequences:   {code:$(attempts(s))}
        Overruns:                     {code:$(overruns(s))}
        Rejections:                   {code:$(rejections(s))}
        Calls (accepted/total):       {code:$(acceptions(s))}/{code:$(invocations(s))}
        Total shrinks:                {code:$(shrinks(s))}
        Property runtime:             {code:$runmean}s mean ({code:$runvar}s variance)
        Input generation time:        {code:$genmean}s mean ({code:$genvar}s variance)
    """)
end


"""
    add_attempt(::Stats) -> Stats

Record an attempts at generating an input for the property under test to the statistics.

Returns a _new_ [`Stats`](@ref) object.
"""
add_attempt(s::Stats)   = merge(s; attempts = s.attempts+1)

"""
    add_invocation(::Stats) -> Stats

Record an invocation of the property under test to the statistics.

Returns a _new_ [`Stats`](@ref) object.
"""
add_invocation(s::Stats)   = merge(s; invocations = s.invocations+1)

"""
    add_validation(::Stats) -> Stats

Record a successful invocation of the property under test to the statistics.
I.e., the property under test returned `true`.

Returns a _new_ [`Stats`](@ref) object.
"""
add_validation(s::Stats)   = merge(s; acceptions = s.acceptions+1)

"""
    add_invalidation(::Stats) -> Stats

Record an invalidation of the property under test to the statistics.
I.e., a counterexample was found.

Returns a _new_ [`Stats`](@ref) object.
"""
add_invalidation(s::Stats) = merge(s; rejections = s.rejections+1)

"""
    add_overrun(::Stats) -> Stats

Record an overrun encountered while trying to add a choice to the statistics.
I.e., we've hit the upper limit of the number of choices we're allowed to make.

Returns a _new_ [`Stats`](@ref) object.
"""
add_overrun(s::Stats)      = merge(s; overruns = s.overruns+1)

"""
    add_shrink(::Stats) -> Stats

Record a shrinking action of a choice sequence to the statistics.

Returns a _new_ [`Stats`](@ref) object.

!!! note "Global statistics"
    This records the _global_ count across the entire shrinking
    process, and not only the number of shrinks taken along a specific path.
"""
add_shrink(s::Stats)       = merge(s; shrinks = s.shrinks+1)

function online_mean(mu, sigma², n, val)
    if isnan(mu)
        delta  = zero(mu)
        new_mean = val
    else
        delta = val - mu
        new_mean = mu + (val-mu)/n
    end
    delta2 = val - new_mean
    new_sigma² = sigma² + delta*delta2
    new_mean, new_sigma²
end

"""
    add_call_duration(::Stats, dur::Float64) -> Stats

Record the duration of one execution of the property under test to the statistics.
This records online statistics of mean & variance.

Returns a _new_ [`Stats`](@ref) object.
"""
function add_call_duration(s::Stats, dur::Float64)
    mean_runtime, squared_dist_runtime = online_mean(runtime_mean(s), s.squared_dist_runtime, invocations(s), dur)
    merge(s; mean_runtime, squared_dist_runtime)
end

"""
    add_gen_duration(::Stats, dur::Float64) -> Stats

Record the duration of generating one input to the statistics.
This records online statistics of mean & variance.

Returns a _new_ [`Stats`](@ref) object.
"""
function add_gen_duration(s::Stats, dur::Float64)
    mean_gentime, squared_dist_gentime = online_mean(gentime_mean(s), s.squared_dist_gentime, attempts(s), dur)
    merge(s; mean_gentime, squared_dist_gentime)
end

"""
    add_total_duration(::Stats, dur::Float64) -> Stats

Record the overall duration of one `@check` to the statistics.

Returns a _new_ [`Stats`](@ref) object.
"""
add_total_duration(s::Stats, dur::Float64) = merge(s; total_time = dur)
