# ============================================================
# | NIST Eval Pattern Tests                                 |
# | -> Approximate entropy and serial tests                 |
# ============================================================

import std/math

import ./constants
import ./math_utils
import ./types


proc patternCounts*(Bs: openArray[uint8], m: int): seq[uint32] =
  ## Bs: input bit sequence (0/1).
  ## m: pattern size.
  var
    n: int = Bs.len
    size: int = 0
    mask: int = 0
    counts: seq[uint32] = @[]
    i: int = 0
    j: int = 0
    window: int = 0
  if m <= 0:
    result = counts
  else:
    size = 1 shl m
    mask = size - 1
    counts.setLen(size)
    if n == 0:
      result = counts
    else:
      while j < m:
        window = (window shl 1) or int(Bs[j mod n])
        j = j + 1
      counts[window] = counts[window] + 1'u32
      i = 1
      while i < n:
        window = ((window shl 1) and mask) or int(Bs[(i + m - 1) mod n])
        counts[window] = counts[window] + 1'u32
        i = i + 1
      result = counts


proc phiForM*(Bs: openArray[uint8], m: int): float64 =
  ## Bs: input bit sequence (0/1).
  ## m: pattern size.
  var
    counts: seq[uint32] = @[]
    n: int = Bs.len
    i: int = 0
    sum: float64 = 0.0
    p: float64 = 0.0
  if n == 0 or m <= 0:
    result = 0.0
  else:
    counts = patternCounts(Bs, m)
    while i < counts.len:
      if counts[i] != 0'u32:
        p = float64(counts[i]) / float64(n)
        sum = sum + p * ln(p)
      i = i + 1
    result = sum


proc approximateEntropyTest*(Bs: openArray[uint8], m: int,
    a: float64 = defaultAlpha): NistResult =
  ## Bs: input bit sequence (0/1).
  ## m: pattern size.
  ## a: alpha threshold.
  var
    n: int = Bs.len
    phiM: float64 = 0.0
    phiM1: float64 = 0.0
    apen: float64 = 0.0
    chi: float64 = 0.0
    p: float64 = 0.0
  if n == 0 or m <= 0:
    result = makeResult("approx_entropy_m" & $m, 0.0, 0.0, a)
  else:
    phiM = phiForM(Bs, m)
    phiM1 = phiForM(Bs, m + 1)
    apen = phiM - phiM1
    chi = 2.0 * float64(n) * (ln(2.0) - apen)
    p = regularizedGammaQ(float64(1 shl (m - 1)), chi / 2.0)
    result = makeResult("approx_entropy_m" & $m, chi, p, a)


proc psi2ForM*(Bs: openArray[uint8], m: int): float64 =
  ## Bs: input bit sequence (0/1).
  ## m: pattern size.
  var
    counts: seq[uint32] = @[]
    n: int = Bs.len
    i: int = 0
    sum: float64 = 0.0
    pow2: int = 0
  if n == 0 or m <= 0:
    result = 0.0
  else:
    counts = patternCounts(Bs, m)
    while i < counts.len:
      sum = sum + float64(counts[i]) * float64(counts[i])
      i = i + 1
    pow2 = 1 shl m
    result = (float64(pow2) / float64(n)) * sum - float64(n)


proc serialTest*(Bs: openArray[uint8], m: int,
    a: float64 = defaultAlpha): tuple[r1, r2: NistResult] =
  ## Bs: input bit sequence (0/1).
  ## m: pattern size (>= 2).
  ## a: alpha threshold.
  var
    psiM: float64 = 0.0
    psiM1: float64 = 0.0
    psiM2: float64 = 0.0
    delta1: float64 = 0.0
    delta2: float64 = 0.0
    p1: float64 = 0.0
    p2: float64 = 0.0
    r1: NistResult
    r2: NistResult
  if m < 3:
    r1 = makeResult("serial_m" & $m & "_1", 0.0, 0.0, a)
    r2 = makeResult("serial_m" & $m & "_2", 0.0, 0.0, a)
  else:
    psiM = psi2ForM(Bs, m)
    psiM1 = psi2ForM(Bs, m - 1)
    psiM2 = psi2ForM(Bs, m - 2)
    delta1 = psiM - psiM1
    delta2 = psiM - 2.0 * psiM1 + psiM2
    p1 = regularizedGammaQ(float64(1 shl (m - 2)), delta1 / 2.0)
    p2 = regularizedGammaQ(float64(1 shl (m - 3)), delta2 / 2.0)
    r1 = makeResult("serial_m" & $m & "_1", delta1, p1, a)
    r2 = makeResult("serial_m" & $m & "_2", delta2, p2, a)
  result = (r1, r2)
