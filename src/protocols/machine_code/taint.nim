## ============================================================
## | Otter Machine Code -> forward search for secret data     |
## | -> which jumps and addresses depend on a secret          |
## ============================================================
##
## A routine is "constant-time" when how long it takes does not depend
## on the secret it was given. On x86-64 three things break that:
##
##   ┌──────────────────────────┬─────────────────────────────────────┐
##   │ what                     │ why it leaks                        │
##   ├──────────────────────────┼─────────────────────────────────────┤
##   │ a conditional jump whose │ one way is longer than the other    │
##   │ condition is secret      │                                     │
##   │ a memory address made    │ the cache remembers which address   │
##   │ from a secret            │ was touched; an observer can time it│
##   │ a division of a secret   │ `div` takes longer for some numbers │
##   └──────────────────────────┴─────────────────────────────────────┘
##
## The search marks places that hold a secret, then walks forward
## through the instructions, marking every place a marked one flows into.
##
## Def. 1  A "place" is a register (rax), the flags, a stack slot
##         (stack@rsp+0x10), the values pushed ("pushed"), or all other
##         memory taken together ("memory").
## Def. 2  A mark ("taint") is a set of two bits:
##           tbSecret   the value itself is secret
##           tbPointer  the value is an address of secret bytes; the
##                      address itself is public
##         Reading memory through a tbPointer address gives tbSecret.
##         Only tbSecret ever causes a finding.
## Def. 3  A "block" is a run of instructions with one way in (the top)
##         and one way out (the bottom). The "control-flow graph" is the
##         blocks plus the arrows "the bottom of A can continue at B".
##
##   entry marks ──> block 0 ──> block 1 ──┐
##                      ▲                   │   marks are merged where
##                      └──── block 2 <─────┘   arrows meet, and the walk
##                                              repeats until no mark grows
##
## The walk ignores which way a jump went: at a merge both ways count.
## It can therefore mark too much, never too little, within what the
## instruction table describes.
##
## Starting marks come from the System V calling convention: the first
## six whole-number arguments arrive in rdi, rsi, rdx, rcx, r8, r9.
##
##   proc f(a: openArray[byte], k: byte)     a.ptr -> rdi  tbPointer
##                                           a.len -> rsi  public
##                                           k     -> rdx  tbSecret

import std/[os, sequtils, sets, strutils, tables]

import runePragmas
import ./objdump
import ./instructions

