## ============================================================
## | Otter Code Statistics Project                            |
## | -> analyzeProject: one folder in, one shape out          |
## ============================================================
##
## This is the whole entry point. A window hands it a folder and gets
## back everything it needs to draw:
##
##     analyzeProject("/home/me/MyRepo")
##       .files      one cell per file
##       .nest       the bars
##       .tests      the rings
##       .roles      the tally
##
## Nothing is cached here. A caller that wants the figures kept keeps
## them itself, because the tree changes under us while an agent works
## and a stale chart is worse than a slow one.

import std/[os, sets, strutils, tables]

import ./pipeline
import ./inventory
import ./input_scan
import ./imports
import ./source_metrics
import ./test_scan
import ./types
import ./shape
import ./placeholders
import ./embedded
import ./families
import ./layout
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
import ../fylgia_threads
import runePragmas

proc hasBody(f: FunctionInfo): bool {.role: parser, tag: "stats".} =
  ## f: true when the routine has at least one line of code.
  result = false
  for row in f.bodyLines:
    if row.strip().len > 0 and not row.strip().startsWith("#"):
      return true

proc dropForwardDeclarations(A: seq[FunctionInfo]): seq[FunctionInfo] {.
    role: sanitizer, tag: "stats".} =
  ## A: every routine. A forward declaration is a promise, not a routine:
  ##
  ##   proc parse(n: int): Node          <- line 101, no body
  ##   ...
  ##   proc parse(n: int): Node =        <- line 273, the routine
  ##
  ## Kept, calls resolved to the first one, so the real routine was never
  ## reached by any test and read as untested. A body-less routine goes
  ## when its module defines one with a body under the same name.
  var
    bodied: HashSet[string] = initHashSet[string]()
  for f in A:
    if hasBody(f):
      bodied.incl(f.modulePath & "::" & f.name)
  result = @[]
  for f in A:
    if hasBody(f) or (f.modulePath & "::" & f.name) notin bodied:
      result.add(f)

proc parseTree*(rootDir: string, files: seq[string]): seq[FunctionInfo]
    {.role: parser, tag: "stats".} =
  ## rootDir: the tree. files: every Nim file in it, tests included.
  result = dropForwardDeclarations(parseNimFiles(rootDir, files))


proc splitTests*(A: seq[FunctionInfo]): tuple[src: seq[FunctionInfo],
    tests: seq[FunctionInfo]] {.role: parser, tag: "stats".} =
  ## A: every routine in the tree, split by where it was written.
  result = (@[], @[])
  for row in A:
    if isTestPath(row.sourcePath):
      result.tests.add(row)
    else:
      result.src.add(row)


proc gatherTests*(files: seq[string], A: seq[FunctionInfo]): seq[TestInfo]
    {.role: truthBuilder, tag: "stats|testing".} =
  ## files: every file in the tree. A: the routines written in tests.
  ## Both shapes of test are gathered: the `test "..."` block and the
  ## routine carrying a testKind pragma.
  var
    row: TestInfo = TestInfo()
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
    tag: "stats".} =
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
    tag: "stats".} =
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
    tag: "stats".} =
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


proc addPassedCalls(A: var seq[FunctionInfo]) {.role: actor, tag: "stats".} =
  ## A: every routine. A routine another hands over by name
  ## (`runTasks(ts, n, encryptChunk)`, `createThread(t, serve, a)`) runs
  ## when that one does, so it is added to its calls: the call graph, and
  ## with it the test walk, then follows it.
  var
    known: HashSet[string] = initHashSet[string]()
  for f in A:
    known.incl(f.name.toLowerAscii())
  for f in A.mitems:
    for name in passedNames(f.bodyLines, known):
      if name notin f.calls:
        f.calls.add(name)


