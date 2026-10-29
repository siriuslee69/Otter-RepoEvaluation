## ============================================================
## | Otter Convention Rule Tests                              |
## | -> The rules one file can prove, and the repo layout     |
## ============================================================
##
## Test the library's file and layout rules from both ends: a real
## violation must be reported and nearby valid code must stay quiet.
## test_agent_hooks.sh checks the lighter shell hook's boundaries separately.

import std/[os, unittest]

import ../../src/protocols/code_stats/conventions
import runePragmas

proc has(R: seq[ConventionFinding], id: string): bool {.testKind: tkUnit,
    covers: "scanConventions".} =
  ## R: what a scan returned   id: the rule looked for.
  var
    i: int = 0
  result = false
  while i < R.len:
    if R[i].checkId == id:
      result = true
      return
    inc i

proc scratchRepo(name: string): string {.testKind: tkUnit,
    covers: "scanLayout".} =
  ## name: which throwaway tree. Built fresh under the build folder so a
  ## failed run never leaves a half-made repository behind.
  result = parentDir(parentDir(parentDir(currentSourcePath()))) /
    "build" / "convention_fixtures" / name
  removeDir(result)
  createDir(result)

suite "conventions: what one file can prove on its own":

  # {.testKind: tkUnit.}
  test "a file with no ## box is reported, once":
    var
      R: seq[ConventionFinding] = scanConventions("bare.nim",
        "proc f() =\n  discard\n")
    check has(R, "fileHeaderCheck")

  # {.testKind: tkUnit.}
  test "a file that opens with a ## box is not reported":
    var
      R: seq[ConventionFinding] = scanConventions("boxed.nim",
        "## what this file does\nproc f() =\n  discard\n")
    check not has(R, "fileHeaderCheck")

  # {.testKind: tkUnit.}
  test "a let declaration is refused, unless it is a branch init":
    var
      bad: seq[ConventionFinding] = scanConventions("a.nim",
        "## box\nlet x = 1\n")
      good: seq[ConventionFinding] = scanConventions("b.nim",
        "## box\nlet x = 1 # branch-init\n")
    check has(bad, "letDeclCheck")
    check not has(good, "letDeclCheck")

  # {.testKind: tkUnit.}
  test "two var lines at one indent are one block written twice":
    var
      R: seq[ConventionFinding] = scanConventions("a.nim",
        "## box\nvar a = 1\nvar b = 2\n")
    check has(R, "blockDeclCheck")

  # {.testKind: tkEdgeCase.}
  test "a keyword ending in a colon is not a colon call":
    var
      R: seq[ConventionFinding] = scanConventions("a.nim",
        "## box\nproc f() =\n  if true:\n    discard\n")
    check not has(R, "colonCallCheck")

  # {.testKind: tkUnit.}
  test "a camelCase parameter is named against the conventions":
    var
      bad: seq[ConventionFinding] = scanConventions("a.nim",
        "## box\nproc f(sourcePath: string) =\n  discard\n")
      good: seq[ConventionFinding] = scanConventions("b.nim",
        "## box\nproc f(dir: string) =\n  discard\n")
    check has(bad, "namingCheck")
    check not has(good, "namingCheck")

  # {.testKind: tkUnit.}
  test "an unfinished body must carry the ph_ name":
    var
      bad: seq[ConventionFinding] = scanConventions("a.nim",
        "## box\nproc widthOf(): int =\n  result = 5 # place" & "holder\n")
      good: seq[ConventionFinding] = scanConventions("b.nim",
        "## box\nproc ph_widthOf(): int =\n  result = 5 # place" &
        "holder\n")
    check has(bad, "place" & "holderCheck")
    check not has(good, "place" & "holderCheck")

  # {.testKind: tkEdgeCase.}
  test "the module does not report its own rule words":
    var
      here: string = parentDir(parentDir(parentDir(currentSourcePath()))) /
        "src" / "protocols" / "code_stats" / "conventions.nim"
      R: seq[ConventionFinding] = scanConventions(here, readFile(here))
    check not has(R, "place" & "holderCheck")
    check not has(R, "forbiddenWordCheck")

  # {.testKind: tkUnit.}
  test "every rule the scanner can report is named and carries a hint":
    var
      A: seq[ConventionRule] = conventionRules()
    check A.len > 0
    for r in A:
      check r.id.len > 0
      check r.title.len > 0
      check ruleHint(r.id) == r.hint
      check r.hint.len > 0