type
  TaintBit* = enum
    tbSecret   ## the value is secret
    tbPointer  ## the value points at secret bytes

  Cell {.role: memory, expectedCount: [0, 512], lifeCycle: lcJob.} = object
    ## The mark on one place, and the instruction that put it there.
    bits: set[TaintBit]
    why: int  ## instruction index, or -(k+1) for parameter k, or noWhy

  State = Table[string, Cell]

  ParamKind* = enum
    ## How a Nim parameter lands in the registers.
    pkScalar     ## one register holding the value
    pkOpenArray  ## pointer register, then length register
    pkLenFirst   ## length register, then pointer register (seq, string)
    pkPointer    ## one register holding an address (var, ptr, array)
    pkFloat      ## one xmm register

  ParamSpec* = object
    name*: string
    kind*: ParamKind
    secret*: bool

  RoutineSpec* {.role: configurator,
      expectedCount: [0, 1000], lifeCycle: lcJob.} = object
    ## Which routine to check, and which of its parameters are secret.
    name*: string            ## the Nim name, "constantTimeEqual"
    params*: seq[ParamSpec]
    origin*: string          ## where this came from, for the report

  FindingKind* = enum
    fkBranch   ## conditional jump on a secret
    fkAddress  ## memory address made from a secret
    fkDivide   ## division of a secret

  Finding* {.role: truthState,
      expectedCount: [0, 10_000], lifeCycle: lcJob.} = object
    kind*: FindingKind
    routine*: string         ## Nim name
    symbol*: string          ## name in the binary
    address*: uint64
    text*: string            ## "je  0xbe80"
    file*: string
    line*: int
    trail*: seq[string]      ## where the secret came from, newest first
    inlinedFrom*: string     ## the source routine the line sits in, when not this one

  RoutineResult* {.role: truthState,
      expectedCount: [0, 1000], lifeCycle: lcJob.} = object
    spec*: RoutineSpec
    symbol*: string
    instrCount*: int
    blockCount*: int
    findings*: seq[Finding]
    unknown*: int            ## instructions the table did not know
    unknownNames*: seq[string]
    notes*: seq[string]

  Search {.role: memory, expectedCount: 1, lifeCycle: lcJob.} = object
    ## Everything one routine's walk needs and collects.
    r: Routine
    paramNotes: seq[string]          ## "parameter `a` (rdi, ...)"
    cause: Table[int, tuple[loc: string, why: int]]
    record: bool                     ## true only on the last pass
    seen: HashSet[string]
    findings: seq[Finding]
    unknown: CountTable[string]
    calls: CallTable                 ## what each routine of the binary touches
    flows: Flows                     ## which arguments reach rax; nil: cautious
    retBits: set[TaintBit]           ## marks seen on rax at a return

  CallSummary* = object
    ## The registers one routine reads and writes, its calls included.
    reads*, writes*: HashSet[string]
    targets: seq[uint64]             ## routines it calls directly

  CallTable* = Table[uint64, CallSummary]  ## start address -> summary

  Flows* = ref object
    ## For each routine of the binary: which argument registers can reach
    ## rax by the time it returns. Worked out only when a call needs it,
    ## then kept. Shared by every check of one binary.
    routines: seq[Routine]
    index: Table[uint64, int]        ## start address -> routines index
    calls*: CallTable
    memo: Table[uint64, set[0 .. 5]]
    busy: HashSet[uint64]            ## being worked out: a call back in is cautious

  Block = object
    first, last: int                 ## instruction indexes, inclusive
    succ: seq[int]                   ## block indexes

  MemRef = object
    ## One memory operand, "BYTE PTR [rdi+rax*1+0x10]".
    isMem: bool
    regs: seq[string]                ## address registers, rip and rsp left out
    slot: string                     ## the stack slot it names, or empty
    perThread: bool                  ## fs: or gs: - the runtime's own per-thread data

const
  noWhy: int = int.low
  maxTrail: int = 8
  maxSteps: int = 2_000_000
  zeroIdioms: array[8, string] = ["xor", "sub", "pxor", "vpxor", "xorps",
    "vxorps", "xorpd", "vxorpd"]

# ---- places ------------------------------------------------------------

proc memRef(op: string): MemRef {.role: parser, tag: "machineCode".} =
  ## op: one operand. Which registers build the address, and which
  ## stack slot it names:
  ##
  ##   "BYTE PTR [rdi+rax*1]"     regs rdi, rax
  ##   "QWORD PTR [rsp+0x10]"     stack@rsp+0x10
  ##   "[rip+0x1615]"             no registers (a fixed address)
  var
    a: int = op.find('[')
    b: int = op.rfind(']')
    inner: string = ""
    reg: string = ""
  result = MemRef(isMem: a >= 0 or op.contains(" PTR "))
  result.perThread = op.contains("fs:") or op.contains("gs:")
  if a < 0 or b <= a:
    return
  inner = op[a + 1 ..< b].replace(" ", "")
  for t in inner.replace("-", "+-").split('+'):
    reg = fullRegister(t.split('*')[0])
    if reg.len > 0 and reg notin ["rip", "rsp"]:
      result.regs.add(reg)
  if inner.startsWith("rsp") or (inner.startsWith("rbp") and result.regs == @["rbp"]):
    if inner.find('*') < 0 and result.regs.len <= 1:
      result.slot = "stack@" & inner

proc cellOf(S: State, k: string): Cell {.inline, role: helper,
    tag: "machineCode".} =
  ## S: the marks   k: a place. Its mark, or an empty one.
  result = S.getOrDefault(k, Cell(bits: {}, why: noWhy))

proc union(a, b: Cell): Cell {.inline, role: math, tag: "machineCode".} =
  ## a, b: two marks. Both bits together; the reason of whichever brought
  ## a secret first.
  result = a
  result.bits = a.bits + b.bits
  if a.bits == {} or (tbSecret notin a.bits and tbSecret in b.bits):
    result.why = b.why

