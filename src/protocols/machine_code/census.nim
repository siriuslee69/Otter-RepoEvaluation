# ============================================================
# | Otter Machine Code -> branch census                      |
# | -> jumps in the machine code vs branches in the Nim      |
# ============================================================
#
# A quick count beside the forward search, line by line:
#
#   source line                          Nim branches   jumps
#   ───────────────────────────────────  ────────────   ─────
#   aes_blocks.nim:17  while i < 256:          1           1    as written
#   aes_blocks.nim:19  acc = acc or ...        0           2    ADDED
#
# A line with jumps but no branch word in the Nim means the compiler put
# them there. Most such jumps are harmless:
#
#   a[i]          bounds check (is i inside a?)        - i is usually public
#   f(x)          Nim's error check after a call       - public
#   a loop        copies of the loop test when the loop is unrolled
#
# So the count is a pointer to where to look, not a verdict: the
# forward search (taint.nim) decides whether a jump depends on a secret.
# An added jump the search also flagged is marked SECRET.
#
# Nim "branch words": if elif while for case of and or try except.
# `else` is not counted: it adds no test of its own.

import std/[os, strutils, tables]

import runePragmas
import ./objdump
import ./taint

type
  AddedLine* = object
    ## One source line with jumps but no branch in the Nim.
    file*: string
    line*: int
    jumps*: int
    hint*: string        ## likely reason, "" when none is guessed
    secret*: bool        ## the forward search flagged a jump here

  BranchCensus* {.role: truthState,
      expectedCount: [0, 1000], lifeCycle: lcJob.} = object
    nimBranches*: int    ## branch words on the lines the routine touches
    jumps*: int          ## conditional jumps in the machine code
    added*: seq[AddedLine]

  SourceCache* = Table[string, seq[string]]  ## file -> its lines

const
  branchWords: array[10, string] = ["if", "elif", "while", "for", "case",
    "of", "and", "or", "try", "except"]

proc codeOf(s: string): string {.role: sanitizer, tag: "machineCode".} =
  ## s: one source line. The line with string contents and the comment
  ## removed, so `"if"` and `# or` are not counted.
  var
    inStr: bool = false
  result = ""
  for c in s:
    if c == '"': inStr = not inStr
    if c == '#' and not inStr: return
    if not inStr: result.add(c)

proc branchWordsIn*(s: string): int {.role: parser, tag: "machineCode".} =
  ## s: one source line. How many branch words it holds:
  ##
  ##   "while i < n and a[i] != 0:"  ->  2   (while, and)
  ##   "x = y or z  # if not"        ->  1   (or; the comment is skipped)
  result = 0
  for w in codeOf(s).split({' ', '(', ')', ':', ',', '[', ']', '\t'}):
    if w in branchWords: result = result + 1

proc sourceLine(C: var SourceCache, file: string, line: int): string {.
    role: dataFetcher, tag: "machineCode".} =
  ## C: lines read so far   file, line: a source position. Its text.
  if file notin C:
    C[file] = (if fileExists(file): readFile(file).splitLines() else: @[])
  if line < 1 or line > C[file].len:
    return ""
  result = C[file][line - 1]

proc hintFor(s: string): string {.role: parser, tag: "machineCode".} =
  ## s: a source line with added jumps. The likely reason.
  var
    t: string = codeOf(s)
  result = ""
  if t.contains('['): return "indexing: bounds check"
  if t.contains('('): return "call: Nim's error check"
  if t.strip().startsWith("raise"): return "raise"

proc isJump(I: Instr): bool {.inline, role: helper, tag: "machineCode".} =
  result = I.mnemonic.startsWith("j") and I.mnemonic != "jmp"

proc censusOf*(r: Routine, x: RoutineResult, C: var SourceCache): BranchCensus {.
    role: truthBuilder, tag: "machineCode".} =
  ## r: a checked routine   x: its result   C: the source cache. Jumps
  ## and Nim branch words per line, and the lines where they disagree.
  var
    J: OrderedTable[string, AddedLine] = initOrderedTable[string, AddedLine]()
    key: string = ""
    s: string = ""
  result = BranchCensus()
  for I in r.instrs:
    if I.line == 0: continue
    key = I.file & ":" & $I.line
    if key notin J:
      J[key] = AddedLine(file: I.file, line: I.line)
      result.nimBranches = result.nimBranches + branchWordsIn(sourceLine(C, I.file, I.line))
    if isJump(I):
      J[key].jumps = J[key].jumps + 1
      result.jumps = result.jumps + 1
  for f in x.findings:
    key = f.file & ":" & $f.line
    if key in J and f.kind == fkBranch: J[key].secret = true
  for k, a in J:
    s = sourceLine(C, a.file, a.line)
    if a.jumps == 0 or branchWordsIn(s) > 0: continue
    result.added.add(a)
    result.added[^1].hint = hintFor(s)

proc censusLines*(c: BranchCensus): seq[string] {.role: actor,
    tag: "machineCode".} =
  ## c: one routine's census. Its lines of the text report.
  var
    n: int = 0
  for a in c.added: n = n + a.jumps
  result = @["  branches: " & $c.nimBranches & " in the Nim lines, " & $c.jumps &
    " jump(s) in the machine code, " & $n & " on " & $c.added.len &
    " line(s) with no branch in the Nim"]
  for a in c.added:
    result.add("    " & (if a.secret: "SECRET " else: "added  ") &
      extractFilename(a.file) & ":" & $a.line & "  " & $a.jumps & " jump(s)" &
      (if a.hint.len > 0: "  - " & a.hint else: ""))
