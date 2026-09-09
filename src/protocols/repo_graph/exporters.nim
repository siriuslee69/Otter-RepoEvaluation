# ============================================================
# | Otter Repo Graph Exporters                               |
# | -> Convert repo graphs into text and JSON outputs        |
# ============================================================

import std/[algorithm, json, sets, strutils, tables]

import ./grouping
import ./types
import runePragmas

proc escapeText(s: string): string {.role: helper, tag: "graph".} =
  result = s.replace("\\", "\\\\")
  result = result.replace("\"", "\\\"")


proc sanitizeNodeId(s: string): string {.role: helper, tag: "graph".} =
  var
    t: string = "n"
  for c in s:
    if c.isAlphaNumeric():
      t.add(c)
    else:
      t.add('_')
  result = t


proc sortedFunctions(g: RepoGraph): seq[FunctionInfo] {.role: helper, tag: "graph".} =
  result = g.functions
  result.sort(proc(a, b: FunctionInfo): int =
    if a.modulePath < b.modulePath:
      return -1
    if a.modulePath > b.modulePath:
      return 1
    if a.lineStart < b.lineStart:
      return -1
    if a.lineStart > b.lineStart:
      return 1
    if a.name < b.name:
      return -1
    if a.name > b.name:
      return 1
    return 0
  )


proc tooltipLineFor(f: FunctionInfo): string {.role: helper, tag: "graph".} =
  var
    s: string = ""
  s = f.name & " [" & roleToString(f.role) & "]"
  if f.returnType.len > 0:
    s.add(" -> " & f.returnType)
  result = s


proc toFunctionLayoutTree*(g: RepoGraph): string {.role: helper, tag: "graph".} =
  var
    fs: seq[FunctionInfo] = @[]
    currentModule: string = ""
    lines: seq[string] = @[]
    line: string = ""
  fs = sortedFunctions(g)
  for f in fs:
    if f.modulePath != currentModule:
      currentModule = f.modulePath
      lines.add(currentModule)
    line = "  |- " & tooltipLineFor(f)
    if f.handlesUserInput:
      line.add(" [user_input]")
    if f.pragmaTags.len > 0:
      line.add(" {tags=" & f.pragmaTags.join(",") & "}")
    lines.add(line)
  result = lines.join("\n")


proc toMermaidFlowchart*(g: RepoGraph): string {.role: helper, tag: "graph".} =
  var
    lines: seq[string] = @["flowchart TD"]
    nid: string = ""
    label: string = ""
  for f in g.functions:
    nid = sanitizeNodeId(f.id)
    label = f.name & "\\n" & roleToString(f.role)
    if f.handlesUserInput:
      label.add("\\nuser_input")
    lines.add("  " & nid & "[\"" & escapeText(label) & "\"]")
  for e in g.edges:
    lines.add("  " & sanitizeNodeId(e.callerId) & " --> " & sanitizeNodeId(e.calleeId))
  result = lines.join("\n")


proc toDotGraph*(g: RepoGraph): string {.role: helper, tag: "graph".} =
  var
    lines: seq[string] = @[
      "digraph OtterRepoGraph {",
      "  rankdir=LR;",
      "  node [shape=box, style=rounded];"
    ]
    label: string = ""
  for f in g.functions:
    label = f.name & "\\n" & roleToString(f.role) & "\\n" & f.modulePath
    if f.handlesUserInput:
      label.add("\\nuser_input")
    label = escapeText(label)
    lines.add("  \"" & escapeText(f.id) & "\" [label=\"" & label & "\"];")
  for e in g.edges:
    lines.add("  \"" & escapeText(e.callerId) & "\" -> \"" & escapeText(e.calleeId) & "\";")
  lines.add("}")
  result = lines.join("\n")


proc normalizeTags(tags: openArray[string]): seq[string] {.role: helper, tag: "graph".} =
  var
    seen: HashSet[string]
    t: string = ""
  seen = initHashSet[string]()
  result = @[]
  for raw in tags:
    t = raw.strip().toLowerAscii()
    if t.len == 0:
      continue
    if t notin seen:
      seen.incl(t)
      result.add(t)
  result.sort(system.cmp[string])


