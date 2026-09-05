# ============================================================
# | Otter Timing State                                      |
# | -> Store timing tuples and flush them to disk           |
# ============================================================

import std/[exitprocs, locks, os, strutils]

import ../../meta/metaPragmas
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

# ------------------------------------------------------------
# The log is written from an exit hook, and by then Nim has already
# torn down this module's own globals: the entry sequence still has
# its length but every string in it has been emptied, so the log came
# out as a column of blank rows.
#
#   recordTiming ─► gOtterMemory.entries   read by this program
#                └─ gOtterText             read by the exit hook
#
# The second copy is a flat block this module allocates itself and
# never frees. Nothing owns it, so nothing can empty it early. A plain
# array holds the path for the same reason.
# ------------------------------------------------------------
var
  gOtterText: ptr UncheckedArray[char] = nil
  gOtterTextLen: int = 0
  gOtterTextCap: int = 0
  gOtterCount: int = 0
  gOtterPath: array[4096, char]
  gOtterPathLen: int = 0


proc flushTimingLog*() {.role: dataWriter, metaTags: {tagLogging, tagTiming}.}


proc keepText(s: string) {.role: dataWriter, metaTags: {tagLogging, tagState}.} =
  ## s: one finished log line, kept where the exit hook can still read
  ## it. The block doubles when it fills and is never given back.
  var
    need: int = gOtterTextLen + s.len
    grown: int = 0
  if s.len == 0:
    return
  if need > gOtterTextCap:
    grown = max(4096, need * 2)
    gOtterText = cast[ptr UncheckedArray[char]](reallocShared(gOtterText, grown))
    gOtterTextCap = grown
  copyMem(addr gOtterText[gOtterTextLen], unsafeAddr s[0], s.len)
  gOtterTextLen = need


proc keptText(): string {.role: dataFetcher, metaTags: {tagLogging, tagState}.} =
  ## Everything recorded so far, as one block of text.
  result = newString(gOtterTextLen)
  if gOtterTextLen > 0:
    copyMem(addr result[0], addr gOtterText[0], gOtterTextLen)


proc keepPath(p: string) {.role: dataWriter, metaTags: {tagLogging, tagState}.} =
  ## p: where the log goes, copied into a plain array so the exit hook
  ## still knows it.
  gOtterPathLen = min(p.len, gOtterPath.len)
  if gOtterPathLen > 0:
    copyMem(addr gOtterPath[0], unsafeAddr p[0], gOtterPathLen)


proc keptPath(): string {.role: dataFetcher, metaTags: {tagLogging, tagState}.} =
  ## Where the log goes. Empty until something set it.
  result = newString(gOtterPathLen)
  if gOtterPathLen > 0:
    copyMem(addr result[0], addr gOtterPath[0], gOtterPathLen)


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
  keepPath(p)
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
  gOtterTextLen = 0
  gOtterCount = 0
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
  keepText(formatTimingEntry(t) & "\n")
  gOtterCount = gOtterCount + 1
  gOtterMemory.flushed = false
  release(gOtterLock)


proc flushTimingLog*() {.role: dataWriter, metaTags: {tagLogging, tagTiming}.} =
  var
    alreadyFlushed: bool = false
    p: string = ""
    body: string = ""
    n: int = 0
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
  if gOtterPathLen == 0:
    keepPath(gOtterMemory.logPath)
  p = keptPath()
  body = keptText()
  n = gOtterCount
  gOtterMemory.flushed = true
  release(gOtterLock)
  ensureLogDir(p)
  lines.add("otter_timing_log")
  lines.add("generated_at=" & isoTimestamp())
  lines.add("entries=" & $n)
  writeFile(p, lines.join("\n") & "\n" & body)
