# ============================================================
# | Otter Code Statistics Pipeline                           |
# | -> One repository read once, measured five ways          |
# ============================================================
#
#   listNimFiles ─► parseNimFile ─┬─► per file   grid cells
#                                 ├─► nesting    bar chart
#                                 ├─► roles      tallies
#                                 ├─► call graph unused routines
#                                 └─► tests      the two rings
#
# The whole tree is parsed once and every figure comes off that one
# pass, so two charts drawn side by side can never disagree.

import std/[algorithm, os, sets, strutils, tables]

import ./nesting
import ./test_scan
import ./types
import ../repo_graph/io_utils
import ../repo_graph/types as graphTypes
import ../../../meta/metaPragmas

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
  CoverWalk* {.role: truthState, metaTags: {tagStats}.} = object
    ## What every test between them reaches, kept once so the rings,
    ## the per-file tally, and the unused list all read the same walk.
    hits*: CountTable[string]
    edge*: HashSet[string]
    bench*: HashSet[string]
    regress*: HashSet[string]
    bug*: HashSet[string]
    kinds*: seq[NameCount]
    declared*: int

proc roleLabel*(raw: string): string {.role: helper, metaTags: {tagStats}.} =
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
    metaTags: {tagStats}.} =
  ## f: one routine. Empty when nothing declared what it is.
  result = ""
  for row in f.pragmaTags:
    if row.toLowerAscii().startsWith("role:"):
      result = roleLabel(row[5 .. ^1])
      return


proc lengthOf*(f: FunctionInfo): int {.role: parser, metaTags: {tagStats}.} =
  ## f: one routine, measured from its first line to its last.
  result = f.lineEnd - f.lineStart + 1
  if result < 1:
    result = 1


proc templateNames*(A: seq[FunctionInfo]): HashSet[string]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## A: every routine in the tree. The names declared as templates,
  ## lowered, so a use of one can be told from an ordinary call.
  result = initHashSet[string]()
  for row in A:
    if row.declKind == "template":
      result.incl(row.name.toLowerAscii())


proc pragmaKey*(tag: string): string {.role: parser, metaTags: {tagStats}.} =
  ## tag: one pragma read off a routine, such as `role:helper`. The
  ## name in front of the colon is the template that was applied.
  var
    i: int = tag.find(':')
  result = tag.toLowerAscii()
  if i > 0:
    result = tag[0 ..< i].toLowerAscii()


proc templateCallsOf*(f: FunctionInfo, marks: HashSet[string]): int
    {.role: parser, metaTags: {tagStats}.} =
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
    metaTags: {tagStats}.} =
  ## A: every routine in the tree. Every template name that was hung on
  ## a routine as a pragma, lowered. A pragma template is written once
  ## and used a thousand times without a single bracket after it, and
  ## calling that unused would be nonsense.
  result = initHashSet[string]()
  for row in A:
    for tagRow in row.pragmaTags:
      result.incl(pragmaKey(tagRow))


proc isInput*(f: FunctionInfo): bool {.role: parser, metaTags: {tagStats}.} =
  ## f: one routine. True when it reads from outside the program or was
  ## declared as the thing that cleans such input up.
  result = f.handlesUserInput or declaredRoleOf(f) == "sanitizer"


proc untestedIn*(A: seq[FunctionInfo], w: CoverWalk): int {.role: parser,
    metaTags: {tagStats}.} =
  ## A: the routines of one file. w: the walk the tests made.
  result = 0
  for row in A:
    if w.hits.getOrDefault(row.id) == 0:
      result = result + 1


proc bandFor*(rank, total: int): SizeBand {.role: parser,
    metaTags: {tagStats}.} =
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


proc byLines(a, b: FileStat): int {.role: helper, metaTags: {tagStats}.} =
  ## a, b: two measured files. Longest first, then by path so two files
  ## of the same length never trade places between runs.
  result = cmp(b.lines, a.lines)
  if result == 0:
    result = cmp(a.path, b.path)


