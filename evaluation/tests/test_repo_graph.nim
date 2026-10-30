## ============================================================
## | Otter Repo Graph Tests                                   |
## | -> Validate merged analysis and sample-runner flows      |
## ============================================================

import std/[json, os, sets, strutils, tables, unittest]

import otter_repo_evaluation

suite "otter repo graph":
  # {.testKind: tkIntegration.}
  test "analyze repo and build orchestrator groups":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_repo_graph_repo")
      srcDir: string = ""
      sampleFile: string = ""
      g: RepoGraph = default(RepoGraph)
      byName: Table[string, FunctionInfo] = default(Table[string, FunctionInfo])
      graphJson: JsonNode = default(JsonNode)
    if dirExists(root):
      removeDir(root)
    srcDir = joinPath(root, "src")
    createDir(srcDir)
    sampleFile = joinPath(srcDir, "sample.nim")
    writeFile(sampleFile, """
## pipeline entry for the repo graph test
proc helperA*(a: int): int =
  ## first helper branch
  result = a + 1

proc helperB*(a: int): int =
  # helper note inside body
  result = helperA(a)

## top orchestration doc
proc runPipeline*(a: int): int =
  var t: int = helperA(a)
  t = helperB(t)
  result = t

proc socketShape*(a, b: int; c: string; d: var float; flag: bool = false): string =
  d = d + 1.0
  result = c
""")
    g = analyzeRepo(root)
    check g.functions.len >= 3
    check g.groups.len >= 1
    byName = initTable[string, FunctionInfo]()
    for f in g.functions:
      byName[f.name] = f
    check byName.hasKey("helperA")
    check byName["helperA"].returnType == "int"
    check byName["helperA"].sockets.len >= 2
    check byName["socketShape"].params == @["a", "b", "c", "d", "flag"]
    check byName["socketShape"].sockets.len >= 6
    check byName["socketShape"].sockets[0].name == "a"
    check byName["socketShape"].sockets[1].name == "b"
    check byName["socketShape"].sockets[2].name == "c"
    check byName["socketShape"].sockets[3].name == "d"
    check byName["socketShape"].sockets[3].direction == sdVarInput
    check byName["socketShape"].sockets[4].name == "flag"
    check byName["socketShape"].sockets[5].name == "result"
    check byName["runPipeline"].docCommentLines.len >= 1
    check byName["helperB"].innerCommentLines.len >= 1
    graphJson = parseJson(toGraphJson(g))
    check graphJson["groups"].len >= 1
    check graphJson["functions"].len >= 3
    removeDir(root)

  # {.testKind: tkIntegration.}
  test "run exported function with generated sample args":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_repo_graph_runner")
      srcDir: string = ""
      sampleFile: string = ""
      g: RepoGraph = default(RepoGraph)
      f: FunctionInfo = default(FunctionInfo)
      r: RunSampleResult = default(RunSampleResult)
    if dirExists(root):
      removeDir(root)
    srcDir = joinPath(root, "src")
    createDir(srcDir)
    sampleFile = joinPath(srcDir, "sample.nim")
    writeFile(sampleFile, """
proc addPair*(a: int, b: int): int =
  result = a + b
""")
    g = analyzeRepo(root)
    f = g.functions[0]
    r = runFunctionSample(root, f.id)
    check r.ok
    check r.resultText == "84"
    check r.generatedArgs.len >= 2
    removeDir(root)

