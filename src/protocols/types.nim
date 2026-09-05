# ============================================================
# | Otter Types                                             |
# | -> Timing tuples and in-memory timing store             |
# ============================================================

import ../../meta/metaPragmas

type
  OtterTimingTuple* {.role: memory, metaTags: {tagTiming, tagState}.} = tuple
    functionName: string
    sourcePath: string
    sourceLine: int
    sourceColumn: int
    startTick: int64
    endTick: int64

  OtterTimingMemory* {.role: memory, metaTags: {tagTiming, tagState, tagLogging}.} = object
    entries*: seq[OtterTimingTuple]
    logPath*: string
    hookRegistered*: bool
    flushed*: bool


proc durationTicks*(t: OtterTimingTuple): int64 {.role: helper, metaTags: {tagTiming, tagState}.} =
  ## t: captured timing tuple.
  var
    q: int64 = 0
  q = t.endTick - t.startTick
  result = q