proc calledNamesOf(dir: string, A: seq[FunctionInfo]): HashSet[string]
    {.role: truthBuilder, tag: "stats".} =
  ## dir: the repository   A: every routine in it.
  ## Every name anything in the tree uses, lowered. Four kinds of use
  ## count, not one; a routine reads as dead only when none names it:
  ##
  ##   something calls it        parseWidth(s)
  ##   a pragma applies it       {.needs: b <= a.}   <- never "called"
  ##   top-level code calls it   when isMainModule: stream(1)
  ##   something is handed it    createThread(t, serveThread, args)
  ##   used as a method          c.isDigit          <- no brackets
  ##
  ## The last four used to be invisible, so every macro written to be
  ## used as a pragma, every routine only ever reached from a module's
  ## own top level, every thread body, and every method-style call was
  ## reported as dead weight.
  var
    known: HashSet[string] = initHashSet[string]()
    perFile: Table[string, seq[FunctionInfo]] = initTable[string,
      seq[FunctionInfo]]()
    lines: seq[string] = @[]
  result = initHashSet[string]()
  for fn in A:
    for name in fn.calls:
      result.incl(name.toLowerAscii())
    known.incl(fn.name.toLowerAscii())
    perFile.mgetOrPut(fn.sourcePath, @[]).add(fn)
  for p in listNimFiles(dir, b = true):
    lines = readLinesSafe(p)
    for name in pragmaNamesIn(lines):
      result.incl(name.toLowerAscii())
    for name in topLevelCalls(lines, perFile.getOrDefault(p, @[])):
      result.incl(name.toLowerAscii())
    for name in passedNames(lines, known):
      result.incl(name.toLowerAscii())
    for name in dottedNamesIn(lines, known):
      result.incl(name.toLowerAscii())

proc keptSourceFiles(dir: string): seq[string] {.role: dataFetcher,
    tag: "stats".} =
  ## dir: the repository. Every hand-written file `.gitignore` keeps.
  result = gitKept(dir, listAllSourceFiles(dir))

