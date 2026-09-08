# ============================================================
# | Otter Code Statistics Project                            |
# | -> analyzeProject: one folder in, one shape out          |
# ============================================================
#
# This is the whole entry point. A window hands it a folder and gets
# back everything it needs to draw:
#
#     analyzeProject("/home/me/MyRepo")
#       .files      one cell per file
#       .nest       the bars
#       .tests      the rings
#       .roles      the tally
#
# Nothing is cached here. A caller that wants the figures kept keeps
# them itself, because the tree changes under us while an agent works
# and a stale chart is worse than a slow one.

import std/[os, sets, strutils, tables]

import ./pipeline
import ./test_scan
import ./types
import ./shape
import ./placeholders
import ./embedded
import ./families
import ./state_writes
import ./yields
import ./secrets
import ./config_touch
import ./timeline
import ./unused
import ./call_depth
import ./coupling
import ../repo_graph/graph_builder
import ../repo_graph/io_utils
import ../repo_graph/nim_parser
import ../repo_graph/types as graphTypes
import otterPragmas

proc parseTree*(rootDir: string, files: seq[string]): seq[FunctionInfo]
    {.role: parser, metaTags: {tagStats}.} =
  ## rootDir: the tree. files: every Nim file in it, tests included.
  result = @[]
  for path in files:
    for row in parseNimFile(rootDir, path):
      result.add(row)


proc splitTests*(A: seq[FunctionInfo]): tuple[src: seq[FunctionInfo],
    tests: seq[FunctionInfo]] {.role: parser, metaTags: {tagStats}.} =
  ## A: every routine in the tree, split by where it was written.
  result = (@[], @[])
  for row in A:
    if isTestPath(row.sourcePath):
      result.tests.add(row)
    else:
      result.src.add(row)


proc gatherTests*(files: seq[string], A: seq[FunctionInfo]): seq[TestInfo]
    {.role: truthBuilder, metaTags: {tagStats, tagTesting}.} =
  ## files: every file in the tree. A: the routines written in tests.
  ## Both shapes of test are gathered: the `test "..."` block and the
  ## routine carrying a testKind pragma.
  var
    row: TestInfo
  result = @[]
  for path in files:
    if not isTestPath(path):
      continue
    for found in scanTestFile(path):
      result.add(found)
  for fn in A:
    row = pragmaTest(fn)
    if row.kind.len > 0:
      result.add(row)


proc rolesOf*(A: seq[FunctionInfo]): seq[NameCount] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A: every routine outside the tests. What each one declared itself
  ## to be, tallied. Routines with no role pragma are counted as
  ## "undeclared", because a blank is a finding of its own.
  var
    name: string = ""
  result = @[]
  for row in A:
    name = declaredRoleOf(row)
    if name.len == 0:
      name = "undeclared"
    addCount(result, name)


proc unusedOf*(A: seq[FunctionInfo], edges: seq[CallEdge], w: CoverWalk,
    pragmas: HashSet[string]): seq[string] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A: the routines outside the tests. edges: the call graph. w: what
  ## the tests reach. pragmas: template names used as pragmas, which is
  ## a use that leaves no call behind. A routine nothing calls and no
  ## test runs is named; an entry point is not, because something
  ## outside the tree calls those.
  var
    called: HashSet[string] = calledSet(edges)
  result = @[]
  for row in A:
    if row.id in called or w.hits.getOrDefault(row.id) > 0:
      continue
    if row.name.toLowerAscii() in pragmas:
      continue
    if row.name == "main" or row.name == "isMainModule":
      continue
    result.add(row.modulePath & "::" & row.name)


proc totalsOf(S: var ProjectStats, A: seq[FunctionInfo]) {.role: actor,
    metaTags: {tagStats}.} =
  ## S: the statistics being filled. A: the routines outside the tests.
  var
    total: int = 0
    name: string = ""
  for row in A:
    total = total + lengthOf(row)
    if row.declKind == "template":
      S.templates = S.templates + 1
    if row.declKind == "macro":
      S.macros = S.macros + 1
    if isInput(row):
      S.inputFunctions = S.inputFunctions + 1
    name = declaredRoleOf(row)
    if name == "math":
      S.mathFunctions = S.mathFunctions + 1
    elif name == "helper":
      S.helperFunctions = S.helperFunctions + 1
    elif name == "truth builder" or name == "truth state" or
        name == "state controller":
      S.truthFunctions = S.truthFunctions + 1
  S.functions = A.len
  if A.len > 0:
    S.avgLines = total.float / A.len.float


