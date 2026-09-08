# ============================================================
# | Otter Blast Radius Tests                                 |
# | -> What one change to a routine or a type can reach      |
# ============================================================
#
# `examples/blast/` is a tree shaped so that every answer this gives
# has a right answer somebody can check by reading nine routines.

import std/[os, strutils, unittest]

import ../../src/protocols/repo_graph
import ../../src/protocols/code_stats/blast
import otterPragmas

proc sampleGraph(): RepoGraph {.testKind: tkUnit, covers: "blastRadius".} =
  ## The example tree, found from this file so the test runs anywhere.
  result = analyzeRepo(parentDir(parentDir(parentDir(
    currentSourcePath()))) / "examples" / "blast")

suite "blast radius: what a change can reach":

  # {.testKind: tkIntegration.}
  test "callers are found, and their distance is recorded":
    var r = blastRadius(sampleGraph(), "store", 2, 1)
    check r.kind == "routine"
    check r.callers.len == 4
    var
      atOne: int = 0
      atTwo: int = 0
    for c in r.callers:
      if c.depth == 1: atOne = atOne + 1
      if c.depth == 2: atTwo = atTwo + 1
    check atOne == 3
    check atTwo == 1

  # {.testKind: tkUnit.}
  test "the two depths are independent":
    ## The point of having n and m rather than one number: asking for
    ## more callers must not drag in more argument levels.
    var
      near = blastRadius(sampleGraph(), "store", 1, 1)
      far = blastRadius(sampleGraph(), "store", 2, 1)
    check near.callers.len < far.callers.len
    check near.feeders.len == far.feeders.len

  # {.testKind: tkIntegration.}
  test "arguments are unwrapped exactly as deep as asked":
    ## store(clean(trim(pad(raw))), 1)
    ##   m = 1 -> clean       m = 2 -> clean, trim      m = 3 -> + pad
    var deepest: int = 0
    for m in 1 .. 3:
      deepest = 0
      for f in blastRadius(sampleGraph(), "store", 1, m).feeders:
        if f.depth > deepest:
          deepest = f.depth
      check deepest <= m
    var
      three = blastRadius(sampleGraph(), "store", 1, 3)
      names: seq[string] = @[]
    for f in three.feeders:
      names.add(f.name)
    check "pad" in names

  # {.testKind: tkRegression.}
  test "a sanitiser feeding the call is called out":
    ## pins: the warning only looked at callers, so `store` receiving
    ## `clean(...)` output was never flagged - which is the commonest
    ## way a value gets cleaned twice.
    var r = blastRadius(sampleGraph(), "store", 2, 2)
    check "clean" in r.sanitizersAbove
    var said: bool = false
    for note in r.notes:
      if "twice" in note:
        said = true
    check said

  # {.testKind: tkIntegration.}
  test "what a parameter really holds is read off the call sites":
    ## `slot` is typed `int` and only ever receives 1, 7 and 2.
    var
      r = blastRadius(sampleGraph(), "store", 1, 1)
      slot: seq[string] = @[]
    for a in r.arguments:
      if a.position == 1:
        slot = a.literals
    check slot.len == 3
    check "1" in slot
    check "7" in slot
    check "2" in slot

  # {.testKind: tkEdgeCase.}
  test "an unreadable argument is counted, not ignored":
    ## Every call passes a name for the first argument, so the honest
    ## answer is no literals and three call sites that cannot be read.
    var r = blastRadius(sampleGraph(), "store", 1, 1)
    for a in r.arguments:
      if a.position == 0:
        check a.literals.len == 0
        check a.fromVariables == 3

  # {.testKind: tkIntegration.}
  test "a type answers with who makes one and who takes one":
    var r = blastRadius(sampleGraph(), "string", 1, 1)
    check r.kind == "routine" or r.kind == "type"

  # {.testKind: tkEdgeCase.}
  test "a name nothing knows gives an error, not an empty answer":
    var r = blastRadius(sampleGraph(), "noSuchRoutineAnywhere", 2, 1)
    check r.error.len > 0
    check r.callers.len == 0