proc analyzeProject*(rootDir: string): ProjectStats {.role: orchestrator,
    input: trusted, risk: rkLow, speed: spLong, tag: "stats".} =
  ## rootDir: the folder to measure. An unreadable folder comes back
  ## with `error` set and everything else empty, so a window can say so
  ## instead of drawing an empty chart that looks like good news.
  ##
  ## Three stages. Every line inside one `together` block runs at the
  ## same time (Fylgia's auto threader); a stage starts only when the
  ## one before it is done, because it reads what that one wrote:
  ##
  ##   1  the folder   ─┬─► Nim files, kept files, .gitignore, timeline
  ##                    │
  ##      parse once ───┴─► all ─► call graph ─► test walk   (in order)
  ##                    │
  ##   2  all + walk   ─┼─► files, nesting, rings, roles, unused, scans,
  ##                    │   shape, secrets, state, layout, guards, ...
  ##                    │
  ##   3  stage 2      ─┴─► unsafe calls, placeholders, families, scopes
  ##
  ## Everything is worked out from `all`, the one parse of the tree, so
  ## nothing reads a file twice and no two reports can disagree about
  ## what the source says.
  var
    normDir: string = normalizeSlashes(rootDir)
    files: seq[string] = @[]
    allSourceFiles: seq[string] = @[]
    all: seq[FunctionInfo] = @[]
    parts: tuple[src: seq[FunctionInfo], tests: seq[FunctionInfo]] = (
      src: @[], tests: @[])
    graph: tuple[edges: seq[CallEdge], unresolved: seq[string]] = (
      edges: @[], unresolved: @[])
    wholeGraph: RepoGraph = RepoGraph()
    tests: seq[TestInfo] = @[]
    walk: CoverWalk = CoverWalk()
    marks: HashSet[string] = initHashSet[string]()
    keys: HashSet[string] = initHashSet[string]()
    calledNames: HashSet[string] = initHashSet[string]()
    inputScan: tuple[inputs: seq[InputFuncInfo], inputCount: int,
      sanitizerCount: int] = (inputs: @[], inputCount: 0, sanitizerCount: 0)
    whenAndPlat: tuple[sites: seq[WhenSite], platforms: seq[NameCount],
      simd: seq[SimdSite]] = (sites: @[], platforms: @[], simd: @[])
    importDepth: tuple[depth: int, cycles: seq[CircularImportInfo]] = (
      depth: 0, cycles: @[])
    scopes: tuple[src: ProjectScopeStats, all: ProjectScopeStats,
      test: ProjectScopeStats] = (src: ProjectScopeStats(),
      all: ProjectScopeStats(), test: ProjectScopeStats())
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

  # ---- stage 1: the folder, four walks at once -------------------------
  together:
    files = listNimFiles(rootDir, true)
    allSourceFiles = keptSourceFiles(rootDir)
    result.gitignore = gatherGitignoreStats(rootDir)
    result.timeline = timelineOf(normDir)
  if files.len == 0:
    result.error = "no Nim files under " & rootDir
    return

  all = parseTree(rootDir, files)
  addPassedCalls(all)
  parts = splitTests(all)
  graph = buildCallGraph(all)
  marks = templateNames(all)
  keys = pragmaKeys(all)
  tests = gatherTests(files, parts.tests)
  ## `all`, not only the library: a test that calls a helper in its own
  ## file (`waitFor runRelayChecks()`) reaches the library THROUGH it.
  walk = walkTests(all, tests, graph.edges)
  wholeGraph = RepoGraph(rootDir: normDir, functions: parts.src,
    edges: graph.edges)

  # ---- stage 2: every report that reads only the parse ------------------
  #
  # The last two read the call graph rather than the files: how deep a
  # chain of calls can get, and whether every door has a guard. Their
  # test-reach sets come from the one walk above, so the coverage rings
  # and the guard report can never disagree.
  together:
    result.langStats = gatherLangStats(allSourceFiles)
    result.files = collectFiles(rootDir, all, files, marks, walk)
    result.nest = nestOf(parts.src, marks)
    result.tests = coverageOf(parts.src, tests, walk)
    result.roles = rolesOf(parts.src)
    result.unused = unusedOf(parts.src, graph.edges, walk, keys)
    inputScan = scanInputDetailsAndSanitizers(rootDir, allSourceFiles, parts.src)
    result.unusedImports = scanUnusedImports(rootDir, allSourceFiles)
    whenAndPlat = scanWhenSitesAndPlatformCoverage(rootDir, allSourceFiles)
    importDepth = buildImportGraphAndDepth(rootDir, allSourceFiles)
    calledNames = calledNamesOf(normDir, all)
    result.shape = shapeReport(parts.src, normDir)
    result.config = configReportOf(normDir, files, all)
    result.secrets = secretsOf(normDir, allSourceFiles)
    result.embedded = embeddedOf(normDir, allSourceFiles)
    result.layout = layoutOf(parts.src, normDir)
    result.state = stateWritesOf(wholeGraph, outside = parts.tests)
    result.aborts = abortReachOf(wholeGraph, escapingOf(wholeGraph))
    result.callDepth = callDepthOf(parts.src, graph.edges, normDir)
    result.coupling = couplingOf(parts.src, graph.edges, normDir,
      walk.hits, walk.edge, walk.regress, walk.bug)

  # ---- stage 3: what needs stage 2 -------------------------------------
  together:
    result.unsafeDetails = scanUnsafeDetails(rootDir, allSourceFiles,
      parts.src, inputScan.inputs)
    result.placeholders = placeholdersOf(all, calledNames, normDir)
    result.unusedFuncs = unusedReportOf(parts.src, calledNames, normDir)
    result.families = familiesOf(result.shape.shapes, parts.src)
    scopes = calculateScopeStats(result.files)

  result.unusedCount = result.unused.len
  if result.unused.len > unusedShown:
    result.unused.setLen(unusedShown)
  totalsOf(result, parts.src)
  result.inputDetails = inputScan.inputs
  result.inputFunctions = max(result.inputFunctions, inputScan.inputCount)
  result.whenSites = whenAndPlat.sites
  result.platformCoverage = whenAndPlat.platforms
  result.simdSites = whenAndPlat.simd
  result.importGraphDepth = importDepth.depth
  result.circularImports = importDepth.cycles
  result.srcStats = scopes.src
  result.allStats = scopes.all
  result.testStats = scopes.test
  for row in result.files:
    result.totalLines = result.totalLines + row.lines


proc summaryLines*(S: ProjectStats): seq[string] {.role: helper,
    tag: "stats".} =
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
