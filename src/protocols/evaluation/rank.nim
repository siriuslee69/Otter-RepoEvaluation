## Binary matrix rank <- pack each bit block and use the shared GF(2) reducer.
## Rank counts independent rows. The statistical test groups blocks into full
## rank, one below full rank, and all lower ranks, then scores those categories.

import std/math
import runePragmas
import var_invariants
import ./constants
import ./gf2
import ./math_utils
import ./types

proc lnPow2MinusPow2(a, b: int): float64 {.role: math.} =
  ## a/b: exponents in log(2^a - 2^b). Factor out 2^a to avoid overflowing exp.
  if a <= b:
    return -Inf
  result = a.float64 * ln(2.0) + ln(1.0 - exp((b - a).float64 * ln(2.0)))

proc rankProbability*(r, c, k: int): float64 {.role: math.} =
  ## r/c: matrix rows and columns; k: target rank. Invalid dimensions yield zero.
  var
    i: int = 0
    logNum: float64 = 0.0
    logDen: float64 = 0.0
  result = 0.0
  if r <= 0 or c <= 0 or k < 0 or k > min(r, c):
    return
  while i < k:
    logNum += lnPow2MinusPow2(r, i) + lnPow2MinusPow2(c, i)
    logDen += lnPow2MinusPow2(k, i)
    inc i
  result = exp(logNum - (r.float64 * c.float64 * ln(2.0) + logDen))

proc packedRow(B: openArray[uint8], c, o: int): seq[uint64] {.role: truthBuilder,
    needsRun: c > 0 and o >= 0 and o <= B.len and c <= B.len - o.} =
  ## B: bits; c: columns; o: first row bit. Consecutive bits occupy low-to-high bits.
  var
    i: int = 0
  result = newSeq[uint64](gf2WordCount(c))
  while i < c:
    if B[o + i] == 1'u8:
      gf2SetBit(result, i)
    inc i

proc binaryMatrixRank*(Bs: openArray[uint8], r, c, o: int): int {.role: math.} =
  ## Bs: bits; r/c: dimensions; o: first bit. Invalid or incomplete ranges yield zero.
  ## Check by division before multiplying dimensions, so oversized inputs cannot wrap.
  var
    M: seq[seq[uint64]] = @[]
    i: int = 0
  result = 0
  if r <= 0 or c <= 0 or o < 0 or o > Bs.len:
    return
  if r > (Bs.len - o) div c:
    return
  while i < r:
    M.add(packedRow(Bs, c, o + i * c))
    inc i
  result = gf2Rank(M, c)

proc rankCategory(k, r: int): int {.inline, role: parser.} =
  ## k: observed rank; r: full rank. Index of full, full-1, or lower.
  if k == r: return 0
  if k == r - 1: return 1
  result = 2

proc rankCounts(B: openArray[uint8], r, c: int): array[3, int] {.role: math.} =
  ## B: bits; r/c: valid block dimensions. Ignore the final incomplete block.
  var
    i: int = 0
    k: int = 0
    m: int = r * c
  result = default(array[3, int])
  while i < B.len div m:
    k = binaryMatrixRank(B, r, c, i * m)
    inc result[rankCategory(k, r)]
    inc i

proc matrixRankTest*(Bs: openArray[uint8], r, c: int,
    a: float64 = defaultAlpha): NistResult {.role: math.} =
  ## Bs: bits; r/c: block dimensions; a: pass threshold.
  ## Invalid dimensions, no complete blocks, or zero-probability categories fail.
  var
    rows: int = min(r, c)
    cols: int = max(r, c)
    C: array[3, int] = default(array[3, int])
    P: array[3, float64] = default(array[3, float64])
    chi: float64 = 0.0
  result = makeResult("rank", 0.0, 0.0, a)
  if rows <= 0 or cols <= 0:
    return
  if rows > Bs.len div cols:
    return
  P[0] = rankProbability(rows, cols, rows)
  P[1] = rankProbability(rows, cols, rows - 1)
  P[2] = 1.0 - P[0] - P[1]
  if not positiveProbabilities(P):
    return
  C = rankCounts(Bs, rows, cols)
  chi = chiSquare(C, P, Bs.len div (rows * cols))
  result = makeResult("rank", chi, regularizedGammaQ(1.0, chi / 2.0), a)
