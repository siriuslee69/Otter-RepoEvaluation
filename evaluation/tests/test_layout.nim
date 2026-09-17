# ============================================================
# | Otter Layout Tests                                       |
# | -> is a routine anywhere near the thing that uses it?    |
# ============================================================
#
# `layout.nim` reads nothing but the routine records, so these tests
# build the records directly rather than shaping an example
# repository. That is deliberate: the whole check is a set of
# thresholds, and a threshold is tested by standing on both sides of
# it, which is fiddly to arrange in real source and trivial here.
#
# The two findings under test both come from a real refactor:
#
#   three constructors of one type, 1500 lines apart
#   one 1796-line file with a thin waist two thirds of the way down

import std/[strutils, unittest]

import ../../src/protocols/repo_graph/types
import ../../src/protocols/code_stats/layout
import runePragmas

proc fn(name: string, first, last: int, calls: seq[string] = @[],
    returns: string = "", exported: bool = false,
    path: string = "one.nim"): FunctionInfo {.testKind: tkUnit,
    covers: "layoutOf".} =
  ## name/first/last: what it is called and where it sits.
  ## calls/returns/exported: the three things the check actually reads.
  ## path: which file it belongs to.
  result.name = name
  result.sourcePath = path
  result.lineStart = first
  result.lineEnd = last
  result.calls = calls
  result.returnType = returns
  result.isExported = exported

proc filler(fromLine, count: int, path: string = "one.nim"): seq[FunctionInfo]
    {.testKind: tkUnit, covers: "layoutOf".} =
  ## fromLine/count: unrelated routines, ten lines each, to sit between
  ## the ones a test cares about. These are the "strangers" the check
  ## counts, and without enough of them nothing is ever reported.
  var
    i: int = 0
  while i < count:
    result.add(fn("filler" & $i, fromLine + i * 10, fromLine + i * 10 + 8,
      path = path))
    i = i + 1

proc scattersIn(r: LayoutReport): seq[LayoutFinding] {.testKind: tkUnit,
    covers: "layoutOf".} =
  ## r: one report, narrowed to the groups sitting apart.
  for f in r.items:
    if f.kind == lkScattered:
      result.add(f)

proc cutsIn(r: LayoutReport): seq[LayoutFinding] {.testKind: tkUnit,
    covers: "layoutOf".} =
  ## r: one report, narrowed to the files with a seam in them.
  for f in r.items:
    if f.kind == lkCleanCut:
      result.add(f)

suite "layout: siblings that are not sitting together":

  # {.testKind: tkUnit.}
  test "three alternatives side by side are left alone":
    ## The finished state. Nothing between them, so nothing to say.
    var
      A: seq[FunctionInfo] = @[
        fn("initAuthPsk", 10, 18, returns = "Auth", exported = true),
        fn("initAuthPinned", 20, 28, returns = "Auth", exported = true),
        fn("initAuthCert", 30, 38, returns = "Auth", exported = true)]
    check scattersIn(layoutOf(A)).len == 0

  # {.testKind: tkRegression, pins: "three constructors of one type, 1500 lines apart".}
  test "three alternatives with a file between them are reported":
    ## The real one. Same three routines, now with forty unrelated
    ## routines in the way, which is the difference between glancing
    ## and searching.
    var
      A: seq[FunctionInfo] = @[
        fn("initAuthPsk", 10, 18, returns = "Auth", exported = true)]
      found: seq[LayoutFinding] = @[]
    A.add(filler(100, 40))
    A.add(fn("initAuthPinned", 600, 608, returns = "Auth", exported = true))
    A.add(fn("initAuthCert", 610, 618, returns = "Auth", exported = true))
    found = scattersIn(layoutOf(A))
    check found.len == 1
    check found[0].routines == @["initAuthPsk", "initAuthPinned",
      "initAuthCert"]
    check found[0].line == 10
    check "Auth" in found[0].evidence
    check found[0].strangers == 40
    ## The remedy carries the three numbers a reader needs to agree
    ## with it without opening the file.
    check "27 lines spread over 609" in found[0].remedy

  # {.testKind: tkEdgeCase.}
  test "a couple of routines in between is not worth mentioning":
    ## Below the stranger floor. Three neighbours and a helper between
    ## them still read as one section.
    var
      A: seq[FunctionInfo] = @[
        fn("initAuthPsk", 10, 18, returns = "Auth", exported = true)]
    A.add(filler(30, 3))
    A.add(fn("initAuthPinned", 70, 78, returns = "Auth", exported = true))
    A.add(fn("initAuthCert", 80, 88, returns = "Auth", exported = true))
    check scattersIn(layoutOf(A)).len == 0

  # {.testKind: tkEdgeCase.}
  test "members that fill their own span are a section, not a scatter":
    ## Distance alone proves nothing. These three are far apart in
    ## lines and there is nothing else between them, because each one
    ## is enormous. That is a long section and it reads fine.
    var
      A: seq[FunctionInfo] = @[
        fn("initAuthPsk", 10, 200, returns = "Auth", exported = true),
        fn("initAuthPinned", 210, 400, returns = "Auth", exported = true),
        fn("initAuthCert", 410, 600, returns = "Auth", exported = true)]
    A.add(filler(602, 5))
    check scattersIn(layoutOf(A)).len == 0

