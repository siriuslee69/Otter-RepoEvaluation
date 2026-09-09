# ============================================================
# | Otter Types                                             |
# | -> Timing tuples and in-memory timing store             |
# ============================================================

import runePragmas

type
  OtterTimingTuple* {.role: memory, tag: "timing|state".} = tuple
    functionName: string
    sourcePath: string
    sourceLine: int
    sourceColumn: int
    startTick: int64
    endTick: int64

  OtterTimingMemory* {.role: memory, tag: "timing|state|logging".} = object
    entries*: seq[OtterTimingTuple]
    logPath*: string
    hookRegistered*: bool
    flushed*: bool


proc durationTicks*(t: OtterTimingTuple): int64 {.role: helper, tag: "timing|state".} =
  ## t: captured timing tuple.
  var
    q: int64 = 0
  q = t.endTick - t.startTick
  result = q
