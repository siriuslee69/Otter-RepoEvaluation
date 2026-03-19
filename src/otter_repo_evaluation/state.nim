# ============================================================
# | Otter Timing State                                      |
# | -> Store timing tuples and flush them to disk           |
# ============================================================

import std/[exitprocs, locks, os, strutils]

import ../../.iron/metaPragmas
import ./types
import ./sigma_bridge

const
  OtterTimingEnabled* {.role: helper, metaTags: {tagTiming, tagParentIntegration}.} = defined(otterTiming)
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
  if gOtterMemory.logPath.len != 0:
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
    s: string = ""
  s = t.functionName & "\tstart=" & $t.startTick & "\tend=" & $t.endTick &
    "\tduration=" & $durationTicks(t)
  result = s


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


proc recordTiming*(n: string, a: int64, b: int64) {.role: helper, metaTags: {tagTiming, tagState}.} =
  ## n: function name.
  ## a: start tick.
  ## b: end tick.
  var
    t: OtterTimingTuple
  if not OtterTimingEnabled:
    return
  ensureOtterHook()
  ensureOtterLock()
  t.functionName = n
  t.startTick = a
  t.endTick = b
  acquire(gOtterLock)
  gOtterMemory.entries.add(t)
  gOtterMemory.flushed = false
  release(gOtterLock)


proc flushTimingLog*() {.role: dataWriter, metaTags: {tagLogging, tagTiming}.} =
  var
    p: string = ""
    A: seq[OtterTimingTuple] = @[]
    lines: seq[string] = @[]
  if not OtterTimingEnabled:
    return
  ensureOtterLock()
  acquire(gOtterLock)
  ensureOtterDefaults()
  p = gOtterMemory.logPath
  A = gOtterMemory.entries
  gOtterMemory.flushed = true
  release(gOtterLock)
  ensureLogDir(p)
  lines.add("otter_timing_log")
  lines.add("generated_at=" & otterIsoTimestamp())
  lines.add("entries=" & $A.len)
  for t in A:
    lines.add(formatTimingEntry(t))
  writeFile(p, lines.join("\n") & "\n")