proc toCallTree*(g: RepoGraph, nDepthLimit: int = 8): string {.role: helper, tag: "graph".} =
  var
    outMap: Table[string, seq[string]]
    inDeg: Table[string, int]
    byId: Table[string, FunctionInfo]
    lines: seq[string] = @[]
    roots: seq[string] = @[]
    childLast: bool = false
  outMap = initTable[string, seq[string]]()
  inDeg = initTable[string, int]()
  byId = functionMapById(g)
  for f in g.functions:
    outMap[f.id] = @[]
    inDeg[f.id] = 0
  for e in g.edges:
    outMap[e.callerId].add(e.calleeId)
    inDeg[e.calleeId] = inDeg.getOrDefault(e.calleeId, 0) + 1
  for k, v in inDeg:
    if v == 0:
      roots.add(k)
  if roots.len == 0 and g.functions.len > 0:
    roots.add(g.functions[0].id)
  roots.sort(system.cmp[string])

  proc walkNode(id: string, prefix: string, isLast: bool, depth: int,
      seen: HashSet[string]) =
    var
      label: string = ""
      localSeen: HashSet[string]
      children: seq[string] = @[]
      i: int = 0
      branchPrefix: string = ""
      nextPrefix: string = ""
    if id in byId:
      label = tooltipLineFor(byId[id])
      if byId[id].handlesUserInput:
        label.add(" [user_input]")
    else:
      label = id
    if depth == 0:
      lines.add(label)
    else:
      branchPrefix = if isLast: "`- " else: "|- "
      lines.add(prefix & branchPrefix & label)
    if depth >= nDepthLimit:
      lines.add(prefix & (if isLast: "   " else: "|  ") & "... depth limit ...")
      return
    localSeen = seen
    localSeen.incl(id)
    children = outMap.getOrDefault(id, @[])
    children.sort(system.cmp[string])
    while i < children.len:
      childLast = i == children.len - 1
      nextPrefix = prefix & (if depth == 0: "" else: (if isLast: "   " else: "|  "))
      if children[i] in localSeen:
        lines.add(nextPrefix & (if childLast: "`- " else: "|- ") &
          byId.getOrDefault(children[i], default(FunctionInfo)).name & " [cycle]")
      else:
        walkNode(children[i], nextPrefix, childLast, depth + 1, localSeen)
      i = i + 1

  for i, root in roots:
    walkNode(root, "", i == roots.len - 1, 0, initHashSet[string]())
  result = lines.join("\n")


proc socketToJson(s: FunctionSocket): JsonNode {.role: helper, tag: "graph".} =
  result = %*{
    "name": s.name,
    "typeName": s.typeName,
    "direction": socketDirectionToString(s.direction),
    "sampleExpr": s.sampleExpr
  }


proc riskToJson(r: RiskTag): JsonNode {.role: helper, tag: "graph".} =
  result = %*{
    "key": r.key,
    "value": r.value
  }


proc groupToJson(g: OrchestratorGroup): JsonNode {.role: helper, tag: "graph".} =
  result = %*{
    "id": g.id,
    "orchestratorId": g.orchestratorId,
    "label": g.label,
    "directMemberIds": g.directMemberIds,
    "memberIds": g.memberIds
  }


proc toGraphJson*(g: RepoGraph): string {.role: helper, tag: "graph".} =
  var
    fnodes: seq[JsonNode] = @[]
    edges: seq[JsonNode] = @[]
    groups: seq[JsonNode] = @[]
    sockets: seq[JsonNode]
    risks: seq[JsonNode]
    tags: seq[JsonNode]
  for f in g.functions:
    sockets = @[]
    risks = @[]
    tags = @[]
    for s in f.sockets:
      sockets.add(socketToJson(s))
    for r in f.riskTags:
      risks.add(riskToJson(r))
    for t in normalizeTags(f.pragmaTags):
      tags.add(%t)
    fnodes.add(%*{
      "id": f.id,
      "declKind": f.declKind,
      "modulePath": f.modulePath,
      "importModulePath": f.importModulePath,
      "sourcePath": f.sourcePath,
      "name": f.name,
      "signature": f.signature,
      "params": f.params,
      "sockets": sockets,
      "returnType": f.returnType,
      "isExported": f.isExported,
      "lineStart": f.lineStart,
      "lineEnd": f.lineEnd,
      "calls": f.calls,
      "docCommentLines": f.docCommentLines,
      "leadingCommentLines": f.leadingCommentLines,
      "innerCommentLines": f.innerCommentLines,
      "tooltipText": f.tooltipText,
      "declaredRole": roleToString(f.declaredRole),
      "role": roleToString(f.role),
      "roleConfidence": f.roleConfidence,
      "roleReason": f.roleReason,
      "pragmaTags": tags,
      "riskTags": risks,
      "issueRefs": f.issueRefs,
      "userInputDeclared": f.userInputDeclared,
      "handlesUserInput": f.handlesUserInput,
      "userInputSignals": f.userInputSignals,
      "userInputReason": f.userInputReason
    })
  for e in g.edges:
    edges.add(%*{
      "callerId": e.callerId,
      "calleeId": e.calleeId,
      "callName": e.callName
    })
  for group in g.groups:
    groups.add(groupToJson(group))
  result = pretty(%*{
    "rootDir": g.rootDir,
    "functions": fnodes,
    "edges": edges,
    "groups": groups,
    "unresolvedCalls": g.unresolvedCalls
  })
