## ================================================================
## | checks.nim  <-  several questions, one reading of the tree     |
## |---------------------------------------------------------------|
## | Every check here starts from the same two things: the routines |
## | of the repository, and the measurement built on them. Asking   |
## | four questions used to read the tree four times.               |
## |                                                                |
## |   otter-repo-graph checks . stats state ui yields:seal         |
## ================================================================
##
## Reading once is worth more than running at once
## -----------------------------------------------
## Parsing the tree is most of the work; the checks on top of it are
## quick. So the first thing this does is read the tree once and hand
## the same result to every check:
##
##   four checks, four readings   ~8s on Tyr
##   four checks, one reading     ~3s, before any threads are involved
##
## `--parallel` then runs the checks themselves at the same time on
## top of that. On a machine with cores to spare it is faster again;
## on a small board, or one sharing its heat with something else, the
## plain form runs them one after another and is the right choice.
## Neither changes a single answer.
##
## What each check needs
## ---------------------
##
##   stats      the measurement          the whole shape of the tree
##   state      the routines             who writes each entry
##   yields     the routines             how a routine can end
##   blast      the routines             what a change can reach
##   ui         the files                how far away a control is
##
## Two things are built at most once each, and only when something
## asks for them, so `checks . ui` never parses a routine at all.

import std/[monotimes, strutils, times]

import ../repo_graph/types as graphTypes
import ../repo_graph/analysis_pipeline
import ./types
import ./project
import ./pipeline
import ./state_writes
import ./yields
import ./blast
import ./ui_depth
import runePragmas

type
  CheckKind* {.role: other, tag: "stats".} = enum
    ckStats,
    ckState,
    ckYields,
    ckBlast,
    ckUi

  CheckRequest* {.role: configurator, tag: "stats".} = object
    ## One question to ask, and what to ask it about.
    kind*: CheckKind
    arg*: string
      ## A type name for `state`, a routine name for `yields` and
      ## `blast`, empty for the rest.

  CheckResult* {.role: preparedData, tag: "stats".} = object
    ## One answer, with what it cost.
    name*: string
    lines*: seq[string]
    millis*: int
    ok*: bool

  CheckInputs* {.role: memory, tag: "stats".} = object
    ## The two expensive things, built at most once each.
    rootDir*: string
    graph*: RepoGraph
    stats*: ProjectStats
    haveGraph*: bool
    haveStats*: bool

proc parseCheck*(word: string): tuple[ok: bool, req: CheckRequest]
    {.role: parser, tag: "stats".} =
  ## word: one word from the command line, `stats` or `yields:seal`.
  ##
  ## The check it names and what to ask it about. A colon separates
  ## the two so that a whole run still fits on one line:
  ##
  ##   checks . stats state:Feed yields:seal blast:parseFrame
  var
    at: int = word.find(':')
    name: string = word
    arg: string = ""
  result = (ok: false, req: CheckRequest(kind: ckStats, arg: ""))
  if at >= 0:
    name = word[0 ..< at]
    arg = word[at + 1 .. ^1]
  case name.toLowerAscii()
  of "stats":
    result = (ok: true, req: CheckRequest(kind: ckStats, arg: arg))
  of "state":
    result = (ok: true, req: CheckRequest(kind: ckState, arg: arg))
  of "yields":
    result = (ok: true, req: CheckRequest(kind: ckYields, arg: arg))
  of "blast":
    result = (ok: true, req: CheckRequest(kind: ckBlast, arg: arg))
  of "ui":
    result = (ok: true, req: CheckRequest(kind: ckUi, arg: arg))
  else:
    result.ok = false

proc checkName*(r: CheckRequest): string {.role: helper,
    tag: "stats".} =
  ## r: one question. What to head its answer with.
  case r.kind
  of ckStats: result = "stats"
  of ckState: result = "state"
  of ckYields: result = "yields"
  of ckBlast: result = "blast"
  of ckUi: result = "ui"
  if r.arg.len > 0:
    result = result & " " & r.arg