proc applyBands*(S: var seq[FileStat]) {.role: actor, metaTags: {tagStats}.} =
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
    metaTags: {tagStats}.} =
  ## rootDir: the tree being measured. path: one file inside it.
  ## A: only the routines declared in that file. marks: template names.
  ## w: the walk the tests made, so the file can say how much of it no
  ## test has ever run.
  var
    total: int = 0
    sites: seq[NestSite] = @[]
  result = FileStat(path: toModulePath(rootDir, path) & ".nim",
    name: path.split('/')[^1].split('\\')[^1], lines: readLinesSafe(path).len,
    functions: 0, templates: 0, macros: 0, avgLines: 0.0, maxLines: 0,
    health: hbOk, size: sbSmall, share: 0.0, inputs: 0, templateCalls: 0,
    nested: 0, deepest: 1, untested: 0, isTest: isTestPath(path))
  for row in A:
    result.functions = result.functions + 1
    total = total + lengthOf(row)
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
  result.health = healthOf(result.avgLines)
  result.untested = untestedIn(A, w)


proc byInner(a, b: NestSite): int {.role: helper, metaTags: {tagStats}.} =
  ## a, b: two nesting sites. Deepest first, then longest, so the list
  ## the window shows starts with the worst of them.
  result = cmp(b.depth, a.depth)
  if result == 0:
    result = cmp(b.innerLines, a.innerLines)


proc addSite(S: var NestStats, row: NestSite) {.role: actor,
    metaTags: {tagStats}.} =
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
    {.role: truthBuilder, metaTags: {tagStats}.} =
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
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## A: the routines a test may reach. Their names, each pointing at
  ## every routine that carries it, because one name can be overloaded.
  result = initTable[string, seq[string]]()
  for row in A:
    if not result.hasKey(row.name):
      result[row.name] = @[]
    result[row.name].add(row.id)


proc calleeIndex*(A: seq[CallEdge]): Table[string, seq[string]]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## A: the call graph. Who each routine calls, ready to walk.
  result = initTable[string, seq[string]]()
  for row in A:
    if not result.hasKey(row.callerId):
      result[row.callerId] = @[]
    result[row.callerId].add(row.calleeId)


proc reachedBy*(seeds: seq[string], edges: Table[string, seq[string]]):
    HashSet[string] {.role: truthBuilder, metaTags: {tagStats}.} =
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
    {.role: parser, metaTags: {tagStats}.} =
  ## t: one test. names: every routine name in the tree.
  result = @[]
  for row in t.calls:
    if names.hasKey(row):
      result.add(names[row])


proc markKind(S: var CoverWalk, kind, id: string) {.role: actor,
    metaTags: {tagStats}.} =
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
    metaTags: {tagStats, tagTesting}.} =
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
    metaTags: {tagStats, tagTesting}.} =
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


proc calledSet*(A: seq[CallEdge]): HashSet[string] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A: the call graph. Everything something else calls.
  result = initHashSet[string]()
  for row in A:
    result.incl(row.calleeId)


proc collectFiles*(rootDir: string, A: seq[FunctionInfo],
    files: seq[string], marks: HashSet[string], w: CoverWalk): seq[FileStat]
    {.role: truthBuilder, metaTags: {tagStats}.} =
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

proc extOf(path: string): string {.inline, role: helper, metaTags: {tagStats}.} =
  var
    dot: int = path.rfind('.')
  if dot >= 0:
    result = path[dot + 1 .. ^1].toLowerAscii()
  else:
    result = "other"

proc langOf(ext: string): string {.inline, role: helper, metaTags: {tagStats}.} =
  case ext
  of "nim", "nims", "nimble": result = "nim"
  of "c", "h": result = "c"
  of "cpp", "hpp", "cc", "cxx": result = "cpp"
  of "js", "mjs", "cjs": result = "javascript"
  of "ts", "tsx": result = "typescript"
  of "css": result = "css"
  of "html", "htm": result = "html"
  of "json", "toml", "yaml", "yml": result = "config"
  else: result = "other"

