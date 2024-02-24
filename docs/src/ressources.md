# PBT Ressources

This page contains a collection of PBT tutorials and other useful ressources
for learning PBT techniques. Most, if not all, should be directly translatable to
Supposition.jl in one form or another. If you find a new tutorial or ressource
that helped you test your code with Supposition.jl in some manner, please don't
hesitate to open a PR adding the ressource here!

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
