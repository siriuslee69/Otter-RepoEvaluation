# ============================================================
# | Otter Repo Graph Analysis Pipeline                       |
# | -> End-to-end repo analysis orchestration               |
# ============================================================

import std/[os]

import ./exporters
import ./graph_builder
import ./grouping
import ./io_utils
import ./nim_parser
import ./role_inference
import ./types
import ../../../meta/metaPragmas

proc analyzeRepo*(rootDir: string, bIncludeTests: bool = false): RepoGraph {.role: orchestrator, metaTags: {tagGraph}.} =
  var
    files: seq[string] = @[]
    fs: seq[FunctionInfo] = @[]
    parsed: seq[FunctionInfo] = @[]
    graph: tuple[edges: seq[CallEdge], unresolved: seq[string]]
  files = listNimFiles(rootDir, bIncludeTests)
  for f in files:
    parsed = parseNimFile(rootDir, f)
    for node in parsed:
      fs.add(node)
  graph = buildCallGraph(fs)
  result = default(RepoGraph)
  result.rootDir = normalizeSlashes(rootDir)
  result.functions = fs
  result.edges = graph.edges
  result.unresolvedCalls = graph.unresolved
  inferRoles(result)
  result.groups = collectOrchestratorGroups(result)


proc graphSummaryLines*(g: RepoGraph): seq[string] {.role: helper, metaTags: {tagGraph}.} =
  var
    nHelpers: int = 0
    nWrappers: int = 0
    nParsers: int = 0
    nTruthBuilders: int = 0
    nActors: int = 0
    nFetchers: int = 0
    nOrchestrators: int = 0
    nMetaOrchestrators: int = 0
    nStates: int = 0
    nUnknown: int = 0
    nUserInput: int = 0
  result = @[]
  for f in g.functions:
    case f.role
    of frHelper:
      nHelpers = nHelpers + 1
    of frWrapper:
      nWrappers = nWrappers + 1
    of frParser:
      nParsers = nParsers + 1
    of frTruthBuilder:
      nTruthBuilders = nTruthBuilders + 1
    of frActor:
      nActors = nActors + 1
    of frDataFetcher:
      nFetchers = nFetchers + 1
    of frOrchestrator:
      nOrchestrators = nOrchestrators + 1
    of frMetaOrchestrator:
      nMetaOrchestrators = nMetaOrchestrators + 1
    of frStateController:
      nStates = nStates + 1
    else:
      nUnknown = nUnknown + 1
    if f.handlesUserInput:
      nUserInput = nUserInput + 1
  result.add("Root: " & g.rootDir)
  result.add("Functions: " & $g.functions.len)
  result.add("Edges: " & $g.edges.len)
  result.add("Unresolved Calls: " & $g.unresolvedCalls.len)
  result.add("Groups: " & $g.groups.len)
  result.add("Roles -> helper=" & $nHelpers &
    ", wrapper=" & $nWrappers &
    ", parser=" & $nParsers &
    ", truthBuilder=" & $nTruthBuilders &
    ", actor=" & $nActors &
    ", fetcher=" & $nFetchers &
    ", orchestrator=" & $nOrchestrators &
    ", meta=" & $nMetaOrchestrators &
    ", state=" & $nStates &
    ", unknown=" & $nUnknown)
  result.add("User Input Handlers: " & $nUserInput)


proc defaultOutputDir*(rootDir: string): string {.role: helper, metaTags: {tagGraph}.} =
  result = normalizeSlashes(joinPath(rootDir, "builds", "analysis"))


proc writeArtifacts*(g: RepoGraph, outputDir: string): seq[string] {.role: dataWriter, metaTags: {tagGraph}.} =
  var
    outRoot: string = outputDir
    pLayout: string = ""
    pCallTree: string = ""
    pMermaid: string = ""
    pDot: string = ""
    pJson: string = ""
  normalizePath(outRoot)
  createDir(outRoot)
  pLayout = joinPath(outRoot, "function_layout_tree.txt")
  pCallTree = joinPath(outRoot, "call_tree.txt")
  pMermaid = joinPath(outRoot, "flowchart.mmd")
  pDot = joinPath(outRoot, "callgraph.dot")
  pJson = joinPath(outRoot, "graph.json")
  writeFile(pLayout, toFunctionLayoutTree(g) & "\n")
  writeFile(pCallTree, toCallTree(g) & "\n")
  writeFile(pMermaid, toMermaidFlowchart(g) & "\n")
  writeFile(pDot, toDotGraph(g) & "\n")
  writeFile(pJson, toGraphJson(g) & "\n")
  result = @[
    normalizeSlashes(pLayout),
    normalizeSlashes(pCallTree),
    normalizeSlashes(pMermaid),
    normalizeSlashes(pDot),
    normalizeSlashes(pJson)
  ]