proc join(S0: var State, S1: State): bool {.role: math, tag: "machineCode".} =
  ## S0: marks at the top of a block   S1: marks arriving along one arrow.
  ## Adds S1 into S0; true when any mark grew.
  var
    t: Cell = Cell(bits: {}, why: noWhy)
  result = false
  for k, c in S1:
    t = cellOf(S0, k)
    if c.bits <= t.bits:
      continue
    S0[k] = union(t, c)
    result = true

# ---- findings -----------------------------------------------------------

proc hexOf*(x: uint64): string {.inline, role: helper, tag: "machineCode".} =
  ## x: an address. "be80": lower case, no leading zeros.
  result = x.toHex().toLowerAscii().strip(trailing = false, chars = {'0'})

proc shortOps(I: Instr): string {.role: helper, tag: "machineCode".} =
  ## I: an instruction. "je  0xbe80" or "movzx  eax, BYTE PTR [rax+rdi*1]".
  if I.hasTarget:
    return I.mnemonic & "  0x" & hexOf(I.target)
  result = (I.mnemonic & "  " & I.operands.join(", ")).strip()

proc whereOf(I: Instr): string {.role: helper, tag: "machineCode".} =
  ## I: an instruction. "s.nim:10", or "" without debug lines.
  if I.line == 0:
    return ""
  result = extractFilename(I.file) & ":" & $I.line

proc trailOf(S: Search, loc: string, why: int): seq[string] {.role: parser,
    tag: "machineCode".} =
  ## S: the finished walk   loc, why: the place that was secret and the
  ## instruction that made it so. The way back to a parameter, one line
  ## per step:
  ##
  ##   rcx  <- 0xbe89  movzx  ecx, BYTE PTR [rdx+rax*1]  (s.nim:10)
  ##   rdx  <- parameter `b`: rdx points at secret bytes
  var
    l: string = loc
    w: int = why
    n: int = 0
    V: HashSet[int] = initHashSet[int]()
    I: Instr = Instr()
  result = @[]
  while n < maxTrail and w != noWhy and w notin V:
    if w < 0:
      result.add(l & "  <- " & S.paramNotes[-(w + 1)])
      return
    V.incl(w)
    I = S.r.instrs[w]
    result.add(l & "  <- 0x" & hexOf(I.address) & "  " & shortOps(I) & "  (" & whereOf(I) & ")")
    (l, w) = S.cause.getOrDefault(w, ("?", noWhy))
    n = n + 1
  result.add("(not traced further)")

proc flag(S: var Search, k: FindingKind, i: int, loc: string, c: Cell) {.
    role: actor, tag: "machineCode".} =
  ## S: the walk   k: what kind   i: the instruction   loc, c: the secret
  ## place that caused it. Recorded only on the last pass, once each.
  var
    key: string = $i & ":" & $k
    I: Instr = S.r.instrs[i]
  if not S.record or tbSecret notin c.bits or key in S.seen:
    return
  S.seen.incl(key)
  S.findings.add(Finding(kind: k, routine: S.r.baseName, symbol: S.r.name,
    address: I.address, text: shortOps(I), file: I.file, line: I.line,
    trail: trailOf(S, loc, c.why)))

# ---- reading and writing places -------------------------------------------

proc checkAddress(S: var Search, St: State, op: string, i: int) {.
    role: actor, tag: "machineCode".} =
  ## St: the marks   op: an operand   i: its instruction. Flags a memory
  ## address built from a secret register.
  for reg in memRef(op).regs:
    flag(S, fkAddress, i, reg, cellOf(St, reg))

proc loadValue(St: State, m: MemRef, i: int): tuple[loc: string, c: Cell] {.
    role: parser, tag: "machineCode".} =
  ## St: the marks   m: a memory operand   i: its instruction. The mark of
  ## the value read from it:
  ##
  ##   a stack slot                        -> that slot's mark
  ##   through an address of secret bytes  -> secret
  ##   through a secret address            -> secret (already flagged)
  ##   fs: or gs: (the runtime's own data) -> public
  ##   anywhere else                       -> the "memory" mark
  var
    c: Cell = Cell(bits: {}, why: noWhy)
  if m.perThread:
    return ("", Cell(bits: {}, why: noWhy))
  if m.slot.len > 0:
    return (m.slot, cellOf(St, m.slot))
  for reg in m.regs:
    c = cellOf(St, reg)
    if c.bits != {}:
      return ("[" & reg & "]", Cell(bits: {tbSecret}, why: c.why))
  result = ("memory", cellOf(St, "memory"))

