## ============================================================
## | Otter Machine Code -> objdump reader                     |
## | -> one binary in, its routines and instructions out      |
## ============================================================
##
## objdump is the program that turns machine code back into text. Asked
## with `-d -M intel --no-show-raw-insn -l`, it prints:
##
##   000000000000be60 <_ZN1s9earlyExitE9openArrayI5uInt8E...>:   <- routine
##   _ZN1s9earlyExitE9openArrayI5uInt8E...():                    <- ignored
##   /home/me/s.nim:10 (discriminator 6)                          <- source line
##       be89:	movzx  ecx,BYTE PTR [rdx+rax*1]                    <- instruction
##       be90:	je     be80 <_ZN1s9earlyExit...+0x20>              <- jump
##
## and this file turns that into:
##
##   Routine  name      "_ZN1s9earlyExitE9openArray..."   (as in the binary)
##            baseName  "earlyExit"                       (as in the .nim)
##            module    "s"
##            instrs    ┌─────────┬──────────┬──────────────────────┬────────┬──────┐
##                      │ address │ mnemonic │ operands             │ target │ line │
##                      ├─────────┼──────────┼──────────────────────┼────────┼──────┤
##                      │ 0xbe89  │ movzx    │ ecx | BYTE PTR [..]  │ -      │ 10   │
##                      │ 0xbe90  │ je       │ be80 <..+0x20>       │ 0xbe80 │ 10   │
##                      └─────────┴──────────┴──────────────────────┴────────┴──────┘
##
## A "mnemonic" is the short name of an instruction (mov, add, je).
## "Operands" are the things it works on, written after it.

import std/[os, osproc, strutils]

import runePragmas
import ../fylgia_threads

type
  Instr* {.role: preparedData,
      expectedCount: [0, 2_000_000], lifeCycle: lcJob.} = object
    ## One machine instruction as objdump printed it.
    address*: uint64        ## where it sits in the binary
    mnemonic*: string       ## "mov", "je", ... without prefixes
    operands*: seq[string]  ## split at the commas, "# comment" removed
    target*: uint64         ## where a jump or call goes
    hasTarget*: bool        ## false for everything but direct jumps/calls
    file*: string           ## source file of the line, "" when unknown
    line*: int              ## source line, 0 when unknown

  Routine* {.role: preparedData,
      expectedCount: [0, 100_000], lifeCycle: lcJob.} = object
    ## One routine of the binary with every instruction inside it.
    name*: string           ## the symbol exactly as in the binary
    baseName*: string       ## the Nim name, "earlyExit"
    module*: string         ## the Nim module, "s"; "" when not encoded
    start*: uint64          ## address of its first instruction
    instrs*: seq[Instr]

const
  ignoredPrefixes: array[13, string] = ["rep", "repz", "repe", "repnz",
    "repne", "lock", "bnd", "notrack", "data16", "cs", "ds", "addr32",
    "es"]

proc digitsEnd(s: string, i: int): int {.inline, role: helper, tag: "machineCode".} =
  ## s: any text   i: where to start. The first place after i that is
  ## not a digit.
  result = i
  while result < s.len and s[result] in Digits:
    result = result + 1

proc nameParts(s: string): seq[string] {.role: parser, tag: "machineCode".} =
  ## s: "_ZN1s9earlyExitE...". The length-prefixed pieces after "_ZN":
  ## @["s", "earlyExit"]. Each piece is its length in digits, then that
  ## many letters; the first letter that is not a digit ends the list.
  var
    i: int = 3
    j: int = 3
  result = @[]
  while i < s.len and s[i] in Digits:
    j = digitsEnd(s, i)
    result.add(s.substr(j, j + parseInt(s[i ..< j]) - 1))
    i = j + parseInt(s[i ..< j])

proc decodeName*(s: string): tuple[baseName, module: string] {.role: parser,
    tag: "machineCode".} =
  ## s: a symbol from the binary. The Nim name hidden in it:
  ##
  ##   _ZN1s9earlyExitE9openArray...   ->  ("earlyExit", "s")
  ##     N  1 "s"  9 "earlyExit"  E        (length, then the letters)
  ##   earlyExit__s_u12                ->  ("earlyExit", "")
  ##   sboxCt.constprop.0              ->  ("sboxCt", "")
  var
    P: seq[string] = @[]
  result = (baseName: s.split('.')[0], module: "")
  if s.startsWith("_ZN"):
    P = nameParts(s)
  if P.len > 0:
    result.baseName = P[^1]
    result.module = P[0 ..< P.len - 1].join(".")
  elif s.find("__") > 0:
    result.baseName = s[0 ..< s.find("__")]

