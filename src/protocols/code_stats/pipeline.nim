## ============================================================
## | Otter Code Statistics Pipeline                           |
## | -> One repository read once, measured five ways          |
## ============================================================
##
##   listNimFiles ─► parseNimFile ─┬─► per file   grid cells
##                                 ├─► nesting    bar chart
##                                 ├─► roles      tallies
##                                 ├─► call graph unused routines
##                                 └─► tests      the two rings
##
## The whole tree is parsed once and every figure comes off that one
## pass, so two charts drawn side by side can never disagree.

import std/[algorithm, sets, strutils, tables]

import ./nesting
import ./test_scan
import ./types
import ../repo_graph/io_utils
import ../repo_graph/types as graphTypes
import runePragmas

const
  roleLabels*: array[12, array[2, string]] = [
    ["truthbuilder", "truth builder"],
    ["truth_builder", "truth builder"],
    ["truthstate", "truth state"],
    ["datafetcher", "data fetcher"],
    ["data_fetcher", "data fetcher"],
    ["datawriter", "data writer"],
    ["metaorchestrator", "meta orchestrator"],
    ["meta_orchestrator", "meta orchestrator"],
    ["metaparser", "meta parser"],
    ["statecontroller", "state controller"],
    ["state_controller", "state controller"],
    ["preparddata", "prepared data"]
  ]
  unusedShown*: int = 40
    ## How many unreachable routines are named. The rest are counted.

type
  CoverWalk* {.role: truthState, tag: "stats".} = object
    ## What every test between them reaches, kept once so the rings,
    ## the per-file tally, and the unused list all read the same walk.
    hits*: CountTable[string]
    edge*: HashSet[string]
    bench*: HashSet[string]
    regress*: HashSet[string]
    bug*: HashSet[string]
    kinds*: seq[NameCount]
    declared*: int

proc roleLabel*(raw: string): string {.role: helper, tag: "stats".} =
  ## raw: whatever was written after `role:` in the pragma.
  var
    t: string = raw.strip().toLowerAscii()
  result = t
  for row in roleLabels:
    if row[0] == t:
      result = row[1]
      return
  if t == "otherrole" or t == "other":
    result = "other"
  elif t == "preparedata" or t == "prepareddata":
    result = "prepared data"
  elif t == "rawdata":
    result = "raw data"


proc declaredRoleOf*(f: FunctionInfo): string {.role: parser,
    tag: "stats".} =
  ## f: one routine. Empty when nothing declared what it is.
  result = ""
  for row in f.pragmaTags:
    if row.toLowerAscii().startsWith("role:"):
      result = roleLabel(row[5 .. ^1])
      return


proc lengthOf*(f: FunctionInfo): int {.role: parser, tag: "stats".} =
  ## f: one routine, measured from its first line to its last.
  result = f.lineEnd - f.lineStart + 1
  if result < 1:
    result = 1


proc isCodeLine(s: string): bool {.role: parser, tag: "stats", inline.} =
  ## s: one source line. Code is anything that is not blank and does not
  ## start with `#` (which covers `##` doc comments too).
  var
    t: string = s.strip()
  result = t.len > 0 and t[0] != '#'

proc codeLengthOf*(L: seq[string], f: FunctionInfo): int {.role: parser,
    tag: "stats".} =
  ## L: the lines of the file f sits in. f: one routine.
  ## Its length without comment and blank lines; never below 1.
  var
    i: int = max(f.lineStart, 1)
    last: int = min(f.lineEnd, L.len)
  result = 0
  while i <= last:
    if isCodeLine(L[i - 1]):
      result = result + 1
    i = i + 1
  result = max(result, 1)

proc codeLinesOf*(L: seq[string]): int {.role: parser, tag: "stats".} =
  ## L: the lines of one file. How many of them are code.
  result = 0
  for row in L:
    if isCodeLine(row):
      result = result + 1


proc templateNames*(A: seq[FunctionInfo]): HashSet[string]
    {.role: truthBuilder, tag: "stats".} =
  ## A: every routine in the tree. The names declared as templates,
  ## lowered, so a use of one can be told from an ordinary call.
  result = initHashSet[string]()
  for row in A:
    if row.declKind == "template":
      result.incl(row.name.toLowerAscii())


