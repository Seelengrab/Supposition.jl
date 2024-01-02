const Option{T} = Union{Some{T}, Nothing}

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