suite "conventions: the layout a repository is expected to have":

  # {.testKind: tkUnit.}
  test "an empty folder is missing every part of the layout":
    var
      dir: string = scratchRepo("empty")
      R: seq[ConventionFinding] = scanLayout(dir)
    check has(R, "layoutCheck")
    check has(R, "agentsFolderCheck")
    check has(R, "pragmaSourceCheck")

  # {.testKind: tkUnit.}
  test "a repository on the current layout is clean":
    var
      dir: string = scratchRepo("current")
      R: seq[ConventionFinding] = @[]
    createDir(dir / "src" / "protocols")
    createDir(dir / "evaluation" / "tests")
    createDir(dir / "agents")
    writeFile(dir / "agents" / "PROGRESS.md", "Commit Message: none\n")
    writeFile(dir / "config.nims", "switch(\"path\", \"../Rune-Pragmas/meta\")\n")
    R = scanLayout(dir)
    check R.len == 0

  # {.testKind: tkRegression.}
  test "the folder agents/ replaced is reported when left behind":
    var
      dir: string = scratchRepo("leftover")
      R: seq[ConventionFinding] = @[]
    createDir(dir / "src" / "protocols")
    createDir(dir / "evaluation" / "tests")
    createDir(dir / "agents")
    createDir(dir / ("." & "iron"))
    writeFile(dir / "agents" / "PROGRESS.md", "Commit Message: none\n")
    writeFile(dir / "config.nims", "switch(\"path\", \"../Rune-Pragmas/meta\")\n")
    R = scanLayout(dir)
    check has(R, "agentsFolderCheck")

  # {.testKind: tkRegression.}
  test "a per-repository pragma copy is reported":
    var
      dir: string = scratchRepo("copied")
      R: seq[ConventionFinding] = @[]
    createDir(dir / "src" / "protocols")
    createDir(dir / "evaluation" / "tests")
    createDir(dir / "agents")
    createDir(dir / "meta")
    writeFile(dir / "agents" / "PROGRESS.md", "Commit Message: none\n")
    writeFile(dir / "meta" / "metaPragmas.nim", "## a copy\n")
    writeFile(dir / "config.nims", "switch(\"path\", \"../Rune-Pragmas/meta\")\n")
    R = scanLayout(dir)
    check has(R, "pragmaSourceCheck")

suite "conventions: source boundaries":
  # {.testKind: tkRegression, covers: "scanConventions".}
  test "separate routines do not share a declaration block":
    var
      R = scanConventions("a.nim", "## module\nproc f() =\n  var x = 1\n  echo x\n" &
        "proc g() =\n  var y = 2\n  echo y\n")
    check not has(R, "blockDeclCheck")

  # {.testKind: tkRegression, covers: "scanConventions".}
  test "program text in multiline strings is data":
    var
      text: string = "## module\nconst sample = \"\"\"\nlet x = 1\nfoo:\n" &
        "proc f(longName: int) = discard\n\"\"\"\n"
      R = scanConventions("a.nim", text)
    check not has(R, "letDeclCheck")
    check not has(R, "colonCallCheck")
    check not has(R, "namingCheck")

  # {.testKind: tkRegression, covers: "scanConventions".}
  test "escaped quotes and hash characters do not start a comment":
    var
      R = scanConventions("a.nim", "## module\nproc f() =\n" &
        "  echo \"escaped \\\" # not implemented\"\n  echo '#'\n")
    check not has(R, "placeholderCheck")

  # {.testKind: tkRegression, covers: "scanConventions".}
  test "nested block comments do not introduce code":
    var
      R = scanConventions("a.nim", "## module\n#[\nlet x = 1\n#[ nested ]#\nfoo:\n]#\n")
    check not has(R, "letDeclCheck")
    check not has(R, "colonCallCheck")

  # {.testKind: tkRegression, covers: "scanConventions".}
  test "continued conditions and block macros are not ordinary colon calls":
    var
      good = scanConventions("a.nim", "## module\nif ready and\n    accepts(x):\n" &
        "  discard\ntogether:\n  work()\n")
      bad = scanConventions("b.nim", "## module\ndoWork:\n  input\n")
    check not has(good, "colonCallCheck")
    check has(bad, "colonCallCheck")

  # {.testKind: tkRegression, covers: "scanConventions".}
  test "typed fields and parameter continuations are not bare colon calls":
    var
      R = scanConventions("a.nim", "## module\nproc f(\n    guards: HashSet[string]):\n" &
        "  discard\nconst\n  table: array[2, byte] = block:\n    [0'u8, 1'u8]\n")
    check not has(R, "colonCallCheck")
