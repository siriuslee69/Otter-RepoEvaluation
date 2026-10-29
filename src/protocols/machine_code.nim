## ============================================================
## | Otter Machine Code Root -> the `ct` check                |
## | -> are our constant-time routines really constant-time?  |
## ============================================================
##
##   import otter_repo_evaluation/protocols/machine_code
##   var r: CtReport = ctCheck("src/tyr.nim", @[])
##   for line in ctLines(r):
##     echo line
##
## The steps, from a .nim file to the findings:
##
##   file.nim ──nim c -d:release --debugger:native──> binary
##      │                                               │
##      │ secret: "a|b" pragmas                         │ objdump.nim
##      ▼                                               ▼
##   RoutineSpec  (name, which parameters)          Routine (instructions)
##      └───────────────────┬───────────────────────────┘
##                          ▼  matched by Nim name
##                       taint.nim  ──>  findings, each with a trail
##
## A routine is named on the command line as `--routine:name:args`, one
## word per parameter, in order:
##
##   ┌──────┬──────────────────────────────────────┬──────────────┐
##   │ word │ the parameter is                     │ registers    │
##   ├──────┼──────────────────────────────────────┼──────────────┤
##   │ s  p │ a number (secret / public)           │ 1            │
##   │ s[]  │ an openArray                         │ ptr, then len│
##   │ s@   │ a seq or string                      │ len, then ptr│
##   │ s*   │ var, ptr, array, object              │ 1 (address)  │
##   │ sf   │ a float                              │ 1 xmm        │
##   └──────┴──────────────────────────────────────┴──────────────┘
##
##   --routine:constantTimeEqual:s[],s[]      both openArrays secret
##   --routine:sboxCt:s                       the one byte is secret
##   --routine:aes_core.init:p*,s[]           only aes_core's `init`
##
## The `secret: "a|b"` pragma says the same from inside the source; the
## parameter types are read from the signature. A --routine flag wins
## over a pragma for the same name.

import std/[json, os, sequtils, strutils, tables]

import runePragmas
import ./fylgia_threads
import ./machine_code/objdump
import ./machine_code/taint
import ./machine_code/census

export objdump
export taint
export census

type
  CtReport* {.role: truthState, expectedCount: 1, lifeCycle: lcJob.} = object
    target*: string                 ## what was handed in
    binary*: string                 ## the binary that was read
    results*: seq[RoutineResult]
    censuses*: seq[BranchCensus]    ## one per result, same order
    warnings*: seq[string]
    error*: string

const
  ctFlags*: string = "-d:release --debugger:native"
    ## the shipped build, plus source lines for the report
  noInlineFlag*: string = "--passC:-fno-inline"
    ## with --noinline: every routine stays its own symbol, so a small
    ## {.inline.} helper such as sboxCt can be checked on its own

# ---- naming the secret parameters --------------------------------------------

proc kindOfWord(w: string): tuple[ok: bool, p: ParamSpec] {.role: parser,
    tag: "machineCode".} =
  ## w: one word of a --routine flag, "s[]". See the table at the top.
  var
    t: string = w.strip()
  result = (ok: true, p: ParamSpec(name: "#" & t, secret: t.startsWith("s")))
  if t.len == 0 or t[0] notin {'s', 'p'}:
    return (ok: false, p: ParamSpec())
  case t[1 .. ^1]
  of "": result.p.kind = pkScalar
  of "[]": result.p.kind = pkOpenArray
  of "@": result.p.kind = pkLenFirst
  of "*": result.p.kind = pkPointer
  of "f": result.p.kind = pkFloat
  else: result.ok = false

