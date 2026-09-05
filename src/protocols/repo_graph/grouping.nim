# ============================================================
# | Otter Repo Graph Grouping                                |
# | -> Collect helper clusters under orchestrator nodes      |
# ============================================================

import std/[sets, tables]

import ./types
import ../../../meta/metaPragmas

proc collectOutMap(g: RepoGraph): Table[string, seq[string]] {.role: helper, metaTags: {tagGraph}.} =
  var
    outMap: Table[string, seq[string]]
  outMap = initTable[string, seq[string]]()
  for f in g.functions:
    outMap[f.id] = @[]
  for e in g.edges:
    outMap[e.callerId] = outMap.getOrDefault(e.callerId, @[])
    outMap[e.callerId].add(e.calleeId)
  result = outMap


proc functionMapById*(g: RepoGraph): Table[string, FunctionInfo] {.role: helper, metaTags: {tagGraph}.} =
  var
    m: Table[string, FunctionInfo]
  m = initTable[string, FunctionInfo]()
  for f in g.functions:
    m[f.id] = f
  result = m


proc collectOrchestratorGroups*(g: RepoGraph): seq[OrchestratorGroup] {.role: truthBuilder, metaTags: {tagGraph}.} =
  var
    byId: Table[string, FunctionInfo]
    outMap: Table[string, seq[string]]
    group: OrchestratorGroup
    memberSet: HashSet[string]
    visitSet: HashSet[string]
  byId = functionMapById(g)
  outMap = collectOutMap(g)
  result = @[]

  proc walkGroup(rootId: string, currentId: string) =
    var
      current: FunctionInfo
    if currentId in visitSet:
      return
    visitSet.incl(currentId)
    if currentId notin byId:
      return
    current = byId[currentId]
    if currentId != rootId and isOrchestratorLike(current.role):
      return
    if currentId != rootId and current.role == frStateController:
      return
    if currentId != rootId and isGroupableRole(current.role):
      if currentId notin memberSet:
        memberSet.incl(currentId)
        group.memberIds.add(currentId)
    for childId in outMap.getOrDefault(currentId, @[]):
      if childId notin byId:
        continue
      if childId == rootId:
        continue
      current = byId[childId]
      if isGroupableRole(current.role):
        if childId notin memberSet:
          memberSet.incl(childId)
          group.memberIds.add(childId)
        walkGroup(rootId, childId)
      elif not isOrchestratorLike(current.role) and current.role != frStateController:
        walkGroup(rootId, childId)

  for f in g.functions:
    if not isOrchestratorLike(f.role):
      continue
    group = default(OrchestratorGroup)
    memberSet = initHashSet[string]()
    visitSet = initHashSet[string]()
    group.id = "group:" & f.id
    group.orchestratorId = f.id
    group.label = f.name
    for childId in outMap.getOrDefault(f.id, @[]):
      if childId notin byId:
        continue
      if isGroupableRole(byId[childId].role):
        group.directMemberIds.add(childId)
      walkGroup(f.id, childId)
    if group.directMemberIds.len == 0 and group.memberIds.len == 0:
      continue
    result.add(group)
