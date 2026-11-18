## ================================================================
## | similar_cluster.nim  <-  pairs become groups                   |
## |---------------------------------------------------------------|
## | A pair says "these two are alike". A cluster says "these NINE  |
## | are alike", which is the thing worth knowing: nine copies of   |
## | one idea are one routine with eight knobs, not nine routines.  |
## |                                                                |
## | How the groups are made (centre-star, not chains):             |
## |                                                                |
## |   1. the chunk with the MOST close partners becomes a centre   |
## |   2. its still-free partners join it                           |
## |   3. repeat with the next-busiest free chunk                   |
## |                                                                |
## |        B ─ A        every member is within the limit of the    |
## |        │            CENTRE, so a group is no wider than twice  |
## |        C ─ D        the limit. A chain A~B~C~D~E... can never  |
## |                     grow into one huge group (single linkage   |
## |   {B A C}  {D E}    did exactly that: 11 348 chunks in one).   |
## |                                                                |
## | Order: more repos first (an idea written in many repos is the  |
## | best candidate for a shared module), then more members, then   |
## | the tighter one.                                               |
## ================================================================

import std/[algorithm, sets, tables]
import runePragmas
import similar_types

type
  Star = object
    ## One group before its numbers are worked out.
    centre: int
    members: seq[int]

proc neighboursOf(C: seq[Chunk], P: seq[Pair], by: string): Table[int, seq[int]] {.
    role: truthBuilder.} =
  ## C: the chunks   P: the close pairs   by: the measure.
  ## For each chunk in a pair: its partners, closest first.
  var
    near: Table[int, seq[tuple[d: float, i: int]]] = initTable[int, seq[tuple[d: float, i: int]]]()
    d: float = 0.0
  result = initTable[int, seq[int]]()
  for p in P:
    d = metricOf(p, by)
    near.mgetOrPut(p.a, @[]).add((d: d, i: p.b))
    near.mgetOrPut(p.b, @[]).add((d: d, i: p.a))
  for k, V in near.mpairs:
    V.sort(proc (x, y: tuple[d: float, i: int]): int = cmp(x.d, y.d))
    result[k] = @[]
    for v in V:
      result[k].add(v.i)

proc starGroups(N: Table[int, seq[int]]): seq[Star] {.role: truthBuilder.} =
  ## N: chunk -> its partners. The groups: busiest chunk first, each taking
  ## its partners that no earlier group took.
  var
    order: seq[int] = @[]
    taken: HashSet[int] = initHashSet[int]()
    g: Star = Star()
  result = @[]
  for k in N.keys:
    order.add(k)
  order.sort(proc (x, y: int): int =
    if N[x].len != N[y].len:
      return cmp(N[y].len, N[x].len)
    result = cmp(x, y))
  for c in order:
    if c in taken:
      continue
    g = Star(centre: c, members: @[c])
    for m in N[c]:
      if m notin taken:
        g.members.add(m)
    if g.members.len >= 2:
      for m in g.members:
        taken.incl(m)
      result.add(g)

proc fillStats(c: var Cluster, C: seq[Chunk], P: seq[Pair]) {.role: actor.} =
  ## c: a cluster with its members and centre   C: the chunks   P: the pairs.
  ## Fills the repos, the mean distances (over the pairs that lie inside
  ## the group) and the number of pairs of exactly the same shape.
  var
    inside: HashSet[int] = c.members.toHashSet()
    seen: HashSet[string] = initHashSet[string]()
    sumShape: float = 0.0
    sumWords: float = 0.0
    n: int = 0
  for p in P:
    if p.a in inside and p.b in inside:
      sumShape = sumShape + p.shapeDist
      sumWords = sumWords + p.wordsDist
      n = n + 1
      c.twins = c.twins + (if p.twin: 1 else: 0)
  for i in c.members:
    if C[i].repo notin seen:
      seen.incl(C[i].repo)
      c.repos.add(C[i].repo)
  if n > 0:
    c.meanShape = sumShape / float(n)
    c.meanWords = sumWords / float(n)
  c.repos.sort()

proc clustersOf*(C: seq[Chunk], P: seq[Pair], by: string): seq[Cluster] {.role: truthBuilder.} =
  ## C: the chunks   P: the close pairs   by: the measure that was used.
  ## The groups, widest first.
  var
    c: Cluster = Cluster()
  result = @[]
  for g in starGroups(neighboursOf(C, P, by)):
    c = Cluster(members: g.members, repos: @[], meanShape: 0.0, meanWords: 0.0,
      twins: 0, centre: g.centre)
    c.members.sort()
    fillStats(c, C, P)
    result.add(c)
  result.sort(proc (x, y: Cluster): int =
    if x.repos.len != y.repos.len:
      return cmp(y.repos.len, x.repos.len)
    if x.members.len != y.members.len:
      return cmp(y.members.len, x.members.len)
    result = cmp(x.meanShape, y.meanShape))