proc parseRoutineFlag*(s: string): tuple[ok: bool, spec: RoutineSpec,
    error: string] {.role: parser, tag: "machineCode".} =
  ## s: what follows `--routine:`, "constantTimeEqual:s[],s[]".
  var
    P: seq[string] = s.split(':')
    got: tuple[ok: bool, p: ParamSpec] = (false, ParamSpec())
    k: int = 0
  result = (ok: false, spec: RoutineSpec(origin: "--routine"), error: "")
  if P.len != 2 or P[0].len == 0:
    result.error = "--routine wants name:args, for example sboxCt:s"
    return
  result.spec.name = P[0]
  for w in P[1].split(','):
    got = kindOfWord(w)
    if not got.ok:
      result.error = "--routine: `" & w & "` is not one of s p s[] p[] s@ p@ s* p* sf pf"
      return
    got.p.name = "#" & $k & " (" & w.strip() & ")"
    result.spec.params.add(got.p)
    k = k + 1
  result.ok = true

proc kindOfType*(t: string): ParamKind {.role: parser, tag: "machineCode".} =
  ## t: a Nim parameter type. How it lands in the registers (top table).
  ## An object type is taken to be passed by address; when it is small
  ## enough to travel by value, name it with --routine instead.
  var
    x: string = t.strip()
  if x.startsWith("var ") and not x.contains("openArray"): return pkPointer
  if x.contains("openArray") or x.startsWith("varargs"): return pkOpenArray
  if x.startsWith("seq[") or x == "string": return pkLenFirst
  if x.startsWith("float"): return pkFloat
  if x.startsWith("int") or x.startsWith("uint") or
      x in ["byte", "char", "bool", "Natural", "Positive"]:
    return pkScalar
  result = pkPointer

proc paramsOf*(s: string): seq[ParamSpec] {.role: parser,
    tag: "machineCode".} =
  ## s: the text between a routine's ( ). Every parameter, in order:
  ##
  ##   "a, b: openArray[byte]; k: int = 0"  ->  a [], b [], k scalar
  var
    depth: int = 0
    cur: string = ""
    I: seq[string] = @[]
    waiting: seq[string] = @[]
    nameAndType: seq[string] = @[]
  result = @[]
  for c in s & ",":
    if c in {'[', '('}: depth = depth + 1
    if c in {']', ')'}: depth = depth - 1
    if c in {',', ';'} and depth == 0:
      I.add(cur.strip())
      cur = ""
    else:
      cur.add(c)
  for item in I:
    nameAndType = item.split('=')[0].split(':')
    waiting.add(nameAndType[0].strip())
    if nameAndType.len < 2:
      continue
    for n in waiting:
      result.add(ParamSpec(name: n, kind: kindOfType(nameAndType[1])))
    waiting = @[]

proc headerAt(text: string, at: int): tuple[ok: bool, start: int] {.
    role: parser, tag: "machineCode".} =
  ## text: a source file   at: where `secret:` was found. Where the
  ## routine it belongs to starts: the nearest `proc ` / `func ` above,
  ## with no `=` closing a body in between.
  var
    i: int = at
    P: array[3, string] = ["proc ", "func ", "method "]
  result = (ok: false, start: 0)
  while i >= 0 and not (text[i] == '=' and i + 1 < text.len and text[i + 1] == '\n'):
    for p in P:
      if text.continuesWith(p, i) and (i == 0 or text[i - 1] in {'\n', ' '}):
        return (ok: true, start: i)
    i = i - 1

proc specAt(text, file: string, at: int): tuple[ok: bool, spec: RoutineSpec] {.
    role: parser, tag: "machineCode".} =
  ## text: a source file   file: its path   at: where `secret:` was found.
  ## The routine's name and parameters, with the named ones made secret.
  var
    h: tuple[ok: bool, start: int] = headerAt(text, at)
    a: int = 0
    b: int = 0
    q0: int = text.find('"', at)
    q1: int = 0
    names: seq[string] = @[]
    k: int = 0
  result = (ok: false, spec: RoutineSpec())
  if not h.ok or q0 < 0:
    return
  q1 = text.find('"', q0 + 1)
  a = text.find('(', h.start)
  b = text.find("):", a)
  if a < 0 or b < 0 or a > at:
    return
  for n in text[q0 + 1 ..< q1].split({'|', ',', ';'}):
    names.add(n.strip())
  result.spec.name = text[h.start ..< a].splitWhitespace()[1].strip(chars = {'*', '`'})
  result.spec.params = paramsOf(text[a + 1 ..< b])
  result.spec.origin = "secret: pragma, " & extractFilename(file) & ":" &
    $(text[0 ..< at].count('\n') + 1)
  while k < result.spec.params.len:
    result.spec.params[k].secret = result.spec.params[k].name in names
    k = k + 1
  result.ok = true