proc readOp(St: State, op: string, i: int): tuple[loc: string, c: Cell] {.
    role: parser, tag: "machineCode".} =
  ## St: the marks   op: an operand   i: its instruction. Where its value
  ## comes from and the mark it carries. Numbers carry none.
  var
    m: MemRef = memRef(op)
    reg: string = fullRegister(op)
  if m.isMem:
    return loadValue(St, m, i)
  if reg.len > 0:
    return (reg, cellOf(St, reg))
  result = ("", Cell(bits: {}, why: noWhy))

proc writeOp(St: var State, op: string, c: Cell) {.role: actor,
    tag: "machineCode".} =
  ## St: the marks   op: an operand   c: the mark of what is written.
  ##
  ##   register        replaced (an 8/16-bit write keeps the old mark too)
  ##   stack slot      replaced
  ##   secret bytes    nothing to do, they are secret already
  ##   other memory    added to the one "memory" mark
  var
    m: MemRef = memRef(op)
    reg: string = fullRegister(op)
    t: Cell = c
  if reg.len > 0 and not m.isMem:
    if isPartialRegister(op): t = union(cellOf(St, reg), c)
    St[reg] = t
  elif m.slot.len > 0:
    St[m.slot] = c
  elif m.isMem and not m.regs.anyIt(tbPointer in cellOf(St, it).bits):
    St["memory"] = union(cellOf(St, "memory"), c)

# ---- one instruction -------------------------------------------------------

proc gather(S: var Search, St: State, i: int, e: Effect): tuple[loc: string,
    c: Cell] {.role: parser, tag: "machineCode".} =
  ## St: the marks   i: the instruction   e: its effect. Every read place
  ## merged into one mark, with the first secret one named as the cause.
  var
    I: Instr = S.r.instrs[i]
    got: tuple[loc: string, c: Cell] = ("", Cell(bits: {}, why: noWhy))
    k: int = 0
  result = ("", Cell(bits: {}, why: noWhy))
  while k < I.operands.len:
    if k in e.readsOps:
      got = readOp(St, I.operands[k], i)
      if result.c.bits == {} and got.c.bits != {}: result.loc = got.loc
      result.c = union(result.c, got.c)
    k = k + 1
  for reg in e.hiddenReads:
    if result.c.bits == {} and cellOf(St, reg).bits != {}: result.loc = reg
    result.c = union(result.c, cellOf(St, reg))
  if e.readsFlags:
    if result.c.bits == {} and cellOf(St, "flags").bits != {}: result.loc = "flags"
    result.c = union(result.c, cellOf(St, "flags"))

proc isZeroIdiom(I: Instr): bool {.inline, role: helper, tag: "machineCode".} =
  ## I: an instruction. `xor eax, eax` and friends: the answer is always 0,
  ## whatever the register held.
  result = I.mnemonic in zeroIdioms and I.operands.len >= 2 and
    I.operands[^1] == I.operands[^2] and fullRegister(I.operands[^1]).len > 0

proc writeAll(S: var Search, St: var State, i: int, e: Effect,
    v: tuple[loc: string, c: Cell]) {.role: actor, tag: "machineCode".} =
  ## St: the marks   i: the instruction   e: its effect   v: what it
  ## computed. Every written place gets v's mark, made by instruction i.
  var
    I: Instr = S.r.instrs[i]
    c: Cell = Cell(bits: v.c.bits, why: i)
    k: int = 0
  if v.c.bits != {}:
    S.cause[i] = (v.loc, v.c.why)
  while k < I.operands.len:
    if k in e.writesOps: writeOp(St, I.operands[k], c)
    k = k + 1
  for reg in e.hiddenWrites:
    St[reg] = c
  if e.writesFlags:
    St["flags"] = c

