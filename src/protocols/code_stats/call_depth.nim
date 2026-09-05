## ==============================================================
## | call_depth.nim  <-  how deep the stack can get              |
## |------------------------------------------------------------|
## | Otter already reports how deep the imports go. This is the  |
## | same question asked of routines instead of files: starting  |
## | from one routine, how long a chain of calls can follow?     |
## |                                                             |
## |   handleRequest        depth 4                              |
## |     └─ parseBody       depth 3                              |
## |          └─ decode     depth 2                              |
## |               └─ trim  depth 1                              |
## |                                                             |
## | A routine at depth 1 calls nothing in this tree: it does its |
## | own work and returns. A routine at depth 9 sits on top of a  |
## | tower, and everything under it has to be understood before   |
## | it can be changed.                                           |
## |                                                             |
## | The depth is counted downwards from each routine rather than |
## | upwards from an entry point, on purpose. Counting from the   |
## | top would need somebody to say which routines are the tops,  |
## | and a library has no single top. Counting downwards works    |
## | for any tree and answers the question people actually ask:   |
## | "if I call this, what am I setting off?"                     |
## |                                                             |
## | Recursion. A routine that calls itself, directly or round a  |
## | ring, has no longest chain — it would count forever. Any     |
## | routine already being counted is treated as the bottom, and  |
## | the ring is written down separately so it can be seen.       |
## |                                                             |
## | The counts are broken down by role as well, because "eleven  |
## | routines sit nine deep" and "eleven *orchestrators* sit nine |
## | deep" mean very different things. Orchestrators are supposed |
## | to be deep; that is their job. Helpers are not.              |
## ==============================================================

