# ============================================================
# | Otter Multi-Check Tests                                  |
# | -> Several questions, one reading, same answers          |
# ============================================================
#
# The one thing that must never differ is the answer. Running the
# checks together, or one after another, is a choice about heat and
# cores, and it may not change a single line of what comes back.

import std/[os, strutils, unittest]

import ../../src/protocols/code_stats/checks
import ../../meta/metaPragmas

proc exampleRoot(name: string): string {.testKind: tkUnit,
    covers: "runChecks".} =
  ## name: which example tree.
  result = parentDir(parentDir(parentDir(currentSourcePath()))) /
    "examples" / name

suite "checks: several questions, one reading of the tree":

  # {.testKind: tkUnit.}
  test "a check is named, and may carry what to ask it about":
    check parseCheck("stats").ok
    check parseCheck("stats").req.kind == ckStats
    check parseCheck("state:Feed").req.kind == ckState
    check parseCheck("state:Feed").req.arg == "Feed"
    check parseCheck("yields:loadWidth").req.kind == ckYields
    check parseCheck("blast:store").req.kind == ckBlast
    check parseCheck("ui").req.kind == ckUi
    check not parseCheck("nonsense").ok
    check not parseCheck("").ok

  # {.testKind: tkUnit.}
  test "the heading says which question was asked":
    check checkName(parseCheck("state:Feed").req) == "state Feed"
    check checkName(parseCheck("ui").req) == "ui"

  # {.testKind: tkIntegration.}
  test "together and one after another give the same answers":
    ## The whole contract of `--parallel`.
    var
      R: seq[CheckRequest] = @[parseCheck("state").req,
        parseCheck("blast:ingest").req, parseCheck("ui").req]
      one = runChecks(exampleRoot("state_writes"), R, bParallel = false)
      many = runChecks(exampleRoot("state_writes"), R, bParallel = true)
    check one.rows.len == 3
    check many.rows.len == 3
    for i in 0 ..< one.rows.len:
      check one.rows[i].name == many.rows[i].name
      check one.rows[i].lines == many.rows[i].lines

  # {.testKind: tkUnit.}
  test "answers come back in the order they were asked for":
    ## A thread that finishes first must not jump the queue: somebody
    ## reading the output asked for them in an order and expects it.
    var
      R: seq[CheckRequest] = @[parseCheck("ui").req,
        parseCheck("state").req, parseCheck("blast:render").req]
      got = runChecks(exampleRoot("state_writes"), R, bParallel = true)
    check got.rows[0].name == "ui"
    check got.rows[1].name == "state"
    check got.rows[2].name == "blast render"

  # {.testKind: tkUnit.}
  test "only what is asked for is read":
    ## Asking about a front end must not parse a routine, and asking
    ## about routines must not build the whole measurement.
    var
      onlyUi = gather(exampleRoot("state_writes"), @[parseCheck("ui").req])
      onlyState = gather(exampleRoot("state_writes"),
        @[parseCheck("state").req])
    check not onlyUi.haveGraph
    check not onlyUi.haveStats
    check onlyState.haveGraph
    check not onlyState.haveStats

  # {.testKind: tkEdgeCase.}
  test "a check that needs a name and is given none says so":
    var
      got = runChecks(exampleRoot("state_writes"),
        @[parseCheck("yields").req, parseCheck("blast").req],
        bParallel = false)
    check "name a routine" in got.rows[0].lines[0]
    check "name a routine or a type" in got.rows[1].lines[0]

  # {.testKind: tkUnit.}
  test "reading the tree is timed apart from the checks":
    ## Folded together, the first check looks slow and the rest look
    ## free, which is the opposite of what is true.
    var
      got = runChecks(exampleRoot("state_writes"),
        @[parseCheck("state").req], bParallel = false)
      lines = checkLines(got.readMillis, got.rows, false)
      seen: bool = false
    for line in lines:
      if "reading the tree, once" in line:
        seen = true
    check seen
    check got.readMillis >= 0

  # {.testKind: tkEdgeCase.}
  test "asking nothing answers nothing rather than falling over":
    var got = runChecks(exampleRoot("state_writes"), @[], bParallel = true)
    check got.rows.len == 0
