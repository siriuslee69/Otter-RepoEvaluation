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
## `--parallel` then lets the reading and the checks spread over every
## core (Fylgia's auto threader). On a machine with cores to spare it
## is faster again; on a small board, or one sharing its heat with
## something else, the plain form holds the thread budget at one and
## runs everything one after another. Neither changes a single answer.
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
import ../fylgia_threads
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

proc graphWhen(rootDir: string, want: bool): RepoGraph {.role: dataFetcher,
    tag: "stats".} =
  ## rootDir: the repository   want: whether any question needs it.
  ## The routines of the tree, or an empty graph when nobody asks.
  result = RepoGraph()
  if want:
    result = analyzeRepo(rootDir)

proc statsWhen(rootDir: string, want: bool): ProjectStats {.role: dataFetcher,
    tag: "stats".} =
  ## rootDir: the repository   want: whether any question needs it.
  ## The whole measurement, or an empty one when nobody asks.
  result = ProjectStats()
  if want:
    result = analyzeProject(rootDir)

proc gather*(rootDir: string, R: seq[CheckRequest]): CheckInputs
    {.role: dataFetcher, tag: "stats".} =
  ## rootDir: the repository   R: everything being asked.
  ##
  ## Reads the tree, once, for whichever of the two expensive things
  ## the questions actually need. Asking only about a front end never
  ## parses a routine. The two readings do not depend on each other,
  ## so they run at the same time.
  var
    wantGraph: bool = false
    wantStats: bool = false
  result = CheckInputs(rootDir: rootDir, graph: RepoGraph(),
    stats: ProjectStats(), haveGraph: false, haveStats: false)
  for r in R:
    wantGraph = wantGraph or needsGraph(r)
    wantStats = wantStats or needsStats(r)
  together:
    result.graph = graphWhen(rootDir, wantGraph)
    result.stats = statsWhen(rootDir, wantStats)
  result.haveGraph = wantGraph
  result.haveStats = wantStats

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

proc answerTimed(T: tuple[inputs: ptr CheckInputs, R: ptr seq[CheckRequest]],
    i: int): CheckResult {.role: actor, tag: "stats".} =
  ## T: the tree, already read, and every question   i: which question.
  ## Its answer, timed. A question that fails says so in its own lines
  ## instead of taking the other answers down with it.
  var
    began: MonoTime = getMonoTime()
  result = CheckResult(name: checkName(T.R[][i]), lines: @[], millis: 0,
    ok: false)
  try:
    result.lines = answer(T.inputs[], T.R[][i])
    result.ok = true
  except CatchableError as e:
    result.lines = @[result.name & " could not be answered: " & e.msg]
  result.millis = int(inMilliseconds(getMonoTime() - began))

proc runChecks*(rootDir: string, R: seq[CheckRequest],
    bParallel: bool): tuple[readMillis: int, rows: seq[CheckResult]]
    {.role: metaOrchestrator, tag: "stats".} =
  ## rootDir: the repository   R: the questions
  ## bParallel: whether to use more than one core.
  ##
  ## The tree is read once either way; that is where the time goes.
  ## Without `bParallel` the thread budget is held at one for the whole
  ## run, so a small board or a machine already busy gets exactly the
  ## same answers a little later.
  var
    began: MonoTime = getMonoTime()
    inputs: CheckInputs = CheckInputs()
    before: int = threadLimit()
  result = (readMillis: 0, rows: @[])
  if R.len == 0:
    return
  if not bParallel:
    setThreadLimit(1)
  inputs = gather(rootDir, R)
  result.readMillis = int(inMilliseconds(getMonoTime() - began))
  result.rows = parallelRange(R.len, (inputs: addr inputs,
    R: unsafeAddr R), answerTimed)
  setThreadLimit(before)

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
