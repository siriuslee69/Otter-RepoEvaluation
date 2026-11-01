## ============================================================
## | Otter Repo Graph Builder                                 |
## | -> Resolve function calls into graph edges               |
## ============================================================

import std/[sets, tables]

import ./types
import runePragmas

proc importPreference(f: FunctionInfo, callName, targetModulePath: string): int {.role: helper, tag: "graph|resolution|importContext".} =
  var
    i: int = 0
  while i < f.importBindings.len:
    if f.importBindings[i].kind == ikSymbol and
        f.importBindings[i].localName == callName and
        f.importBindings[i].modulePath == targetModulePath:
      result = i
      return
    i = i + 1
  i = 0
  while i < f.importBindings.len:
    if f.importBindings[i].kind == ikModule and
        f.importBindings[i].modulePath == targetModulePath:
      result = 1024 + i
      return
    i = i + 1
  result = high(int)


proc chooseTargetIndex(fs: seq[FunctionInfo], callerIdx: int,
    idxs: seq[int], callName: string): int {.role: helper, tag: "graph|resolution".} =
  var
    bestIdx: int = -1
    bestRank: int = high(int)
    callerModule: string = ""
    rank: int = 0
  if idxs.len == 0:
    result = -1
    return
  if idxs.len == 1:
    result = idxs[0]
    return
  callerModule = fs[callerIdx].modulePath
  for i in idxs:
    if fs[i].modulePath == callerModule:
      result = i
      return
  for i in idxs:
    rank = importPreference(fs[callerIdx], callName, fs[i].modulePath)
    if rank < bestRank:
      bestRank = rank
      bestIdx = i
  if bestIdx >= 0:
    result = bestIdx
    return
  result = idxs[0]


proc addCalls(fs: seq[FunctionInfo], caller: int,
    names: Table[string, seq[int]], seen: var HashSet[string],
    edges: var seq[CallEdge], unresolved: var seq[string])
    {.role: truthBuilder.} =
  ## fs: functions; caller: source index; names: candidate indices by name.
  ## seen: existing edges; edges and unresolved: results to append to.
  var
    target: int = -1
    key: string = ""
    e: CallEdge = default(CallEdge)
  for callName in fs[caller].calls:
    target = chooseTargetIndex(fs, caller, names.getOrDefault(callName, @[]),
      callName)
    if target < 0:
      unresolved.add(fs[caller].id & "::" & callName)
      continue
    if target == caller:
      continue
    key = fs[caller].id & "->" & fs[target].id
    if key in seen:
      continue
    seen.incl(key)
    e = default(CallEdge)
    e.callerId = fs[caller].id
    e.calleeId = fs[target].id
    e.callName = callName
    edges.add(e)

proc buildCallGraph*(fs: seq[FunctionInfo]): tuple[edges: seq[CallEdge],
    unresolved: seq[string]] {.role: truthBuilder, tag: "graph|resolution".} =
  var
    nameMap: Table[string, seq[int]] = default(Table[string, seq[int]])
    edgeSet: HashSet[string] = default(HashSet[string])
    callerIdx: int = 0
  result.edges = @[]
  result.unresolved = @[]
  nameMap = initTable[string, seq[int]]()
  edgeSet = initHashSet[string]()
  for i, f in fs:
    if f.name notin nameMap:
      nameMap[f.name] = @[]
    nameMap[f.name].add(i)
  while callerIdx < fs.len:
    addCalls(fs, callerIdx, nameMap, edgeSet, result.edges, result.unresolved)
    callerIdx = callerIdx + 1