proc specsFromSource*(text, file: string): seq[RoutineSpec] {.role: parser,
    tag: "machineCode".} =
  ## text: one .nim file   file: its path. Every routine in it that
  ## carries a `secret: "..."` pragma.
  var
    i: int = text.find("secret:")
    got: tuple[ok: bool, spec: RoutineSpec] = (false, RoutineSpec())
  result = @[]
  while i >= 0:
    got = specAt(text, file, i)
    if got.ok: result.add(got.spec)
    i = text.find("secret:", i + 1)

proc repoRootOf(file: string): string {.role: helper, tag: "machineCode".} =
  ## file: a .nim file. The nearest folder above it holding a .nimble
  ## file, or the file's own folder.
  var
    d: string = file.absolutePath().parentDir()
  result = file.absolutePath().parentDir()
  while d.len > 1:
    for _ in walkFiles(d / "*.nimble"):
      return d
    d = d.parentDir()

proc scanSpecs*(file: string): seq[RoutineSpec] {.role: dataFetcher,
    tag: "machineCode".} =
  ## file: the .nim file to be compiled. `secret:` routines in it and in
  ## every .nim file under its repository's src/ folder.
  var
    root: string = repoRootOf(file)
    F: seq[string] = @[file.absolutePath()]
  if dirExists(root / "src"):
    for f in walkDirRec(root / "src"):
      if f.endsWith(".nim") and f notin F: F.add(f)
  result = @[]
  for f in F:
    result.add(specsFromSource(readFile(f), f))

proc mergeSpecs(A, B: seq[RoutineSpec]): seq[RoutineSpec] {.role: helper,
    tag: "machineCode".} =
  ## A: from pragmas   B: from --routine flags. B wins on the same name.
  result = B
  for a in A:
    if not B.anyIt(it.name == a.name): result.add(a)

# ---- which source routine a line belongs to ----------------------------------
#
# With inlining on, a small routine has no symbol of its own: its
# instructions sit inside its callers. Their source lines still point
# at it, so the line is what tells them apart:
#
#   encryptBlock  0x6207  and al, BYTE PTR [r8+rdx*1]  (aes_blocks.nim:19)
#                                                       └─ inside sboxCt
#
# LineOwners holds, for each source file read so far, the routine every
# line sits in: the nearest proc/func/iterator/template header above it.

type
  LineOwners = Table[string, seq[string]]  ## file -> routine name per line

const
  headerWords: array[6, string] = ["proc ", "func ", "method ", "iterator ",
    "template ", "converter "]

proc headerName(s: string): string {.role: parser, tag: "machineCode".} =
  ## s: one source line. The routine it starts, or "".
  var
    t: string = s.strip()
  result = ""
  for w in headerWords:
    if t.startsWith(w):
      return t[w.len .. ^1].split({'*', '(', '[', ' ', ':', '='})[0].strip(chars = {'`'})

proc ownerOf(O: var LineOwners, file: string, line: int): string {.
    role: parser, tag: "machineCode".} =
  ## O: the cache   file, line: a source position. The routine it sits
  ## in, or "" when the file cannot be read.
  var
    L: seq[string] = @[]
    cur: string = ""
  if file notin O:
    if fileExists(file):
      for s in readFile(file).splitLines():
        if headerName(s).len > 0: cur = headerName(s)
        L.add(cur)
    O[file] = L
  if line < 1 or line > O[file].len:
    return ""
  result = O[file][line - 1]

