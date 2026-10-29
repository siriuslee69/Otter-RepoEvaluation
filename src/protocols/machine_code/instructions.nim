## ============================================================
## | Otter Machine Code -> instruction table                  |
## | -> for each mnemonic: what it reads, what it writes      |
## ============================================================
##
## The forward search (taint.nim) needs one answer per instruction:
## which places does it look at, and which places does it change?
##
##   add  rax, rcx      reads  rax, rcx          writes  rax, flags
##   mov  rax, rcx      reads  rcx               writes  rax
##   cmp  rax, rcx      reads  rax, rcx          writes  flags
##   mul  rcx           reads  rax, rcx  (hidden)  writes  rax, rdx, flags
##
## "Operand 0" is the first thing written after the mnemonic, "operand 1"
## the second, and so on. "Hidden" registers are ones the instruction
## uses without naming them. "Flags" is the small register a compare
## writes and a conditional jump reads.
##
## Registers are named by their full 64-bit name. The smaller names are
## windows onto the same register:
##
##   rax ┌────────────────────────────────────────────┐
##   eax │                      ┌─────────────────────┤
##   ax  │                      │          ┌──────────┤
##   al  │                      │          │   ┌──────┤
##       └──────────────────────┴──────────┴───┴──────┘
##
## so `al` and `eax` both count as `rax`. Vector registers xmm3, ymm3 and
## zmm3 all count as `xmm3`.
##
## An instruction missing from this table gets a cautious default: every
## operand is read, the first one and the flags are written. `known` is
## false then, and the report counts how often that happened.

import std/[strutils]

import runePragmas

type
  InstrClass* = enum
    ## What kind of thing an instruction does, where the generic
    ## "written <- read" rule is not enough on its own.
    icPlain       ## the generic rule covers it
    icLea         ## computes an address but does not read memory
    icCondJump    ## jumps or not depending on the flags
    icJump        ## always jumps
    icCall        ## calls another routine
    icReturn      ## leaves the routine
    icStop        ## never continues (ud2, hlt)
    icDivide      ## time depends on the values
    icPush        ## stores onto the stack
    icPop         ## loads from the stack
    icLeave       ## rsp <- rbp, then pop rbp
    icExchange    ## swaps two places
    icNop         ## does nothing that matters here

  Effect* {.role: preparedData, expectedCount: 1, lifeCycle: lcScratch.} = object
    ## What one instruction reads and writes.
    cls*: InstrClass
    readsOps*: set[0 .. 3]     ## operand positions it reads
    writesOps*: set[0 .. 3]    ## operand positions it writes
    hiddenReads*: seq[string]  ## registers it reads without naming them
    hiddenWrites*: seq[string] ## registers it writes without naming them
    readsFlags*: bool
    writesFlags*: bool
    known*: bool               ## false: the cautious default was used

const
  argRegisters*: array[6, string] = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
    ## where the System V calling convention puts the first six whole-number
    ## arguments, in order
  callerSaved*: array[9, string] = ["rax", "rcx", "rdx", "rsi", "rdi", "r8",
    "r9", "r10", "r11"]
    ## registers a called routine may leave changed
  gprNames: array[16, string] = ["rax", "rbx", "rcx", "rdx", "rsi", "rdi",
    "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"]
  aluOps: array[22, string] = ["add", "sub", "and", "or", "xor", "imul",
    "shl", "shr", "sar", "sal", "rol", "ror", "andn", "shld", "shrd",
    "rcl", "rcr", "btc", "btr", "bts", "xadd", "cmpxchg"]
    ## dst <- dst op src, flags written
  carryOps: array[2, string] = ["adc", "sbb"]
    ## dst <- dst op src op carry flag
  compareOps: array[3, string] = ["cmp", "test", "bt"]
    ## flags <- a op b, nothing else written
  unaryOps: array[4, string] = ["inc", "dec", "neg", "bswap"]
    ## dst <- op dst
  countOps: array[5, string] = ["bsf", "bsr", "tzcnt", "lzcnt", "popcnt"]
    ## dst <- count over src, flags written
  moveOps: array[20, string] = ["mov", "movzx", "movsx", "movsxd", "movabs",
    "movd", "movq", "movdqa", "movdqu", "movaps", "movups", "movapd",
    "movupd", "movss", "movsd", "movbe", "movnti", "movntdq", "pmovmskb",
    "movmskps"]
    ## dst <- src, nothing else
  vectorOps: array[50, string] = ["pxor", "por", "pand", "pandn", "paddb",
    "paddw", "paddd", "paddq", "psubb", "psubw", "psubd", "psubq",
    "pcmpeqb", "pcmpeqw", "pcmpeqd", "pcmpeqq", "pcmpgtb", "pcmpgtw",
    "pcmpgtd", "pcmpgtq", "pminub", "pmaxub", "pminsb", "pmaxsb",
    "pshufb", "pshufd", "pshuflw", "pshufhw", "punpcklbw", "punpckhbw",
    "punpcklwd", "punpckhwd", "punpckldq", "punpckhdq", "punpcklqdq",
    "punpckhqdq", "psllw", "pslld", "psllq", "psrlw", "psrld", "psrlq",
    "psraw", "psrad", "pslldq", "psrldq", "pmullw", "pmulld", "pinsrb",
    "pinsrq"]
    ## dst <- dst op src (vector registers, no flags)
  vectorMoreOps: array[22, string] = ["shufps", "shufpd", "unpcklps",
    "unpckhps", "unpcklpd", "unpckhpd", "xorps", "andps", "orps", "andnps",
    "xorpd", "andpd", "orpd", "pextrb", "pextrw", "pextrd", "pextrq",
    "pinsrw", "pinsrd", "packuswb", "packsswb", "palignr"]
  nopOps: array[11, string] = ["nop", "endbr64", "endbr32", "pause",
    "lfence", "mfence", "sfence", "prefetcht0", "prefetcht1",
    "prefetchnta", "int3"]

