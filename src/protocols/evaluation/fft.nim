## ============================================================
## | NIST Eval Spectral Test                                 |
## | -> FFT-based spectral test implementation               |
## ============================================================

import runePragmas

import std/complex, std/math

import ./bits
import ./constants
import ./types

proc fftBlock(S: var seq[Complex64], start, half: int,
    wlen: Complex64) {.role: math, inline.} =
  ## S: samples; start: block offset; half: butterfly count; wlen: phase step.
  var
    j: int = 0
    w: Complex64 = complex64(1.0, 0.0)
    u, v: Complex64 = default(Complex64)
  while j < half:
    u = S[start + j]
    v = S[start + j + half] * w
    S[start + j] = u + v
    S[start + j + half] = u - v
    w = w * wlen
    inc j

proc fftStage(S: var seq[Complex64], width: int) {.role: math.} =
  ## S: samples; width: number of samples in each butterfly block.
  var
    half: int = width shr 1
    ang: float64 = -2.0 * PI / float64(width)
    wlen: Complex64 = complex64(cos(ang), sin(ang))
    i: int = 0
  while i < S.len:
    fftBlock(S, i, half, wlen)
    i = i + width


proc fftRadix2*(Xs: seq[Complex64]): seq[Complex64] {.role: math.} =
  ## Xs: input complex samples (length must be power of two).
  var
    rs: seq[Complex64] = @[]
    n: int = Xs.len
    bits: int = 0
    i: int = 0
    j: int = 0
    l: int = 0
    u: Complex64 = default(Complex64)
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
      fftStage(rs, l)
      l = l shl 1
    result = rs


proc spectralTest*(Bs: openArray[uint8], n: int,
    a: float64 = defaultAlpha): NistResult {.role: math.} =
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
