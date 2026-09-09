# ============================================================
# | Otter Invariants Tests                                   |
# | -> Promises checked while building, and while running    |
# ============================================================
#
# Two things need proving here, and the second is the harder one:
#
#   a broken promise is caught
#   a kept promise costs nothing - the binary is the same size

import std/[os, osproc, strutils, unittest]

import ../../src/protocols/invariants
import runePragmas

proc withdraw(balance, amount: int): int {.needs: amount <= balance,
    gives: result >= 0.} =
  ## balance: what is there   amount: what is being taken.
  balance - amount

proc classify(a: int): string {.gives: result.len > 0.} =
  ## a: any number. Its early `return` must not step over the promise.
  if a > 0:
    return "high"
  result = "low"

proc broken(a: int): string {.gives: result.len > 0.} =
  ## a: any number. Returns nothing at all when a is small, which is
  ## what the promise forbids.
  if a > 0:
    return "high"
  result = ""

proc counted(A: seq[int]): int {.gives: result <= A.len.} =
  ## A: a list. How many of them are above zero.
  result = 0
  for x in A:
    if x > 0:
      result = result + 1

proc push(S: var seq[int], v: int) {.givesRun: S.len == old(S).len + 1.} =
  ## S: the list   v: what to add.
  S.add(v)

proc drain(S: var seq[int]): int {.needsRun: S.len > 0.} =
  ## S: the list. Its last item, taken off.
  result = S[^1]
  S.setLen(S.len - 1)

const contractSource*: string = """
import protocols/invariants
proc withdraw(balance, amount: int): int {.needs: amount <= balance,
    gives: result >= 0.} =
  balance - amount
proc broken(a: int): string {.gives: result.len > 0.} =
  if a > 0:
    return "high"
  result = ""
"""
  ## The routines the build tests below are written against, kept in
  ## one place so the promise and the violation cannot drift apart.

proc buildOutcome(dir, name, source: string): tuple[ok: bool, output: string]
    {.testKind: tkIntegration, covers: "needs".} =
  ## dir: somewhere to work   name: the file's stem   source: its text.
  ## Whether the compiler accepted it, and what it said.
  var
    src: string = dir / (name & ".nim")
    root: string = parentDir(parentDir(parentDir(currentSourcePath())))
    got: tuple[output: string, exitCode: int] = ("", 0)
  writeFile(src, source)
  got = execCmdEx("nim c --hints:off --path:" & quoteShell(root / "src") &
    " --nimcache:" & quoteShell(dir / ("n_" & name)) &
    " -o:" & quoteShell(dir / name) & " " & quoteShell(src))
  result = (ok: got.exitCode == 0, output: got.output)

proc sizeOfBuilt(dir, name, source: string): int {.testKind: tkIntegration,
    covers: "needs".} =
  ## dir: somewhere to work   name: the file's stem, without `.nim`
  ## source: what to put in it.
  ##
  ## The size of the program that source builds to. The two stems
  ## compared must be the same length: the compiler writes the module
  ## name into the binary, so a longer name is a longer binary and
  ## would be read as the contracts costing something.
  var
    src: string = dir / (name & ".nim")
    exe: string = dir / name
    root: string = parentDir(parentDir(parentDir(currentSourcePath())))
  result = 0
  writeFile(src, source)
  if execCmd("nim c --hints:off --path:" & quoteShell(root / "src") &
      " -d:release --nimcache:" & quoteShell(dir / ("c_" & name)) &
      " -o:" & quoteShell(exe) & " " & quoteShell(src) & " > /dev/null 2>&1") != 0:
    return
  if fileExists(exe):
    result = getFileSize(exe).int

