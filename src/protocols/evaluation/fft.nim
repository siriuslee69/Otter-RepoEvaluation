# ============================================================
# | NIST Eval Spectral Test                                 |
# | -> FFT-based spectral test implementation               |
# ============================================================

import std/complex, std/math

import ./bits
import ./constants
import ./types


proc fftRadix2*(Xs: seq[Complex64]): seq[Complex64] =
  ## Xs: input complex samples (length must be power of two).
  var
    rs: seq[Complex64] = @[]
    n: int = Xs.len
    bits: int = 0
    i: int = 0
    j: int = 0
    l: int = 0
    half: int = 0
    ang: float64 = 0.0
    wlen: Complex64
    w: Complex64
    u: Complex64
    v: Complex64
    t: int = 0
  rs = Xs
  if n <= 1:
    result = rs
  else:
    t = n
    while t > 1:
      bits = bits + 1
      t = t shr 1
    i = 0
    while i < n:
      j = bitReverse(i, bits)
      if j > i:
        u = rs[i]
        rs[i] = rs[j]
        rs[j] = u
      i = i + 1
    l = 2
    while l <= n:
      half = l shr 1
      ang = -2.0 * PI / float64(l)
      wlen = complex64(cos(ang), sin(ang))
      i = 0
      while i < n:
        w = complex64(1.0, 0.0)
        j = 0
        while j < half:
          u = rs[i + j]
          v = rs[i + j + half] * w
          rs[i + j] = u + v
          rs[i + j + half] = u - v
          w = w * wlen
          j = j + 1
        i = i + l
      l = l shl 1
    result = rs


proc spectralTest*(Bs: openArray[uint8], n: int,
    a: float64 = defaultAlpha): NistResult =
  ## Bs: input bit sequence (0/1).
  ## n: maximum number of bits to use (0 for full length).
  ## a: alpha threshold.
  var
    l: int = Bs.len
    nUse: int = 0
    maxBits: int = n
    cs: seq[Complex64] = @[]
    fs: seq[Complex64] = @[]
    i: int = 0
    t: float64 = 0.0
    mag: float64 = 0.0
    n1: int = 0
    n0: float64 = 0.0
    d: float64 = 0.0
    p: float64 = 0.0
  if l == 0:
    result = makeResult("spectral", 0.0, 0.0, a)
  else:
    if maxBits <= 0 or maxBits > l:
      maxBits = l
    nUse = largestPow2(maxBits)
    if nUse < 2:
      result = makeResult("spectral", 0.0, 0.0, a)
    else:
      cs.setLen(nUse)
      i = 0
      while i < nUse:
        if Bs[i] == 1'u8:
          t = 1.0
        else:
          t = -1.0
        cs[i] = complex64(t, 0.0)
        i = i + 1
      fs = fftRadix2(cs)
      t = sqrt(ln(1.0 / 0.05) * float64(nUse))
      n1 = 0
      i = 0
      while i < nUse div 2:
        mag = sqrt(fs[i].re * fs[i].re + fs[i].im * fs[i].im)
        if mag < t:
          n1 = n1 + 1
        i = i + 1
      n0 = 0.95 * float64(nUse) / 2.0
      d = (float64(n1) - n0) / sqrt(float64(nUse) * 0.95 * 0.05 / 4.0)
      p = erfc(abs(d) / sqrt(2.0))
      result = makeResult("spectral", d, p, a)