proc listAllSourceFiles*(rootDir: string): seq[string] {.role: dataFetcher,
    metaTags: {tagStats}.} =
  ## Recursively find all source and config files in rootDir, skipping ignored dirs
  result = @[]
  if not dirExists(rootDir): return
  try:
    for path in walkDirRec(rootDir, yieldFilter = {pcFile}):
      var rel = path[rootDir.len .. ^1]
      rel = rel.replace('\\', '/')
      if rel.startsWith("/"): rel = rel[1 .. ^1]
      if rel.startsWith(".git/") or rel.contains("/.git/") or
         rel.startsWith("nimcache/") or rel.contains("/nimcache/") or
         rel.startsWith("build/") or rel.contains("/build/") or
         rel.startsWith("builds/") or rel.contains("/builds/") or
         rel.startsWith("node_modules/") or rel.contains("/node_modules/"):
        continue
      let ext = extOf(rel)
      if ext in ["nim", "c", "h", "cpp", "hpp", "js", "ts", "html", "css", "json", "toml", "md", "py", "sh"]:
        result.add(path)
  except CatchableError:
    discard

proc gatherLangStats*(files: seq[string]): seq[LangStat] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  var
    counts = initTable[string, tuple[files: int, lines: int]]()
  for path in files:
    let ext = extOf(path)
    let group = if ext in ["nim", "c", "js", "ts"]: ext else: "other"
    let linesCount = readLinesSafe(path).len
    if not counts.hasKey(group):
      counts[group] = (files: 0, lines: 0)
    var cur = counts[group]
    cur.files = cur.files + 1
    cur.lines = cur.lines + linesCount
    counts[group] = cur
  result = @[]
  for key in ["nim", "c", "js", "ts", "other"]:
    if counts.hasKey(key):
      result.add(LangStat(ext: key, files: counts[key].files, lines: counts[key].lines))

proc parseGitignorePatterns(rootDir: string): seq[string] {.role: parser, metaTags: {tagStats}.} =
  result = @[]
  let gitignorePath = rootDir / ".gitignore"
  if fileExists(gitignorePath):
    for line in readLinesSafe(gitignorePath):
      let s = line.strip()
      if s.len > 0 and not s.startsWith("#"):
        result.add(s)

proc gatherGitignoreStats*(rootDir: string): GitignoreStat {.role: truthBuilder,
    metaTags: {tagStats}.} =
  var
    ignoredFilesCount: int = 0
    ignoredLinesCount: int = 0
    patterns = parseGitignorePatterns(rootDir)
  result = GitignoreStat(ignoredFiles: 0, ignoredLines: 0)
  if patterns.len == 0 or not dirExists(rootDir): return
  try:
    for path in walkDirRec(rootDir, yieldFilter = {pcFile}):
      var rel = path[rootDir.len .. ^1].replace('\\', '/')
      if rel.startsWith("/"): rel = rel[1 .. ^1]
      if rel.startsWith(".git/"): continue
      var matched = false
      for p in patterns:
        let pat = p.replace("*", "").replace("/", "")
        if pat.len > 0 and rel.contains(pat):
          matched = true
          break
      if matched:
        ignoredFilesCount = ignoredFilesCount + 1
        ignoredLinesCount = ignoredLinesCount + readLinesSafe(path).len
  except CatchableError:
    discard
  result = GitignoreStat(ignoredFiles: ignoredFilesCount, ignoredLines: ignoredLinesCount)