import std/[algorithm, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import ../../../meta/metaPragmas

const
  depthCap*: int = 64
    ## No chain is followed past this. A tree that goes deeper than
    ## sixty-four is either recursing in a way the ring test missed or
    ## is beyond what a person can hold in their head anyway.
  deepestShown*: int = 25
    ## How many of the deepest routines are named. The rest are counted.

type
  DepthBucket* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Every routine that sits exactly this deep, and what they are.
    ##
    ##   roles  one entry per role seen at this depth, so a bar can be
    ##          split by colour rather than being one flat block
    depth*: int
    count*: int
    roles*: seq[NameCountPair]

  NameCountPair* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One label and how often it turned up. Declared here rather than
    ## borrowed from `types.nim`, because that file imports this one.
    name*: string
    count*: int

  DeepRoutine* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One routine that sits a long way up a tower of calls.
    name*: string
    path*: string
    role*: string
    chain*: seq[string]
      ## One of the longest chains under it, named, so a person can
      ## follow what they would be setting off.
    line*: int
    depth*: int

  CallRing* {.role: preparedData, metaTags: {tagStats}.} = object
    ## A set of routines that call each other round in a circle.
    members*: seq[string]

  CallDepthStats* {.role: truthState, metaTags: {tagStats}.} = object
    ## How deep the calls go in one repository.
    ##
    ##   maxDepth   the longest chain anywhere in the tree
    ##   avgDepth   the average over every routine, so a tree with one
    ##              deep tower reads differently from one that is deep
    ##              all over
    buckets*: seq[DepthBucket]
    deepest*: seq[DeepRoutine]
    rings*: seq[CallRing]
    maxDepth*: int
    avgDepth*: float
    counted*: int

proc addPair*(A: var seq[NameCountPair], name: string) {.role: actor,
    metaTags: {tagStats}.} =
  ## A <- a tally being grown   name <- one more of these seen
  var
    i: int = 0
  if name.len == 0:
    return
  while i < A.len:
    if A[i].name == name:
      A[i].count = A[i].count + 1
      return
    i = i + 1
  A.add(NameCountPair(name: name, count: 1))

proc calleeMap*(A: seq[FunctionInfo], E: seq[CallEdge]):
    Table[string, seq[string]] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A <- every routine   E <- every call between them
  ## Who each routine calls, by id, ready to walk.
  var
    known: HashSet[string] = initHashSet[string]()
  result = initTable[string, seq[string]]()
  for row in A:
    known.incl(row.id)
    result[row.id] = @[]
  for row in E:
    # A call out to something this tree does not hold — into the
    # standard library, say — is not part of this tree's depth.
    if row.callerId in known and row.calleeId in known:
      result[row.callerId].add(row.calleeId)

proc depthOf*(id: string, M: Table[string, seq[string]],
    S: var Table[string, int], onStack: var HashSet[string],
    R: var seq[CallRing], best: var Table[string, string]): int
    {.role: math, metaTags: {tagStats}.} =
  ## id <- the routine being measured   M <- who calls whom
  ## S <- depths already worked out, kept so each routine is measured
  ## once   onStack <- what is being measured right now, which is how a
  ## ring is spotted   R <- rings found   best <- the deepest callee of
  ## each routine, for naming a chain later
  ##
  ## A routine that calls nothing is 1 deep. Otherwise it is one more
  ## than the deepest thing it calls.
  var
    below: int = 0
    deepest: int = 0
    pick: string = ""
  if S.hasKey(id):
    return S[id]
  if id in onStack:
    # Round in a circle. Stop here and note the ring rather than
    # following it forever.
    R.add(CallRing(members: @[id]))
    return 0
  onStack.incl(id)
  for callee in M.getOrDefault(id, @[]):
    below = depthOf(callee, M, S, onStack, R, best)
    if below > deepest:
      deepest = below
      pick = callee
    if deepest >= depthCap:
      break
  onStack.excl(id)
  result = deepest + 1
  if result > depthCap:
    result = depthCap
  S[id] = result
  if pick.len > 0:
    best[id] = pick

proc chainFrom*(id: string, best: Table[string, string],
    names: Table[string, string]): seq[string] {.role: parser,
    metaTags: {tagStats}.} =
  ## id <- where to start   best <- the deepest callee of each routine
  ## names <- what each id is called
  ## One of the longest chains under a routine, named end to end.
  var
    at: string = id
    seen: HashSet[string] = initHashSet[string]()
  result = @[]
  while at.len > 0 and not seen.containsOrIncl(at):
    result.add(names.getOrDefault(at, at))
    if not best.hasKey(at):
      break
    at = best[at]
    if result.len >= depthCap:
      break

proc byDepth(a, b: DeepRoutine): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b <- two routines, the deepest first.
  result = cmp(b.depth, a.depth)
  if result == 0:
    result = cmp(a.path, b.path)
  if result == 0:
    result = cmp(a.name, b.name)

proc byLevel(a, b: DepthBucket): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b <- two depth levels, shallowest first, so a chart reads left
  ## to right the way a person counts.
  result = cmp(a.depth, b.depth)

proc callDepthOf*(A: seq[FunctionInfo], E: seq[CallEdge], root: string):
    CallDepthStats {.role: orchestrator, metaTags: {tagStats}.} =
  ## A <- every routine in the tree   E <- every call between them
  ## root <- the repository folder, cut off the front of each path
  var
    M: Table[string, seq[string]] = initTable[string, seq[string]]()
    S: Table[string, int] = initTable[string, int]()
    best: Table[string, string] = initTable[string, string]()
    names: Table[string, string] = initTable[string, string]()
    onStack: HashSet[string] = initHashSet[string]()
    rings: seq[CallRing] = @[]
    levels: Table[int, DepthBucket] = initTable[int, DepthBucket]()
    deep: seq[DeepRoutine] = @[]
    total: int = 0
    d: int = 0
    role: string = ""
    rel: string = ""
  result = CallDepthStats(buckets: @[], deepest: @[], rings: @[],
    maxDepth: 0, avgDepth: 0.0, counted: 0)
  if A.len == 0:
    return
  M = calleeMap(A, E)
  for row in A:
    names[row.id] = row.name
  for row in A:
    d = depthOf(row.id, M, S, onStack, rings, best)
    role = roleToString(row.role)
    if not levels.hasKey(d):
      levels[d] = DepthBucket(depth: d, count: 0, roles: @[])
    levels[d].count = levels[d].count + 1
    addPair(levels[d].roles, role)
    total = total + d
    if d > result.maxDepth:
      result.maxDepth = d
    rel = row.sourcePath
    if root.len > 0 and rel.startsWith(root):
      rel = rel[root.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    deep.add(DeepRoutine(name: row.name, path: rel, role: role,
      chain: @[], line: row.lineStart, depth: d))
  result.counted = A.len
  if A.len > 0:
    result.avgDepth = total.float / A.len.float
  for _, bucket in levels.pairs:
    result.buckets.add(bucket)
  result.buckets.sort(byLevel)
  deep.sort(byDepth)
  if deep.len > deepestShown:
    deep.setLen(deepestShown)
  # The chain is only worked out for the handful actually shown; doing
  # it for every routine in the tree would be work nobody reads.
  for row in deep.mitems:
    for other in A:
      if other.name == row.name and other.lineStart == row.line:
        row.chain = chainFrom(other.id, best, names)
        break
  result.deepest = deep
  result.rings = rings