proc fullRegister*(s: string): string {.role: parser, tag: "machineCode".} =
  ## s: one operand. The full register it names, or "" when it is not a
  ## register:
  ##
  ##   "al" "ax" "eax" "rax"     -> "rax"
  ##   "r8b" "r8w" "r8d" "r8"    -> "r8"
  ##   "sil" "dil" "bpl" "spl"   -> "rsi" "rdi" "rbp" "rsp"
  ##   "xmm3" "ymm3" "zmm3"      -> "xmm3"
  var
    t: string = s.strip().toLowerAscii()
  result = ""
  if t in gprNames:
    return t
  case t
  of "al", "ah", "ax", "eax": return "rax"
  of "bl", "bh", "bx", "ebx": return "rbx"
  of "cl", "ch", "cx", "ecx": return "rcx"
  of "dl", "dh", "dx", "edx": return "rdx"
  of "sil", "si", "esi": return "rsi"
  of "dil", "di", "edi": return "rdi"
  of "bpl", "bp", "ebp": return "rbp"
  of "spl", "sp", "esp": return "rsp"
  else: discard
  if t.len >= 3 and t[0] == 'r' and t[1] in Digits:
    return "r" & t[1 .. ^1].strip(leading = false, chars = {'b', 'w', 'd'})
  if t.len >= 4 and t[1 .. 2] == "mm" and t[0] in {'x', 'y', 'z'}:
    return "xmm" & t[3 .. ^1]

proc isPartialRegister*(s: string): bool {.role: parser, tag: "machineCode".} =
  ## s: one register operand. True when writing it keeps the rest of the
  ## full register: an 8- or 16-bit name (al, ax, r8b, r8w). A 32-bit
  ## write (eax) clears the upper half, so it is not partial.
  var
    t: string = s.strip().toLowerAscii()
  result = t in ["al", "ah", "ax", "bl", "bh", "bx", "cl", "ch", "cx", "dl",
    "dh", "dx", "sil", "si", "dil", "di", "bpl", "bp", "spl", "sp"]
  if t.len >= 3 and t[0] == 'r' and t[1] in Digits:
    result = t[^1] in {'b', 'w'}

proc plainEffect(r, w: set[0 .. 3], rf, wf: bool): Effect {.inline,
    role: helper, tag: "machineCode".} =
  ## r, w: operand positions read and written   rf, wf: flags read, written.
  result = Effect(cls: icPlain, readsOps: r, writesOps: w, readsFlags: rf,
    writesFlags: wf, known: true)

proc classEffect(c: InstrClass, r, w: set[0 .. 3]): Effect {.inline,
    role: helper, tag: "machineCode".} =
  ## c: the special kind   r, w: operand positions read and written.
  result = Effect(cls: c, readsOps: r, writesOps: w, known: true)

proc conditionalEffect(m: string): tuple[ok: bool, e: Effect] {.
    role: parser, tag: "machineCode".} =
  ## m: mnemonic. The families named by a condition
  ## suffix: jcc (je, jne, jb ...), cmovcc and setcc.
  result = (ok: true, e: Effect())
  if m.startsWith("cmov"):
    result.e = plainEffect({0, 1}, {0}, true, false)
  elif m.startsWith("set"):
    result.e = plainEffect({}, {0}, true, false)
  elif m in ["jrcxz", "jecxz", "loop"]:
    result.e = classEffect(icCondJump, {}, {})
    result.e.hiddenReads = @["rcx"]
  elif m.startsWith("j") and m != "jmp":
    result.e = classEffect(icCondJump, {}, {})
    result.e.readsFlags = true
  else:
    result.ok = false

