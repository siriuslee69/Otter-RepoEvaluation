# ============================================================
# | Otter Smoke Tests                                       |
# | -> Verify timing, evaluation helpers, and exit logging  |
# ============================================================

import std/[os, osproc, strutils, unittest]

import otterPragmas
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

  test "benchmark helpers are reachable through otter":
    var
      A: array[1, BenchAlgo]
      R: seq[BenchResult] = @[]
      S: seq[StableBenchResult] = @[]
      s: string = ""
    A[0] = BenchAlgo(name: "localBranch", bytesPerOp: 4,
      run: proc() {.closure.} = discard localBranch(5))
    R = compareAlgorithms(A, loops = 2, warmup = 1)
    s = formatBenchResults(R)
    check R.len == 1
    check s.contains("localBranch")
    S = compareAlgorithmsStable(A, loops = 2, warmup = 1, samples = 3)
    check S.len == 1
    check S[0].samples == 3
    check S[0].bytesPerOp == 4
    check formatStableBenchResults(S).contains("median_ns=")

  test "rank probabilities match binary matrix reference values":
    var
      p32, p31, pRest: float64
    p32 = rankProbability(32, 32, 32)
    p31 = rankProbability(32, 32, 31)
    pRest = 1.0 - p32 - p31
    check abs(p32 - 0.2887880951538411) < 1.0e-12
    check abs(p31 - 0.5775761901732048) < 1.0e-12
    check abs(pRest - 0.1336357146729541) < 1.0e-12

  test "statistical suite is reachable through otter":
    var
      Bs: seq[uint8] = @[]
      p: NistParams
      R: seq[NistResult] = @[]
      i: int = 0
    Bs.setLen(2048)
    while i < Bs.len:
      Bs[i] = uint8(i mod 256)
      i = i + 1
    p.blockSize = 128
    p.patternSize = 4
    p.longRunBlock = 8
    p.alpha = defaultAlpha
    p.rankRows = 32
    p.rankCols = 32
    p.spectralMaxBits = 1 shl 12
    p.templateSize = 9
    p.templateBlockSize = 1032
    p.templateCount = 8
    p.overlapTemplateSize = 9
    p.overlapTemplateBlock = 1032
    p.linearComplexityBlock = 500
    p.universalBlockSize = 7
    p.universalInitBlocks = 0
    R = nistSuiteFromBytes(Bs, p)
    check R.len > 0
    p = nistParamsForBits(Bs.len * 8)
    R = nistCoreSuiteFromBytes(Bs, p)
    check R.len == 11

  test "timed child writes its log on process exit":
    var
      logPath: string = "evaluation/tests/build/otter_enabled.log"
      cmd: string = ""
      r: tuple[output: string, exitCode: int]
      content: string = ""
    createDir("evaluation/tests/build")
    if fileExists(logPath):
      removeFile(logPath)
    cmd = "nim c --path:src --nimcache:build/nimcache_child -d:otterTiming -r evaluation/tests/test_child_enabled.nim"
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
      logPath: string = absolutePath("evaluation/tests/build/otter_cli.log")
      cliPath: string = joinPath("build", "otter-nim" & ExeExt)
      cmd: string = ""
      content: string = ""
      hadLogPath: bool = false
      r: tuple[output: string, exitCode: int]
    createDir("evaluation/tests/build")
    createDir("build")
    if fileExists(logPath):
      removeFile(logPath)
    cmd = "nim c --path:src -o:" & quoteShell(cliPath) & " src/clients/cli/otter_nim.nim"
    r = execCmdEx(cmd, options = {poUsePath, poStdErrToStdOut})
    check r.exitCode == 0
    oldLogPath = getEnv("OTTER_TIMING_LOG_PATH")
    hadLogPath = oldLogPath.len > 0
    putEnv("OTTER_TIMING_LOG_PATH", logPath)
    cmd = quoteShell(cliPath) & " c --path:src --nimcache:build/nimcache_cli -r evaluation/tests/samples/auto_trace_sample.nim"
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
    check content.contains("evaluation/tests/samples/auto_trace_sample.nim")
