## ============================================================
## | Otter Machine Code Tests                                 |
## | -> objdump reading, and the ct check on known samples    |
## ============================================================
##
##   canned objdump text  ──parseObjdump──>  routines, as expected?
##   ct_samples.nim       ──ctCheck──────>   leaks where expected,
##                                           clean where expected?
##
## The second half needs `nim` and `objdump` on the PATH.

import std/[os, sequtils, strutils, tables, unittest]

import runePragmas
import ../../src/protocols/machine_code

const
  canned: string = """
000000000000be60 <_ZN1s9earlyExitE9openArrayI5uInt8E9openArrayI5uInt8E>:
_ZN1s9earlyExitE9openArrayI5uInt8E9openArrayI5uInt8E():
/home/me/s.nim:10 (discriminator 6)
    be89:	movzx  ecx,BYTE PTR [rdx+rax*1]
    be8d:	cmp    BYTE PTR [rdi+rax*1],cl
    be90:	je     be80 <_ZN1s9earlyExitE9openArrayI5uInt8E9openArrayI5uInt8E+0x20>
/home/me/s.nim:12
    be94:	ret

000000000000bea0 <sboxCt__aes_u12.constprop.0>:
    bea4:	lea    rax,[rip+0x1615]        # d4c0 <T__f_u13>
    beab:	rep stos QWORD PTR es:[rdi],rax
"""
  samples: string = currentSourcePath().parentDir() / "ct_samples" / "ct_samples.nim"

proc resultFor(r: CtReport, name: string): RoutineResult {.role: helper.} =
  ## r: a report   name: a Nim name. Its result, or an empty one.
  result = RoutineResult()
  for x in r.results:
    if x.spec.name == name: return x

suite "objdump reading":
  # {.testKind: tkUnit.}
  test "routines, names and instructions are read":
    var
      R: seq[Routine] = parseObjdump(canned)
    check R.len == 2
    check R[0].baseName == "earlyExit"
    check R[0].module == "s"
    check R[0].instrs.len == 4
    check R[1].baseName == "sboxCt"

  # {.testKind: tkUnit.}
  test "operands, jump targets and source lines":
    var
      I: seq[Instr] = parseObjdump(canned)[0].instrs
    check I[1].mnemonic == "cmp"
    check I[1].operands == @["BYTE PTR [rdi+rax*1]", "cl"]
    check I[2].hasTarget and I[2].target == 0xbe80'u64
    check I[0].line == 10 and I[0].file == "/home/me/s.nim"
    check I[3].line == 12

  # {.testKind: tkEdgeCase.}
  test "prefixes and objdump's # notes are dropped":
    var
      I: seq[Instr] = parseObjdump(canned)[1].instrs
    check I[0].operands == @["rax", "[rip+0x1615]"]
    check I[1].mnemonic == "stos"
    check I[0].line == 0

  # {.testKind: tkUnit.}
  test "routine flags and signatures become specs":
    var
      f: tuple[ok: bool, spec: RoutineSpec, error: string] =
        parseRoutineFlag("constantTimeEqual:s[],p@,s")
      S: seq[RoutineSpec] = specsFromSource(
        "proc eq(a, b: openArray[byte]; n: int): bool {.secret: \"b\".} =\n  discard\n", "x.nim")
    check f.ok
    check f.spec.params.len == 3
    check f.spec.params[0].kind == pkOpenArray and f.spec.params[0].secret
    check f.spec.params[1].kind == pkLenFirst and not f.spec.params[1].secret
    check not parseRoutineFlag("eq:x").ok
    check S.len == 1 and S[0].name == "eq"
    check S[0].params.len == 3
    check not S[0].params[0].secret and S[0].params[1].secret
    check S[0].params[2].kind == pkScalar

suite "ct on compiled samples":
  var
    r: CtReport = ctCheck(samples, @[])

  # {.testKind: tkIntegration.}
  test "the samples compile and all three are found":
    check r.error == ""
    check r.warnings.len == 0
    check r.results.len == 3

  # {.testKind: tkIntegration.}
  test "an early-exit compare is flagged":
    var
      x: RoutineResult = resultFor(r, "earlyExitEqual")
    check x.findings.len >= 1
    check x.findings[0].kind == fkBranch
    check x.findings[0].trail[^1].contains("parameter `")

  # {.testKind: tkIntegration.}
  test "an xor-accumulate compare comes out clean":
    var
      x: RoutineResult = resultFor(r, "xorAccumulateEqual")
    check x.instrCount > 0
    check x.findings.len == 0

  # {.testKind: tkIntegration.}
  test "a lookup indexed by a secret byte is flagged":
    var
      x: RoutineResult = resultFor(r, "secretLookup")
    check x.findings.len >= 1
    check x.findings[0].kind == fkAddress
    check x.findings[0].trail[^1].contains("parameter `x`")

suite "branch census":
  # {.testKind: tkUnit.}
  test "branch words are counted outside strings and comments":
    check branchWordsIn("while i < n and a[i] != 0:") == 2
    check branchWordsIn("x = y or z  # if not") == 1
    check branchWordsIn("echo \"if or and\"") == 0
    check branchWordsIn("acc = acc xor b") == 0

  # {.testKind: tkIntegration.}
  test "samples: the constant-time routine keeps its added jumps public":
    var
      r: CtReport = ctCheck(samples, @[])
      k: int = 0
    check r.censuses.len == r.results.len
    while k < r.results.len:
      check r.censuses[k].jumps >= r.results[k].findings.countIt(it.kind == fkBranch)
      # Optimized line information can assign the early-exit comparison to a
      # line without a branch word. Keep reporting that secret jump. The clean
      # sample still has to have only public added jumps, regardless of location.
      if r.results[k].spec.name == "xorAccumulateEqual":
        check not r.censuses[k].added.anyIt(it.secret)
      k = k + 1

  # {.testKind: tkRegression, covers: "censusOf|censusLines".}
  test "a secret jump on a branch-free source line stays visible":
    var
      C: SourceCache = initTable[string, seq[string]]()
      r: Routine = Routine(instrs: @[
        Instr(file: "sample.nim", line: 1, mnemonic: "jne"),
        Instr(file: "sample.nim", line: 2, mnemonic: "je"),
        Instr(file: "sample.nim", line: 3, mnemonic: "jne"),
        Instr(file: "sample.nim", line: 3, mnemonic: "jmp")])
      x: RoutineResult = RoutineResult(findings: @[
        Finding(file: "sample.nim", line: 1, kind: fkBranch),
        Finding(file: "sample.nim", line: 2, kind: fkBranch)])
      c: BranchCensus = BranchCensus()
    C["sample.nim"] = @["if value > 0:", "result = value", "result = other"]
    c = censusOf(r, x, C)
    check c.nimBranches == 1
    check c.jumps == 3
    check c.added.len == 2
    check c.added[0].line == 2
    check c.added[0].secret
    check c.added[1].line == 3
    check not c.added[1].secret
    check censusLines(c).join("\n").contains("SECRET sample.nim:2")
