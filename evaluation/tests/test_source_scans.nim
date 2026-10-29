## Source scan regressions <- path identity, ignore rules, and scope totals.

import std/[os, unittest]
import otter_repo_evaluation

suite "source scans":
  var
    dir: string = getTempDir() / ("otter-source-scans-" & $getCurrentProcessId())
  setup:
    createDir(dir / "src")
  teardown:
    removeDir(dir)

  # {.testKind: tkRegression, covers: "scanUnsafeDetails".}
  test "input handlers with the same name in different files stay distinct":
    var
      a: string = dir / "src" / "input.nim"
      b: string = dir / "src" / "internal.nim"
      F: seq[FunctionInfo] = @[]
      P: seq[string] = @[a, b]
      inputs: seq[InputFuncInfo] = @[]
      R: seq[UnsafeFuncInfo] = @[]
    writeFile(a, "proc handle(p: pointer): int {.role: dataFetcher.} =\n  cast[int](p)\n")
    writeFile(b, "proc handle(p: pointer): int {.role: helper.} =\n  cast[int](p)\n")
    F = parseNimFile(dir, a) & parseNimFile(dir, b)
    inputs = scanInputDetailsAndSanitizers(dir, P, F).inputs
    R = scanUnsafeDetails(dir, P, F, inputs)
    check inputs.len == 1
    check R.len == 2
    check R[0].touchesExternalData
    check not R[1].touchesExternalData
    check R[0].path == "src/input.nim"

  # {.testKind: tkRegression, covers: "buildImportGraphAndDepth".}
  test "local import depth does not depend on file order or external libraries":
    var
      a: string = dir / "src" / "a.nim"
      b: string = dir / "src" / "b.nim"
      c: string = dir / "src" / "c.nim"
    writeFile(a, "import ./b\n")
    writeFile(b, "import ./c\n")
    writeFile(c, "import std/math\n")
    check buildImportGraphAndDepth(dir, @[a, b, c]).depth == 3
    check buildImportGraphAndDepth(dir, @[c, b, a]).depth == 3

  # {.testKind: tkRegression, covers: "buildImportGraphAndDepth".}
  test "equal file names in separate folders do not become a cycle":
    var
      a: string = dir / "src" / "left" / "types.nim"
      b: string = dir / "src" / "right" / "types.nim"
    createDir(parentDir(a))
    createDir(parentDir(b))
    writeFile(a, "import ../right/types\n")
    writeFile(b, "## leaf\n")
    check buildImportGraphAndDepth(dir, @[a, b]).depth == 2
    check buildImportGraphAndDepth(dir, @[a, b]).cycles.len == 0
    writeFile(b, "import ../left/types\n")
    check buildImportGraphAndDepth(dir, @[a, b]).cycles.len == 1

  # {.testKind: tkRegression, covers: "gatherGitignoreStats".}
  test "Git ignore negations keep a named exception":
    check gitOut(dir, ["init", "--quiet"]).ok
    writeFile(dir / ".gitignore", "*.tmp\n!keep.tmp\n")
    writeFile(dir / "drop.tmp", "one\n")
    writeFile(dir / "keep.tmp", "two\n")
    check gatherGitignoreStats(dir).ignoredFiles == 1

  # {.testKind: tkRegression, covers: "calculateScopeStats".}
  test "a tests folder under src belongs only to the test scope":
    var
      R = calculateScopeStats(@[
        FileStat(path: "src/core.nim", functions: 2, lines: 10),
        FileStat(path: "src/check/tests/test_core.nim", functions: 1, lines: 5)])
    check R.all.files == 2
    check R.src.files == 1
    check R.test.files == 1
    check R.src.avgLines == 5.0

  # {.testKind: tkUnit, covers: "scanWhenSitesAndPlatformCoverage".}
  test "platform counters have a stable order":
    var
      p: string = dir / "src" / "platform.nim"
    writeFile(p, "when defined(windows):\n  discard\nwhen defined(linux):\n  discard\n")
    check scanWhenSitesAndPlatformCoverage(dir, @[p]).platforms == @[
      NameCount(name: "windows", count: 1), NameCount(name: "linux", count: 1),
      NameCount(name: "nixos", count: 0), NameCount(name: "posix", count: 0)]

  # {.testKind: tkRegression, covers: "isTestPath".}
  test "deep fixtures are tests while production test tooling stays source":
    check isTestPath("evaluation/tests/fixtures/probe/src/worker.nim")
    check not isTestPath("src/protocols/test_scan.nim")
    check not isTestPath("src/protocols/test_ui/catalog.nim")
    check not isTestPath("/tmp/my_test_repo/src/core.nim")
    check isTestPath("test_core.nim")