proc scanInputDetailsAndSanitizers*(rootDir: string, files: seq[string],
    nimFunctions: seq[FunctionInfo]): tuple[inputs: seq[InputFuncInfo], inputCount: int, sanitizerCount: int] {.
    role: truthBuilder, metaTags: {tagStats}.} =
  var
    inputList: seq[InputFuncInfo] = @[]
    inCount: int = 0
    sanCount: int = 0
  for fn in nimFunctions:
    let role = declaredRoleOf(fn)
    let isIn = fn.handlesUserInput or role == "data fetcher" or role == "input"
    let isSan = role == "sanitizer"
    if isIn or isSan:
      if isIn: inCount = inCount + 1
      if isSan: sanCount = sanCount + 1
      var relPath = toModulePath(rootDir, fn.sourcePath) & ".nim"
      inputList.add(InputFuncInfo(
        name: fn.name,
        path: relPath,
        line: fn.lineStart,
        lang: "nim",
        role: if isSan: "sanitizer" else: "input",
        inputSource: if isSan: "sanitizer" else: "user/network",
        sanitizerName: if isSan: fn.name else: ""
      ))
  for path in files:
    let ext = extOf(path)
    if ext in ["c", "js", "ts"]:
      var rel = path[rootDir.len .. ^1].replace('\\', '/')
      if rel.startsWith("/"): rel = rel[1 .. ^1]
      let lines = readLinesSafe(path)
      var lineIdx = 0
      while lineIdx < lines.len:
        let lineStr = lines[lineIdx]
        if lineStr.contains("{.role:") or lineStr.contains("{.input:"):
          let lower = lineStr.toLowerAscii()
          let isSan = lower.contains("sanitizer")
          let isIn = lower.contains("datafetcher") or lower.contains("input") or lower.contains("user")
          var fnName = "anonymous"
          if lineIdx + 1 < lines.len:
            let nextLine = lines[lineIdx + 1].strip()
            let parts = nextLine.split({' ', '(', '{', ':'})
            for p in parts:
              if p.len > 1 and p notin ["function", "async", "void", "int", "char", "const", "static", "proc", "fn"]:
                fnName = p
                break
          if isIn or isSan:
            if isIn: inCount = inCount + 1
            if isSan: sanCount = sanCount + 1
            inputList.add(InputFuncInfo(
              name: fnName,
              path: rel,
              line: lineIdx + 1,
              lang: ext,
              role: if isSan: "sanitizer" else: "input",
              inputSource: if isSan: "sanitizer" else: "commentPragma",
              sanitizerName: if isSan: fnName else: ""
            ))
        lineIdx = lineIdx + 1
  result = (inputs: inputList, inputCount: inCount, sanitizerCount: sanCount)

proc scanUnsafeDetails*(rootDir: string, files: seq[string],
    nimFunctions: seq[FunctionInfo], inputFuncs: seq[InputFuncInfo],
    edges: seq[CallEdge]): seq[UnsafeFuncInfo] {.role: truthBuilder, metaTags: {tagStats}.} =
  result = @[]
  var inputNames = initHashSet[string]()
  for item in inputFuncs:
    inputNames.incl(item.name.toLowerAscii())

  for path in files:
    let ext = extOf(path)
    var rel = path[rootDir.len .. ^1].replace('\\', '/')
    if rel.startsWith("/"): rel = rel[1 .. ^1]
    let lines = readLinesSafe(path)
    var lineIdx = 0
    while lineIdx < lines.len:
      let lineStr = lines[lineIdx]
      var unsafeKind = ""
      if ext in ["nim", "nims"]:
        if lineStr.contains("cast["): unsafeKind = "cast"
        elif lineStr.contains("addr(") or lineStr.contains("unsafeAddr("): unsafeKind = "addr"
        elif lineStr.contains("UncheckedArray[") or lineStr.contains("uncheckedArray"): unsafeKind = "uncheckedArray"
        elif lineStr.contains("alloc(") or lineStr.contains("dealloc("): unsafeKind = "alloc"
        elif lineStr.contains("copyMem("): unsafeKind = "copyMem"
      elif ext in ["c", "cpp", "h"]:
        if lineStr.contains("malloc(") or lineStr.contains("free("): unsafeKind = "malloc"
        elif lineStr.contains("memcpy(") or lineStr.contains("strcpy("): unsafeKind = "memcpy"
        elif lineStr.contains("(void*)") or lineStr.contains("cast"): unsafeKind = "pointerCast"

      if unsafeKind.len > 0:
        var fnName = rel.split('/')[^1]
        for fn in nimFunctions:
          if fn.sourcePath == path and lineIdx + 1 >= fn.lineStart and lineIdx + 1 <= fn.lineEnd:
            fnName = fn.name
            break

        let touchesInput = fnName.toLowerAscii() in inputNames
        var trace = ""
        if touchesInput:
          trace = "Direct input handler: " & fnName
        else:
          trace = "Internal function: " & fnName

        result.add(UnsafeFuncInfo(
          name: fnName,
          path: rel,
          line: lineIdx + 1,
          lang: ext,
          kind: unsafeKind,
          touchesExternalData: touchesInput,
          externalDataTrace: trace
        ))
      lineIdx = lineIdx + 1

