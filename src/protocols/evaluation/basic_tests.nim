## ============================================================
## | NIST Eval Basic Tests                                   |
## | -> Frequency, runs, longest-run, cumulative sums        |
## ============================================================

import runePragmas
import var_invariants

import std/math

import ./bits
import ./constants
import ./math_utils
import ./types


proc monobitTest*(Bs: openArray[uint8], a: float64 = defaultAlpha): NistResult {.role: math.} =
  ## Bs: input bit sequence (0/1).
  ## a: alpha threshold.
  var
    n: int = Bs.len
    i: int = 0
    sum: int = 0
    sObs: float64 = 0.0
    p: float64 = 0.0
  if n == 0:
    result = makeResult("monobit", 0.0, 0.0, a)
  else:
    while i < n:
      if Bs[i] == 1'u8:
        sum = sum + 1
      else:
        sum = sum - 1
      i = i + 1
    sObs = abs(float64(sum)) / sqrt(float64(n))
    p = erfc(sObs / sqrt(2.0))
    result = makeResult("monobit", sObs, p, a)


proc blockFrequencyTest*(Bs: openArray[uint8], m: int,
    a: float64 = defaultAlpha): NistResult {.role: math.} =
  ## Bs: input bit sequence (0/1).
  ## m: block size in bits.
  ## a: alpha threshold.
  var
    n: int = Bs.len
    nBlocks: int = 0
    i: int = 0
    j: int = 0
    ones: int = 0
    pi: float64 = 0.0
    sum: float64 = 0.0
    chi: float64 = 0.0
    p: float64 = 0.0
  if m <= 0:
    result = makeResult("block_frequency", 0.0, 0.0, a)
  else:
    nBlocks = n div m
    if nBlocks == 0:
      result = makeResult("block_frequency", 0.0, 0.0, a)
    else:
      while i < nBlocks:
        ones = 0
        j = 0
        while j < m:
          if Bs[i * m + j] == 1'u8:
            ones = ones + 1
          j = j + 1
        pi = float64(ones) / float64(m)
        sum = sum + (pi - 0.5) * (pi - 0.5)
        i = i + 1
      chi = 4.0 * float64(m) * sum
      p = regularizedGammaQ(float64(nBlocks) / 2.0, chi / 2.0)
      result = makeResult("block_frequency", chi, p, a)


proc runsTest*(Bs: openArray[uint8], a: float64 = defaultAlpha): NistResult {.role: math.} =
  ## Bs: input bit sequence (0/1).
  ## a: alpha threshold.
  var
    n: int = Bs.len
    ones: uint32 = 0'u32
    pi: float64 = 0.0
    v: uint32 = 0'u32
    num: float64 = 0.0
    den: float64 = 0.0
    p: float64 = 0.0
  if n == 0:
    result = makeResult("runs", 0.0, 0.0, a)
  else:
    ones = countOnesBits(Bs)
    pi = float64(ones) / float64(n)
    if abs(pi - 0.5) >= 2.0 / sqrt(float64(n)):
      result = makeResult("runs", 0.0, 0.0, a)
    else:
      v = countRunsBits(Bs)
      num = abs(float64(v) - 2.0 * float64(n) * pi * (1.0 - pi))
      den = 2.0 * sqrt(2.0 * float64(n)) * pi * (1.0 - pi)
      p = erfc(num / den)
      result = makeResult("runs", float64(v), p, a)


proc longestRunModel(m: int): tuple[first: int, P: seq[float64]]
    {.role: truthBuilder.} =
  ## m: supported block length. First/last categories include their tails.
  case m
  of 8: result = (1, @[0.2148, 0.3672, 0.2305, 0.1875])
  of 128: result = (4, @[0.1174, 0.2430, 0.2493, 0.1752, 0.1027, 0.1124])
  of 10000: result = (10, @[0.0882, 0.2092, 0.2483, 0.1933, 0.1208, 0.0675, 0.0727])
  else: result = (0, @[])

proc longestInBlock(B: openArray[uint8], o, m: int): int {.role: math,
    needsRun: o >= 0 and m > 0 and o <= B.len and m <= B.len - o.} =
  ## B: bits; o: first index; m: block length. The checked range stays in B.
  var
    i: int = o
    run: int = 0
  result = 0
  while i < o + m:
    if B[i] == 1'u8:
      inc run
    else:
      run = 0
    result = max(result, run)
    inc i

