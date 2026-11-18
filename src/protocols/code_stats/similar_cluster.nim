## ================================================================
## | similar_cluster.nim  <-  pairs become groups                   |
## |---------------------------------------------------------------|
## | A pair says "these two are alike". A cluster says "these NINE  |
## | are alike", which is the thing worth knowing: nine copies of   |
## | one idea are one routine with eight knobs, not nine routines.  |
## |                                                                |
## |   pairs:   A~B   B~C   D~E            clusters:  {A B C}  {D E}|
## |                                                                |
## | Pairs are joined with union-find (single linkage): if A~B and  |
## | B~C then A, B, C are one group even when A and C are farther   |
## | apart. The mean distances in the cluster show how loose that   |
## | made it: a cluster whose mean is much larger than the limit    |
## | is a chain, not a family, and wants a look by a person.        |
## |                                                                |
## | Order: more repos first (an idea written in many repos is the  |
## | best candidate for a shared module), then more members, then   |
## | the tighter one.                                               |
## ================================================================

import std/[algorithm, sets, tables]
import runePragmas
import similar_types

proc rootOf(P: var seq[int], x: int): int {.role: helper.} =
  ## P: the parent of each chunk (union-find)   x: a chunk.
  ## The chunk at the top of x's group. Shortens the path on the way.
  var
    r: int = x
    t: int = 0
    cur: int = x
  while P[r] != r:
    r = P[r]
  while P[cur] != r:
    t = P[cur]
    P[cur] = r
    cur = t
  result = r

proc joinGroups(P: var seq[int], a, b: int) {.role: actor.} =
  ## P: the parents   a, b: two chunks that are alike. Puts them in one group.
  var
    ra: int = rootOf(P, a)
    rb: int = rootOf(P, b)
  if ra != rb:
    P[rb] = ra

proc membersByRoot(C: seq[Chunk], P: seq[Pair]): Table[int, seq[int]] {.role: truthBuilder.} =
  ## C: the chunks   P: the close pairs.
  ## Group number -> the chunks in it, only for chunks that are in a pair.
  var
    parent: seq[int] = newSeq[int](C.len)
    inPair: HashSet[int] = initHashSet[int]()
    r: int = 0
  result = initTable[int, seq[int]]()
  for i in 0 ..< parent.len:
    parent[i] = i
  for p in P:
    joinGroups(parent, p.a, p.b)
    inPair.incl(p.a)
    inPair.incl(p.b)
  for i in inPair:
    r = rootOf(parent, i)
    result.mgetOrPut(r, @[]).add(i)

proc fillStats(c: var Cluster, C: seq[Chunk], P: seq[Pair], by: string) {.role: actor.} =
  ## c: a cluster with its members   C: the chunks   P: the close pairs
  ## by: the measure. Fills repos, mean distances, twins and the centre.
  var
    inside: HashSet[int] = c.members.toHashSet()
    seen: HashSet[string] = initHashSet[string]()
    sumShape: float = 0.0
    sumWords: float = 0.0
    n: int = 0
    link: Table[int, float] = initTable[int, float]()
    best: float = 1.0e30
  for p in P:
    if p.a in inside and p.b in inside:
      sumShape = sumShape + p.shapeDist
      sumWords = sumWords + p.wordsDist
      n = n + 1
      c.twins = c.twins + (if p.twin: 1 else: 0)
      link[p.a] = link.getOrDefault(p.a, 0.0) + metricOf(p, by)
      link[p.b] = link.getOrDefault(p.b, 0.0) + metricOf(p, by)
  for i in c.members:
    if C[i].repo notin seen:
      seen.incl(C[i].repo)
      c.repos.add(C[i].repo)
    if link.getOrDefault(i, 1.0e29) < best:
      best = link.getOrDefault(i, 1.0e29)
      c.centre = i
  if n > 0:
    c.meanShape = sumShape / float(n)
    c.meanWords = sumWords / float(n)
  c.repos.sort()

proc clustersOf*(C: seq[Chunk], P: seq[Pair], by: string): seq[Cluster] {.role: truthBuilder.} =
  ## C: the chunks   P: the close pairs   by: the measure that was used.
  ## The groups, widest first.
  var
    G: Table[int, seq[int]] = membersByRoot(C, P)
    c: Cluster = Cluster()
  result = @[]
  for r, M in G:
    c = Cluster(members: M, repos: @[], meanShape: 0.0, meanWords: 0.0, twins: 0, centre: M[0])
    c.members.sort()
    fillStats(c, C, P, by)
    result.add(c)
  result.sort(proc (x, y: Cluster): int =
    if x.repos.len != y.repos.len:
      return cmp(y.repos.len, x.repos.len)
    if x.members.len != y.members.len:
      return cmp(y.members.len, x.members.len)
    result = cmp(x.meanShape, y.meanShape))