proc scanUnusedImports*(rootDir: string, files: seq[string]): seq[UnusedImportInfo] {.
    role: truthBuilder, metaTags: {tagStats}.} =
  result = @[]
  for path in files:
    if extOf(path) notin ["nim", "nims"]: continue
    var rel = path[rootDir.len .. ^1].replace('\\', '/')
    if rel.startsWith("/"): rel = rel[1 .. ^1]
    let lines = readLinesSafe(path)
    var fullContent = lines.join("\n")
    var lineIdx = 0
    while lineIdx < lines.len:
      let lineStr = lines[lineIdx].strip()
      if lineStr.startsWith("import "):
        let impStr = lineStr[7 .. ^1]
        let modules = impStr.split({',', ' '})
        for modRaw in modules:
          let m = modRaw.strip().split('/')[^1].strip()
          if m.len > 1 and not m.startsWith("[") and not m.startsWith("]"):
            let countMatches = fullContent.count(m)
            if countMatches <= 1:
              result.add(UnusedImportInfo(moduleName: m, path: rel, line: lineIdx + 1))
      lineIdx = lineIdx + 1

proc scanWhenSitesAndPlatformCoverage*(rootDir: string, files: seq[string]): tuple[
    sites: seq[WhenSite], platforms: seq[NameCount], simd: seq[SimdSite]] {.
    role: truthBuilder, metaTags: {tagStats}.} =
  var
    sitesList: seq[WhenSite] = @[]
    platTable = initTable[string, int]()
    simdList: seq[SimdSite] = @[]

  platTable["windows"] = 0
  platTable["linux"] = 0
  platTable["nixos"] = 0
  platTable["posix"] = 0

  for path in files:
    var rel = path[rootDir.len .. ^1].replace('\\', '/')
    if rel.startsWith("/"): rel = rel[1 .. ^1]
    let lines = readLinesSafe(path)
    var lineIdx = 0
    while lineIdx < lines.len:
      let lineStr = lines[lineIdx]
      let trimmed = lineStr.strip()
      if trimmed.startsWith("when ") or trimmed.startsWith("#ifdef ") or trimmed.startsWith("#if "):
        sitesList.add(WhenSite(path: rel, line: lineIdx + 1, condition: trimmed))
        let lower = trimmed.toLowerAscii()
        if lower.contains("windows") or lower.contains("_win32"):
          platTable["windows"] = platTable["windows"] + 1
        if lower.contains("linux") or lower.contains("__linux__"):
          platTable["linux"] = platTable["linux"] + 1
        if lower.contains("nixos") or lower.contains("nix"):
          platTable["nixos"] = platTable["nixos"] + 1
        if lower.contains("posix"):
          platTable["posix"] = platTable["posix"] + 1

      if lineStr.contains("nimsimd") or lineStr.contains("avx") or lineStr.contains("sse") or
         lineStr.contains("neon") or lineStr.contains("vector"):
        var feat = "SIMD"
        if lineStr.contains("avx"): feat = "AVX"
        elif lineStr.contains("sse"): feat = "SSE"
        elif lineStr.contains("neon"): feat = "NEON"
        simdList.add(SimdSite(path: rel, line: lineIdx + 1, feature: feat))

      lineIdx = lineIdx + 1

  var platCounts: seq[NameCount] = @[]
  for key, val in platTable.pairs:
    platCounts.add(NameCount(name: key, count: val))

  result = (sites: sitesList, platforms: platCounts, simd: simdList)

