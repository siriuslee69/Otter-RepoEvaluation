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
import otterPragmas

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
    check r.yours.len == 0
    check r.nearby.len == 0
    removeDir(dir)

  # {.testKind: tkIntegration.}
  test "a finding on a line the change touched is the reader's own":
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
    check r.hunks > 0
    for f in r.yours:
      if f.kind notin kinds:
        kinds.add(f.kind)
    check "NESTING" in kinds
    check "DEAD CODE" in kinds
    removeDir(dir)

  # {.testKind: tkUnit.}
  test "every finding carries the command that found it":
    ## A reader who has to work out how to look again mostly does not
    ## look again.
    var
      dir: string = getTempDir() / "otter_diff_cmd"
      r: DiffReview = DiffReview()
    buildRepo(dir)
    writeFile(dir / "src" / "work.nim", messySource)
    r = diffReview(dir, "HEAD")
    check r.yours.len > 0
    for f in r.yours:
      check f.command.len > 0
      check f.command.startsWith("otter-repo-graph ")
    removeDir(dir)

  # {.testKind: tkIntegration.}
  test "removing the last call to something says so":
    ## The far-reaching effect a diff hides best: the routine left
    ## with no way in sits in a file the author never opened. The
    ## removed lines name what they called, so the diff itself is
    ## enough to find it without measuring a second tree.
    var
      dir: string = getTempDir() / "otter_diff_orphan"
      r: DiffReview = DiffReview()
      names: seq[string] = @[]
    buildRepo(dir)
    writeFile(dir / "src" / "work.nim", """
proc trim*(s: string): string =
  ## s: any text. The same text without its ends.
  result = s

proc handle*(s: string): string =
  ## s: any text. What to show for it.
  result = s
""")
    r = diffReview(dir, "HEAD")
    for f in r.orphaned:
      names.add(f.what)
    check names.len == 1
    check "trim" in names[0]
    check "removed the last call" in names[0]
    removeDir(dir)

  # {.testKind: tkRegression.}
  test "the working tree is never touched, and nothing is unpacked":
    ## An earlier version wrote the whole tree as it used to be into a
    ## scratch folder. This one reads the diff instead, so there is
    ## nothing to clean up and nothing to go wrong in a folder
    ## somebody is in the middle of editing.
    var
      dir: string = getTempDir() / "otter_diff_safe"
      before: string = ""
    buildRepo(dir)
    writeFile(dir / "src" / "work.nim", messySource)
    before = readFile(dir / "src" / "work.nim")
    discard diffReview(dir, "HEAD")
    check readFile(dir / "src" / "work.nim") == before
    check git(dir, "diff --quiet") != 0
    removeDir(dir)

  # {.testKind: tkUnit.}
  test "a hunk header names the lines of the file as it is now":
    check parseHunkHeader("@@ -12,3 +40,5 @@ proc x()", "a.nim").first == 40
    check parseHunkHeader("@@ -12,3 +40,5 @@", "a.nim").last == 44
    check parseHunkHeader("@@ -12 +40 @@", "a.nim").first == 40
    check parseHunkHeader("@@ -12,3 +40,0 @@", "a.nim").last == 40
    check parseHunkHeader("nonsense", "a.nim").last < 0

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

  # {.testKind: tkRegression.}
  test "a finding somewhere the change did not touch is not the reader's":
    ## Prose added at the top of a file moves every finding in it
    ## down. Those findings are still not new, and saying they are
    ## would make the report noise.
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
    check r.yours.len == 0
    check r.nearby.len > 0
    removeDir(dir)
