## ================================================================
## | similar_index.nim  <-  find the close pairs without comparing  |
## |                        every chunk with every other chunk      |
## |---------------------------------------------------------------|
## | 60 000 chunks would be 1 800 000 000 pairs. Instead:           |
## |                                                                |
## |   1. every chunk has a 64-bit SimHash (similar_vector.nim)     |
## |   2. the 64 bits are cut into 11 blocks (ten of 6 bits, one    |
## |      of 4). Two chunks whose hashes differ in few bits agree   |
## |      completely in at least one block.                         |
## |   3. per block, chunks are sorted by their bits; chunks that   |
## |      share the bits stand in one run = one bucket              |
## |   4. only chunks in the same bucket are looked at together:    |
## |        cheap test   hashes differ in at most 20 bits?          |
## |        cheap test   sizes within a factor of 2.5?              |
## |        exact test   distance of the full vectors               |
## |   5. a bucket larger than maxBucket is skipped and counted:    |
## |      it is made of very common code, which says nothing.       |
## |                                                                |
## |   hash A  010110 | 110011 | 001010 | ...                       |
## |   hash B  010110 | 110111 | 001010 | ...  blocks 1 and 3 equal |
## |                    ^ one bit differs       -> same bucket     |
## ================================================================

import std/[algorithm, bitops, sets]
import runePragmas
import similar_types
import similar_vector

const
  blockCount: int = 11
  blockBits: int = 6
  maxHamming: int = 20
  minSizeRatio: float = 0.4

type
  Finder = object
    ## The pairs found so far, and which pairs were already looked at
    ## (the same pair can share more than one block).
    seen: HashSet[uint64]
    pairs: seq[Pair]

proc blockKey(h: uint64, b: int): uint32 {.inline, role: parser.} =
  ## h: a SimHash   b: block number 0..10. The bits of that block.
  var
    mask: uint64 = (1'u64 shl uint64(blockBits)) - 1
  result = uint32((h shr uint64(b * blockBits)) and mask)

proc usable(c: Chunk): bool {.inline, role: helper.} =
  ## c: a chunk. Has it vectors (was it long enough to measure)?
  result = c.shape.len == shapeDim and c.words.len == wordsDim

proc sizeClose(a, b: Chunk): bool {.inline, role: helper.} =
  ## a, b: two chunks. Is the smaller at least 40 % as long as the larger?
  result = float(min(a.lines, b.lines)) >= minSizeRatio * float(max(a.lines, b.lines))

proc passesCheap(C: seq[Chunk], a, b: int, o: SimilarOptions): bool {.role: sanitizer.} =
  ## C: all chunks   a, b: two of them   o: the options.
  ## The tests that cost almost nothing.
  result = true
  if o.across and C[a].repo == C[b].repo:
    result = false
  elif C[a].wordsOnly != C[b].wordsOnly:
    result = false
  elif not sizeClose(C[a], C[b]):
    result = false
  elif popcount(C[a].simhash xor C[b].simhash) > maxHamming:
    result = false

proc consider(F: var Finder, C: seq[Chunk], i, j: int, o: SimilarOptions) {.role: actor.} =
  ## F: the finder   C: all chunks   i, j: two chunks in one bucket
  ## o: the options. Measures the pair and keeps it when it is close.
  var
    a: int = min(i, j)
    b: int = max(i, j)
    k: uint64 = (uint64(a) shl 32) or uint64(b)
    p: Pair = Pair()
  if not passesCheap(C, a, b, o):
    return
  if k in F.seen:
    return
  F.seen.incl(k)
  p = Pair(a: a, b: b, shapeDist: cosineDist(C[a].shape, C[b].shape),
    wordsDist: cosineDist(C[a].words, C[b].words), twin: C[a].twin == C[b].twin,
    byWords: C[a].wordsOnly)
  if metricOf(p, o.by) <= o.maxDist:
    F.pairs.add(p)

proc scanRun(F: var Finder, C: seq[Chunk], K: seq[tuple[key: uint32, idx: int]],
    lo, hi: int, o: SimilarOptions) {.role: actor.} =
  ## F: the finder   C: all chunks   K: keys and chunk numbers, sorted
  ## lo, hi: the run K[lo ..< hi] that shares one key   o: the options.
  for p in lo ..< hi:
    for q in p + 1 ..< hi:
      consider(F, C, K[p].idx, K[q].idx, o)

proc scanBlock(F: var Finder, C: seq[Chunk], U: seq[int], b: int,
    o: SimilarOptions): int {.role: actor.} =
  ## F: the finder   C: all chunks   U: numbers of the usable chunks
  ## b: block number   o: the options. Returns how many buckets were skipped.
  var
    K: seq[tuple[key: uint32, idx: int]] = @[]
    lo: int = 0
    hi: int = 0
  result = 0
  for i in U:
    K.add((key: blockKey(C[i].simhash, b), idx: i))
  K.sort(proc (x, y: tuple[key: uint32, idx: int]): int = cmp(x.key, y.key))
  while lo < K.len:
    hi = lo
    while hi < K.len and K[hi].key == K[lo].key:
      hi = hi + 1
    if hi - lo > o.maxBucket:
      result = result + 1
    else:
      scanRun(F, C, K, lo, hi, o)
    lo = hi

proc findPairs*(C: seq[Chunk], o: SimilarOptions): tuple[pairs: seq[Pair], skipped: int] {.
    role: orchestrator.} =
  ## C: all chunks of all repos   o: the options.
  ## Every pair whose distance (by the chosen measure) is at most o.maxDist,
  ## most alike first, and how many too-common buckets were left out.
  var
    F: Finder = Finder(seen: initHashSet[uint64](), pairs: @[])
    U: seq[int] = @[]
  result = (pairs: @[], skipped: 0)
  for i in 0 ..< C.len:
    if usable(C[i]):
      U.add(i)
  for b in 0 ..< blockCount:
    result.skipped = result.skipped + scanBlock(F, C, U, b, o)
  F.pairs.sort(proc (x, y: Pair): int =
    cmp(metricOf(x, o.by), metricOf(y, o.by)))
  result.pairs = F.pairs
