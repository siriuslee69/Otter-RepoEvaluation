# ============================================================
# | Benchmark Helpers                                        |
# | -> Compare algorithm runtimes over repeated loops        |
# ============================================================

import std/[algorithm, monotimes, strutils, times]

type
  BenchAlgo* = object
    name*: string
    run*: proc() {.closure.}
    bytesPerOp*: int

  BenchResult* = object
    name*: string
    loops*: int
    totalTicks*: int64
    avgTicks*: int64

  StableBenchResult* = object
    name*: string
    loops*: int
    samples*: int
    bytesPerOp*: int
    minNs*: int64
    medianNs*: int64
    meanNs*: float64
    maxNs*: int64
    mibPerSecond*: float64


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


proc warmAlgorithm(a: BenchAlgo, warmup: int) =
  ## a: algorithm callback. warmup: untimed operation count.
  var
    i: int = 0
  while i < warmup:
    a.run()
    i = i + 1


proc measureAlgorithm(a: BenchAlgo, loops: int): int64 =
  ## a: algorithm callback. loops: operations in one timing sample.
  var
    i: int = 0
    started: int64 = 0
  started = monotonicTick()
  while i < loops:
    a.run()
    i = i + 1
  result = monotonicTick() - started


proc stableBenchResult(a: BenchAlgo, loops, samples: int): StableBenchResult =
  ## a: algorithm callback. loops/samples: completed timing dimensions.
  var
    Ns: seq[int64] = @[]
    i: int = 0
    elapsed: int64 = 0
    total: float64 = 0.0
  Ns.setLen(samples)
  i = 0
  while i < samples:
    elapsed = measureAlgorithm(a, loops)
    Ns[i] = elapsed div int64(loops)
    total = total + float64(elapsed) / float64(loops)
    i = i + 1
  Ns.sort()
  result.name = a.name
  result.loops = loops
  result.samples = samples
  result.bytesPerOp = a.bytesPerOp
  result.minNs = Ns[0]
  result.medianNs = Ns[samples div 2]
  result.meanNs = total / float64(samples)
  result.maxNs = Ns[Ns.high]
  if a.bytesPerOp > 0 and result.medianNs > 0:
    result.mibPerSecond = float64(a.bytesPerOp) * 1_000_000_000.0 /
      float64(result.medianNs) / 1_048_576.0


proc compareAlgorithmsStable*(algos: openArray[BenchAlgo], loops: int = 10000,
    warmup: int = 100, samples: int = 9): seq[StableBenchResult] =
  ## algos: callbacks with optional bytes-per-operation metadata.
  ## loops/warmup/samples: repeated-sampling benchmark dimensions.
  var
    i: int = 0
  if loops <= 0 or samples <= 0:
    return
  i = 0
  while i < algos.len:
    warmAlgorithm(algos[i], warmup)
    result.add(stableBenchResult(algos[i], loops, samples))
    i = i + 1


proc formatStableBenchResults*(R: openArray[StableBenchResult]): string =
  ## R: stable benchmark results to format as one line per algorithm.
  var
    L: seq[string] = @[]
    i: int = 0
  i = 0
  while i < R.len:
    L.add(R[i].name & " median_ns=" & $R[i].medianNs &
      " min_ns=" & $R[i].minNs & " max_ns=" & $R[i].maxNs &
      " mean_ns=" & formatFloat(R[i].meanNs, ffDecimal, 2) &
      " mib_s=" & formatFloat(R[i].mibPerSecond, ffDecimal, 2) &
      " loops=" & $R[i].loops & " samples=" & $R[i].samples)
    i = i + 1
  result = L.join("\n")
