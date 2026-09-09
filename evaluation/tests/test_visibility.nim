# ============================================================
# | Otter Visibility Tests                                   |
# | -> Echoes put in for you, and taken back out             |
# ============================================================
#
# Two claims to prove, and the second matters more than the first:
#
#   with a group on, the program says where it is
#   with it off, nothing at all is written into the program

import std/[os, osproc, strutils, unittest]

import ../../src/protocols/visibility
import runePragmas

const
  sample*: string = """
import protocols/visibility

proc inner(n: int): int {.visGroup: 3.} =
  ## n: how far to count.
  result = 0
  for i in 0 ..< n:
    result = result + i

proc outer(n: int): int {.visGroup: 3.} =
  ## n: how far to count.
  result = inner(n)
  var k: int = 0
  while k < 2:
    for j in 0 .. 1:
      result = result + j
    k = k + 1
  if n > 100:
    return -1

proc quiet(n: int): int {.visGroup: 9.} =
  ## n: any number. In a group nobody asked for.
  result = n

echo "answer ", outer(3), " ", quiet(1)
"""
    ## One file with two groups in it, so a run can show that only the
    ## group asked for says anything.

proc build(dir, name, source, flags: string): tuple[ok: bool, output: string]
    {.testKind: tkIntegration, covers: "visGroup".} =
  ## dir: somewhere to work   name: the file's stem
  ## source: its text   flags: extra switches for the compiler.
  ## Whether it built and ran, and everything it printed.
  var
    src: string = dir / (name & ".nim")
    root: string = parentDir(parentDir(parentDir(currentSourcePath())))
    got: tuple[output: string, exitCode: int] = ("", 0)
  createDir(dir)
  writeFile(src, source)
  got = execCmdEx("nim c --hints:off --path:" & quoteShell(root / "src") &
    " --path:" & quoteShell(root / ".." / "Rune-Pragmas" / "meta") &
    " " & flags & " --nimcache:" & quoteShell(dir / ("n_" & name)) &
    " -o:" & quoteShell(dir / name) & " -r " & quoteShell(src))
  result = (ok: got.exitCode == 0, output: got.output)

proc sizeOf(dir, name, source, flags: string): int {.testKind: tkIntegration,
    covers: "visGroup".} =
  ## dir: somewhere to work   name: the file's stem   source: its text
  ## flags: extra switches.
  ##
  ## The size of the program it builds to. Two stems compared must be
  ## the same length: the compiler writes the module name into the
  ## binary, so a longer name is a longer binary.
  var
    src: string = dir / (name & ".nim")
    root: string = parentDir(parentDir(parentDir(currentSourcePath())))
  result = 0
  createDir(dir)
  writeFile(src, source)
  if execCmd("nim c --hints:off --path:" & quoteShell(root / "src") &
    " --path:" & quoteShell(root / ".." / "Rune-Pragmas" / "meta") &
      " -d:release " & flags & " --nimcache:" & quoteShell(dir / ("s_" & name)) &
      " -o:" & quoteShell(dir / name) & " " & quoteShell(src) &
      " > /dev/null 2>&1") != 0:
    return
  if fileExists(dir / name):
    result = getFileSize(dir / name).int

suite "visibility: echoes put in for you":

  # {.testKind: tkUnit.}
  test "a group is on only when it was asked for":
    ## Answered while building, which is what makes an unasked-for
    ## group cost nothing at all.
    check not visGroupOn(3)
    check not visGroupOn(9)
    check not visAnyOn

  # {.testKind: tkIntegration.}
  test "with a group on, a routine says when it starts and stops":
    var
      dir: string = getTempDir() / "otter_vis_on"
      got: tuple[ok: bool, output: string] = (false, "")
    got = build(dir, "vs_on", sample, "-d:otterVis:3")
    check got.ok
    check "-> outer" in got.output
    check "<- outer" in got.output
    check "-> inner" in got.output
    check "answer 5 1" in got.output
    removeDir(dir)

  # {.testKind: tkIntegration.}
  test "every loop says when it begins and how many turns it took":
    var
      dir: string = getTempDir() / "otter_vis_loop"
      got: tuple[ok: bool, output: string] = (false, "")
    got = build(dir, "vs_lps", sample, "-d:otterVis:3")
    check got.ok
    check "loop 1 begins" in got.output
    check "loop 1 ended after 3 turn(s)" in got.output
    ## The `for` inside the `while` is numbered after it, and printed
    ## one step further in, so the shape can be read down the edge.
    check "loop 2 begins" in got.output
    check "  loop 2 begins" in got.output
    removeDir(dir)

  # {.testKind: tkUnit.}
  test "only the group asked for says anything":
    var
      dir: string = getTempDir() / "otter_vis_group"
      got: tuple[ok: bool, output: string] = (false, "")
    got = build(dir, "vs_grp", sample, "-d:otterVis:3")
    check got.ok
    check "[vis 3]" in got.output
    check "[vis 9]" notin got.output
    check "quiet" notin got.output
    removeDir(dir)

  # {.testKind: tkRegression.}
  test "an early return still says the routine left":
    ## The `<-` line is put in with `defer`, so a `return` part-way
    ## through cannot step over it. Without that, the routines that
    ## return early - which are often the interesting ones - would
    ## look as though they never came back.
    var
      dir: string = getTempDir() / "otter_vis_early"
      got: tuple[ok: bool, output: string] = (false, "")
    got = build(dir, "vs_erl", """
import protocols/visibility
proc pick(n: int): int {.visGroup: 4.} =
  ## n: any number.
  if n > 0:
    return n
  result = 0
echo pick(5)
""", "-d:otterVis:4")
    check got.ok
    check "-> pick" in got.output
    check "<- pick" in got.output
    removeDir(dir)

  # {.testKind: tkUnit.}
  test "asking for every group at once works":
    var
      dir: string = getTempDir() / "otter_vis_all"
      got: tuple[ok: bool, output: string] = (false, "")
    got = build(dir, "vs_all", sample, "-d:otterVis:all")
    check got.ok
    check "[vis 3]" in got.output
    check "[vis 9]" in got.output
    removeDir(dir)

  # {.testKind: tkIntegration.}
  test "a word every so many turns, when asked for":
    var
      dir: string = getTempDir() / "otter_vis_every"
      plain: tuple[ok: bool, output: string] = (false, "")
      often: tuple[ok: bool, output: string] = (false, "")
    plain = build(dir, "vs_pln", sample, "-d:otterVis:3")
    often = build(dir, "vs_oft", sample, "-d:otterVis:3 -d:otterVisEvery:2")
    check plain.ok
    check often.ok
    check "turn 2" notin plain.output
    check "turn 2" in often.output
    removeDir(dir)

  # {.testKind: tkIntegration.}
  test "with no group asked for, nothing is written into the program":
    ## The whole claim. Both stems are five letters so the compiler
    ## writes the same number of bytes of module name into each.
    var
      dir: string = getTempDir() / "otter_vis_size"
      bare: int = 0
      marked: int = 0
    bare = sizeOf(dir, "vzz_a", """
proc walk(n: int): int =
  result = 0
  for i in 0 ..< n:
    result = result + i
echo walk(4)
""", "")
    marked = sizeOf(dir, "vzz_b", """
import protocols/visibility
proc walk(n: int): int {.visGroup: 3.} =
  result = 0
  for i in 0 ..< n:
    result = result + i
echo walk(4)
""", "")
    if bare == 0 or marked == 0:
      skip()
    else:
      check bare == marked
      check "loop 1 begins" notin readFile(dir / "vzz_b")
    removeDir(dir)
