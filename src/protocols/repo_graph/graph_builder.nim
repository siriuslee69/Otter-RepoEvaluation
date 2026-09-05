# ============================================================
# | Otter Repo Graph Builder                                 |
# | -> Resolve function calls into graph edges               |
# ============================================================

import std/[sets, tables]

import ./types
import ../../../meta/metaPragmas

proc importPreference(f: FunctionInfo, callName, targetModulePath: string): int {.role: helper, metaTags: {tagGraph, tagResolution, tagImportContext}.} =
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
    idxs: seq[int], callName: string): int {.role: helper, metaTags: {tagGraph, tagResolution}.} =
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


proc buildCallGraph*(fs: seq[FunctionInfo]): tuple[edges: seq[CallEdge],
    unresolved: seq[string]] {.role: truthBuilder, metaTags: {tagGraph, tagResolution}.} =
  var
    nameMap: Table[string, seq[int]]
    edgeSet: HashSet[string]
    callerIdx: int = 0
    idxs: seq[int] = @[]
    calleeIdx: int = -1
    edgeKey: string = ""
    e: CallEdge
  result.edges = @[]
  result.unresolved = @[]
  nameMap = initTable[string, seq[int]]()
  edgeSet = initHashSet[string]()
  for i, f in fs:
    if f.name notin nameMap:
      nameMap[f.name] = @[]
    nameMap[f.name].add(i)
  while callerIdx < fs.len:
    for callName in fs[callerIdx].calls:
      idxs = nameMap.getOrDefault(callName, @[])
      calleeIdx = chooseTargetIndex(fs, callerIdx, idxs, callName)
      if calleeIdx >= 0 and calleeIdx != callerIdx:
        edgeKey = fs[callerIdx].id & "->" & fs[calleeIdx].id
        if edgeKey notin edgeSet:
          edgeSet.incl(edgeKey)
          e = default(CallEdge)
          e.callerId = fs[callerIdx].id
          e.calleeId = fs[calleeIdx].id
          e.callName = callName
          result.edges.add(e)
      elif calleeIdx < 0:
        result.unresolved.add(fs[callerIdx].id & "::" & callName)
    callerIdx = callerIdx + 1