proc markInlined(O: var LineOwners, x: var RoutineResult) {.role: actor,
    tag: "machineCode".} =
  ## x: one checked routine. Each finding learns which source routine its
  ## line sits in, when that is not the routine itself.
  var
    k: int = 0
    o: string = ""
  while k < x.findings.len:
    o = ownerOf(O, x.findings[k].file, x.findings[k].line)
    if o.len > 0 and o != x.spec.name: x.findings[k].inlinedFrom = o
    k = k + 1

proc inlinedInto(O: var LineOwners, R: seq[Routine], name: string): seq[string] {.
    role: parser, tag: "machineCode".} =
  ## R: every routine of the binary   name: a routine with no symbol.
  ## The routines that carry its lines, so their callers can be checked.
  result = @[]
  for r in R:
    if r.baseName in result: continue
    for I in r.instrs:
      if I.line > 0 and ownerOf(O, I.file, I.line) == name:
        result.add(r.baseName)
        break

# ---- building and reading -----------------------------------------------------

proc compileForCt*(file: string, noInline: bool = false): tuple[bin,
    error: string] {.role: dataWriter, tag: "machineCode".} =
  ## file: a .nim file   noInline: keep every routine as its own symbol.
  ## Builds it the way it ships, with source lines kept, into the temp
  ## folder. Run from the file's own folder so its config.nims applies.
  var
    dir: string = getTempDir() / "otter-ct" / file.splitFile().name
    o: tuple[output: string, exitCode: int] = ("", 0)
    flags: string = ctFlags
  if noInline: flags = flags & " " & noInlineFlag
  createDir(dir)
  result = (bin: dir / file.splitFile().name, error: "")
  o = execCmdShared("nim c --hints:off " & flags & " --nimcache:" &
    quoteShell(dir / "nimcache") & " -o:" & quoteShell(result.bin) & " " &
    quoteShell(file.absolutePath()), workingDir = file.absolutePath().parentDir())
  if o.exitCode != 0:
    result.error = "compiling " & file & " failed:\n" & o.output.strip()

proc nameMatches(r: Routine, name: string): bool {.inline, role: parser,
    tag: "machineCode".} =
  ## r: a routine of the binary   name: "init", or "aes_core.init" to
  ## leave out every other module's `init` (system has one too).
  var
    P: seq[string] = name.rsplit('.', maxsplit = 1)
  if P.len == 1:
    return r.baseName == name
  result = r.baseName == P[1] and (r.module == P[0] or r.module.endsWith("." & P[0]))

proc missingWarning(O: var LineOwners, R: seq[Routine], s: RoutineSpec): string {.
    role: parser, tag: "machineCode".} =
  ## s: a routine with no symbol. Where it went, as one warning line.
  var
    A: seq[string] = inlinedInto(O, R, s.name.rsplit('.', maxsplit = 1)[^1])
  result = "`" & s.name & "` (" & s.origin & ") has no symbol in the binary"
  if A.len == 0:
    return result & ": never called, or no source lines to follow"
  result = result & ": inlined into " & A.join(", ") &
    " - check those with their secret parameters, or use --noinline"

proc checkSpecs(R: seq[Routine], S: seq[RoutineSpec],
    rep: var CtReport) {.role: orchestrator, tag: "machineCode".} =
  ## R: the binary's routines   S: what to check. Every routine whose Nim
  ## name matches is checked; a name with no match is a warning. The
  ## ".cold" pieces gcc splits off a routine are left out: they start in
  ## the middle and receive no arguments.
  var
    hit: bool = false
    F: Flows = newFlows(R)
    O: LineOwners = initTable[string, seq[string]]()
    SC: SourceCache = initTable[string, seq[string]]()
  for s in S:
    hit = false
    for r in R:
      if not nameMatches(r, s.name) or r.name.contains(".cold"): continue
      rep.results.add(checkRoutine(r, s, F))
      markInlined(O, rep.results[^1])
      rep.censuses.add(censusOf(r, rep.results[^1], SC))
      hit = true
    if not hit: rep.warnings.add(missingWarning(O, R, s))

