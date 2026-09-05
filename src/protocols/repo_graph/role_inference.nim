# ============================================================
# | Otter Repo Graph Role Inference                          |
# | -> Heuristic role scoring for untagged functions         |
# ============================================================

import std/[math, strutils, tables]

import ./types
import ../../../meta/metaPragmas

proc countBranches(ls: seq[string]): int {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  result = 0
  for raw in ls:
    t = raw.strip().toLowerAscii()
    if t.startsWith("if ") or t.startsWith("elif ") or t.startsWith("case ") or t.startsWith("of "):
      result = result + 1


proc hasStateSignal(f: FunctionInfo): bool {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  for p in f.params:
    t = p.toLowerAscii()
    if t == "s" or t.startsWith("s") or "state" in t:
      result = true
      return
  for line in f.bodyLines:
    t = line.toLowerAscii()
    if ".state" in t or "case s" in t or "case state" in t:
      result = true
      return


proc nameContainsOneOf(s: string, A: openArray[string]): bool {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = s.toLowerAscii()
  for item in A:
    if item in t:
      result = true
      return


proc inferRoles*(g: var RepoGraph) {.role: truthBuilder, metaTags: {tagGraph, tagParsing}.} =
  var
    inDeg: Table[string, int]
    outDeg: Table[string, int]
    i: int = 0
    f: FunctionInfo
    dIn: int = 0
    dOut: int = 0
    nBranches: int = 0
    nLines: int = 0
    bState: bool = false
    nameLower: string = ""
    sHelper: float = 0.0
    sWrapper: float = 0.0
    sParser: float = 0.0
    sTruthBuilder: float = 0.0
    sActor: float = 0.0
    sFetcher: float = 0.0
    sOrchestrator: float = 0.0
    sMetaOrchestrator: float = 0.0
    sState: float = 0.0
    best: FunctionRole = frUnknown
    score: float = 0.0
  inDeg = initTable[string, int]()
  outDeg = initTable[string, int]()
  for node in g.functions:
    inDeg[node.id] = 0
    outDeg[node.id] = 0
  for e in g.edges:
    outDeg[e.callerId] = outDeg.getOrDefault(e.callerId, 0) + 1
    inDeg[e.calleeId] = inDeg.getOrDefault(e.calleeId, 0) + 1
  while i < g.functions.len:
    f = g.functions[i]
    dIn = inDeg.getOrDefault(f.id, 0)
    dOut = outDeg.getOrDefault(f.id, 0)
    nBranches = countBranches(f.bodyLines)
    nLines = f.bodyLines.len
    bState = hasStateSignal(f)
    nameLower = f.name.toLowerAscii()
    sHelper = 0.0
    sWrapper = 0.0
    sParser = 0.0
    sTruthBuilder = 0.0
    sActor = 0.0
    sFetcher = 0.0
    sOrchestrator = 0.0
    sMetaOrchestrator = 0.0
    sState = 0.0
    best = frUnknown
    score = 0.0
    if f.declaredRole != frUnknown:
      f.role = f.declaredRole
      f.roleConfidence = 1.0
      if f.roleReason.len == 0:
        f.roleReason = "declared role"
      g.functions[i] = f
      i = i + 1
      continue
    if dOut <= 1:
      sHelper = sHelper + 0.35
    if nBranches <= 1:
      sHelper = sHelper + 0.2
    if nLines <= 14:
      sHelper = sHelper + 0.2
    if dIn >= 1:
      sHelper = sHelper + 0.25
    if dOut == 1:
      sWrapper = sWrapper + 0.5
    if nLines <= 8:
      sWrapper = sWrapper + 0.25
    if nBranches == 0:
      sWrapper = sWrapper + 0.25
    if nameContainsOneOf(nameLower, ["parse", "token", "scan", "decode"]):
      sParser = sParser + 0.55
    if dOut <= 1:
      sParser = sParser + 0.2
    if nameContainsOneOf(nameLower, ["build", "compose", "assemble", "make"]):
      sTruthBuilder = sTruthBuilder + 0.5
    if dOut >= 1:
      sTruthBuilder = sTruthBuilder + 0.2
    if nameContainsOneOf(nameLower, ["fetch", "read", "load", "pull"]):
      sFetcher = sFetcher + 0.55
    if dOut <= 1:
      sFetcher = sFetcher + 0.2
    if nameContainsOneOf(nameLower, ["emit", "write", "apply", "commit", "run", "act"]):
      sActor = sActor + 0.45
    if dOut >= 1:
      sActor = sActor + 0.15
    if dOut >= 2:
      sOrchestrator = sOrchestrator + 0.4
    if nLines >= 8:
      sOrchestrator = sOrchestrator + 0.2
    if nBranches >= 1:
      sOrchestrator = sOrchestrator + 0.2
    if dIn == 0:
      sOrchestrator = sOrchestrator + 0.2
    if dOut >= 4:
      sMetaOrchestrator = sMetaOrchestrator + 0.45
    if dIn == 0:
      sMetaOrchestrator = sMetaOrchestrator + 0.2
    if nLines >= 12:
      sMetaOrchestrator = sMetaOrchestrator + 0.15
    if nBranches >= 3:
      sState = sState + 0.5
    if bState:
      sState = sState + 0.3
    if dOut >= 1:
      sState = sState + 0.2
    best = frHelper
    score = sHelper
    if sWrapper > score:
      best = frWrapper
      score = sWrapper
    if sParser > score:
      best = frParser
      score = sParser
    if sTruthBuilder > score:
      best = frTruthBuilder
      score = sTruthBuilder
    if sFetcher > score:
      best = frDataFetcher
      score = sFetcher
    if sActor > score:
      best = frActor
      score = sActor
    if sOrchestrator > score:
      best = frOrchestrator
      score = sOrchestrator
    if sMetaOrchestrator > score:
      best = frMetaOrchestrator
      score = sMetaOrchestrator
    if sState > score:
      best = frStateController
      score = sState
    if score < 0.45:
      best = frUnknown
    f.role = best
    f.roleConfidence = round(score * 100.0) / 100.0
    f.roleReason = "in=" & $dIn & ", out=" & $dOut & ", branches=" & $nBranches
    g.functions[i] = f
    i = i + 1