suite "otter repo graph: where a routine ends":

  # {.testKind: tkRegression.}
  test "a body stops at the routine's own indentation, not at the next proc":
    ## Pins a parser bug that moved every number drawn from a body.
    ## Only the next routine used to end a body, so a trailing
    ## `when isMainModule` block, and any `type` or `const` section
    ## written after the last routine of a file, were handed to
    ## whoever came last. That routine then looked longer than it is,
    ## looked as though it asserted, and hid any routine declared
    ## inside the block from being found at all.
    var
      root: string = joinPath(getCurrentDir(), "build", "test_parser_end")
      g: RepoGraph = RepoGraph()
      byName: Table[string, FunctionInfo] = initTable[string, FunctionInfo]()
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    writeFile(joinPath(root, "sample.nimble"), "srcDir = \"src\"\n")
    writeFile(joinPath(root, "src", "edges.nim"), """
proc stream*(n: int): seq[byte] =
  ## n: how many bytes.
  result = newSeq[byte](n)

when defined(extras):
  proc hidden*(a: int): int =
    ## a: any number.
    result = a

type
  Late* = object
    width*: int

when isMainModule:
  doAssert stream(1).len == 1
""")
    g = analyzeRepo(root)
    for f in g.functions:
      byName[f.name] = f
    check byName.hasKey("stream")
    check byName["stream"].bodyLines.len == 2
    for line in byName["stream"].bodyLines:
      check "doAssert" notin line
      check "Late" notin line
    ## A routine written inside a `when` block used to be swallowed by
    ## the routine above it and never found.
    check byName.hasKey("hidden")
    removeDir(root)

  # {.testKind: tkRegression.}
  test "a pragma and a top-level call both count as using a routine":
    ## A macro written to be used as a pragma is applied by name and
    ## never called, and a routine reached only from a module's own
    ## top level has no caller either. Both used to read as dead.
    var
      root: string = joinPath(getCurrentDir(), "build", "test_parser_uses")
      s: ProjectStats = ProjectStats()
      dead: seq[string] = @[]
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    writeFile(joinPath(root, "sample.nimble"), "srcDir = \"src\"\n")
    writeFile(joinPath(root, "src", "uses.nim"), """
import std/macros

macro loud*(def: untyped): untyped =
  ## def: a routine. Handed back unchanged.
  result = def

macro wrapped*(cond: untyped, def: untyped): untyped =
  ## cond: anything   def: a routine. Handed back unchanged.
  result = def

proc onlyFromTop*(a: int): int =
  ## a: any number.
  result = a

proc marked*(a: int): int {.loud.} =
  ## a: any number.
  result = a

proc spread*(a, b: int): int {.wrapped: a <= b,
    loud.} =
  ## a, b: any numbers.
  result = b - a

echo onlyFromTop(3), marked(1), spread(1, 2)
""")
    s = analyzeProject(root)
    for it in s.unusedFuncs.items:
      dead.add(it.name)
    check "loud" notin dead
    check "wrapped" notin dead
    check "onlyFromTop" notin dead
    removeDir(root)

suite "tag pragma shapes":
  ## Tags used to be a per-repository enum, which forced the pragma file to
  ## be copied per repository. They are strings now, and three shapes are in
  ## the tree at once while the workspace catches up. All three have to reach
  ## the charts as the same bare names, or a repo silently loses its tags.
  # {.testKind: tkRegression.}
  test "string, list and the older enum set all yield the same tags":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_tag_shapes_repo")
      srcDir: string = ""
      g: RepoGraph = default(RepoGraph)
      byName: Table[string, FunctionInfo] = initTable[string, FunctionInfo]()
    if dirExists(root):
      removeDir(root)
    srcDir = joinPath(root, "src")
    createDir(srcDir)
    writeFile(joinPath(srcDir, "shapes.nim"), """
proc viaString*() {.role: parser, tag: "ame|kdf".} =
  discard

proc viaList*() {.role: parser, tag: ["ame", "kdf"].} =
  discard

proc viaEnumSet*() {.role: parser, tag: "ame|kdf".} =
  discard
""")
    g = analyzeRepo(root)
    for f in g.functions:
      byName[f.name] = f
    for name in ["viaString", "viaList", "viaEnumSet"]:
      check byName.hasKey(name)
      ## Bare names, whichever shape they were written in: no brackets, no
      ## quotes, no braces, and no `tag` prefix left over from the enum.
      check "ame" in byName[name].pragmaTags
      check "kdf" in byName[name].pragmaTags
      check "tagame" notin byName[name].pragmaTags
      check "{tagame" notin byName[name].pragmaTags
    removeDir(root)

  # {.testKind: tkRegression, pins: "a doc line `## @tags` was read as `@tag`, so its first word became a tag".}
  test "a doc directive named tags is read as tags, not as a tag with a stray word":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_doc_tags_repo")
      g: RepoGraph = default(RepoGraph)
      byName: Table[string, FunctionInfo] = initTable[string, FunctionInfo]()
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    writeFile(joinPath(root, "src", "docs.nim"), """
## @tags alpha|beta
proc tagged*(): int =
  1
""")
    g = analyzeRepo(root)
    for f in g.functions:
      byName[f.name] = f
    check byName.hasKey("tagged")
    check "alpha" in byName["tagged"].pragmaTags
    check "beta" in byName["tagged"].pragmaTags
    check "s alpha" notin byName["tagged"].pragmaTags
    removeDir(root)

  # {.testKind: tkRegression, pins: "routines written inside a triple-quoted string were counted as code".}
  test "text inside a triple-quoted string is not read as code":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_quoted_repo")
      g: RepoGraph = default(RepoGraph)
      names: seq[string] = @[]
      q3: string = "\"\"\""
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    writeFile(joinPath(root, "src", "fixture.nim"),
      "const sample* = " & q3 & "\nproc inner*() =\n  discard\n" & q3 &
      "\n\nproc outer*(): int =\n  1\n")
    g = analyzeRepo(root)
    for f in g.functions:
      names.add(f.name)
    check "outer" in names
    check "inner" notin names
    removeDir(root)

