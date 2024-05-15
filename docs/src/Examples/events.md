# Events & Oracle testing

One of the most useful applications of Supposition.jl is to assist developers when porting code from another language
to Julia, while trying to optimize that same code a bit. In these cases, it can be extremely useful to compare
the output of the port with the output of the original implementation (which is usually called a [test oracle](https://en.wikipedia.org/wiki/Test_oracle)).

A typical fuzzing test making use of an oracle looks like this:

```julia
@check function checkOracle(input=...)
    new_res = optimized_func(input)
    old_res = old_func(input)
    new_res == old_res
end
```

which generates some valid input and simply compares whether the new implementation produces the same output as the old implementation.

In order not to get bogged down in the abstract, let's look at a concrete example of how this can be used in practice.
The following example is inspired by the work `@tecosaur` has recently done in StyledStrings.jl, huge shoutout
for giving permission to use it as an example!

## Porting an example

The task is seemingly simple - map an `NTuple{3, UInt8}` representing an RGB color to an 8-bit colour space,
via some imperfect mapping.

The original function we're trying to port here is the following, from [tmux](https://github.com/tmux/tmux/blob/b79e28b2c30e7ef9b1f7ec6233eeb70a1a177231/colour.c):

```c
/*
 * Copyright (c) 2008 Nicholas Marriott <nicholas.marriott@gmail.com>
 * Copyright (c) 2016 Avi Halachmi <avihpit@yahoo.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF MIND, USE, DATA OR PROFITS, WHETHER
 * IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
 * OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#include <sys/types.h>

static int
colour_dist_sq(int R, int G, int B, int r, int g, int b)
{
	return ((R - r) * (R - r) + (G - g) * (G - g) + (B - b) * (B - b));
}

static int
colour_to_6cube(int v)
{
	if (v < 48)
		return (0);
	if (v < 114)
		return (1);
	return ((v - 35) / 40);
}

int
colour_find_rgb(u_char r, u_char g, u_char b)
{
	static const int	q2c[6] = { 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };
	int			qr, qg, qb, cr, cg, cb, d, idx;
	int			grey_avg, grey_idx, grey;

	/* Map RGB to 6x6x6 cube. */
	qr = colour_to_6cube(r); cr = q2c[qr];
	qg = colour_to_6cube(g); cg = q2c[qg];
	qb = colour_to_6cube(b); cb = q2c[qb];

	/* If we have hit the colour exactly, return early. */
	if (cr == r && cg == g && cb == b)
		return (16 + (36 * qr) + (6 * qg) + qb);

	/* Work out the closest grey (average of RGB). */
	grey_avg = (r + g + b) / 3;
	if (grey_avg > 238)
		grey_idx = 23;
	else
		grey_idx = (grey_avg - 3) / 10;
	grey = 8 + (10 * grey_idx);

	/* Is grey or 6x6x6 colour closest? */
	d = colour_dist_sq(cr, cg, cb, r, g, b);
	if (colour_dist_sq(grey, grey, grey, r, g, b) < d)
		idx = 232 + grey_idx;
	else
		idx = 16 + (36 * qr) + (6 * qg) + qb;
	return idx;
}
```

!!! note "Modifications"
    I've modified the code slightly, since we don't really care for the flags tmux is storing in the upper bits of the result.
    The transform would be simple enough to undo when fuzzing/using this as an oracle, but would mostly just distract from
    the core of what I'm trying to show here.

That is quite a handful of code! There's lots of magic numbers, two basically-one-liner helper functions and very specific input types,
the behavior of which must all be taken into account.

One attempt at a port to Julia might look like this (courtesy of `@tecosaur`):

```@example tmux_oracle
function termcolor8bit(r::UInt8, g::UInt8, b::UInt8)
    # Magic numbers? Lots.
    cdistsq(r1, g1, b1) = (r1 - r)^2 + (g1 - g)^2 + (b1 - b)^2
    to6cube(value) = (value - 35) ÷ 40
    from6cube(r6, g6, b6) = 16 + 6^2 * r6 + 6^1 * g6 + 6^0 * b6
    sixcube = (0, 95:40:255...)
    r6cube, g6cube, b6cube = to6cube(r), to6cube(g), to6cube(b)
    rnear, gnear, bnear = sixcube[r6cube+1], sixcube[g6cube+1], sixcube[b6cube+1]
    colorcode = if r == rnear && g == gnear && b == bnear
        from6cube(r6cube, g6cube, b6cube)
    else
        grey_avg = Int(r + g + b) ÷ 3
        grey_index = if grey_avg > 238 23 else (grey_avg - 3) ÷ 10 end
        grey = 8 + 10 * grey_index
        if cdistsq(grey, grey, grey) <= cdistsq(rnear, gnear, bnear)
            16 + 6^3 + grey_index
        else
            from6cube(r6cube, g6cube, b6cube)
        end
    end
    UInt8(colorcode)
end
```

The basic structure is the same, albeit formatted a bit differently and with inner helper functions instead of outer ones.
There are also some additional subtleties, such as the `+1` that are necessary when indexing into `sixcube` and the explicit call
to construct an `Int` for the average.

So without further ado, let's compare the two implementations! We can compile the C code with `gcc -shared colors.c -o colors.o`
and wrap the resulting shared object from Julia like so:

```@example tmux_oracle
# `colors.o` is stored in a subdirectory relative to this file!
so_path = joinpath(@__DIR__, "tmux_colors", "colors.o")
tmux_8bit_oracle(r::UInt8, g::UInt8, b::UInt8) = @ccall so_path.colour_find_rgb(r::UInt8, g::UInt8, b::UInt8)::UInt8
```

Great, this now allows us to call the oracle function and compare to our ported implementation:

```@repl tmux_oracle
tmux_8bit_oracle(0x4, 0x2, 0x3)
termcolor8bit(0x4, 0x2, 0x3)
```

And at least for this initial example, the 8-bit colorcodes we get out are the same.

But are they the same for all colors? You're reading the docs of Supposition.jl, so let's `@check` that out,
following the pattern for oracle tests we saw earlier:

```@example tmux_oracle
using Supposition
uint8gen = Data.Integers{UInt8}()
@check function oracle_8bit(r=uint8gen,g=uint8gen,b=uint8gen)
    jl = termcolor8bit(r,g,b)
    tmux = tmux_8bit_oracle(r,g,b)
    jl == tmux
end
```

and indeed, we find a counterexample where our port doesn't match the original code for some reason.
It would be really interesting to see what exactly these two functions put out, so that it's easier to
reconstruct where the port has gone wrong (or perhaps even the oracle!).
Now, while we *could* go in and add `@info` or manually call `termcolor8bit` and `tmux_8bit_oracl` with the minimized input,
neither of those is really attractive, for multiple reasons:

 * `@info` will output logs for _every_ invocation of our property, which is potentially quite a lot. That's a lot of
   text to scroll back through, both locally and in CI. In the worst case, we might even hit the scrollback limit
   of our terminal, or fill the disk on a resource-limited CI.
 * Calling the functions manually can quickly get cumbersome, since you have to copy the output of `@check`, make sure
   you format it correctly to call the various functions etc. The interfaces between the two functionalities may be
   entirely different too in a more complex example than this one, adding more complexity that a developer has to
   keep in mind.

No, "manual" checking & reading logs is certainly not in the spirit of Supposition.jl! Indeed, there's a feature we
can make use of here that gives us exactly the information we wanted to have in the first place - [`event!`](@ref).
We simply insert calls to it into our property, and it records any events we consider to be interesting enough to
record. We can also optionally give these events a label, though that's only used for display purposes:

```@example tmux_oracle
@check function oracle_8bit(r=uint8gen,g=uint8gen,b=uint8gen)
    jl = termcolor8bit(r,g,b)
    event!("Port", jl)
    tmux = tmux_8bit_oracle(r,g,b)
    event!("Oracle", tmux)
    jl == tmux
end
```

The first argument in the 2-arg form of `event!` is any `AbstractString`, so even the (upcoming with Julia 1.11) `AnnotatedString`s
from the `styled""` macro are an option, for fancy labelling. The recorded object can be arbitrary, but be aware that it will be kept
alive for the entire duration of the testsuite, so it's better to record small objects. Only the events associated with the "most important"
test case encountered during fuzzing will be kept alive; if a better one comes around, the existing events are deleted.

## When to use this

Events are a great way to diagnose & trace how a minimal input affects deeper parts of your code, in particular when you have a failing minimal example
that you can't quite seem to get a handle on when debugging. In those cases, you can add `event!` calls into your code base and check the resulting
trace for clues what might be going wrong.
