# PBT Resources

This page contains a collection of PBT tutorials and other useful resources
for learning PBT techniques. Most, if not all, should be directly translatable to
Supposition.jl in one form or another. If you find a new tutorial or resource
that helped you test your code with Supposition.jl in some manner, please don't
hesitate to open a PR adding the resource here!

 * [The purpose of Hypothesis](https://hypothesis.readthedocs.io/en/latest/manifesto.html) by David R. MacIver
   * > [...], the larger purpose of Hypothesis is to drag the world kicking and screaming into a new and terrifying age of high quality software.
 * [Hypothesis testing with Oracle functions](https://www.hillelwayne.com/post/hypothesis-oracles/) by Hillel Wayne
   * A blogpost about using existing (but slower/partially incorrect) implementations to make sure
     a refactored or new implementation still conforms to all expected contracts of the old implementation.
 * [Solving the Water Jug Problem from Die Hard 3 with TLA+ and Hypothesis](https://nchammas.com/writing/how-not-to-die-hard-with-hypothesis) by Nicholas Chammas
   * A blogpost about helping out John McClane (Bruce Willis) and Zeus Carver (Samuel L. Jackson) ~defuse a bomb~ solve fun children's games.
   * This blogpost has been translated to Supposition.jl! Check it out in [the examples](@ref "Juggling Jugs").
 * [Rule Based Stateful Testing](https://hypothesis.works/articles/rule-based-stateful-testing/) by David R. MacIver
   * A blogpost from the main developer behind Hypothesis, showing how to test stateful systems with Hypothesis.
   * This blogpost has been translated to Supposition.jl! Check it out in [the examples](@ref "Juggling Jugs").
     * Note: Not all features of Hypothesis have been ported to Supposition.jl, in particular the UX for stateful testing
       is very bare bones. The linked example contains a very manual implementation of the features utilized by
       Hypothesis for much the same thing, but should be easily adaptable for all kinds of stateful tests.
 * [Proprty Testing Stateful Code in Rust](https://rtpg.co/2024/02/02/property-testing-with-imperative-rust/) by Raphael Gashignard
   * A blogpost about fuzzing internal datastructures of [nushell](https://www.nushell.sh/) using PBT and the Rust library
     [proptest](https://github.com/proptest-rs/proptest).
 * [Automate Your Way to Better Code: Advanced Property Testing (with Oskar Wickström)](https://youtu.be/wHJZ0icwSkc) by Kris Jenkins from Developer Voices
   * > My Job as a programmer is to be lazy in the smart way - I see *that* many unit tests, and I just want to automate the problem away.
     > Well that's the promise of property testing - write a bit of code that describes the shape of your software, and it will go away
     > and create 10_000 unit tests to see if you're right, if it actually does work that way.
     > [..] we're also going to address my biggest disappointment so far with property testing: which is that it only seems to work in theory.
     > It's great for textbook examples, I'm sold on the principle, but I've struggled to make it work on my more gnarly real world code.
   * This is an absolutely delightful listen! A nice definition of what property based testing is, as well as a lot of discussion
     on how to start out with property based testing and continue with the approach onto more difficult pastures.
     Don't let yourself be intimidated by the length - take your time with this one, it's well worth it!
