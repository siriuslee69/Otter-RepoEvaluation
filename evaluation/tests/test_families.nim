# ============================================================
# | Otter Routine Family Tests                               |
# | -> Many routines that are one routine with a knob        |
# ============================================================
#
# The two example repositories under `examples/families/` are shaped
# after two real refactors, and this file is what keeps Otter able to
# see them. They are read as plain source rather than as git
# repositories, because the statistics CLI wants a `.git` folder and
# nesting repositories inside this one buys nothing.

import std/[os, strutils, unittest]

import ../../src/protocols/repo_graph
import ../../src/protocols/code_stats/shape
import ../../src/protocols/code_stats/families
import runePragmas

proc examplesRoot(): string {.testKind: tkUnit, covers: "familiesOf".} =
  ## Where the two shaped repositories live, found from this file so the
  ## test runs from any working folder.
  result = parentDir(parentDir(parentDir(currentSourcePath()))) /
    "examples" / "families"

proc familiesFor(name: string): FamilyReport {.testKind: tkUnit,
    covers: "familiesOf".} =
  ## name: which example repository to measure.
  var
    root: string = examplesRoot() / name
    g = analyzeRepo(root)
  result = familiesOf(shapeReport(g.functions, root).shapes, g.functions)

proc routineWith(name: string, L: seq[string]): FunctionInfo
    {.testKind: tkUnit, covers: "dispatchPeers".} =
  ## name: what to call it   L: its body, line by line.
  ## Builds one routine record without an object constructor at the
  ## call site, which keeps the declaration checker happy.
  result.name = name
  result.bodyLines = L

suite "families: many routines that are one routine":

  # {.testKind: tkIntegration.}
  test "the profile family is seen, and asked for a parameter":
    ## Shaped after Bifrost's link profiles: one routine per named
    ## situation, identical but for the numbers each fills in.
    var r = familiesFor("bifrost_shape")
    check r.total == 1
    check r.families[0].axis == faValue
    check r.families[0].members.len == 5
    check r.families[0].varyingDims == 0
    check r.families[0].agreement > 0.99
    check "parameter" in r.families[0].remedy
    check r.linesSaved > 0

  # {.testKind: tkIntegration.}
  test "the search family is seen, and asked for a sum of terms":
    ## Shaped after Lineage's two searches before they were rolled into
    ## one line. The advice has to name the zero coefficient, because
    ## that is the mechanism that makes one sum cover every subset.
    var r = familiesFor("lineage_shape")
    check r.total == 1
    check r.families[0].axis == faTerm
    check r.families[0].members.len == 3
    check "coefficient of zero" in r.families[0].remedy
    check "SUM" in r.families[0].remedy

  # {.testKind: tkUnit.}
  test "agreement is one for a routine against itself, and low across kinds":
    check skeletonAgreement("VAAAAR", "VAAAAR") == 1.0
    check skeletonAgreement("VAAAAR", "VAAAAR") > skeletonAgreement(
      "VAAAAR", "VLLBBCCR")
    check skeletonAgreement("", "") == 0.0

  # {.testKind: tkEdgeCase.}
  test "two alike routines are a pair, not a family":
    ## `shape.nim` already reports duplicate pairs. A family starts at
    ## three, unless a dispatch says otherwise.
    check minFamily == 3

  # {.testKind: tkUnit.}
  test "a dispatch names the routines it chooses between":
    ## The author of a case statement has stated that its branches are
    ## alternatives for one job. That is firmer evidence than a shared
    ## folder, so it is read directly.
    var lines: seq[string] = @[
      "  case mode",
      "  of amClassic:",
      "    result = buildClassicHello(s)",
      "  of amShared:",
      "    result = buildSharedHello(s)",
      "  of amMutual:",
      "    result = buildMutualHello(s)"
    ]
    var
      f = routineWith("chooseHello", lines)
      peers = dispatchPeers(f)
    check peers.len == 1
    check peers[0].len == 3
    check "buildClassicHello" in peers[0]
    check "buildMutualHello" in peers[0]

  # {.testKind: tkEdgeCase.}
  test "a body with no fork names nobody":
    var plainLines: seq[string] = @[
      "  var t = 0",
      "  t = add(t, 1)",
      "  result = t"
    ]
    var g = routineWith("plain", plainLines)
    check dispatchPeers(g).len == 0
