# ============================================================
# | Otter Sigma Bridge                                      |
# | -> Reuse Sigma benchmark helpers and monotonic ticks    |
# ============================================================

import std/[monotimes, times]

import ../../.iron/metaPragmas
import sigma_bench_and_eval as sigma

type
  BenchAlgo* {.role: helper, metaTags: {tagSigma, tagTiming}.} = sigma.BenchAlgo
  BenchResult* {.role: helper, metaTags: {tagSigma, tagTiming}.} = sigma.BenchResult


proc compareAlgorithms*(A: openArray[BenchAlgo], loops: int = 10000,
    warmup: int = 100): seq[BenchResult] {.role: helper, metaTags: {tagSigma, tagTiming}.} =
  ## A: benchmark algorithm list.
  ## loops: timed loop count.
  ## warmup: untimed warmup loop count.
  var
    t: seq[BenchResult] = @[]
  t = sigma.compareAlgorithms(A, loops, warmup)
  result = t


proc formatBenchResults*(R: openArray[BenchResult]): string {.role: helper, metaTags: {tagSigma, tagTiming}.} =
  ## R: benchmark result list.
  var
    t: string = ""
  t = sigma.formatBenchResults(R)
  result = t


proc otterTick*(): int64 {.role: helper, metaTags: {tagSigma, tagTiming}.} =
  ## Return a monotonic clock tick count using the same base clock style as Sigma.
  var
    t: int64 = 0
  t = getMonoTime().ticks
  result = t


proc otterIsoTimestamp*(): string {.role: helper, metaTags: {tagSigma, tagLogging}.} =
  ## Return a UTC timestamp string for log headers.
  var
    t: string = ""
    dt: DateTime
  dt = now().utc
  t = dt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  result = t
