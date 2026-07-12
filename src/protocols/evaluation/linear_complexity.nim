# ============================================================
# | NIST Eval Linear Complexity                             |
# | -> Berlekamp-Massey based linear complexity test        |
# ============================================================

import std/math

import ./constants
import ./math_utils
import ./types


proc berlekampMassey*(Bs: openArray[uint8], m, o: int): int =
  ## Bs: input bit sequence (0/1).
  ## m: block length in bits.
  ## o: starting offset in bits.
  var
    cs: seq[uint8] = @[]
    ps: seq[uint8] = @[]
    ts: seq[uint8] = @[]
    n: int = 0
    l: int = 0
    mShift: int = -1
    d: uint8 = 0'u8
    i: int = 0
    shift: int = 0
  cs.setLen(m)
  ps.setLen(m)
  cs[0] = 1'u8
  ps[0] = 1'u8
  l = 0
  n = 0
  mShift = -1
  while n < m:
    d = Bs[o + n]
    i = 1
    while i <= l:
      d = d xor (cs[i] and Bs[o + n - i])
      i = i + 1
    if d == 1'u8:
      ts = cs
      shift = n - mShift
      i = 0
      while i + shift < m:
        cs[i + shift] = cs[i + shift] xor ps[i]
        i = i + 1
      if l <= n div 2:
        l = n + 1 - l
        mShift = n
        ps = ts
    n = n + 1
  result = l


proc linearComplexityTest*(Bs: openArray[uint8], m: int,
    a: float64 = defaultAlpha): NistResult =
  ## Bs: input bit sequence (0/1).
  ## m: block size in bits.
  ## a: alpha threshold.
  var
    n: int = Bs.len
    nBlocks: int = 0
    i: int = 0
    l: int = 0
    mu: float64 = 0.0
    t: float64 = 0.0
    v0: int = 0
    v1: int = 0
    v2: int = 0
    v3: int = 0
    v4: int = 0
    v5: int = 0
    v6: int = 0
    chi: float64 = 0.0
    p: float64 = 0.0
    nF: float64 = 0.0
    signMu: float64 = 0.0
    signT: float64 = 0.0
  if m <= 0:
    result = makeResult("linear_complexity_m" & $m, 0.0, 0.0, a)
  else:
    nBlocks = n div m
    if nBlocks == 0:
      result = makeResult("linear_complexity_m" & $m, 0.0, 0.0, a)
    else:
      if (m mod 2) == 0:
        signMu = -1.0
        signT = 1.0
      else:
        signMu = 1.0
        signT = -1.0
      mu = float64(m) / 2.0 + (9.0 + signMu) / 36.0 -
        (float64(m) / 3.0 + 2.0 / 9.0) / pow(2.0, float64(m))
      i = 0
      while i < nBlocks:
        l = berlekampMassey(Bs, m, i * m)
        t = signT * (float64(l) - mu) + 2.0 / 9.0
        if t <= -2.5:
          v0 = v0 + 1
        elif t <= -1.5:
          v1 = v1 + 1
        elif t <= -0.5:
          v2 = v2 + 1
        elif t <= 0.5:
          v3 = v3 + 1
        elif t <= 1.5:
          v4 = v4 + 1
        elif t <= 2.5:
          v5 = v5 + 1
        else:
          v6 = v6 + 1
        i = i + 1
      nF = float64(nBlocks)
      chi = ((float64(v0) - nF * linearComplexityPis[0]) *
        (float64(v0) - nF * linearComplexityPis[0])) / (nF * linearComplexityPis[0])
      chi = chi + ((float64(v1) - nF * linearComplexityPis[1]) *
        (float64(v1) - nF * linearComplexityPis[1])) / (nF * linearComplexityPis[1])
      chi = chi + ((float64(v2) - nF * linearComplexityPis[2]) *
        (float64(v2) - nF * linearComplexityPis[2])) / (nF * linearComplexityPis[2])
      chi = chi + ((float64(v3) - nF * linearComplexityPis[3]) *
        (float64(v3) - nF * linearComplexityPis[3])) / (nF * linearComplexityPis[3])
      chi = chi + ((float64(v4) - nF * linearComplexityPis[4]) *
        (float64(v4) - nF * linearComplexityPis[4])) / (nF * linearComplexityPis[4])
      chi = chi + ((float64(v5) - nF * linearComplexityPis[5]) *
        (float64(v5) - nF * linearComplexityPis[5])) / (nF * linearComplexityPis[5])
      chi = chi + ((float64(v6) - nF * linearComplexityPis[6]) *
        (float64(v6) - nF * linearComplexityPis[6])) / (nF * linearComplexityPis[6])
      p = regularizedGammaQ(3.0, chi / 2.0)
      result = makeResult("linear_complexity_m" & $m, chi, p, a)