proc splitOperands*(s: string): seq[string] {.role: parser,
    tag: "machineCode".} =
  ## s: everything after the mnemonic. Split at commas that are not
  ## inside [ ], with objdump's "# 404010 <sbox>" note cut off first:
  ##
  ##   "eax,BYTE PTR [rax+rdi*1]"  ->  @["eax", "BYTE PTR [rax+rdi*1]"]
  var
    t: string = s
    depth: int = 0
    cur: string = ""
  result = @[]
  if t.find('#') >= 0:
    t = t[0 ..< t.find('#')]
  for c in t:
    if c == '[': depth = depth + 1
    if c == ']': depth = depth - 1
    if c == ',' and depth == 0:
      result.add(cur.strip())
      cur = ""
    else:
      cur.add(c)
  if cur.strip().len > 0:
    result.add(cur.strip())

proc jumpTarget(I: var Instr) {.role: parser, tag: "machineCode".} =
  ## I: an instruction whose first operand may read "be80 <name+0x20>".
  var
    w: string = ""
  if I.operands.len != 1 or I.operands[0].find('<') < 0:
    return
  w = I.operands[0].split(' ')[0]
  try:
    I.target = uint64(parseHexInt(w))
    I.hasTarget = true
  except ValueError:
    I.hasTarget = false

proc parseInstrLine*(s, file: string, line: int): tuple[ok: bool,
    ins: Instr] {.role: parser, tag: "machineCode".} =
  ## s: "    be89:\tmovzx  ecx,BYTE PTR [rdx+rax*1]"   file, line: the
  ## source line printed above it. ok is false for any other line.
  var
    colon: int = s.find(':')
    a: string = ""
    body: string = ""
    W: seq[string] = @[]
    k: int = 0
  result = (ok: false, ins: Instr())
  if colon < 1 or s.find('\t') < 0:
    return
  a = s[0 ..< colon].strip()
  if a.len == 0 or not a.allCharsInSet(HexDigits):
    return
  body = s[colon + 1 .. ^1].strip()
  W = body.splitWhitespace()
  while k < W.len and (W[k] in ignoredPrefixes or W[k].startsWith("rex")):
    k = k + 1
  if k >= W.len:
    return
  result.ins.address = uint64(parseHexInt(a))
  result.ins.mnemonic = W[k]
  result.ins.operands = splitOperands(W[k + 1 .. ^1].join(" "))
  result.ins.file = file
  result.ins.line = line
  jumpTarget(result.ins)
  result.ok = true

proc parseRoutineHeader(s: string): tuple[ok: bool, r: Routine] {.
    role: parser, tag: "machineCode".} =
  ## s: "000000000000be60 <name>:". ok is false for any other line.
  var
    lt: int = s.find(" <")
    d: tuple[baseName, module: string] = ("", "")
  result = (ok: false, r: Routine())
  if lt < 1 or not s.endsWith(">:") or not s[0 ..< lt].allCharsInSet(HexDigits):
    return
  result.r.name = s[lt + 2 ..< s.len - 2]
  result.r.start = uint64(parseHexInt(s[0 ..< lt]))
  d = decodeName(result.r.name)
  result.r.baseName = d.baseName
  result.r.module = d.module
  result.ok = true

proc parseSourceLine(s: string): tuple[ok: bool, file: string, line: int] {.
    role: parser, tag: "machineCode".} =
  ## s: "/home/me/s.nim:10 (discriminator 6)". ok is false otherwise.
  var
    t: string = s.split(" (")[0]
    c: int = t.rfind(':')
  result = (ok: false, file: "", line: 0)
  if c < 1 or not t.startsWith("/") or not t[c + 1 .. ^1].allCharsInSet(Digits):
    return
  if c + 1 >= t.len:
    return
  result = (ok: true, file: t[0 ..< c], line: parseInt(t[c + 1 .. ^1]))

proc parseObjdump*(text: string): seq[Routine] {.role: truthBuilder,
    tag: "machineCode".} =
  ## text: what objdump printed. Every routine with its instructions, in
  ## the order of the binary.
  var
    h: tuple[ok: bool, r: Routine] = (false, Routine())
    src: tuple[ok: bool, file: string, line: int] = (false, "", 0)
    ins: tuple[ok: bool, ins: Instr] = (false, Instr())
    file: string = ""
    line: int = 0
  result = @[]
  for s in text.splitLines():
    h = parseRoutineHeader(s)
    if h.ok:
      result.add(h.r)
      file = ""
      line = 0
      continue
    src = parseSourceLine(s)
    if src.ok:
      file = src.file
      line = src.line
      continue
    ins = parseInstrLine(s, file, line)
    if ins.ok and result.len > 0:
      result[^1].instrs.add(ins.ins)

proc disassemble*(path: string): tuple[R: seq[Routine], error: string] {.
    role: dataFetcher, tag: "machineCode".} =
  ## path: a binary. Runs the installed objdump on it and reads the answer.
  var
    o: tuple[output: string, exitCode: int] = ("", 0)
  result = (R: @[], error: "")
  o = execCmdShared("objdump -d -M intel --no-show-raw-insn -l " &
    quoteShell(path), {poUsePath})
  if o.exitCode != 0:
    result.error = "objdump failed on " & path & ": " &
      o.output.strip().splitLines()[0]
    return
  result.R = parseObjdump(o.output)