suite "layout: a shared return type is not enough on its own":

  # {.testKind: tkRegression, pins: "four encoders reported because they all return bytes".}
  test "routines that merely return the same buffer are not alternatives":
    ## The noise case. Four scattered routines all returning `ByteSeq`
    ## share nothing in their names, so nobody named them as a set and
    ## they are not a set.
    var
      A: seq[FunctionInfo] = @[
        fn("encodeCertificate", 10, 18, returns = "ByteSeq", exported = true)]
    A.add(filler(100, 40))
    A.add(fn("serverBlockBytes", 600, 608, returns = "ByteSeq",
      exported = true))
    A.add(fn("pskExchangeBinder", 610, 618, returns = "ByteSeq",
      exported = true))
    check scattersIn(layoutOf(A)).len == 0

  # {.testKind: tkUnit.}
  test "a shared prefix is enough to call them a set":
    var
      A: seq[FunctionInfo] = @[
        fn("buildAlpha", 10, 18, returns = "Thing", exported = true)]
    A.add(filler(100, 40))
    A.add(fn("buildBeta", 600, 608, returns = "Thing", exported = true))
    A.add(fn("buildGamma", 610, 618, returns = "Thing", exported = true))
    check scattersIn(layoutOf(A)).len == 1

  # {.testKind: tkUnit.}
  test "a shared suffix is enough as well":
    var
      A: seq[FunctionInfo] = @[
        fn("alphaHandler", 10, 18, returns = "Thing", exported = true)]
    A.add(filler(100, 40))
    A.add(fn("betaHandler", 600, 608, returns = "Thing", exported = true))
    A.add(fn("gammaHandler", 610, 618, returns = "Thing", exported = true))
    check scattersIn(layoutOf(A)).len == 1

suite "layout: steps one routine calls":

  # {.testKind: tkUnit.}
  test "an orchestrator whose steps are scattered is reported":
    var
      A: seq[FunctionInfo] = @[fn("stepOne", 10, 18)]
      found: seq[LayoutFinding] = @[]
    A.add(filler(100, 40))
    A.add(fn("stepTwo", 600, 608))
    A.add(fn("stepThree", 610, 618))
    A.add(fn("runIt", 700, 720,
      calls = @["stepOne", "stepTwo", "stepThree"]))
    found = scattersIn(layoutOf(A))
    check found.len == 1
    check "runIt" in found[0].evidence
    check "steps" in found[0].evidence

  # {.testKind: tkRegression, pins: "four callers of one helper set reported four times".}
  test "several callers of the same steps are one finding, not several":
    ## Four orchestrators reaching for the same three helpers is one
    ## thing out of place. Reporting it four times buries everything
    ## else -- and that several callers agree is stronger evidence,
    ## so it is said rather than dropped.
    var
      A: seq[FunctionInfo] = @[fn("stepOne", 10, 18)]
      found: seq[LayoutFinding] = @[]
    A.add(filler(100, 40))
    A.add(fn("stepTwo", 600, 608))
    A.add(fn("stepThree", 610, 618))
    A.add(fn("runA", 700, 720, calls = @["stepOne", "stepTwo", "stepThree"]))
    A.add(fn("runB", 730, 750, calls = @["stepOne", "stepTwo", "stepThree"]))
    A.add(fn("runC", 760, 780, calls = @["stepOne", "stepTwo", "stepThree"]))
    found = scattersIn(layoutOf(A))
    check found.len == 1
    check "and by 2 other routine(s)" in found[0].evidence

