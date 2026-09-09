# ============================================================
# | Otter Yield Path Tests                                   |
# | -> Every way a routine can end, not only the good one    |
# ============================================================
#
# `examples/yields/` is one file of seven routines, each ending in a
# different way. Its doc box names the expected verdict for each.

import std/[os, sets, unittest]

import ../../src/protocols/repo_graph
import ../../src/protocols/code_stats/yields
import runePragmas

proc sampleGraph(): RepoGraph {.testKind: tkUnit, covers: "escapingOf".} =
  ## The example tree, found from this file so the test runs anywhere.
  result = analyzeRepo(parentDir(parentDir(parentDir(
    currentSourcePath()))) / "examples" / "yields")

proc ask(name: string): YieldPaths {.testKind: tkUnit,
    covers: "yieldPathsOf".} =
  ## name: a routine of the example tree.
  var g: RepoGraph = sampleGraph()
  result = yieldPathsOf(g, name, escapingOf(g))

proc sample(n, s: string, A: seq[string]): FunctionInfo {.testKind: tkUnit,
    covers: "ownOutcomes".} =
  ## n: a routine name   s: its declaration   A: its body lines.
  ## Enough of a routine for the scanners, without a wrapped
  ## constructor in every test that needs one.
  result = FunctionInfo()
  result.name = n
  result.signature = s
  result.bodyLines = A

proc names(r: YieldPaths): seq[string] {.testKind: tkUnit,
    covers: "yieldPathsOf".} =
  ## r: one answer. Just the endings, for comparing against a list.
  result = @[]
  for o in r.outcomes:
    result.add(o.name)

suite "yield paths: every way a routine can end":

  # {.testKind: tkIntegration.}
  test "a library call is an ending, and the chain names it":
    var r = ask("readRaw")
    check r.returnType == "string"
    check names(r) == @["IOError"]
    check r.outcomes[0].via == @["readRaw", "readFile"]
    check r.outcomes[0].source == "library"

  # {.testKind: tkIntegration.}
  test "endings travel up through however many routines it takes":
    ## loadWidth raises one itself and inherits two from two levels
    ## down, one of them through a routine that raises nothing.
    var r = ask("loadWidth")
    check "IOError" in names(r)
    check "ValueError" in names(r)
    check "RangeDefect" in names(r)
    for o in r.outcomes:
      if o.name == "IOError":
        check o.via == @["loadWidth", "readRaw", "readFile"]

  # {.testKind: tkUnit.}
  test "a catch subtracts exactly what it names":
    var r = ask("pickWidth")
    check "ValueError" notin names(r)
    check "IOError" in names(r)
    check "ValueError" in r.caught

  # {.testKind: tkUnit.}
  test "a routine catching everything is a barrier and lets nothing out":
    var r = ask("safeWidth")
    check r.outcomes.len == 0
    check r.barrier
    check r.caught == @["everything"]

  # {.testKind: tkUnit.}
  test "a return type carrying an error entry is named as an ending":
    var r = ask("loadAll")
    check r.carriesError
    check r.errorField == "error"

  # {.testKind: tkEdgeCase.}
  test "stopping the program is told apart from raising":
    ## Nobody above can catch this one, so it is not an exception and
    ## must not be listed as though somebody could handle it.
    var
      r = ask("demand")
      stops: int = 0
    for o in r.outcomes:
      if o.kind == okAbort:
        stops = stops + 1
    check stops == 1
    check r.outcomes[0].kind == okAbort

  # {.testKind: tkRegression.}
  test "a name inside a string is a word, not a call":
    ## Pins the first thing this got wrong: `row.startsWith("doAssert
    ## false")` was read as an assertion, and a routine that only ever
    ## reads text was reported as able to stop the program.
    check ownOutcomes(sample("look", "proc look(s: string): bool =",
      @["""  result = s.startsWith("doAssert false")"""]),
      libraryRaisers(), initHashSet[string]()).len == 0

  # {.testKind: tkRegression.}
  test "a check that runs while building is not a check that stops a run":
    ## Pins the second: `static: doAssert supportsCopyMem(T)` fails a
    ## build. Reading it as a crash sends somebody looking for one
    ## that cannot happen.
    var f: FunctionInfo = sample("wipe", "proc wipe[T](x: var T) =",
      @["  static:", "    doAssert sizeof(T) > 0", "  go(x)"])
    check notRunLines(f).len == 1
    check ownOutcomes(f, libraryRaisers(), initHashSet[string]()).len == 0

  # {.testKind: tkRegression.}
  test "a when isMainModule block belongs to nobody":
    ## Pins the third: the parser hands a trailing `when isMainModule`
    ## block to the last routine above it, so a test written at the
    ## foot of a file was reported as an ending of that routine.
    check ownOutcomes(sample("stream", "proc stream(n: int): seq[byte] =",
      @["  result = @[]", "", "when isMainModule:",
        "  doAssert stream(1).len == 1"]),
      libraryRaisers(), initHashSet[string]()).len == 0

  # {.testKind: tkUnit.}
  test "a repository's own name outranks a library name":
    ## A tree with its own `open` does not raise IOError because the
    ## standard library's `open` would have.
    var
      f: FunctionInfo = sample("load", "proc load() =", @["  open(path)"])
      known: HashSet[string] = ["open"].toHashSet()
    check ownOutcomes(f, libraryRaisers(), initHashSet[string]()).len == 1
    check ownOutcomes(f, libraryRaisers(), known).len == 0

  # {.testKind: tkUnit.}
  test "a stated raises pragma is the truth and nothing argues with it":
    var said = declaredRaises("proc f(): int {.raises: [IOError, OSError].} =")
    check said.stated
    check said.names == @["IOError", "OSError"]
    check declaredRaises("proc g(): int {.raises: [].} =").stated
    check declaredRaises("proc h(): int =").stated == false

  # {.testKind: tkIntegration.}
  test "asking this repository something answers rather than falling over":
    var
      g = analyzeRepo(parentDir(parentDir(parentDir(currentSourcePath()))))
      e = escapingOf(g)
    check yieldPathsOf(g, "analyzeProject", e).error.len == 0
    check yieldPathsOf(g, "notARoutineAnywhere", e).error.len > 0
