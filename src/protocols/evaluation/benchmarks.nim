# ============================================================
# | Benchmark Helpers                                        |
# | -> Compare algorithm runtimes over repeated loops        |
# ============================================================

import std/[monotimes, strutils, times]

type
  BenchAlgo* = object
    name*: string
    run*: proc() {.closure.}

  BenchResult* = object
    name*: string
    loops*: int
    totalTicks*: int64
    avgTicks*: int64


proc monotonicTick*(): int64 =
  ## Return the current monotonic clock tick.
  result = getMonoTime().ticks


proc isoTimestamp*(): string =
  ## Return a UTC timestamp suitable for report headers.
  var
    dt: DateTime
  dt = now().utc
  result = dt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")


proc compareAlgorithms*(algos: openArray[BenchAlgo], loops: int = 10000,
    warmup: int = 100): seq[BenchResult] =
  ## Compare algorithms by running each one `loops` times.
  ## Uses a small warmup to reduce first-run effects.
  var
    results: seq[BenchResult] = @[]
    total: int64 = 0
    started: int64 = 0
    i: int = 0
    w: int = 0
  if loops <= 0:
    return results
  for algo in algos:
    w = 0
    while w < warmup:
      algo.run()
      inc w
    i = 0
    started = monotonicTick()
    while i < loops:
      algo.run()
      inc i
    total = monotonicTick() - started
    results.add(BenchResult(
      name: algo.name,
      loops: loops,
      totalTicks: total,
      avgTicks: total div loops
    ))
  result = results


proc formatBenchResults*(results: openArray[BenchResult]): string =
  ## Format benchmark results for printing.
  var
    lines: seq[string] = @[]
  for r in results:
    lines.add(r.name & " total=" & $r.totalTicks & " avg=" & $r.avgTicks &
      " loops=" & $r.loops)
  result = lines.join("\n")