proc pragmaKey*(tag: string): string {.role: parser, tag: "stats".} =
  ## tag: one pragma read off a routine, such as `role:helper`. The
  ## name in front of the colon is the template that was applied.
  var
    i: int = tag.find(':')
  result = tag.toLowerAscii()
  if i > 0:
    result = tag[0 ..< i].toLowerAscii()


proc templateCallsOf*(f: FunctionInfo, marks: HashSet[string]): int
    {.role: parser, tag: "stats".} =
  ## f: one routine. marks: every template name in the tree, lowered.
  ## A template is used two ways in Nim — written as a call, or hung on
  ## a routine as a pragma — and both are counted, because a repository
  ## whose templates are all pragmas would otherwise read as zero.
  result = 0
  for row in f.calls:
    if row.toLowerAscii() in marks:
      result = result + 1
  for row in f.pragmaTags:
    if pragmaKey(row) in marks:
      result = result + 1


proc pragmaKeys*(A: seq[FunctionInfo]): HashSet[string] {.role: truthBuilder,
    tag: "stats".} =
  ## A: every routine in the tree. Every template name that was hung on
  ## a routine as a pragma, lowered. A pragma template is written once
  ## and used a thousand times without a single bracket after it, and
  ## calling that unused would be nonsense.
  result = initHashSet[string]()
  for row in A:
    for tagRow in row.pragmaTags:
      result.incl(pragmaKey(tagRow))


proc isInput*(f: FunctionInfo): bool {.role: parser, tag: "stats".} =
  ## f: one routine. True when it reads from outside the program or was
  ## declared as the thing that cleans such input up.
  result = f.handlesUserInput or declaredRoleOf(f) == "sanitizer"


proc untestedIn*(A: seq[FunctionInfo], w: CoverWalk): int {.role: parser,
    tag: "stats".} =
  ## A: the routines of one file. w: the walk the tests made.
  result = 0
  for row in A:
    if w.hits.getOrDefault(row.id) == 0:
      result = result + 1


proc bandFor*(rank, total: int): SizeBand {.role: parser,
    tag: "stats".} =
  ## rank: this file's place once every file is ordered longest first.
  ## total: how many files there are. Four bands of roughly equal size,
  ## because the grid has four row heights and no more.
  var
    quarter: int = 0
  result = sbSmall
  if total <= 0:
    return
  quarter = (total + 3) div 4
  if rank < quarter:
    result = sbHuge
  elif rank < quarter * 2:
    result = sbBig
  elif rank < quarter * 3:
    result = sbMid


proc byLines(a, b: FileStat): int {.role: helper, tag: "stats".} =
  ## a, b: two measured files. Longest first, then by path so two files
  ## of the same length never trade places between runs.
  result = cmp(b.lines, a.lines)
  if result == 0:
    result = cmp(a.path, b.path)


proc applyBands*(S: var seq[FileStat]) {.role: actor, tag: "stats".} =
  ## S: every measured file. Gives each one its size band and its share
  ## of the longest file, which is what the grid draws as height.
  var
    i: int = 0
    longest: int = 1
  S.sort(byLines)
  if S.len > 0:
    longest = max(1, S[0].lines)
  while i < S.len:
    S[i].size = bandFor(i, S.len)
    S[i].share = S[i].lines.float / longest.float
    i = i + 1