proc ctCheck*(target: string, flagSpecs: seq[RoutineSpec],
    noInline: bool = false): CtReport {.role: metaOrchestrator,
    tag: "machineCode".} =
  ## target: a binary, or a .nim file to compile first   flagSpecs: the
  ## --routine flags   noInline: build with inlining off (a .nim only).
  var
    S: seq[RoutineSpec] = flagSpecs
    c: tuple[bin, error: string] = (target, "")
    d: tuple[R: seq[Routine], error: string] = (@[], "")
  result = CtReport(target: target, binary: target)
  if not fileExists(target):
    result.error = "no such file: " & target
    return
  if target.endsWith(".nim"):
    S = mergeSpecs(scanSpecs(target), flagSpecs)
    c = compileForCt(target, noInline)
    result.binary = c.bin
  if c.error.len > 0:
    result.error = c.error
    return
  if S.len == 0:
    result.error = "nothing to check: give --routine:name:args, or mark a routine with secret: \"a|b\""
    return
  d = disassemble(result.binary)
  result.error = d.error
  checkSpecs(d.R, S, result)

# ---- answers ---------------------------------------------------------------

proc findingCount*(r: CtReport): int {.role: parser, tag: "machineCode".} =
  result = 0
  for x in r.results: result = result + x.findings.len

const
  kindWords: array[FindingKind, string] = ["BRANCH ", "ADDRESS", "DIVIDE "]

proc resultLines(x: RoutineResult): seq[string] {.role: actor,
    tag: "machineCode".} =
  ## x: one checked routine. Its block of the text report.
  result = @[]
  result.add((if x.findings.len == 0: "CLEAN  " else: "LEAKS  ") & x.spec.name &
    "  [" & x.symbol & "]  " & $x.instrCount & " instructions, " &
    $x.findings.len & " finding(s)")
  for f in x.findings:
    result.add("  " & kindWords[f.kind] & "  0x" & hexOf(f.address) & "  " &
      f.text & "  (" & extractFilename(f.file) & ":" & $f.line & ")")
    if f.inlinedFrom.len > 0: result[^1].add("  inlined from " & f.inlinedFrom)
    for t in f.trail: result.add("             " & t)
  if x.unknown > 0:
    result.add("  " & $x.unknown & " instruction(s) not in the table, read cautiously: " &
      x.unknownNames.join(", "))
  for n in x.notes: result.add("  note: " & n)

proc ctLines*(r: CtReport): seq[string] {.role: actor, tag: "machineCode".} =
  ## r: a report. What a person reads.
  result = @["Otter ct  " & r.binary]
  if r.error.len > 0:
    result.add("error: " & r.error)
  for w in r.warnings: result.add("warning: " & w)
  for k, x in r.results:
    result.add(resultLines(x))
    if k < r.censuses.len: result.add(censusLines(r.censuses[k]))
  result.add($r.results.len & " routine(s) checked, " & $findingCount(r) &
    " finding(s)")

proc ctJson*(r: CtReport): JsonNode {.role: actor, tag: "machineCode".} =
  ## r: a report. The same as ctLines, for a program to read.
  result = %*{"target": r.target, "binary": r.binary, "error": r.error,
    "warnings": r.warnings, "findings": findingCount(r), "routines": []}
  for k, x in r.results:
    result["routines"].add(%*{"census": (if k < r.censuses.len: %r.censuses[k] else: newJNull()),"name": x.spec.name, "symbol": x.symbol,
      "origin": x.spec.origin, "instructions": x.instrCount,
      "blocks": x.blockCount, "unknown": x.unknown,
      "unknownNames": x.unknownNames, "notes": x.notes,
      "findings": x.findings.mapIt(%*{"kind": $it.kind,
        "address": "0x" & hexOf(it.address), "text": it.text,
        "file": it.file, "line": it.line, "inlinedFrom": it.inlinedFrom, "trail": it.trail})})