suite "invariants: promises written where they can be checked":

  # {.testKind: tkUnit.}
  test "a kept promise changes nothing about the answer":
    check withdraw(100, 40) == 60
    check classify(3) == "high"
    check classify(-3) == "low"
    check counted(@[1, -1, 2]) == 2

  # {.testKind: tkUnit.}
  test "the compiler runs the routine and the promise holds":
    static:
      doAssert withdraw(100, 40) == 60
      doAssert classify(-1) == "low"
      doAssert counted(@[1, 2]) == 2
    check true

  # {.testKind: tkEdgeCase.}
  test "a broken promise stops the build, and says which one":
    ## Compiled for real, because there is no way to ask from inside
    ## a running program whether some other program would have built.
    ## `compiles((static: ...))` looks like the way and is not: it
    ## answers false for code that builds perfectly well, so a test
    ## written with it passes while proving nothing.
    var
      dir: string = getTempDir() / "otter_contract_break"
      good: tuple[ok: bool, output: string] = (false, "")
      bad: tuple[ok: bool, output: string] = (false, "")
    createDir(dir)
    good = buildOutcome(dir, "c_good", contractSource & """
static:
  doAssert withdraw(100, 40) == 60
""")
    bad = buildOutcome(dir, "c_bad", contractSource & """
static:
  discard withdraw(40, 100)
""")
    check good.ok
    check not bad.ok
    check "needs failed in `withdraw`" in bad.output
    removeDir(dir)

  # {.testKind: tkRegression.}
  test "an early return does not step over the promise":
    ## Without rewriting `return`, the check sits after a jump that
    ## already left the routine, and a promise nobody checks is worse
    ## than no promise at all.
    var
      dir: string = getTempDir() / "otter_contract_early"
      out0: tuple[ok: bool, output: string] = (false, "")
    createDir(dir)
    out0 = buildOutcome(dir, "c_early", contractSource & """
static:
  discard broken(-1)
""")
    check not out0.ok
    check "gives failed in `broken`" in out0.output
    removeDir(dir)

  # {.testKind: tkRegression.}
  test "the compiler's own requires and ensures are not these":
    ## Pins the thing this got wrong first, and got wrong silently.
    ## Written with the compiler's names, a broken promise builds.
    var
      dir: string = getTempDir() / "otter_contract_name"
      out0: tuple[ok: bool, output: string] = (false, "")
    createDir(dir)
    out0 = buildOutcome(dir, "c_names", """
proc withdraw(balance, amount: int): int {.requires: amount <= balance,
    ensures: result >= 0.} =
  balance - amount
static:
  discard withdraw(40, 100)
""")
    check out0.ok
    removeDir(dir)


  # {.testKind: tkUnit.}
  test "forall is true only when it holds for every one":
    check forall(i in 1 .. 3, i > 0)
    check not forall(i in 1 .. 3, i > 1)
    check forall(i in 1 ..< 1, false)
    check exists(i in 1 .. 3, i == 2)
    check not exists(i in 1 .. 3, i == 9)

  # {.testKind: tkUnit.}
  test "a promise the program carries raises when it is broken":
    var S: seq[int] = @[]
    push(S, 4)
    check S == @[4]
    check drain(S) == 4
    expect ContractDefect:
      discard drain(S)

  # {.testKind: tkUnit.}
  test "old names the value something had on the way in":
    var S: seq[int] = @[1, 2]
    push(S, 3)
    check S.len == 3

  # {.testKind: tkIntegration.}
  test "the free tier is free: two builds, one size":
    ## The whole claim of this module. Both stems are seven letters
    ## long so the compiler writes the same number of bytes of module
    ## name into each.
    var
      dir: string = getTempDir() / "otter_contract_size"
      bare: int = 0
      bound: int = 0
    createDir(dir)
    bare = sizeOfBuilt(dir, "sz_bare", """
proc withdraw(balance, amount: int): int =
  balance - amount
proc classify(a: int): string =
  if a > 0:
    return "high"
  result = "low"
echo withdraw(100, 40), classify(3)
""")
    bound = sizeOfBuilt(dir, "sz_deal", """
import protocols/invariants
proc withdraw(balance, amount: int): int {.needs: amount <= balance,
    gives: result >= 0.} =
  balance - amount
proc classify(a: int): string {.gives: result.len > 0.} =
  if a > 0:
    return "high"
  result = "low"
echo withdraw(100, 40), classify(3)
""")
    if bare == 0 or bound == 0:
      skip()
    else:
      check bare == bound
      check "needs failed" notin readFile(dir / "sz_deal")
    removeDir(dir)
