# ============================================================
# | Otter Code Statistics Tests                              |
# | -> Nesting, bands, test kinds, and one whole repository  |
# ============================================================
#
# A small tree is written to disk, measured, and checked figure by
# figure. Writing the tree out rather than pointing at Otter itself
# keeps the numbers stable while Otter is being worked on.

import std/[os, unittest]

import otter_repo_evaluation
import runePragmas

const
  sampleSource = """
## a small module for the statistics tests
import std/strutils

template role*(x: untyped) {.pragma.}
template guard*(x: untyped) {.pragma.}

proc tidy*(s: string): string {.role: sanitizer.} =
  ## s: text straight from a person
  result = s.strip()

proc mean*(A: seq[seq[int]]): int {.role: math.} =
  result = 0
  for row in A:
    for cell in row:
      result = result + cell

proc walk*(A: seq[seq[int]]): int {.role: helper.} =
  result = 0
  for row in A:
    for cell in row:
      if cell > 0:
        while cell > 0:
          result = result + 1

proc lonely*(): int {.role: helper.} =
  result = 7
"""
  sampleTests = """
import std/unittest
import ../../src/sample

suite "sample":
  test "the average adds every row":
    check mean(@[@[1, 2]]) == 3

  # {.testKind: tkEdgeCase.}
  test "an empty list is still an answer":
    check mean(@[]) == 0

  # {.testKind: tkBenchmark.}
  test "walking a wide table":
    check walk(@[@[1, 2]]) == 3
"""

proc sampleTree(): string {.role: dataWriter, tag: "stats".} =
  ## The tree every test below reads, rebuilt from nothing each run.
  result = joinPath(getCurrentDir(), "build", "code_stats_sample")
  if dirExists(result):
    removeDir(result)
  createDir(joinPath(result, ".git"))
  createDir(joinPath(result, "src"))
  createDir(joinPath(result, "tests"))
  writeFile(joinPath(result, "src", "sample.nim"), sampleSource)
  writeFile(joinPath(result, "tests", "test_sample.nim"), sampleTests)


proc pick(S: ProjectStats, name: string): FileStat {.role: parser,
    tag: "stats".} =
  ## S: the measured tree. name: the file wanted, by its bare name.
  result = FileStat()
  for row in S.files:
    if row.name == name:
      result = row
      return


suite "otter code statistics":
  test "a block inside a block is a site, and the deepest one is a leaf":
    var
      s: ProjectStats = analyzeProject(sampleTree())
      deep: int = 0
      leaves: int = 0
    check s.error.len == 0
    for row in s.nest.sites:
      deep = max(deep, row.depth)
      if row.leaf:
        leaves = leaves + 1
    check deep == 4
    check leaves > 0
    check s.nest.doubles >= 1
    check s.nest.triples >= 1
    check s.nest.deeper >= 1

  test "one for loop on its own is not nesting":
    var
      s: ProjectStats = analyzeProject(sampleTree())
    check s.nest.nestedFunctions == 2
    check s.nest.mathNested == 1
    check s.nest.nonMathNested == 1

  # {.testKind: tkEdgeCase.}
  test "a folder with no Nim files says so instead of reading as clean":
    var
      empty: string = joinPath(getCurrentDir(), "build", "code_stats_bare")
      s: ProjectStats
    createDir(empty)
    s = analyzeProject(empty)
    check s.error.len > 0
    check s.files.len == 0

  test "a declared kind beats the wording, and is counted as declared":
    var
      s: ProjectStats = analyzeProject(sampleTree())
    check s.tests.tests == 3
    check s.tests.declaredKinds == 2
    check countOf(s.tests.kinds, "edge case") == 1
    check countOf(s.tests.kinds, "benchmark") == 1

  test "a routine no test reaches lands in the first bucket":
    var
      s: ProjectStats = analyzeProject(sampleTree())
    check s.tests.buckets[0] >= 1
    check s.tests.functions == 6
    check "src/sample::lonely" in s.unused

  test "the sanitizer role marks the file as taking input":
    var
      s: ProjectStats = analyzeProject(sampleTree())
      f: FileStat = pick(s, "sample.nim")
    check f.inputs == 1
    check f.functions == 6
    check f.isTest == false

  test "every file lands in a size band and keeps its share":
    var
      s: ProjectStats = analyzeProject(sampleTree())
    check s.files.len == 2
    check s.files[0].size == sbHuge
    check s.files[0].share == 1.0
    check s.files[^1].share <= 1.0

  test "the health band follows the average routine length":
    check healthOf(4.0) == hbOk
    check healthOf(20.0) == hbAlright
    check healthOf(30.0) == hbPoor
    check healthOf(90.0) == hbCritical

  # {.testKind: tkEdgeCase.}
  test "the inner-line buckets hold at their two ends":
    check bucketOf(0) == 0
    check bucketOf(2) == 0
    check bucketOf(41) == 5
    check bucketOf(4000) == 5

  test "a pragma is a template use, so pragma-only repositories count":
    var
      s: ProjectStats = analyzeProject(sampleTree())
    check s.nest.templateCalls >= 4

  test "the role tally names what was declared and what was not":
    var
      s: ProjectStats = analyzeProject(sampleTree())
    check countOf(s.roles, "sanitizer") == 1
    check countOf(s.roles, "math") == 1
    check countOf(s.roles, "helper") == 2

  test "the words decide the kind only when no pragma did":
    check kindFromWords("an empty list is refused", "") == "edge case"
    check kindFromWords("benchmark the sweep", "") == "benchmark"
    check kindFromWords("this is a regression", "") == "regression"
    check kindFromWords("it adds two numbers", "") == "unit"
    check kindFromPragma("testkind:tkBugfix") == "bugfix"
    check kindFromPragma("role:helper") == ""

  test "a routine written inside another one starts its nesting again":
    check indentOf("    x") == 4
    check firstWord("  if a == 1:") == "if"
    check opensBlock("  if a == 1:")
    check opensBlock("  result = 1") == false
    check continuesBlock("  else:")
    check startsRoutine("  proc inner() =")