suite "layout: a file that is already two files":

  # {.testKind: tkRegression, pins: "a 1796-line file with a thin waist two thirds down".}
  test "a thin waist is found, and the line to cut at is named":
    ## Forty routines. The bottom half reaches back for exactly two of
    ## the top half's names and nothing else, which is a seam.
    var
      A: seq[FunctionInfo] = @[fn("shared", 10, 20)]
      found: seq[LayoutFinding] = @[]
      i: int = 0
    while i < 20:
      A.add(fn("top" & $i, 40 + i * 30, 40 + i * 30 + 25,
        calls = @["top" & $(i - 1)]))
      i = i + 1
    i = 0
    while i < 20:
      A.add(fn("bottom" & $i, 700 + i * 30, 700 + i * 30 + 25,
        calls = @["bottom" & $(i - 1), "shared"]))
      i = i + 1
    found = cutsIn(layoutOf(A))
    check found.len == 1
    ## `shared` sits at the very top, so it is above the cut wherever
    ## the cut lands, and it is the one name the bottom half needs.
    check found[0].routines == @["shared"]
    check found[0].above > 0
    check found[0].below > 0
    check "cut at line" in found[0].remedy

  # {.testKind: tkEdgeCase.}
  test "a file that is genuinely one thing is left alone":
    ## Every routine below calls a different routine above, so wherever
    ## it is cut the bottom half drags most of the top half with it.
    ## Long, and correctly reported as nothing.
    var
      A: seq[FunctionInfo] = @[]
      i: int = 0
    while i < 20:
      A.add(fn("top" & $i, 10 + i * 30, 10 + i * 30 + 25))
      i = i + 1
    i = 0
    while i < 20:
      A.add(fn("bottom" & $i, 700 + i * 30, 700 + i * 30 + 25,
        calls = @["top" & $i]))
      i = i + 1
    check cutsIn(layoutOf(A)).len == 0

  # {.testKind: tkEdgeCase.}
  test "a short file is never cut, however thin its waist":
    var
      A: seq[FunctionInfo] = @[]
      i: int = 0
    while i < 20:
      A.add(fn("top" & $i, 10 + i * 5, 10 + i * 5 + 3))
      i = i + 1
    i = 0
    while i < 20:
      A.add(fn("bottom" & $i, 200 + i * 5, 200 + i * 5 + 3))
      i = i + 1
    check cutsIn(layoutOf(A)).len == 0

  # {.testKind: tkRegression, pins: "a handful of small helpers at the top reported as half a file".}
  test "a cut always has enough LINES on both sides, not just routines":
    ## The trap that counting routines alone falls into. Fourteen tiny
    ## routines at the top are half the routines in this file and a
    ## fourteenth of its lines, so cutting after them is not the
    ## repair anybody wanted -- whatever the waist there looks like.
    var
      A: seq[FunctionInfo] = @[]
      found: seq[LayoutFinding] = @[]
      i: int = 0
    while i < 14:
      A.add(fn("tiny" & $i, 10 + i * 6, 10 + i * 6 + 4))
      i = i + 1
    i = 0
    while i < 14:
      A.add(fn("big" & $i, 200 + i * 60, 200 + i * 60 + 55,
        calls = @["tiny0"]))
      i = i + 1
    found = cutsIn(layoutOf(A))
    ## Cutting after the fourteen tinies would leave 79 lines above and
    ## 890 below. Whatever cut is offered instead, both halves carry
    ## real weight.
    for f in found:
      check f.above > 14
      check f.aboveLines >= 300
      check f.belowLines >= 300

suite "layout: what the report says about itself":

  # {.testKind: tkUnit.}
  test "the worst is first, and cuts come before scatters":
    ## A gate shows the first few findings and nothing else, so the
    ## order is the difference between a useful report and a list.
    var
      A: seq[FunctionInfo] = @[fn("stepOne", 10, 18)]
      r: LayoutReport = default(LayoutReport)
    ## Under 700 lines on purpose, so this file can only ever be a
    ## scatter and never a cut -- otherwise the test would be counting
    ## two findings from one fixture and proving nothing about order.
    A.add(filler(30, 40))
    A.add(fn("stepTwo", 450, 458))
    A.add(fn("stepThree", 460, 468))
    A.add(fn("runIt", 480, 500,
      calls = @["stepOne", "stepTwo", "stepThree"]))
    ## A second file, long, with one shared name across a thin waist.
    var
      i: int = 0
    while i < 20:
      A.add(fn("top" & $i, 10 + i * 30, 10 + i * 30 + 25,
        calls = @["top" & $(i - 1)], path = "two.nim"))
      i = i + 1
    A.add(fn("shared", 620, 640, path = "two.nim"))
    i = 0
    while i < 20:
      A.add(fn("bottom" & $i, 700 + i * 30, 700 + i * 30 + 25,
        calls = @["bottom" & $(i - 1), "shared"], path = "two.nim"))
      i = i + 1
    r = layoutOf(A)
    check r.total == r.scattered + r.cuts
    check r.cuts == 1
    check r.scattered == 1
    check r.items[0].kind == lkCleanCut

  # {.testKind: tkUnit.}
  test "a root turns absolute paths into the ones a person would type":
    var
      A: seq[FunctionInfo] = @[
        fn("buildAlpha", 10, 18, returns = "Thing", exported = true,
          path = "/home/me/repo/src/one.nim")]
      r: LayoutReport = default(LayoutReport)
    A.add(filler(100, 40, path = "/home/me/repo/src/one.nim"))
    A.add(fn("buildBeta", 600, 608, returns = "Thing", exported = true,
      path = "/home/me/repo/src/one.nim"))
    A.add(fn("buildGamma", 610, 618, returns = "Thing", exported = true,
      path = "/home/me/repo/src/one.nim"))
    r = layoutOf(A, "/home/me/repo")
    check r.items.len == 1
    check r.items[0].path == "src/one.nim"