proc callValue(St: State): tuple[loc: string, c: Cell] {.role: parser,
    tag: "machineCode".} =
  ## St: the marks before a call. What the called routine may hand back:
  ## secret when any argument register carried any mark.
  result = ("", Cell(bits: {}, why: noWhy))
  for reg in argRegisters:
    if result.c.bits == {} and cellOf(St, reg).bits != {}:
      result = (reg, Cell(bits: {tbSecret}, why: cellOf(St, reg).why))

# ---- what a called routine really touches ------------------------------------
#
# The convention says a called routine MAY change rax, rcx, rdx, rsi,
# rdi, r8-r11. gcc knows better for routines in the same binary, and
# keeps a loop counter in rdx across a call to a routine that never
# touches rdx. Reading every call as "all of those become secret" then
# marks that counter and reports a jump that is not there. So each
# routine of the binary gets a summary:
#
#   ctEq          reads rdi, rsi        writes rax, rsi
#   nimErrorFlag  reads (nothing)       writes rax
#
# and a call changes only what its summary writes, and hands back a
# secret only when an argument register it reads carried a mark.
# A call to something outside the binary keeps the cautious rule.

proc regsOf(op: string): seq[string] {.role: parser, tag: "machineCode".} =
  ## op: an operand. The registers it names, as a value or inside [ ].
  var
    m: MemRef = memRef(op)
  result = m.regs
  if not m.isMem and fullRegister(op).len > 0:
    result.add(fullRegister(op))

proc addInstrRegs(c: var CallSummary, I: Instr) {.role: truthBuilder,
    tag: "machineCode".} =
  ## c: a summary being built   I: one of its routine's instructions. A
  ## register counts as read only when it is read before the routine
  ## first writes it (in the order the instructions are written down);
  ## after that write it no longer holds what the caller handed in.
  var
    e: Effect = effectOf(I.mnemonic, I.operands.len)
    k: int = 0
  if e.cls == icCall and I.hasTarget:
    c.targets.add(I.target)
    return
  while k < I.operands.len:
    for reg in regsOf(I.operands[k]):
      if (k in e.readsOps or memRef(I.operands[k]).isMem) and reg notin c.writes:
        c.reads.incl(reg)
    if k in e.writesOps and not memRef(I.operands[k]).isMem:
      c.writes.incl(fullRegister(I.operands[k]))
    k = k + 1
  for reg in e.hiddenReads:
    if reg notin c.writes: c.reads.incl(reg)
  for reg in e.hiddenWrites: c.writes.incl(reg)

proc summarize*(R: seq[Routine]): CallTable {.role: truthBuilder,
    tag: "machineCode".} =
  ## R: every routine of the binary. Each one's summary, with what the
  ## routines it calls touch folded in (a few rounds deep; a call to
  ## something outside the binary counts as touching everything).
  var
    c: CallSummary = CallSummary()
    n: int = 0
    grew: bool = true
  result = initTable[uint64, CallSummary]()
  for r in R:
    c = CallSummary()
    for I in r.instrs: addInstrRegs(c, I)
    result[r.start] = c
  while grew and n < 16:
    grew = false
    for a, s in result.mpairs:
      for t in s.targets:
        if t notin result:
          s.reads.incl(toHashSet(argRegisters))
          s.writes.incl(toHashSet(callerSaved))
          continue
        if result[t].reads <= s.reads and result[t].writes <= s.writes: continue
        s.reads.incl(result[t].reads)
        s.writes.incl(result[t].writes)
        grew = true
    n = n + 1

proc flowOf(F: Flows, t: uint64): set[0 .. 5] {.role: parser, tag: "machineCode".}

proc callEffect(S: var Search, St: var State, i: int) {.role: actor,
    tag: "machineCode".} =
  ## St: the marks before call i, changed into the marks after it.
  var
    I: Instr = S.r.instrs[i]
    c: CallSummary = S.calls[I.target]
    A: set[0 .. 5] = {0 .. 5}
    k: int = 0
    v: tuple[loc: string, c: Cell] = ("", Cell(bits: {}, why: noWhy))
    m: Cell = Cell(bits: {}, why: noWhy)
  if S.flows != nil: A = flowOf(S.flows, I.target)
  while k < 6:
    if k in A and (S.flows != nil or argRegisters[k] in c.reads) and
        cellOf(St, argRegisters[k]).bits != {} and v.c.bits == {}:
      v = (argRegisters[k], Cell(bits: {tbSecret}, why: cellOf(St, argRegisters[k]).why))
    k = k + 1
  m = Cell(bits: v.c.bits, why: i)
  if v.c.bits != {}: S.cause[i] = (v.loc, v.c.why)
  for reg in c.writes:
    if reg in callerSaved or reg.startsWith("xmm"): St[reg] = m
  St["flags"] = m