proc analyzeProject*(rootDir: string): ProjectStats {.role: orchestrator,
    input: trusted, risk: low, speed: long, metaTags: {tagStats}.} =
  ## rootDir: the folder to measure. An unreadable folder comes back
  ## with `error` set and everything else empty, so a window can say so
  ## instead of drawing an empty chart that looks like good news.
  var
    files: seq[string] = @[]
    allSourceFiles: seq[string] = @[]
    all: seq[FunctionInfo] = @[]
    parts: tuple[src: seq[FunctionInfo], tests: seq[FunctionInfo]]
    graph: tuple[edges: seq[CallEdge], unresolved: seq[string]]
    wholeGraph: RepoGraph = RepoGraph()
    tests: seq[TestInfo] = @[]
    walk: CoverWalk
    marks: HashSet[string]
  let normDir = normalizeSlashes(rootDir)
  result = ProjectStats(rootDir: normDir, isGitRepo: false, files: @[],
    totalLines: 0, functions: 0, templates: 0, macros: 0, avgLines: 0.0,
    inputFunctions: 0, truthFunctions: 0, mathFunctions: 0,
    helperFunctions: 0, unusedCount: 0, unused: @[], roles: @[],
    langStats: @[], gitignore: GitignoreStat(), inputDetails: @[],
    unsafeDetails: @[], unusedImports: @[], whenSites: @[], importGraphDepth: 0,
    circularImports: @[], platformCoverage: @[], simdSites: @[],
    srcStats: ProjectScopeStats(), allStats: ProjectScopeStats(), testStats: ProjectScopeStats(),
    nest: NestStats(), tests: TestStats(), error: "")

  # Git initialized workspace enforcement
  if not dirExists(normDir / ".git") and not fileExists(normDir / ".git"):
    result.error = "Not a git initialized workspace: .git folder missing"
    return

  result.isGitRepo = true
  files = listNimFiles(rootDir, true)
  if files.len == 0:
    result.error = "no Nim files under " & rootDir
    return

  allSourceFiles = listAllSourceFiles(rootDir)
  result.langStats = gatherLangStats(allSourceFiles)
  result.gitignore = gatherGitignoreStats(rootDir)

  all = parseTree(rootDir, files)
  parts = splitTests(all)
  graph = buildCallGraph(all)
  marks = templateNames(all)
  tests = gatherTests(files, parts.tests)
  walk = walkTests(parts.src, tests, graph.edges)
  result.files = collectFiles(rootDir, all, files, marks, walk)
  result.nest = nestOf(parts.src, marks)
  result.tests = coverageOf(parts.src, tests, walk)
  result.roles = rolesOf(parts.src)
  result.unused = unusedOf(parts.src, graph.edges, walk, pragmaKeys(all))
  result.unusedCount = result.unused.len
  if result.unused.len > unusedShown:
    result.unused.setLen(unusedShown)
  totalsOf(result, parts.src)

  let inputScan = scanInputDetailsAndSanitizers(rootDir, allSourceFiles, parts.src)
  result.inputDetails = inputScan.inputs
  result.inputFunctions = max(result.inputFunctions, inputScan.inputCount)

  result.unsafeDetails = scanUnsafeDetails(rootDir, allSourceFiles, parts.src, inputScan.inputs, graph.edges)
  result.unusedImports = scanUnusedImports(rootDir, allSourceFiles)

  let whenAndPlat = scanWhenSitesAndPlatformCoverage(rootDir, allSourceFiles)
  result.whenSites = whenAndPlat.sites
  result.platformCoverage = whenAndPlat.platforms
  result.simdSites = whenAndPlat.simd

  let graphDepthAndCycles = buildImportGraphAndDepth(rootDir, allSourceFiles)
  result.importGraphDepth = graphDepthAndCycles.depth
  result.circularImports = graphDepthAndCycles.cycles

  let scopeBreakdowns = calculateScopeStats(result.files)
  result.srcStats = scopeBreakdowns.src
  result.allStats = scopeBreakdowns.all
  result.testStats = scopeBreakdowns.test

  for row in result.files:
    result.totalLines = result.totalLines + row.lines

  # ---- the six reports beside this file ------------------------------
  #
  # All six are worked out from `all`, the one parse of the tree made
  # near the top of this routine, so nothing here reads a file twice
  # and no two reports can disagree about what the source says.
  #
  #   all ─┬─► shape        alike routines, and the point cloud
  #        ├─► placeholders routines that do nothing yet
  #        ├─► unused       routines nothing calls, and their size
  #        └─► config       which settings anything reads
  #
  #   the folder ─┬─► secrets   keys, in the tree and in its history
  #               └─► timeline  the tree at a spread of past moments
  #
  # `calledNames` is every name anything in the tree calls, lowered.
  # Two of the reports need it and neither should build it again.
  #
  # Three kinds of use count, not one. A routine reads as dead only
  # when none of them names it:
  #
  #   something calls it        parseWidth(s)
  #   a pragma applies it       {.needs: b <= a.}   <- never "called"
  #   top-level code calls it   when isMainModule: stream(1)
  #
  # The last two used to be invisible, so every macro written to be
  # used as a pragma, and every routine only ever reached from a
  # module's own top level, was reported as dead weight.
  var
    calledNames: HashSet[string] = initHashSet[string]()
    perFile: Table[string, seq[FunctionInfo]] = initTable[string,
      seq[FunctionInfo]]()
    lines: seq[string] = @[]
  for fn in all:
    for name in fn.calls:
      calledNames.incl(name.toLowerAscii())
    if not perFile.hasKey(fn.sourcePath):
      perFile[fn.sourcePath] = @[]
    perFile[fn.sourcePath].add(fn)
  for p in listNimFiles(normDir, bIncludeTests = true):
    lines = readLinesSafe(p)
    for name in pragmaNamesIn(lines):
      calledNames.incl(name.toLowerAscii())
    for name in topLevelCalls(lines, perFile.getOrDefault(p, @[])):
      calledNames.incl(name.toLowerAscii())
  result.shape = shapeReport(parts.src, normDir)
  result.placeholders = placeholdersOf(all, calledNames, normDir)
  result.unusedFuncs = unusedReportOf(parts.src, calledNames, normDir)
  result.config = configReportOf(normDir, files, all)
  result.secrets = secretsOf(normDir, allSourceFiles)
  result.embedded = embeddedOf(normDir, allSourceFiles)
  result.families = familiesOf(result.shape.shapes, parts.src)
  wholeGraph = RepoGraph(rootDir: normDir, functions: parts.src,
    edges: graph.edges)
  result.state = stateWritesOf(wholeGraph)
  result.aborts = abortReachOf(wholeGraph, escapingOf(wholeGraph))
  result.timeline = timelineOf(normDir)

  # Two more, both reading the call graph rather than the files:
  #
  #   how deep a chain of calls can get, and who sits at each depth
  #   whether every door has a guard, and whether the guards are tested
  #
  # The test-reach sets come from the one walk of the tests made
  # further up, so what the coverage rings say and what the guard
  # report says can never disagree.
  result.callDepth = callDepthOf(parts.src, graph.edges, normDir)
  result.coupling = couplingOf(parts.src, graph.edges, normDir,
    walk.hits, walk.edge, walk.regress, walk.bug)


