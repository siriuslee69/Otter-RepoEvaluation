# ============================================================
# | Otter Timing State                                      |
# | -> Store timing tuples and flush them to disk           |
# ============================================================

import std/[exitprocs, locks, os, strutils]

import ../../.iron/metaPragmas
import ./types
import ./evaluation/benchmarks

const
  OtterTimingEnabled* {.role: helper, metaTags: {tagTiming, tagParentIntegration}.} = defined(otterTiming)
  OtterDebugEnabled* {.role: helper, metaTags: {tagTiming, tagParentIntegration}.} = defined(otterDebug)
  DefaultOtterLogPath* {.role: helper, metaTags: {tagLogging, tagParentIntegration}.} = "build/otter_timings.log"

var
  gOtterLock: Lock
  gOtterLockReady: bool = false
  gOtterMemory: OtterTimingMemory


proc flushTimingLog*() {.role: dataWriter, metaTags: {tagLogging, tagTiming}.}


proc ensureOtterLock() {.role: helper, metaTags: {tagState, tagTiming}.} =
  if gOtterLockReady:
    return
  initLock(gOtterLock)
  gOtterLockReady = true


proc ensureOtterDefaults() {.role: helper, metaTags: {tagState, tagLogging}.} =
  var
    envPath: string = ""
  if gOtterMemory.logPath.len != 0:
    return
  envPath = getEnv("TYR_OTTER_TIMING_LOG_PATH")
  if envPath.len == 0:
    envPath = getEnv("OTTER_TIMING_LOG_PATH")
  if envPath.len > 0:
    gOtterMemory.logPath = envPath
    return
  if dirExists("/data/local/tmp"):
    gOtterMemory.logPath = "/data/local/tmp/otter_timings.log"
    return
  gOtterMemory.logPath = DefaultOtterLogPath


proc ensureLogDir(p: string) {.role: helper, metaTags: {tagLogging}.} =
  ## p: target log file path.
  var
    d: string = ""
  d = parentDir(p)
  if d.len == 0:
    return
  if d == ".":
    return
  if dirExists(d):
    return
  createDir(d)


proc formatTimingEntry*(t: OtterTimingTuple): string {.role: helper, metaTags: {tagLogging, tagTiming}.} =
  ## t: captured timing tuple.
  var
    loc: string = ""
    s: string = ""
  loc = t.sourcePath & ":" & $t.sourceLine & ":" & $t.sourceColumn
  s = t.functionName & "\tlocation=" & loc & "\tstart=" & $t.startTick & "\tend=" & $t.endTick &
    "\tduration=" & $durationTicks(t)
  result = s


proc emitOtterDebug*(phase: string, n: string, p: string, l: int, c: int,
    a: int64 = 0, b: int64 = 0) {.role: helper, metaTags: {tagTiming, tagLogging}.} =
  ## phase: enter, exit, or exception.
  ## n: function name.
  ## p: source path.
  ## l: source line.
  ## c: source column.
  ## a: optional start tick.
  ## b: optional end tick.
  var
    duration: int64 = 0
    loc: string = ""
    s: string = ""
  if not OtterDebugEnabled:
    return
  loc = p & ":" & $l & ":" & $c
  s = "[otter] " & phase & " " & n & " " & loc
  if phase == "exit":
    duration = b - a
    s.add(" duration=" & $duration)
  stderr.writeLine(s)


proc ensureOtterHook*() {.role: orchestrator, metaTags: {tagLogging, tagTiming}.} =
  var
    needsHook: bool = false
  if not OtterTimingEnabled:
    return
  ensureOtterLock()
  acquire(gOtterLock)
  ensureOtterDefaults()
  if not gOtterMemory.hookRegistered:
    gOtterMemory.hookRegistered = true
    needsHook = true
  release(gOtterLock)
  if needsHook:
    addExitProc(flushTimingLog)


proc setLogPath*(p: string) {.role: helper, metaTags: {tagLogging, tagParentIntegration}.} =
  ## p: target log file path.
  if not OtterTimingEnabled:
    return
  ensureOtterLock()
  acquire(gOtterLock)
  gOtterMemory.logPath = p
  gOtterMemory.flushed = false
  release(gOtterLock)


proc getLogPath*(): string {.role: helper, metaTags: {tagLogging, tagState}.} =
  var
    t: string = ""
  ensureOtterLock()
  acquire(gOtterLock)
  ensureOtterDefaults()
  t = gOtterMemory.logPath
  release(gOtterLock)
  result = t


proc clearTimings*() {.role: helper, metaTags: {tagTiming, tagState}.} =
  ensureOtterLock()
  acquire(gOtterLock)
  gOtterMemory.entries = @[]
  gOtterMemory.flushed = false
  release(gOtterLock)


proc snapshotTimings*(): seq[OtterTimingTuple] {.role: helper, metaTags: {tagTiming, tagState}.} =
  var
    t: seq[OtterTimingTuple] = @[]
  ensureOtterLock()
  acquire(gOtterLock)
  t = gOtterMemory.entries
  release(gOtterLock)
  result = t


proc timingCount*(): int {.role: helper, metaTags: {tagTiming, tagState}.} =
  var
    t: int = 0
  ensureOtterLock()
  acquire(gOtterLock)
  t = gOtterMemory.entries.len
  release(gOtterLock)
  result = t


proc recordTiming*(n: string, p: string, l: int, c: int, a: int64,
    b: int64) {.role: helper, metaTags: {tagTiming, tagState}.} =
  ## n: function name.
  ## p: source path.
  ## l: source line.
  ## c: source column.
  ## a: start tick.
  ## b: end tick.
  var
    t: OtterTimingTuple
  if not OtterTimingEnabled:
    return
  ensureOtterHook()
  ensureOtterLock()
  t.functionName = n
  t.sourcePath = p
  t.sourceLine = l
  t.sourceColumn = c
  t.startTick = a
  t.endTick = b
  acquire(gOtterLock)
  gOtterMemory.entries.add(t)
  gOtterMemory.flushed = false
  release(gOtterLock)


proc flushTimingLog*() {.role: dataWriter, metaTags: {tagLogging, tagTiming}.} =
  var
    alreadyFlushed: bool = false
    p: string = ""
    A: seq[OtterTimingTuple] = @[]
    lines: seq[string] = @[]
  if not OtterTimingEnabled:
    return
  ensureOtterLock()
  acquire(gOtterLock)
  alreadyFlushed = gOtterMemory.flushed
  ensureOtterDefaults()
  if alreadyFlushed:
    release(gOtterLock)
    return
  p = gOtterMemory.logPath
  A = gOtterMemory.entries
  gOtterMemory.flushed = true
  release(gOtterLock)
  ensureLogDir(p)
  lines.add("otter_timing_log")
  lines.add("generated_at=" & isoTimestamp())
  lines.add("entries=" & $A.len)
  for t in A:
    lines.add(formatTimingEntry(t))
  writeFile(p, lines.join("\n") & "\n")