proc stepSpecial(S: var Search, St: var State, i: int, e: Effect) {.
    role: actor, tag: "machineCode".} =
  ## St: the marks   i: the instruction   e: its effect. The kinds the
  ## generic "written <- read" rule does not describe.
  var
    I: Instr = S.r.instrs[i]
    v: tuple[loc: string, c: Cell] = gather(S, St, i, e)
    w: tuple[loc: string, c: Cell] = ("", Cell(bits: {}, why: noWhy))
  case e.cls
  of icCondJump: flag(S, fkBranch, i, v.loc, v.c)
  of icJump:
    if not I.hasTarget: flag(S, fkBranch, i, v.loc, v.c)
    if not I.hasTarget or I.target < S.r.start or I.target > S.r.instrs[^1].address:
      S.retBits = S.retBits + callValue(St).c.bits
  of icReturn: S.retBits = S.retBits + cellOf(St, "rax").bits
  of icCall:
    if not I.hasTarget: flag(S, fkBranch, i, v.loc, v.c)
    if I.hasTarget and I.target in S.calls: callEffect(S, St, i)
    else: writeAll(S, St, i, e, callValue(St))
  of icDivide:
    flag(S, fkDivide, i, v.loc, v.c)
    writeAll(S, St, i, e, v)
  of icPush: St["pushed"] = union(cellOf(St, "pushed"), Cell(bits: v.c.bits, why: i))
  of icPop: writeAll(S, St, i, e, ("pushed", cellOf(St, "pushed")))
  of icLeave: St["rbp"] = cellOf(St, "pushed")
  of icLea:
    for reg in memRef(I.operands[^1]).regs:
      if w.c.bits == {} and cellOf(St, reg).bits != {}: w.loc = reg
      w.c = union(w.c, cellOf(St, reg))
    writeAll(S, St, i, e, w)
  of icExchange:
    w = readOp(St, I.operands[1], i)
    writeOp(St, I.operands[1], Cell(bits: readOp(St, I.operands[0], i).c.bits, why: i))
    writeOp(St, I.operands[0], Cell(bits: w.c.bits, why: i))
  else: discard

proc step(S: var Search, St: var State, i: int) {.role: actor,
    tag: "machineCode".} =
  ## St: the marks before instruction i, changed into the marks after it.
  var
    I: Instr = S.r.instrs[i]
    e: Effect = effectOf(I.mnemonic, I.operands.len)
    v: tuple[loc: string, c: Cell] = ("", Cell(bits: {}, why: noWhy))
  if not e.known and S.record:
    S.unknown.inc(I.mnemonic)
  if e.cls notin {icLea, icNop}:
    for op in I.operands: checkAddress(S, St, op, i)
  if e.cls != icPlain:
    stepSpecial(S, St, i, e)
    return
  if not isZeroIdiom(I):
    v = gather(S, St, i, e)
  writeAll(S, St, i, e, v)

# ---- the graph -------------------------------------------------------------

proc classOf(I: Instr): InstrClass {.inline, role: helper, tag: "machineCode".} =
  result = effectOf(I.mnemonic, I.operands.len).cls

proc leadersOf(r: Routine, A: Table[uint64, int]): seq[int] {.role: parser,
    tag: "machineCode".} =
  ## r: a routine   A: address -> instruction index. Indexes where a block
  ## starts: the first instruction, every jump target inside the
  ## routine, and every instruction right after a jump or return.
  var
    L: HashSet[int] = toHashSet([0])
    i: int = 0
    c: InstrClass = icPlain
  while i < r.instrs.len:
    c = classOf(r.instrs[i])
    if r.instrs[i].hasTarget and c in {icCondJump, icJump} and r.instrs[i].target in A:
      L.incl(A[r.instrs[i].target])
    if c in {icCondJump, icJump, icReturn, icStop} and i + 1 < r.instrs.len:
      L.incl(i + 1)
    i = i + 1
  result = @[]
  i = 0
  while i < r.instrs.len:
    if i in L: result.add(i)
    i = i + 1