proc longestRunCounts(B: openArray[uint8], m, first, bins: int): seq[int]
    {.role: math.} =
  ## B: bits; m: block length; first: first category; bins: category count.
  ## The incomplete final block is left out, as in the other block tests.
  var
    i: int = 0
    bucket: int = 0
  result = newSeq[int](bins)
  while i < B.len div m:
    bucket = clamp(longestInBlock(B, i * m, m) - first, 0, bins - 1)
    inc result[bucket]
    inc i

proc longestRunChi(C: seq[int], P: seq[float64], n: int): float64
    {.role: math.} =
  ## C: observed counts; P: category probabilities; n: complete blocks.
  var
    i: int = 0
    expected: float64 = 0.0
    delta: float64 = 0.0
  result = 0.0
  while i < C.len:
    expected = n.float64 * P[i]
    delta = C[i].float64 - expected
    result += delta * delta / expected
    inc i

proc longestRunOfOnesTest*(Bs: openArray[uint8], m: int,
    a: float64 = defaultAlpha): NistResult {.role: math.} =
  ## Bs: bits (0/1); m: 8, 128, or 10000; a: pass threshold.
  ## Unsupported lengths and streams shorter than one block fail with p=0.
  var
    model: tuple[first: int, P: seq[float64]] = longestRunModel(m)
    C: seq[int] = @[]
    n: int = 0
    chi: float64 = 0.0
    p: float64 = 0.0
    name: string = "longest_run_m" & $m
  result = makeResult(name, 0.0, 0.0, a)
  if model.P.len == 0:
    return
  n = Bs.len div m
  if n == 0:
    return
  C = longestRunCounts(Bs, m, model.first, model.P.len)
  chi = longestRunChi(C, model.P, n)
  p = regularizedGammaQ((model.P.len - 1).float64 / 2.0, chi / 2.0)
  result = makeResult(name, chi, p, a)


proc maxCumulativeSum*(Bs: openArray[uint8], f: bool): int {.role: math.} =
  ## Bs: input bit sequence (0/1).
  ## f: true for forward, false for backward.
  var
    n: int = Bs.len
    i: int = 0
    idx: int = 0
    s: int = 0
    m: int = 0
    t: int = 0
  while i < n:
    if f:
      idx = i
    else:
      idx = n - 1 - i
    if Bs[idx] == 1'u8:
      s = s + 1
    else:
      s = s - 1
    t = abs(s)
    if t > m:
      m = t
    i = i + 1
  result = m


proc cumulativeSumsPValue*(z: float64, n: float64): float64 {.role: math.} =
  ## z: max excursion.
  ## n: total number of bits.
  var
    kStart: int = 0
    kEnd: int = 0
    k: int = 0
    sum1: float64 = 0.0
    sum2: float64 = 0.0
    x1: float64 = 0.0
    x2: float64 = 0.0
    y1: float64 = 0.0
    y2: float64 = 0.0
  if z == 0.0:
    result = 1.0
  else:
    kStart = int(floor((-n / z + 1.0) / 4.0))
    kEnd = int(floor((n / z - 1.0) / 4.0))
    k = kStart
    while k <= kEnd:
      x1 = (4.0 * float64(k) + 1.0) * z / sqrt(n)
      x2 = (4.0 * float64(k) - 1.0) * z / sqrt(n)
      sum1 = sum1 + (normalCdf(x1) - normalCdf(x2))
      k = k + 1
    kStart = int(floor((-n / z - 3.0) / 4.0))
    kEnd = int(floor((n / z - 1.0) / 4.0))
    k = kStart
    while k <= kEnd:
      y1 = (4.0 * float64(k) + 3.0) * z / sqrt(n)
      y2 = (4.0 * float64(k) + 1.0) * z / sqrt(n)
      sum2 = sum2 + (normalCdf(y1) - normalCdf(y2))
      k = k + 1
    result = 1.0 - sum1 + sum2


proc cumulativeSumsTest*(Bs: openArray[uint8], f: bool,
    a: float64 = defaultAlpha): NistResult {.role: math.} =
  ## Bs: input bit sequence (0/1).
  ## f: true for forward, false for backward.
  ## a: alpha threshold.
  var
    n: int = Bs.len
    z: int = 0
    p: float64 = 0.0
    name: string = ""
  if n == 0:
    result = makeResult("cumulative_sums", 0.0, 0.0, a)
  else:
    z = maxCumulativeSum(Bs, f)
    p = cumulativeSumsPValue(float64(z), float64(n))
    if f:
      name = "cumulative_sums_fwd"
    else:
      name = "cumulative_sums_rev"
    result = makeResult(name, float64(z), p, a)