proc fileRow*(rootDir, path: string, A: seq[FunctionInfo],
    marks: HashSet[string], w: CoverWalk): FileStat {.role: truthBuilder,
    tag: "stats".} =
  ## rootDir: the tree being measured. path: one file inside it.
  ## A: only the routines declared in that file. marks: template names.
  ## w: the walk the tests made, so the file can say how much of it no
  ## test has ever run.
  var
    total: int = 0
    totalCode: int = 0
    sites: seq[NestSite] = @[]
    L: seq[string] = readLinesSafe(path)
  result = FileStat(path: toModulePath(rootDir, path) & ".nim",
    name: path.split('/')[^1].split('\\')[^1], lines: L.len,
    functions: 0, templates: 0, macros: 0, avgLines: 0.0, avgCodeLines: 0.0,
    codeLines: codeLinesOf(L), commentLines: 0, maxLines: 0,
    healthWithComments: hbOk, health: hbOk, size: sbSmall, share: 0.0,
    inputs: 0, templateCalls: 0,
    nested: 0, deepest: 1, untested: 0, isTest: isTestPath(path))
  for row in A:
    result.functions = result.functions + 1
    total = total + lengthOf(row)
    totalCode = totalCode + codeLengthOf(L, row)
    result.maxLines = max(result.maxLines, lengthOf(row))
    result.templateCalls = result.templateCalls + templateCallsOf(row, marks)
    sites = nestSites(row)
    result.nested = result.nested + sites.len
    result.deepest = max(result.deepest, deepestOf(sites))
    if row.declKind == "template":
      result.templates = result.templates + 1
    if row.declKind == "macro":
      result.macros = result.macros + 1
    if isInput(row):
      result.inputs = result.inputs + 1
  if result.functions > 0:
    result.avgLines = total.float / result.functions.float
    result.avgCodeLines = totalCode.float / result.functions.float
  result.commentLines = L.len - result.codeLines
  result.healthWithComments = healthOf(result.avgLines)
  result.health = healthOf(result.avgCodeLines)
  result.untested = untestedIn(A, w)


proc byInner(a, b: NestSite): int {.role: helper, tag: "stats".} =
  ## a, b: two nesting sites. Deepest first, then longest, so the list
  ## the window shows starts with the worst of them.
  result = cmp(b.depth, a.depth)
  if result == 0:
    result = cmp(b.innerLines, a.innerLines)


proc addSite(S: var NestStats, row: NestSite) {.role: actor,
    tag: "stats".} =
  ## S: the tally. row: one site being counted into it.
  if row.depth == 2:
    S.doubles = S.doubles + 1
  elif row.depth == 3:
    S.triples = S.triples + 1
  else:
    S.deeper = S.deeper + 1
  if row.leaf:
    S.innerBuckets[bucketOf(row.innerLines)] =
      S.innerBuckets[bucketOf(row.innerLines)] + 1
  S.sites.add(row)


proc nestOf*(A: seq[FunctionInfo], marks: HashSet[string]): NestStats
    {.role: truthBuilder, tag: "stats".} =
  ## A: every routine in the tree. marks: the template names.
  var
    sites: seq[NestSite] = @[]
    isMath: bool = false
  result = NestStats(templateCalls: 0, doubles: 0, triples: 0, deeper: 0,
    nestedFunctions: 0, nonMathNested: 0, mathNested: 0,
    innerBuckets: [0, 0, 0, 0, 0, 0], sites: @[])
  for row in A:
    result.templateCalls = result.templateCalls + templateCallsOf(row, marks)
    sites = nestSites(row)
    if sites.len == 0:
      continue
    result.nestedFunctions = result.nestedFunctions + 1
    isMath = declaredRoleOf(row) == "math"
    if isMath:
      result.mathNested = result.mathNested + 1
    else:
      result.nonMathNested = result.nonMathNested + 1
    for site in sites:
      addSite(result, site)
  result.sites.sort(byInner)
  if result.sites.len > maxSites:
    result.sites.setLen(maxSites)


proc nameIndex*(A: seq[FunctionInfo]): Table[string, seq[string]]
    {.role: truthBuilder, tag: "stats".} =
  ## A: the routines a test may reach. Their names, each pointing at
  ## every routine that carries it, because one name can be overloaded.
  result = initTable[string, seq[string]]()
  for row in A:
    if not result.hasKey(row.name):
      result[row.name] = @[]
    result[row.name].add(row.id)


proc calleeIndex*(A: seq[CallEdge]): Table[string, seq[string]]
    {.role: truthBuilder, tag: "stats".} =
  ## A: the call graph. Who each routine calls, ready to walk.
  result = initTable[string, seq[string]]()
  for row in A:
    if not result.hasKey(row.callerId):
      result[row.callerId] = @[]
    result[row.callerId].add(row.calleeId)


proc reachedBy*(seeds: seq[string], edges: Table[string, seq[string]]):
    HashSet[string] {.role: truthBuilder, tag: "stats".} =
  ## seeds: the routines one test calls directly. edges: who calls whom.
  ## Everything the test can set running, not only what it names, so a
  ## helper three calls down still counts as tested.
  var
    queue: seq[string] = seeds
    head: int = 0
    node: string = ""
  result = initHashSet[string]()
  while head < queue.len:
    node = queue[head]
    head = head + 1
    if node in result:
      continue
    result.incl(node)
    if not edges.hasKey(node):
      continue
    for row in edges[node]:
      if row notin result:
        queue.add(row)


