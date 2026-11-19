## ============================================================
## | Door findings tests                                       |
## | -> a bad and a good sample for each of the five rules     |
## ============================================================
##
##   rule            bad sample (flagged)           good sample (silent)
##   --------------  -----------------------------  ---------------------------------
##   OUTSIDE NUMBER  newSeq(n), loop to m = n*2     refusing `if`, `bounded`, `min`,
##                                                  an allowed site with a reason
##   OPEN DOOR       var Slots, no Admitted;        takes Admitted; `door` routine
##                   admit() outside a door
##   RE-READ         checked, then original used;   one parse, one use
##                   two parsers on one text
##   SECRET BRANCH   tag == expectedTag; a loop     constantTimeEqual; `.len == 32`
##                   over a secret that returns
##   NO DEADLINE     recv(512), waitForExit()       recv(512, timeoutMs), waitForExit(2000)

import std/[os, sets, strutils, unittest]

import otter_repo_evaluation
import ../../src/protocols/code_stats/doors
import ../../src/protocols/code_stats/doors_text

const
  sample = """
## sample for the door findings
import protocols/intake/admitted

type
  Slots* {.role: truthState, tag: "doored".} = object
    n: int

proc decodeBad(A: openArray[byte]): seq[int] {.role: parser.} =
  var
    n: int = readU16(A, 0)
  result = newSeq[int](n)

proc loopBad(A: openArray[byte]) {.role: parser.} =
  var
    n: int = readU32Le(A, 0)
    m: int = n * 2
  for i in 0 ..< m:
    discard i

proc decodeGuarded(A: openArray[byte]): seq[int] {.role: parser.} =
  var
    n: int = readU16(A, 0)
  if n > 1000:
    return @[]
  result = newSeq[int](n)

proc decodeBounded(A: openArray[byte]): seq[int] {.role: parser.} =
  var
    c: BoundedResult = bounded(readU16(A, 0), entryLimit)
  if not c.ok:
    return @[]
  result = boundedSeq[int](c.value)

proc decodeMin(A: openArray[byte]): seq[int] {.role: parser.} =
  var
    n: int = min(readU16(A, 0), 100)
  result = newSeq[int](n)

proc decodeAllowed(A: openArray[byte]): seq[int] {.role: parser.} =
  var
    n: int = readU16(A, 0)
  # otter: door number a datagram is 1200 bytes, so 600 entries at most
  result = newSeq[int](n)

proc addRow(S: var Slots, key: string) {.role: actor.} =
  S.n = S.n + 1

proc addRowSafe(S: var Slots, key: string, a: Admitted) {.role: actor.} =
  S.n = S.n + 1

proc checkAndAdmit(w: Who, nowMs: uint64): Admitted {.role: actor, tag: "door".} =
  result = admit(w, prKey, nowMs)

proc sneak(w: Who): Admitted {.role: actor.} =
  result = admit(w, prKey, 1'u64)

proc loadBad(p: string): string {.role: sanitizer.} =
  if not isSafePath(p):
    return ""
  result = readFile(p)

proc twoParsers(s: string): int {.role: parser.} =
  var
    h: int = parseHeader(s)
    b: int = parseBody(s)
  result = h + b

proc oneParse(s: string): int {.role: parser.} =
  var
    h: int = parseHeader(s)
  result = h

proc badCompare(tag, expectedTag: seq[byte]): bool {.role: parser.} =
  result = tag == expectedTag

proc badLoop(secret: seq[byte]): bool {.role: parser.} =
  result = true
  for b in secret:
    if b == 0'u8:
      return false

proc okCompare(tag, other: seq[byte]): bool {.role: parser.} =
  result = constantTimeEqual(tag, other)

proc okLength(key: seq[byte]): bool {.role: parser.} =
  result = key.len == 32

proc badWait(s: Socket): string {.role: dataFetcher.} =
  result = s.recv(512)

proc goodWait(s: Socket, timeoutMs: int): string {.role: dataFetcher.} =
  result = s.recv(512, timeoutMs)

proc posixWait(fd: cint): int {.role: dataFetcher.} =
  result = recv(fd, addr buf[0], 16, 0)

proc literalWait(s: Socket): string {.role: dataFetcher.} =
  result = s.recv(512, 500)

proc literalConnect(s: Socket, h: string, p: int) {.role: actor.} =
  s.connect(h, Port(p), 1000)

proc badExit(p: Process): int {.role: actor.} =
  result = p.waitForExit()

proc goodExit(p: Process): int {.role: actor.} =
  result = p.waitForExit(2000)
"""

proc flaggedBy(r: DoorReport, k: DoorKind): HashSet[string] =
  ## r/k: the names of the routines the report lists under one kind.
  result = initHashSet[string]()
  for f in r.findings:
    if f.kind == k:
      result.incl(f.routine)

suite "door findings":
  var
    root: string = joinPath(getCurrentDir(), "build", "test_doors_repo")
    r: DoorReport = default(DoorReport)

  # {.testKind: tkIntegration, covers: "doorReport".}
  setup:
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    writeFile(joinPath(root, "src", "sample.nim"), sample)
    r = doorReport(analyzeRepo(root), root)

  # {.testKind: tkUnit, covers: "checkNumbers".}
  test "OUTSIDE NUMBER names the unchecked sinks and nothing else":
    check flaggedBy(r, dkNumber) == toHashSet(["decodeBad", "loopBad"])

  # {.testKind: tkUnit, covers: "checkNumbers".}
  test "a site with a written reason is counted, not listed":
    check r.allowed == 1
    check "decodeAllowed" notin flaggedBy(r, dkNumber)

  # {.testKind: tkUnit, covers: "checkOpenDoor".}
  test "OPEN DOOR: a doored table without Admitted, and admit() outside a door":
    check flaggedBy(r, dkOpenDoor) == toHashSet(["addRow", "sneak"])
    check r.dooredTypes == @["Slots"]

  # {.testKind: tkUnit, covers: "checkReread".}
  test "RE-READ: a text checked and then used as it was; two readers of one buffer are not it":
    check flaggedBy(r, dkReread) == toHashSet(["loadBad"])

  # {.testKind: tkUnit, covers: "checkSecret".}
  test "SECRET BRANCH: == on a tag, and a loop over a secret that returns":
    check flaggedBy(r, dkSecret) == toHashSet(["badCompare", "badLoop"])

  # {.testKind: tkUnit, covers: "checkDeadline".}
  test "NO DEADLINE: a wait that names no time; a literal timeout in connect and recv counts":
    check flaggedBy(r, dkDeadline) == toHashSet(["badWait", "badExit", "posixWait"])

  # {.testKind: tkUnit, covers: "doorLines".}
  test "the report says what, where and why, one heading per kind":
    var
      L: string = doorLines(r).join("\n")
    check "OUTSIDE NUMBER — 2 place(s)." in L
    check "sample.nim:" in L
    check "reaches newSeq with no limit" in L

suite "door text reading":

  # {.testKind: tkEdgeCase, covers: "lineCode".}
  test "a comment and the inside of a string are not code":
    check lineCode("n = f(1) # recv(2)").strip() == "n = f(1)"
    check "recv" notin lineCode("raise newException(E, \"recv() failed\")")

  # {.testKind: tkUnit, covers: "callsOf".}
  test "calls carry their name, arguments and receiver":
    var
      C: seq[Call] = callsOf("x = newSeq[byte](n * 4) + s.recv(512)")
    check C.len == 2
    check C[0].name == "newSeq"
    check C[0].args == "n * 4"
    check C[1].name == "recv"
    check C[1].recv == "s"
