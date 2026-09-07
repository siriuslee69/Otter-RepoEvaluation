# ============================================================
# | Otter Diff Review Tests                                  |
# | -> What one change did, rather than what the tree is like |
# ============================================================
#
# A throwaway repository is built in a scratch folder, committed,
# changed, and measured. That is the only honest way to test this:
# it works by measuring two trees, so it needs two trees.

import std/[os, osproc, strutils, unittest]

import ../../src/protocols/code_stats/diff_review
import ../../meta/metaPragmas

const
  cleanSource*: string = """
proc trim*(s: string): string =
  ## s: any text. The same text without its ends.
  result = s

proc handle*(s: string): string =
  ## s: any text. What to show for it.
  result = trim(s)
"""
    ## A small, tidy module. Nothing in it is worth reporting.

  messySource*: string = """
proc trim*(s: string): string =
  ## s: any text. The same text without its ends.
  result = s

proc handle*(s: string): string =
  ## s: any text. What to show for it.
  result = trim(s)

proc buried*(A: seq[seq[seq[int]]]): int =
  ## A: numbers, three deep.
  result = 0
  for a in A:
    for b in a:
      for c in b:
        if c > 0:
          if c < 100:
            result = result + c

proc lonely*(a: int): int =
  ## a: a number nobody asks about.
  result = a
"""
    ## The same module with a routine buried five blocks deep and one
    ## nothing calls.

proc git(dir, args: string): int {.testKind: tkIntegration,
    covers: "diffReview".} =
  ## dir: the repository   args: the rest of the command line.
  result = execCmd("git -C " & quoteShell(dir) & " " & args &
    " > /dev/null 2>&1")

proc buildRepo(dir: string) {.testKind: tkIntegration,
    covers: "diffReview".} =
  ## dir: where to put it.
  ## A repository with one tidy module in it, committed.
  removeDir(dir)
  createDir(dir / "src")
  writeFile(dir / "sample.nimble", """
version       = "0.1.0"
author        = "test"
description   = "a throwaway tree"
license       = "Unlicense"
srcDir        = "src"
""")
  writeFile(dir / "src" / "work.nim", cleanSource)
  discard git(dir, "init -q")
  discard git(dir, "config user.email otter-test")
  discard git(dir, "config user.name test")
  discard git(dir, "add -A")
  discard git(dir, "commit -q -m first")

suite "diff review: what one change did":

  # {.testKind: tkIntegration.}
  test "an unchanged tree reports nothing":
    var
      dir: string = getTempDir() / "otter_diff_none"
      r: DiffReview = DiffReview()
    buildRepo(dir)
    r = diffReview(dir, "HEAD")
    check r.error.len == 0
    check r.files.len == 0
    check r.appeared.len == 0
    check r.went.len == 0
    removeDir(dir)

  # {.testKind: tkIntegration.}
  test "a change that makes things worse says which things":
    var
      dir: string = getTempDir() / "otter_diff_worse"
      r: DiffReview = DiffReview()
      kinds: seq[string] = @[]
    buildRepo(dir)
    writeFile(dir / "src" / "work.nim", messySource)
    r = diffReview(dir, "HEAD")
    check r.error.len == 0
    check r.files == @["src/work.nim"]
    check r.added > 0
    for f in r.appeared:
      if f.kind notin kinds:
        kinds.add(f.kind)
    check "NESTING" in kinds
    check "DEAD CODE" in kinds
    removeDir(dir)

  # {.testKind: tkRegression.}
  test "the working tree is never touched":
    ## The tree as it was is unpacked into a scratch folder. Nothing
    ## is checked out, stashed or reset, so a folder somebody is in
    ## the middle of editing comes back exactly as it was - which is
    ## the only state this is ever run in.
    var
      dir: string = getTempDir() / "otter_diff_safe"
      before: string = ""
    buildRepo(dir)
    writeFile(dir / "src" / "work.nim", messySource)
    before = readFile(dir / "src" / "work.nim")
    discard diffReview(dir, "HEAD")
    check readFile(dir / "src" / "work.nim") == before
    check fileExists(dir / "src" / "work.nim")
    check git(dir, "diff --quiet") != 0
    removeDir(dir)

  # {.testKind: tkUnit.}
  test "numbers come back with both ends of the comparison":
    var
      dir: string = getTempDir() / "otter_diff_nums"
      r: DiffReview = DiffReview()
      found: bool = false
    buildRepo(dir)
    writeFile(dir / "src" / "work.nim", messySource)
    r = diffReview(dir, "HEAD")
    for m in r.metrics:
      if m.name != "routines":
        continue
      found = true
      check m.before == 2
      check m.after == 4
    check found
    removeDir(dir)

  # {.testKind: tkEdgeCase.}
  test "a folder that is not a repository is said so, not crashed on":
    var
      dir: string = getTempDir() / "otter_diff_bare"
      r: DiffReview = DiffReview()
    removeDir(dir)
    createDir(dir)
    r = diffReview(dir, "HEAD")
    check r.error.len > 0
    check "not a git repository" in r.error
    removeDir(dir)

  # {.testKind: tkEdgeCase.}
  test "a revision that does not exist is said so":
    var
      dir: string = getTempDir() / "otter_diff_rev"
      r: DiffReview = DiffReview()
    buildRepo(dir)
    r = diffReview(dir, "no-such-branch")
    check r.error.len > 0
    check "no commit or branch" in r.error
    removeDir(dir)

  # {.testKind: tkUnit.}
  test "a finding is matched by name, so moved lines are not new findings":
    ## Ten lines added at the top of a file move every finding in it
    ## ten lines down. Matched by line, all of them would read as gone
    ## and all of them as new, and the report would be noise.
    var
      dir: string = getTempDir() / "otter_diff_shift"
      r: DiffReview = DiffReview()
    buildRepo(dir)
    writeFile(dir / "src" / "work.nim", messySource)
    discard git(dir, "add -A")
    discard git(dir, "commit -q -m second")
    writeFile(dir / "src" / "work.nim",
      "## a new line of prose\n## and another\n" & messySource)
    r = diffReview(dir, "HEAD")
    check r.appeared.len == 0
    check r.went.len == 0
    removeDir(dir)
