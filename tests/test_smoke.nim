# ============================================================
# | Otter Smoke Tests                                       |
# | -> Verify flag gating, Sigma bridge, and exit logging   |
# ============================================================

import std/[os, osproc, strutils, unittest]

import ../.iron/metaPragmas
import otter_repo_evaluation

otterInstrument:
  proc localLeaf*(a: int): int {.role: helper, metaTags: {tagTesting}.} =
    ## a: input value.
    var
      t: int = 0
    t = a + 1
    result = t

  proc localBranch*(a: int): int {.role: helper, metaTags: {tagTesting}.} =
    ## a: input value.
    var
      t: int = 0
    t = localLeaf(a)
    result = t + 1


proc pragmaLeaf*(a: int): int {.otterBench, role: helper, metaTags: {tagTesting}.} =
  ## a: input value.
  var
    t: int = 0
  t = a * 2
  result = t


suite "otter smoke":
  test "flag off keeps local timing store empty":
    clearTimings()
    check localBranch(4) == 6
    check pragmaLeaf(4) == 8
    check timingCount() == 0
    check snapshotTimings().len == 0

  test "sigma benchmark helpers are reachable through otter":
    var
      A: array[1, BenchAlgo]
      R: seq[BenchResult] = @[]
      s: string = ""
    A[0] = BenchAlgo(name: "localBranch", run: proc() {.closure.} = discard localBranch(5))
    R = compareAlgorithms(A, loops = 2, warmup = 1)
    s = formatBenchResults(R)
    check R.len == 1
    check s.contains("localBranch")

  test "timed child writes its log on process exit":
    var
      logPath: string = "tests/build/otter_enabled.log"
      cmd: string = ""
      r: tuple[output: string, exitCode: int]
      content: string = ""
    createDir("tests/build")
    if fileExists(logPath):
      removeFile(logPath)
    cmd = "nim c --path:src --nimcache:build/nimcache_child -d:otterTiming -r tests/test_child_enabled.nim"
    r = execCmdEx(cmd)
    check r.exitCode == 0
    check fileExists(logPath)
    content = readFile(logPath)
    check content.contains("otter_timing_log")
    check content.contains("childLeaf")
    check content.contains("childBranch")
