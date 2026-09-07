# ============================================================
# | Otter Repo Graph CLI                                     |
# | -> Analyze repos, write artifacts, and run sample calls  |
# ============================================================

import std/[json, os, strutils]

import ../../../meta/metaPragmas
import ../../otter_repo_evaluation

proc printUsage() {.role: helper, metaTags: {tagGraph, tagExecution}.} =
  echo "Usage:"
  echo "  otter_repo_graph snapshot [repoRoot] [--include-tests]"
  echo "  otter_repo_graph artifacts [repoRoot] [outputDir] [--include-tests]"
  echo "  otter_repo_graph run [repoRoot] [functionId] [--include-tests]"
  echo "  otter_repo_graph stats [repoRoot] [--json]"
  echo "  otter_repo_graph blast [repoRoot] <name> [--callers:n] [--feeders:m] [--json]"


proc flagPresent(args: seq[string], flag: string): bool {.role: helper, metaTags: {tagGraph, tagExecution}.} =
  for a in args:
    if a == flag:
      result = true
      return


proc positionalArgs(args: seq[string]): seq[string] {.role: helper, metaTags: {tagGraph, tagExecution}.} =
  for a in args:
    if a.startsWith("--"):
      continue
    result.add(a)


proc cliArgs(): seq[string] {.role: helper, metaTags: {tagGraph, tagExecution}.} =
  var
    i: int = 1
  while i <= paramCount():
    result.add(paramStr(i))
    i = i + 1


proc runSnapshot(args: seq[string]) {.role: actor, metaTags: {tagGraph, tagExecution}.} =
  var
    items: seq[string] = @[]
    rootDir: string = "."
    includeTests: bool = false
    g: RepoGraph
  items = positionalArgs(args)
  if items.len > 0:
    rootDir = items[0]
  includeTests = flagPresent(args, "--include-tests")
  g = analyzeRepo(rootDir, includeTests)
  echo toGraphJson(g)


proc runArtifacts(args: seq[string]) {.role: actor, metaTags: {tagGraph, tagExecution}.} =
  var
    items: seq[string] = @[]
    rootDir: string = "."
    outputDir: string = ""
    includeTests: bool = false
    g: RepoGraph
  items = positionalArgs(args)
  if items.len > 0:
    rootDir = items[0]
  if items.len > 1:
    outputDir = items[1]
  if outputDir.len == 0:
    outputDir = defaultOutputDir(rootDir)
  includeTests = flagPresent(args, "--include-tests")
  g = analyzeRepo(rootDir, includeTests)
  discard writeArtifacts(g, outputDir)
  for line in graphSummaryLines(g):
    echo line
  echo "Artifacts: " & outputDir


proc runSample(args: seq[string]) {.role: actor, metaTags: {tagGraph, tagExecution}.} =
  var
    items: seq[string] = @[]
    rootDir: string = "."
    functionId: string = ""
    includeTests: bool = true
    r: RunSampleResult
  items = positionalArgs(args)
  if items.len > 0:
    rootDir = items[0]
  if items.len > 1:
    functionId = items[1]
  if functionId.len == 0:
    printUsage()
    quit(1)
  includeTests = true
  r = runFunctionSample(rootDir, functionId, includeTests)
  echo toRunSampleJson(r)
  if not r.ok:
    quit(1)


proc flagValue(args: seq[string], flag: string, fallback: int): int
    {.role: parser, metaTags: {tagGraph, tagExecution}.} =
  ## args: the words after the command   flag: what to look for
  ## fallback: what to use when it is absent or unreadable.
  var prefix: string = flag & ":"
  result = fallback
  for a in args:
    if not a.startsWith(prefix):
      continue
    try:
      result = parseInt(a[prefix.len .. ^1])
    except ValueError:
      result = fallback

proc runBlast(args: seq[string]) {.role: actor,
    metaTags: {tagGraph, tagExecution}.} =
  ## args: the words after `blast`. What one change to a routine or a
  ## type can reach, up through its callers and down into what is
  ## handed to it.
  var
    items: seq[string] = @[]
    rootDir: string = "."
    name: string = ""
    n: int = 0
    m: int = 0
    r: BlastRadius
    g: RepoGraph
  items = positionalArgs(args)
  if items.len < 2:
    echo "Usage: otter_repo_graph blast <repoRoot> <name> " &
      "[--callers:n] [--feeders:m] [--json]"
    quit(1)
  rootDir = items[0]
  name = items[1]
  n = flagValue(args, "--callers", defaultCallerDepth)
  m = flagValue(args, "--feeders", defaultFeederDepth)
  g = analyzeRepo(rootDir)
  r = blastRadius(g, name, n, m)
  if flagPresent(args, "--json"):
    echo blastJson(r)
    return
  for line in blastLines(r):
    echo line
  if r.error.len > 0:
    quit(1)

proc runStats(args: seq[string]) {.role: actor,
    metaTags: {tagGraph, tagStats, tagExecution}.} =
  ## args: the words after `stats`. Prints the summary a person reads,
  ## or the whole shape a window reads, but never both.
  var
    items: seq[string] = @[]
    rootDir: string = "."
    s: ProjectStats
  items = positionalArgs(args)
  if items.len > 0:
    rootDir = items[0]
  s = analyzeProject(rootDir)
  if flagPresent(args, "--json"):
    echo statsJson(s)
    return
  for line in summaryLines(s):
    echo line
  if s.error.len > 0:
    quit(1)


proc runCli*() {.role: orchestrator, metaTags: {tagGraph, tagExecution}.} =
  var
    args: seq[string] = @[]
    cmd: string = ""
    rest: seq[string] = @[]
  args = cliArgs()
  if args.len == 0 or args[0] == "--help" or args[0] == "-h":
    printUsage()
    return
  cmd = args[0]
  if args.len > 1:
    rest = args[1 .. ^1]
  else:
    rest = @[]
  case cmd
  of "snapshot":
    runSnapshot(rest)
  of "artifacts":
    runArtifacts(rest)
  of "run":
    runSample(rest)
  of "stats":
    runStats(rest)
  of "blast":
    runBlast(rest)
  else:
    printUsage()
    quit(1)


when isMainModule:
  runCli()