proc needsGraph(r: CheckRequest): bool {.inline.} =
  result = r.kind in {ckState, ckYields, ckBlast}

proc needsStats(r: CheckRequest): bool {.inline.} =
  result = r.kind == ckStats

proc gather*(rootDir: string, R: seq[CheckRequest]): CheckInputs
    {.role: dataFetcher, tag: "stats".} =
  ## rootDir: the repository   R: everything being asked.
  ##
  ## Reads the tree, once, for whichever of the two expensive things
  ## the questions actually need. Asking only about a front end never
  ## parses a routine.
  var
    wantGraph: bool = false
    wantStats: bool = false
  result = CheckInputs(rootDir: rootDir, graph: RepoGraph(),
    stats: ProjectStats(), haveGraph: false, haveStats: false)
  for r in R:
    wantGraph = wantGraph or needsGraph(r)
    wantStats = wantStats or needsStats(r)
  if wantGraph:
    result.graph = analyzeRepo(rootDir)
    result.haveGraph = true
  if wantStats:
    result.stats = analyzeProject(rootDir)
    result.haveStats = true

proc answer*(inputs: CheckInputs, r: CheckRequest): seq[string]
    {.role: orchestrator, tag: "stats".} =
  ## inputs: the tree, already read   r: one question.
  ## Its answer as plain lines. Pure: it reads what `gather` built and
  ## writes nothing, which is what lets several run at once.
  result = @[]
  case r.kind
  of ckStats:
    result = summaryLines(inputs.stats)
  of ckState:
    result = stateLines(stateWritesOf(inputs.graph, r.arg))
  of ckYields:
    if r.arg.len == 0:
      result = @["yields: name a routine, as `yields:seal`"]
      return
    result = yieldLines(yieldPathsOf(inputs.graph, r.arg,
      escapingOf(inputs.graph)))
  of ckBlast:
    if r.arg.len == 0:
      result = @["blast: name a routine or a type, as `blast:parseFrame`"]
      return
    result = blastLines(blastRadius(inputs.graph, r.arg))
  of ckUi:
    result = uiDepthLines(uiDepthOf(inputs.rootDir,
      listAllSourceFiles(inputs.rootDir)))

var
  sharedInputs: CheckInputs = CheckInputs()
    ## What every check reads. Written once before any thread starts
    ## and never written again, so no thread has to wait for it.
  sharedRequests: seq[CheckRequest] = @[]
  sharedResults: seq[CheckResult] = @[]
    ## One slot per question, filled in place. Each thread writes only
    ## its own slot and the sequence is never grown while they run, so
    ## the slots do not move under one another.

proc runOne(i: int) {.role: actor, tag: "stats".} =
  ## i: which question. Answers it into slot `i`, timing it.
  var
    began: MonoTime = getMonoTime()
  try:
    sharedResults[i].lines = answer(sharedInputs, sharedRequests[i])
    sharedResults[i].ok = true
  except CatchableError as e:
    sharedResults[i].lines = @[checkName(sharedRequests[i]) &
      " could not be answered: " & e.msg]
    sharedResults[i].ok = false
  sharedResults[i].millis = int(inMilliseconds(getMonoTime() - began))

proc runOneThread(i: int) {.thread, role: actor, tag: "stats".} =
  ## i: which question. The same work, on a thread of its own.
  ##
  ## The cast is a promise, so here is the reasoning behind it. Three
  ## globals are touched. Two of them - the tree and the list of
  ## questions - are written once before the first thread starts and
  ## never again, so there is nothing to race for. The third is a list
  ## of answer slots, one per question, filled to its final length
  ## before any thread starts: no thread grows it, so no slot moves
  ## under another thread, and each thread writes only its own index.
  {.cast(gcsafe).}:
    runOne(i)

var
  gatherRoot: string = ""
    ## Where the two readings below happen. Written before either
    ## thread starts.

proc readGraph(i: int) {.thread, role: dataFetcher, tag: "stats".} =
  ## i: unused; a thread has to take something.
  ## Reads the routines of the tree into the shared inputs.
  {.cast(gcsafe).}:
    sharedInputs.graph = analyzeRepo(gatherRoot)
    sharedInputs.haveGraph = true

