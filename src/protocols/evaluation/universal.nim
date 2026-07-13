# ============================================================
# | NIST Eval Universal Test                                |
# | -> Maurer universal statistical test                    |
# ============================================================

import std/math

import ./constants
import ./types


proc universalTest*(Bs: openArray[uint8], l, q: int,
    a: float64 = defaultAlpha): NistResult =
  ## Bs: input bit sequence (0/1).
  ## l: block size for patterns.
  ## q: initialization blocks (0 for default).
  ## a: alpha threshold.
  var
    n: int = Bs.len
    qUse: int = q
    nBlocks: int = 0
    k: int = 0
    vSize: int = 0
    vs: seq[int] = @[]
    i: int = 0
    j: int = 0
    idx: int = 0
    t: int = 0
    sum: float64 = 0.0
    phi: float64 = 0.0
    e: float64 = 0.0
    v: float64 = 0.0
    c: float64 = 0.0
    sigma: float64 = 0.0
    p: float64 = 0.0
    name: string = ""
  name = "universal_statistical_L" & $l
  if l < 6 or l > 16:
    result = makeResult(name, 0.0, 0.0, a)
  else:
    nBlocks = n div l
    if qUse <= 0:
      qUse = 10 * (1 shl l)
    if nBlocks <= qUse:
      result = makeResult(name, 0.0, 0.0, a)
    else:
      k = nBlocks - qUse
      vSize = 1 shl l
      vs.setLen(vSize)
      i = 0
      while i < vSize:
        vs[i] = 0
        i = i + 1
      i = 0
      while i < qUse:
        idx = 0
        j = 0
        while j < l:
          idx = (idx shl 1) or int(Bs[i * l + j])
          j = j + 1
        vs[idx] = i + 1
        i = i + 1
      i = qUse
      sum = 0.0
      while i < nBlocks:
        idx = 0
        j = 0
        while j < l:
          idx = (idx shl 1) or int(Bs[i * l + j])
          j = j + 1
        t = i + 1 - vs[idx]
        vs[idx] = i + 1
        if t > 0:
          sum = sum + log2(float64(t))
        i = i + 1
      phi = sum / float64(k)
      e = universalExpected[l]
      v = universalVariance[l]
      if v <= 0.0:
        result = makeResult(name, phi, 0.0, a)
      else:
        c = 0.7 - 0.8 / float64(l) + (4.0 + 32.0 / float64(l)) *
          pow(float64(k), -3.0 / float64(l)) / 15.0
        sigma = c * sqrt(v / float64(k))
        if sigma <= 0.0:
          result = makeResult(name, phi, 0.0, a)
        else:
          p = erfc(abs(phi - e) / (sqrt(2.0) * sigma))
          result = makeResult(name, phi, p, a)
