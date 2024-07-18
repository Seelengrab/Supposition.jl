import Random

"""
    windows(array, a, b)

Split `array` into three windows, with split points at `a` and `b`.
The split points belong to the middle window.
"""
function windows(array, a,b)
    head = @view array[begin:a-1]
    middle = @view array[a:b]
    tail = @view array[b+1:end]
    head, middle, tail
end


lerp(x,y,t) = y*t + x*(1-t)
function smootherstep(a, b, t)
    x = clamp((t - a)/(b-a), 0.0, 1.0)
    return x*x*x*(x*(6.0*x - 15.00) + 10.0)
end