proc hiddenEffect(m: string, n: int): tuple[ok: bool, e: Effect] {.
    role: parser, tag: "machineCode".} =
  ## m: mnemonic   n: operand count. The instructions that use registers
  ## they do not name.
  ##
  ##   mul x / imul x   rdx:rax <- rax * x            (one operand form)
  ##   div x / idiv x   rax, rdx <- (rdx:rax) / x     time depends on values
  ##   cdqe / cwde      rax <- rax widened
  ##   cqo / cdq        rdx <- copies of rax's sign bit
  ##   push / pop       the stack, through rsp
  ##   call             the argument registers in, the scratch ones out
  result = (ok: true, e: Effect())
  case m
  of "mul", "imul":
    if m == "imul" and n >= 2:
      result.e = plainEffect({0, 1}, {0}, false, true)
      if n == 3: result.e.readsOps = {1, 2}
      return
    result.e = plainEffect({0}, {}, false, true)
    result.e.hiddenReads = @["rax"]
    result.e.hiddenWrites = @["rax", "rdx"]
  of "div", "idiv":
    result.e = classEffect(icDivide, {0}, {})
    result.e.hiddenReads = @["rax", "rdx"]
    result.e.hiddenWrites = @["rax", "rdx"]
  of "cdqe", "cwde", "cbw":
    result.e = plainEffect({}, {}, false, false)
    result.e.hiddenReads = @["rax"]
    result.e.hiddenWrites = @["rax"]
  of "cqo", "cdq", "cwd":
    result.e = plainEffect({}, {}, false, false)
    result.e.hiddenReads = @["rax"]
    result.e.hiddenWrites = @["rdx"]
  of "push": result.e = classEffect(icPush, {0}, {})
  of "pop": result.e = classEffect(icPop, {}, {0})
  of "leave": result.e = classEffect(icLeave, {}, {})
  of "call":
    result.e = classEffect(icCall, {0}, {})
    result.e.hiddenReads = @argRegisters
    result.e.hiddenWrites = @callerSaved
  else:
    result.ok = false

proc flowEffect(m: string): tuple[ok: bool, e: Effect] {.role: parser,
    tag: "machineCode".} =
  ## m: mnemonic. Jumps, returns, stops, swaps and the no-ops.
  result = (ok: true, e: Effect())
  case m
  of "jmp": result.e = classEffect(icJump, {0}, {})
  of "ret", "retq", "iret": result.e = classEffect(icReturn, {}, {})
  of "ud2", "hlt": result.e = classEffect(icStop, {}, {})
  of "lea": result.e = classEffect(icLea, {}, {0})
  of "xchg": result.e = classEffect(icExchange, {0, 1}, {0, 1})
  of "clc", "stc", "cld", "std", "cmc": result.e = plainEffect({}, {}, false, true)
  of "cpuid", "rdtsc", "rdtscp":
    result.e = plainEffect({}, {}, false, false)
    result.e.hiddenWrites = @["rax", "rdx", "rcx", "rbx"]
  else:
    if m in nopOps or m.startsWith("prefetch"):
      result.e = classEffect(icNop, {}, {})
    else:
      result.ok = false

proc tableEffect(m: string, n: int): tuple[ok: bool, e: Effect] {.
    role: parser, tag: "machineCode".} =
  ## m: mnemonic   n: operand count. The plain arithmetic and moves.
  result = (ok: true, e: Effect())
  if m in aluOps: result.e = plainEffect({0, 1, 2}, {0}, false, true)
  elif m in carryOps: result.e = plainEffect({0, 1}, {0}, true, true)
  elif m in compareOps: result.e = plainEffect({0, 1}, {}, false, true)
  elif m in unaryOps: result.e = plainEffect({0}, {0}, false, m != "bswap")
  elif m == "not": result.e = plainEffect({0}, {0}, false, false)
  elif m in countOps: result.e = plainEffect({1}, {0}, false, true)
  elif m in moveOps or m.startsWith("cvt"): result.e = plainEffect({1}, {0}, false, false)
  elif m in vectorOps or m in vectorMoreOps:
    result.e = plainEffect({0, 1, 2}, {0}, false, false)
  else: result.ok = false

proc effectOf*(m: string, n: int): Effect {.role: parser,
    tag: "machineCode".} =
  ## m: mnemonic   n: how many operands it was written with. What it reads
  ## and writes. A "v" form (vpxor xmm0, xmm1, xmm2) is read as its plain
  ## form with one more source: dst <- src1 op src2.
  var
    got: tuple[ok: bool, e: Effect] = (false, Effect())
  got = conditionalEffect(m)
  if not got.ok: got = hiddenEffect(m, n)
  if not got.ok: got = flowEffect(m)
  if not got.ok: got = tableEffect(m, n)
  if not got.ok and m.len > 1 and m[0] == 'v':
    got = tableEffect(m[1 .. ^1], n)
    if got.ok and n == 3: got.e.readsOps = {1, 2}
  if got.ok:
    return got.e
  result = Effect(cls: icPlain, readsOps: {0, 1, 2, 3}, writesOps: {0},
    writesFlags: true, known: false)
  if n == 0: result.writesOps = {}