proc successorsOf(r: Routine, b: Block, A: Table[uint64, int],
    B: Table[int, int], n: int): seq[int] {.role: parser, tag: "machineCode".} =
  ## r: a routine   b: one block   A: address -> instruction index
  ## B: first instruction -> block index   n: block count. Where the
  ## bottom of b can continue. A jump through a register could go
  ## anywhere, so it leads to every block.
  var
    I: Instr = r.instrs[b.last]
    c: InstrClass = classOf(I)
    k: int = 0
  result = @[]
  if c in {icReturn, icStop}:
    return
  if c in {icJump, icCondJump} and not I.hasTarget and c == icJump:
    while k < n:
      result.add(k)
      k = k + 1
    return
  if I.hasTarget and c in {icJump, icCondJump} and I.target in A:
    result.add(B[A[I.target]])
  if c != icJump and b.last + 1 in B:
    result.add(B[b.last + 1])

proc blocksOf*(r: Routine): seq[Block] {.role: truthBuilder,
    tag: "machineCode".} =
  ## r: a routine. Its control-flow graph (Def. 3).
  var
    A: Table[uint64, int] = initTable[uint64, int]()
    B: Table[int, int] = initTable[int, int]()
    L: seq[int] = @[]
    i: int = 0
  for k, I in r.instrs: A[I.address] = k
  L = leadersOf(r, A)
  result = @[]
  while i < L.len:
    result.add(Block(first: L[i], last: (if i + 1 < L.len: L[i + 1] - 1 else: r.instrs.len - 1)))
    B[L[i]] = i
    i = i + 1
  i = 0
  while i < result.len:
    result[i].succ = successorsOf(r, result[i], A, B, result.len)
    i = i + 1

# ---- starting marks --------------------------------------------------------

proc entryState(spec: RoutineSpec, notes: var seq[string],
    warn: var seq[string]): State {.role: truthBuilder, tag: "machineCode".} =
  ## spec: which parameters are secret. The marks on the argument
  ## registers when the routine starts (see the table at the top).
  ## notes gets one line per parameter for the trails.
  var
    g: int = 0
    x: int = 0
    k: int = 0
    R: seq[string] = @[]
    bits: set[TaintBit] = {}
  result = initTable[string, Cell]()
  notes = @[]
  while k < spec.params.len:
    R = @[]
    case spec.params[k].kind
    of pkFloat:
      R = @["xmm" & $x, ""]
      x = x + 1
    of pkScalar, pkPointer:
      R = @[(if g < 6: argRegisters[g] else: "stack"), ""]
      g = g + 1
    of pkOpenArray:
      R = @[(if g < 6: argRegisters[g] else: "stack"), (if g + 1 < 6: argRegisters[g + 1] else: "stack")]
      g = g + 2
    of pkLenFirst:
      R = @[(if g + 1 < 6: argRegisters[g + 1] else: "stack"), (if g < 6: argRegisters[g] else: "stack")]
      g = g + 2
    bits = (if spec.params[k].kind in {pkScalar, pkFloat}: {tbSecret} else: {tbPointer})
    notes.add("parameter `" & spec.params[k].name & "`: " & R[0] &
      (if tbPointer in bits: " points at secret bytes" else: " holds the secret"))
    if spec.params[k].secret and R[0] == "stack":
      warn.add("parameter `" & spec.params[k].name & "` arrives on the stack; not tracked")
    elif spec.params[k].secret:
      result[R[0]] = Cell(bits: bits, why: -(k + 1))
    k = k + 1

# ---- the walk --------------------------------------------------------------

proc runBlock(S: var Search, St: var State, b: Block) {.role: actor,
    tag: "machineCode".} =
  ## St: the marks at the top of b, changed into the marks at its bottom.
  var
    i: int = b.first
  while i <= b.last:
    step(S, St, i)
    i = i + 1