proc summaryLines*(S: ProjectStats): seq[string] {.role: helper,
    metaTags: {tagStats}.} =
  ## S: one measured repository, put into lines a terminal can print.
  result = @[]
  result.add("Root: " & S.rootDir)
  if S.error.len > 0:
    result.add("Error: " & S.error)
    return
  result.add("Files: " & $S.files.len & "   Lines: " & $S.totalLines)
  result.add("Routines: " & $S.functions & "   average " &
    formatFloat(S.avgLines, ffDecimal, 1) & " lines")
  result.add("Templates: " & $S.templates & "   macros: " & $S.macros &
    "   template calls: " & $S.nest.templateCalls)
  result.add("Nesting: " & $S.nest.doubles & " double, " & $S.nest.triples &
    " triple, " & $S.nest.deeper & " deeper")
  result.add("Nested routines: " & $S.nest.nestedFunctions & " (" &
    $S.nest.nonMathNested & " outside math)")
  result.add("Input handlers: " & $S.inputFunctions & "   truth states: " &
    $S.truthFunctions & "   math: " & $S.mathFunctions)
  result.add("Tests: " & $S.tests.tests & " (" & $S.tests.declaredKinds &
    " with a declared kind)")
  result.add("Untested routines: " & $S.tests.buckets[0] & " of " &
    $S.tests.functions)
  result.add("Edge-case cover: " & $S.tests.edgeCovered &
    "   benchmark cover: " & $S.tests.benchCovered)
  result.add("Never called: " & $S.unusedCount)