suite "otter repo graph: headers and uses that read like something else":
  # {.testKind: tkRegression, pins: "a default value ending a line was read as the body, and the role after it was lost".}
  test "a parameter default at the end of a line is not the body":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_default_eq_repo")
      g: RepoGraph = default(RepoGraph)
      byName: Table[string, FunctionInfo] = initTable[string, FunctionInfo]()
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    writeFile(joinPath(root, "src", "limits.nim"), """
proc openConnection*(L: int =
    defaultLimit()): int {.role: truthBuilder,
    tag: "http".} =
  result = L
""")
    g = analyzeRepo(root)
    for f in g.functions:
      byName[f.name] = f
    check byName.hasKey("openConnection")
    check "role:truth_builder" in byName["openConnection"].pragmaTags
    removeDir(root)

  # {.testKind: tkRegression, pins: "a routine only handed to createThread was reported as dead".}
  test "a routine handed over by name is used":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_passed_repo")
      s: ProjectStats = ProjectStats()
      dead: seq[string] = @[]
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    writeFile(joinPath(root, "sample.nimble"), "srcDir = \"src\"\n")
    writeFile(joinPath(root, "src", "threads.nim"), """
proc worker(a: int) {.thread.} =
  ## a: any number.
  discard a

proc cmpRows(a, b: int): int =
  ## a, b: two rows.
  result = a - b

proc start*() =
  var
    t: Thread[int]
    rows: seq[int] = @[3, 1]
  createThread(t, worker, 1)
  rows.sort(cmpRows)
""")
    s = analyzeProject(root)
    for it in s.unusedFuncs.items:
      dead.add(it.name)
    check "worker" notin dead
    check "cmpRows" notin dead

  # {.testKind: tkRegression, pins: "converters, generic calls and operators were reported as dead".}
  test "a converter, a generic call and an operator are used":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_implicit_repo")
      s: ProjectStats = ProjectStats()
      dead: seq[string] = @[]
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    writeFile(joinPath(root, "sample.nimble"), "srcDir = \"src\"\n")
    writeFile(joinPath(root, "src", "implicit.nim"), """
type
  Row = object
    n: int

converter toRow*(n: int): Row =
  result = Row(n: n)

proc `$`*(r: Row): string =
  result = "row"

proc decodeAs[T](v: int): T =
  result = T(v)

proc start*(): string =
  var
    r: Row = 3
  result = $r & $decodeAs[int](4)
""")
    s = analyzeProject(root)
    for it in s.unusedFuncs.items:
      dead.add(it.name)
    check "toRow" notin dead
    check "decodeAs" notin dead
    check "$" notin dead

  # {.testKind: tkRegression, pins: "a routine passed on a continuation line of a call was reported as dead".}
  test "a routine passed by name on a continuation line is used":
    var
      known: HashSet[string] = ["checkbuilt", "fill"].toHashSet()
      got: seq[string] = passedNames(@["  result = fill(A, \"cipher\",",
        "    checkBuilt)"], known)
    check "checkBuilt" in got

suite "otter test walk: what a test really reaches":
  # {.testKind: tkRegression, pins: "calls resolved to a forward declaration, so the routine itself read as untested".}
  test "a forward-declared routine is reached through its declaration":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_fwd_repo")
      s: ProjectStats = ProjectStats()
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    createDir(joinPath(root, "evaluation", "tests"))
    writeFile(joinPath(root, "sample.nimble"), "srcDir = \"src\"\n")
    writeFile(joinPath(root, "src", "fwd.nim"), """
proc parseNode*(n: int): int

proc parseList*(n: int): int =
  result = parseNode(n) + 1

proc parseNode*(n: int): int =
  result = n * 2
""")
    writeFile(joinPath(root, "evaluation", "tests", "test_fwd.nim"), """
import unittest
import ../../src/fwd
suite "fwd":
  test "list":
    check parseList(1) == 3
""")
    s = analyzeProject(root)
    check s.tests.untested.len == 0
    removeDir(root)

  # {.testKind: tkRegression, pins: "a routine a test reached only through a thread or a callback read as untested".}
  test "a routine handed over by name is reached through the one it is handed to":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_walk_passed_repo")
      s: ProjectStats = ProjectStats()
    if dirExists(root):
      removeDir(root)
    createDir(joinPath(root, "src"))
    createDir(joinPath(root, "evaluation", "tests"))
    writeFile(joinPath(root, "sample.nimble"), "srcDir = \"src\"\n")
    writeFile(joinPath(root, "src", "tasks.nim"), """
proc doubleIt*(x: var int) =
  x = x * 2

proc runAll*(A: var seq[int], work: proc (x: var int)) =
  for a in A.mitems:
    work(a)

proc doubleAll*(A: var seq[int]) =
  runAll(A, doubleIt)
""")
    writeFile(joinPath(root, "evaluation", "tests", "test_tasks.nim"), """
import unittest
import ../../src/tasks
proc helper(): seq[int] =
  result = @[1, 2]
  doubleAll(result)
suite "tasks":
  test "doubles":
    check helper() == @[2, 4]
""")
    s = analyzeProject(root)
    check s.tests.untested.len == 0
    removeDir(root)