proc buildImportGraphAndDepth*(rootDir: string, files: seq[string]): tuple[
    depth: int, cycles: seq[CircularImportInfo]] {.role: truthBuilder, metaTags: {tagStats}.} =
  var
    adj = initTable[string, seq[string]]()
    cyclesList: seq[CircularImportInfo] = @[]
    maxD: int = 0

  for path in files:
    if extOf(path) notin ["nim", "nims"]: continue
    var rel = path[rootDir.len .. ^1].replace('\\', '/')
    if rel.startsWith("/"): rel = rel[1 .. ^1]
    let modName = rel.split('/')[^1].replace(".nim", "").replace(".nims", "")
    if not adj.hasKey(modName):
      adj[modName] = @[]
    for line in readLinesSafe(path):
      let s = line.strip()
      if s.startsWith("import "):
        let impStr = s[7 .. ^1]
        for item in impStr.split({',', ' '}):
          let target = item.strip().split('/')[^1].replace(".nim", "").strip()
          if target.len > 0 and target != modName:
            adj[modName].add(target)

  var visited = initHashSet[string]()
  var recStack = initHashSet[string]()

  proc dfs(node: string, currentDepth: int, pathSeq: seq[string]) =
    maxD = max(maxD, currentDepth)
    visited.incl(node)
    recStack.incl(node)
    if adj.hasKey(node):
      for neighbor in adj[node]:
        if neighbor in recStack:
          var cyclePath = pathSeq
          cyclePath.add(neighbor)
          cyclesList.add(CircularImportInfo(cycle: cyclePath))
        elif neighbor notin visited:
          var nextSeq = pathSeq
          nextSeq.add(neighbor)
          dfs(neighbor, currentDepth + 1, nextSeq)
    recStack.excl(node)

  for node in adj.keys:
    if node notin visited:
      dfs(node, 1, @[node])

  result = (depth: maxD, cycles: cyclesList)

proc calculateScopeStats*(files: seq[FileStat]): tuple[
    src: ProjectScopeStats, all: ProjectScopeStats, test: ProjectScopeStats] {.
    role: truthBuilder, metaTags: {tagStats}.} =
  var
    srcS = ProjectScopeStats()
    allS = ProjectScopeStats()
    testS = ProjectScopeStats()
    srcTotLines, allTotLines, testTotLines = 0

  for f in files:
    let isT = f.isTest or f.path.startsWith("tests/") or f.path.contains("/tests/")
    let isSrc = f.path.startsWith("src/") or f.path.contains("/src/")

    allS.files = allS.files + 1
    allS.lines = allS.lines + f.lines
    allS.functions = allS.functions + f.functions
    allS.templates = allS.templates + f.templates
    allS.macros = allS.macros + f.macros
    allS.inputFunctions = allS.inputFunctions + f.inputs
    allS.unsafeFunctions = allS.unsafeFunctions + f.unsafeCount
    allTotLines = allTotLines + f.lines

    if isSrc or not isT:
      srcS.files = srcS.files + 1
      srcS.lines = srcS.lines + f.lines
      srcS.functions = srcS.functions + f.functions
      srcS.templates = srcS.templates + f.templates
      srcS.macros = srcS.macros + f.macros
      srcS.inputFunctions = srcS.inputFunctions + f.inputs
      srcS.unsafeFunctions = srcS.unsafeFunctions + f.unsafeCount
      srcTotLines = srcTotLines + f.lines

    if isT:
      testS.files = testS.files + 1
      testS.lines = testS.lines + f.lines
      testS.functions = testS.functions + f.functions
      testS.templates = testS.templates + f.templates
      testS.macros = testS.macros + f.macros
      testS.inputFunctions = testS.inputFunctions + f.inputs
      testS.unsafeFunctions = testS.unsafeFunctions + f.unsafeCount
      testTotLines = testTotLines + f.lines

  if srcS.functions > 0: srcS.avgLines = srcTotLines.float / srcS.functions.float
  if allS.functions > 0: allS.avgLines = allTotLines.float / allS.functions.float
  if testS.functions > 0: testS.avgLines = testTotLines.float / testS.functions.float

  result = (src: srcS, all: allS, test: testS)
