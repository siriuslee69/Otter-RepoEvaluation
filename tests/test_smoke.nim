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

  test "otter-nim auto-wraps a plain Nim file":
    var
      oldLogPath: string = ""
      logPath: string = absolutePath("tests/build/otter_cli.log")
      cmd: string = ""
      content: string = ""
      hadLogPath: bool = false
      r: tuple[output: string, exitCode: int]
    createDir("tests/build")
    if fileExists(logPath):
      removeFile(logPath)
    oldLogPath = getEnv("OTTER_TIMING_LOG_PATH")
    hadLogPath = oldLogPath.len > 0
    putEnv("OTTER_TIMING_LOG_PATH", logPath)
    cmd = "./otter-nim c --path:src --nimcache:build/nimcache_cli -r tests/samples/auto_trace_sample.nim"
    r = execCmdEx(cmd, options = {poUsePath, poStdErrToStdOut})
    if hadLogPath:
      putEnv("OTTER_TIMING_LOG_PATH", oldLogPath)
    else:
      delEnv("OTTER_TIMING_LOG_PATH")
    check r.exitCode == 0
    check r.output.contains("[otter] enter autoLeaf")
    check r.output.contains("[otter] exit autoBranch")
    check fileExists(logPath)
    content = readFile(logPath)
    check content.contains("autoLeaf")
    check content.contains("autoBranch")
    check content.contains("tests/samples/auto_trace_sample.nim")