proc seedsOf*(t: TestInfo, names: Table[string, seq[string]]): seq[string]
    {.role: parser, tag: "stats".} =
  ## t: one test. names: every routine name in the tree.
  result = @[]
  for row in t.calls:
    if names.hasKey(row):
      result.add(names[row])


proc markKind(S: var CoverWalk, kind, id: string) {.role: actor,
    tag: "stats".} =
  ## S: the walk being filled. kind: what the test was for. id: one
  ## routine that test can set running.
  if kind == kindNames[1]:
    S.edge.incl(id)
  elif kind == kindNames[2]:
    S.bench.incl(id)
  elif kind == kindNames[3]:
    S.regress.incl(id)
  elif kind == kindNames[4]:
    S.bug.incl(id)


proc walkTests*(A: seq[FunctionInfo], tests: var seq[TestInfo],
    edges: seq[CallEdge]): CoverWalk {.role: truthBuilder,
    tag: "stats|testing".} =
  ## A: the routines that are not themselves tests. tests: every test
  ## found; each is told afterwards how much it reaches. edges: the
  ## call graph the walk follows.
  var
    names: Table[string, seq[string]] = nameIndex(A)
    graph: Table[string, seq[string]] = calleeIndex(edges)
    live: HashSet[string] = initHashSet[string]()
    known: HashSet[string] = initHashSet[string]()
    i: int = 0
  result = CoverWalk(hits: initCountTable[string](),
    edge: initHashSet[string](), bench: initHashSet[string](),
    regress: initHashSet[string](), bug: initHashSet[string](),
    kinds: @[], declared: 0)
  for row in A:
    known.incl(row.id)
  while i < tests.len:
    live = reachedBy(seedsOf(tests[i], names), graph)
    tests[i].reaches = 0
    if tests[i].declared:
      result.declared = result.declared + 1
    addCount(result.kinds, tests[i].kind)
    for row in live:
      if row notin known:
        continue
      tests[i].reaches = tests[i].reaches + 1
      result.hits.inc(row)
      markKind(result, tests[i].kind, row)
    i = i + 1


proc coverageOf*(A: seq[FunctionInfo], tests: seq[TestInfo],
    w: CoverWalk): TestStats {.role: truthBuilder,
    tag: "stats|testing".} =
  ## A: the routines under test. tests: every test found. w: the walk
  ## those tests already made through the call graph.
  var
    n: int = 0
  result = TestStats(tests: tests.len, declaredKinds: w.declared,
    functions: A.len, buckets: [0, 0, 0, 0, 0, 0], edgeCovered: w.edge.len,
    benchCovered: w.bench.len, regressionCovered: w.regress.len,
    bugfixCovered: w.bug.len, kinds: w.kinds)
  for row in A:
    n = min(5, w.hits.getOrDefault(row.id))
    result.buckets[n] = result.buckets[n] + 1
    if n == 0:
      result.untested.add(row.sourcePath & ":" & $row.lineStart & " " & row.name)


proc calledSet*(A: seq[CallEdge]): HashSet[string] {.role: truthBuilder,
    tag: "stats".} =
  ## A: the call graph. Everything something else calls.
  result = initHashSet[string]()
  for row in A:
    result.incl(row.calleeId)


proc collectFiles*(rootDir: string, A: seq[FunctionInfo],
    files: seq[string], marks: HashSet[string], w: CoverWalk): seq[FileStat]
    {.role: truthBuilder, tag: "stats".} =
  ## rootDir: the tree. A: every routine. files: every file that was
  ## read, so a file without a single routine still gets its cell.
  ## marks: the template names. w: the walk the tests made.
  var
    byFile: Table[string, seq[FunctionInfo]] = initTable[string,
      seq[FunctionInfo]]()
    key: string = ""
  result = @[]
  for row in A:
    key = normalizeSlashes(row.sourcePath)
    if not byFile.hasKey(key):
      byFile[key] = @[]
    byFile[key].add(row)
  for path in files:
    key = normalizeSlashes(path)
    result.add(fileRow(rootDir, path, byFile.getOrDefault(key, @[]), marks, w))
  applyBands(result)