proc settle(S: var Search, G: seq[Block], E: var seq[State],
    reached: var seq[bool]) {.role: orchestrator, tag: "machineCode".} =
  ## G: the graph   E: marks at the top of every block. Walks the graph
  ## until no mark grows (or a step budget runs out).
  var
    W: seq[int] = @[0]
    b: int = 0
    St: State = initTable[string, Cell]()
    n: int = 0
  reached[0] = true
  while W.len > 0 and n < maxSteps:
    b = W.pop()
    St = E[b]
    runBlock(S, St, G[b])
    n = n + G[b].last - G[b].first + 1
    for t in G[b].succ:
      if join(E[t], St) or not reached[t]:
        reached[t] = true
        W.add(t)

proc checkRoutine*(r: Routine, spec: RoutineSpec, F: Flows = nil): RoutineResult {.
    role: orchestrator, tag: "machineCode".} =
  ## r: a routine read from the binary   spec: which parameters are
  ## secret   F: from `newFlows`, or nil for the cautious call rule.
  ## secret. Builds the graph, settles the marks, then walks every
  ## reached block once more to record what was found.
  var
    S: Search = Search(r: r, record: false, flows: F)
    G: seq[Block] = @[]
    E: seq[State] = @[]
    reached: seq[bool] = @[]
    St: State = initTable[string, Cell]()
    k: int = 0
  result = RoutineResult(spec: spec, symbol: r.name, instrCount: r.instrs.len)
  if r.instrs.len == 0:
    result.notes.add("no instructions")
    return
  if F != nil: S.calls = F.calls
  G = blocksOf(r)
  E = newSeq[State](G.len)
  reached = newSeq[bool](G.len)
  E[0] = entryState(spec, S.paramNotes, result.notes)
  settle(S, G, E, reached)
  S.record = true
  while k < G.len:
    St = E[k]
    if reached[k]: runBlock(S, St, G[k])
    k = k + 1
  result.blockCount = G.len
  result.findings = S.findings
  for m, n in S.unknown:
    result.unknown = result.unknown + n
    result.unknownNames.add(m)

# ---- what reaches rax: one search per argument ------------------------------
#
#   flowOf(nimNewObj)   rdi marked alone -> rax marked at ret?  yes  -> {0}
#                       rsi marked alone -> ...                 no
#                       ...
#
# A call then hands back a secret only when an argument that reaches
# rax carried a mark. The same walk as above, with nothing recorded.

proc newFlows*(R: seq[Routine]): Flows {.role: truthBuilder,
    tag: "machineCode".} =
  ## R: every routine of the binary.
  result = Flows(routines: R, calls: summarize(R))
  for k, r in R: result.index[r.start] = k

proc reachesReturn(F: Flows, r: Routine, G: seq[Block], reg: string): bool {.
    role: parser, tag: "machineCode".} =
  ## r: a routine   G: its graph   reg: one argument register. True when
  ## a mark put on reg alone is on rax at some return.
  var
    S: Search = Search(r: r, record: false, calls: F.calls, flows: F,
      paramNotes: @["argument " & reg])
    E: seq[State] = newSeq[State](G.len)
    reached: seq[bool] = newSeq[bool](G.len)
  E[0] = {reg: Cell(bits: {tbSecret}, why: -1)}.toTable()
  settle(S, G, E, reached)
  result = S.retBits != {}

proc flowOf(F: Flows, t: uint64): set[0 .. 5] {.role: parser.} =
  ## F: the binary's flows   t: a routine's start. Which of the six
  ## argument registers can reach rax. Unknown, or already being worked
  ## out further up (a loop of calls): all six, to be safe.
  var
    r: Routine = Routine()
    G: seq[Block] = @[]
    k: int = 0
  if t in F.memo:
    return F.memo[t]
  if t notin F.index or t in F.busy:
    return {0 .. 5}
  F.busy.incl(t)
  r = F.routines[F.index[t]]
  G = blocksOf(r)
  result = {}
  while k < 6 and G.len > 0:
    if reachesReturn(F, r, G, argRegisters[k]): result.incl(k)
    k = k + 1
  F.busy.excl(t)
  F.memo[t] = result