proc readStats(i: int) {.thread, role: dataFetcher, tag: "stats".} =
  ## i: unused; a thread has to take something.
  ## Builds the whole measurement into the shared inputs.
  {.cast(gcsafe).}:
    sharedInputs.stats = analyzeProject(gatherRoot)
    sharedInputs.haveStats = true

proc gatherParallel(rootDir: string, R: seq[CheckRequest])
    {.role: orchestrator, tag: "stats".} =
  ## rootDir: the repository   R: the questions.
  ##
  ## The two readings are independent of each other and are most of
  ## the time, so on a repository of any size this is where a second
  ## core actually earns something. Each writes its own field of the
  ## shared inputs and reads none of the other's.
  var
    wantGraph: bool = false
    wantStats: bool = false
    two: array[2, Thread[int]] = default(array[2, Thread[int]])
  gatherRoot = rootDir
  sharedInputs = CheckInputs(rootDir: rootDir, graph: RepoGraph(),
    stats: ProjectStats(), haveGraph: false, haveStats: false)
  for r in R:
    wantGraph = wantGraph or needsGraph(r)
    wantStats = wantStats or needsStats(r)
  if wantGraph and wantStats:
    createThread(two[0], readGraph, 0)
    createThread(two[1], readStats, 0)
    joinThreads(two)
    return
  if wantGraph:
    readGraph(0)
  if wantStats:
    readStats(0)

proc runChecks*(rootDir: string, R: seq[CheckRequest],
    bParallel: bool): tuple[readMillis: int, rows: seq[CheckResult]]
    {.role: metaOrchestrator, tag: "stats".} =
  ## rootDir: the repository   R: the questions
  ## bParallel: whether to answer them at once.
  ##
  ## The tree is read once either way; that is where the time goes.
  ## `bParallel` only decides whether the cheap part runs together, so
  ## a small board or a machine already busy can leave it off and get
  ## exactly the same answers a little later.
  var
    threads: seq[Thread[int]] = @[]
    began: MonoTime = getMonoTime()
    i: int = 0
  result = (readMillis: 0, rows: @[])
  if R.len == 0:
    return
  sharedRequests = R
  sharedResults = @[]
  for r in R:
    sharedResults.add(CheckResult(name: checkName(r), lines: @[],
      millis: 0, ok: false))
  if bParallel:
    gatherParallel(rootDir, R)
  else:
    sharedInputs = gather(rootDir, R)
  result.readMillis = int(inMilliseconds(getMonoTime() - began))
  if not bParallel or R.len == 1:
    while i < R.len:
      runOne(i)
      i = i + 1
    result.rows = sharedResults
    return
  threads.setLen(R.len)
  i = 0
  while i < R.len:
    createThread(threads[i], runOneThread, i)
    i = i + 1
  joinThreads(threads)
  result.rows = sharedResults

proc checkLines*(readMillis: int, A: seq[CheckResult],
    bParallel: bool): seq[string] {.role: dataWriter, tag: "stats".} =
  ## readMillis: what reading the tree cost   A: every answer
  ## bParallel: how they were run, for the closing line.
  ##
  ## Reading the tree is counted apart from the checks because it is
  ## usually most of the time, and a report that folded it into the
  ## first check would make that check look slow and the rest look
  ## free.
  ## All of them one after another, each under its own heading, in the
  ## order they were asked for rather than the order they finished.
  var
    total: int = 0
  result = @[]
  for r in A:
    result.add("")
    result.add("── " & r.name & "  (" & $r.millis & " ms)")
    for line in r.lines:
      result.add(line)
    total = total + r.millis
  result.add("")
  result.add("── reading the tree, once: " & $readMillis & " ms")
  if bParallel:
    result.add("── " & $A.len & " check(s), together, " & $total &
      " ms of work on top")
  else:
    result.add("── " & $A.len & " check(s), one after another, " & $total &
      " ms on top")
