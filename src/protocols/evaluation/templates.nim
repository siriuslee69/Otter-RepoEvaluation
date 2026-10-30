## Template tests <- count bit patterns per block, then score the counts.
## Non-overlapping matches skip the matched bits; overlapping matches share them.
## A final incomplete block is ignored. The existing probability model is retained.

import std/math
import runePragmas
import var_invariants
import ./constants
import ./math_utils
import ./types

type
  TemplatePlan {.role: preparedData.} = object
    ## One non-overlapping test's block dimensions and expected counts.
    width, blockSize, blocks: int
    mean, variance, alpha: float64

const
  maxTemplateBits = sizeof(int) * 8 - 2
    ## The positive integer range must hold 2^width as well as the patterns.

proc buildTemplateList*(m, c: int): seq[int] {.role: truthBuilder.} =
  ## m: width in 1..(sizeof(int)*8-2); c: maximum patterns, <=0 uses the default.
  ## Enumerate the same positive integer patterns as before. Invalid widths yield [].
  var
    limit: int = c
    last: int = 0
    v: int = 1
  result = @[]
  if m <= 0 or m > maxTemplateBits:
    return
  last = (1 shl m) - 1
  if limit <= 0:
    limit = (if m == 9: 148 else: 16)
  limit = min(limit, last)
  while v <= limit:
    result.add(v)
    inc v

proc bitWindow(B: openArray[uint8], m, o: int): int {.inline, role: math,
    needsRun: m > 0 and m <= maxTemplateBits and o >= 0 and
      o <= B.len and m <= B.len - o.} =
  ## B: bits; m: window width; o: first bit. Most significant bit is read first.
  var
    i: int = 0
  result = 0
  while i < m:
    result = (result shl 1) or int(B[o + i])
    inc i

proc nonOverlappingCount(B: openArray[uint8], v, m, o, b: int): int
    {.role: math, needsRun: m > 0 and m <= maxTemplateBits and b >= m and
      o >= 0 and o <= B.len and b <= B.len - o.} =
  ## B: bits; v: pattern; m: pattern width; o/b: block start and length.
  var
    pos: int = 0
    window: int = bitWindow(B, m, o)
    mask: int = (1 shl m) - 1
    matched: bool = false
  result = 0
  while pos <= b - m:
    matched = window == v
    if matched:
      inc result
    pos += (if matched: m else: 1)
    if pos > b - m:
      break
    if matched:
      window = bitWindow(B, m, o + pos)
    else:
      window = ((window shl 1) and mask) or int(B[o + pos + m - 1])

proc templatePlan(m, b, n: int, a: float64): TemplatePlan {.role: truthBuilder.} =
  ## m/b: pattern and block widths; n: complete blocks; a: pass threshold.
  var
    p: float64 = pow(2.0, -m.float64)
  result = TemplatePlan(width: m, blockSize: b, blocks: n, alpha: a,
    mean: (b - m + 1).float64 * p,
    variance: b.float64 * (p - (2 * m - 1).float64 * p * p))

proc templateResult(B: openArray[uint8], p: TemplatePlan, v, i: int): NistResult
    {.role: math.} =
  ## B: bits; p: dimensions and expected counts; v: pattern; i: result index.
  var
    j: int = 0
    w: int = 0
    delta: float64 = 0.0
    chi: float64 = 0.0
  while j < p.blocks:
    w = nonOverlappingCount(B, v, p.width, j * p.blockSize, p.blockSize)
    delta = w.float64 - p.mean
    chi += delta * delta / p.variance
    inc j
  result = makeResult("non_overlapping_m" & $p.width & "_t" & $i, chi,
    regularizedGammaQ(p.blocks.float64 / 2.0, chi / 2.0), p.alpha)

proc nonOverlappingTemplateTests*(Bs: openArray[uint8], m, b, c: int,
    a: float64 = defaultAlpha): seq[NistResult] {.role: math.} =
  ## Bs: bits; m: representable pattern width; b: block length; c: pattern limit.
  ## a: pass threshold. Invalid dimensions or no complete blocks yield [].
  var
    T: seq[int] = @[]
    p: TemplatePlan = TemplatePlan()
  result = @[]
  if m <= 0 or m > maxTemplateBits or b < m or b > Bs.len:
    return
  T = buildTemplateList(m, c)
  p = templatePlan(m, b, Bs.len div b, a)
  if p.variance <= 0.0:
    return
  for i, v in T:
    result.add(templateResult(Bs, p, v, i))

proc overlappingCount(B: openArray[uint8], m, o, b: int): int {.role: math,
    needsRun: m > 0 and b >= m and o >= 0 and o <= B.len and b <= B.len - o.} =
  ## B: bits; m: all-ones pattern width; o/b: block start and length.
  var
    pos: int = o
    run: int = 0
  result = 0
  while pos < o + b:
    run = (if B[pos] == 1'u8: run + 1 else: 0)
    if run >= m:
      inc result
    inc pos

proc overlappingCounts(B: openArray[uint8], m, b: int): array[6, int]
    {.role: math.} =
  ## B: bits; m/b: pattern and block lengths. Categories are 0,1,2,3,4,5+.
  var
    i: int = 0
    w: int = 0
  result = default(array[6, int])
  while i < B.len div b:
    w = overlappingCount(B, m, i * b, b)
    inc result[min(w, 5)]
    inc i

proc overlapProbabilities(x: float64): array[6, float64] {.role: math.} =
  ## x: half the expected match count. Retain the existing Poisson categories.
  var
    i: int = 1
    sum: float64 = 0.0
  result = default(array[6, float64])
  result[0] = exp(-x)
  sum = result[0]
  while i < 5:
    result[i] = result[i - 1] * x / i.float64
    sum += result[i]
    inc i
  result[5] = 1.0 - sum

proc overlappingTemplateTest*(Bs: openArray[uint8], m, b: int,
    a: float64 = defaultAlpha): NistResult {.role: math.} =
  ## Bs: bits; m/b: pattern and block lengths; a: pass threshold.
  ## Invalid dimensions or a numerically degenerate model fail with p=0.
  var
    C: array[6, int] = default(array[6, int])
    P: array[6, float64] = default(array[6, float64])
    chi: float64 = 0.0
    name: string = "overlapping_template_m" & $m
  result = makeResult(name, 0.0, 0.0, a)
  if m <= 0 or b < m or b > Bs.len:
    return
  P = overlapProbabilities((b - m + 1).float64 * pow(2.0, -m.float64) / 2.0)
  if not positiveProbabilities(P):
    return
  C = overlappingCounts(Bs, m, b)
  chi = chiSquare(C, P, Bs.len div b)
  result = makeResult(name, chi, regularizedGammaQ(2.5, chi / 2.0), a)
