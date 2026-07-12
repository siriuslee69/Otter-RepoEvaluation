# ============================================================
# | NIST Eval Basic Tests                                   |
# | -> Frequency, runs, longest-run, cumulative sums        |
# ============================================================

import std/math

import ./bits
import ./constants
import ./math_utils
import ./types


proc monobitTest*(Bs: openArray[uint8], a: float64 = defaultAlpha): NistResult =
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
    a: float64 = defaultAlpha): NistResult =
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


proc runsTest*(Bs: openArray[uint8], a: float64 = defaultAlpha): NistResult =
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


proc longestRunOfOnesTest*(Bs: openArray[uint8], m: int,
    a: float64 = defaultAlpha): NistResult =
  ## Bs: input bit sequence (0/1).
  ## m: block size for longest-run calculation.
  ## a: alpha threshold.
  var
    n: int = Bs.len
    nBlocks: int = 0
    i: int = 0
    j: int = 0
    longest: int = 0
    run: int = 0
    v0: int = 0
    v1: int = 0
    v2: int = 0
    v3: int = 0
    v4: int = 0
    v5: int = 0
    v6: int = 0
    chi: float64 = 0.0
    p: float64 = 0.0
    exp0: float64 = 0.0
    exp1: float64 = 0.0
    exp2: float64 = 0.0
    exp3: float64 = 0.0
    exp4: float64 = 0.0
    exp5: float64 = 0.0
    exp6: float64 = 0.0
  nBlocks = n div m
  if nBlocks == 0:
    result = makeResult("longest_run_m" & $m, 0.0, 0.0, a)
  elif m == 8:
    while i < nBlocks:
      longest = 0
      run = 0
      j = 0
      while j < m:
        if Bs[i * m + j] == 1'u8:
          run = run + 1
          if run > longest:
            longest = run
        else:
          run = 0
        j = j + 1
      if longest <= 1:
        v0 = v0 + 1
      elif longest == 2:
        v1 = v1 + 1
      elif longest == 3:
        v2 = v2 + 1
      else:
        v3 = v3 + 1
      i = i + 1
    exp0 = float64(nBlocks) * 0.2148
    exp1 = float64(nBlocks) * 0.3672
    exp2 = float64(nBlocks) * 0.2305
    exp3 = float64(nBlocks) * 0.1875
    chi = ((float64(v0) - exp0) * (float64(v0) - exp0)) / exp0
    chi = chi + ((float64(v1) - exp1) * (float64(v1) - exp1)) / exp1
    chi = chi + ((float64(v2) - exp2) * (float64(v2) - exp2)) / exp2
    chi = chi + ((float64(v3) - exp3) * (float64(v3) - exp3)) / exp3
    p = regularizedGammaQ(1.5, chi / 2.0)
    result = makeResult("longest_run_m8", chi, p, a)
  elif m == 128:
    while i < nBlocks:
      longest = 0
      run = 0
      j = 0
      while j < m:
        if Bs[i * m + j] == 1'u8:
          run = run + 1
          if run > longest:
            longest = run
        else:
          run = 0
        j = j + 1
      if longest <= 4:
        v0 = v0 + 1
      elif longest == 5:
        v1 = v1 + 1
      elif longest == 6:
        v2 = v2 + 1
      elif longest == 7:
        v3 = v3 + 1
      elif longest == 8:
        v4 = v4 + 1
      else:
        v5 = v5 + 1
      i = i + 1
    exp0 = float64(nBlocks) * 0.1174
    exp1 = float64(nBlocks) * 0.2430
    exp2 = float64(nBlocks) * 0.2493
    exp3 = float64(nBlocks) * 0.1752
    exp4 = float64(nBlocks) * 0.1027
    exp5 = float64(nBlocks) * 0.1124
    chi = ((float64(v0) - exp0) * (float64(v0) - exp0)) / exp0
    chi = chi + ((float64(v1) - exp1) * (float64(v1) - exp1)) / exp1
    chi = chi + ((float64(v2) - exp2) * (float64(v2) - exp2)) / exp2
    chi = chi + ((float64(v3) - exp3) * (float64(v3) - exp3)) / exp3
    chi = chi + ((float64(v4) - exp4) * (float64(v4) - exp4)) / exp4
    chi = chi + ((float64(v5) - exp5) * (float64(v5) - exp5)) / exp5
    p = regularizedGammaQ(2.5, chi / 2.0)
    result = makeResult("longest_run_m128", chi, p, a)
  elif m == 10000:
    while i < nBlocks:
      longest = 0
      run = 0
      j = 0
      while j < m:
        if Bs[i * m + j] == 1'u8:
          run = run + 1
          if run > longest:
            longest = run
        else:
          run = 0
        j = j + 1
      if longest <= 10:
        v0 = v0 + 1
      elif longest == 11:
        v1 = v1 + 1
      elif longest == 12:
        v2 = v2 + 1
      elif longest == 13:
        v3 = v3 + 1
      elif longest == 14:
        v4 = v4 + 1
      elif longest == 15:
        v5 = v5 + 1
      else:
        v6 = v6 + 1
      i = i + 1
    exp0 = float64(nBlocks) * 0.0882
    exp1 = float64(nBlocks) * 0.2092
    exp2 = float64(nBlocks) * 0.2483
    exp3 = float64(nBlocks) * 0.1933
    exp4 = float64(nBlocks) * 0.1208
    exp5 = float64(nBlocks) * 0.0675
    exp6 = float64(nBlocks) * 0.0727
    chi = ((float64(v0) - exp0) * (float64(v0) - exp0)) / exp0
    chi = chi + ((float64(v1) - exp1) * (float64(v1) - exp1)) / exp1
    chi = chi + ((float64(v2) - exp2) * (float64(v2) - exp2)) / exp2
    chi = chi + ((float64(v3) - exp3) * (float64(v3) - exp3)) / exp3
    chi = chi + ((float64(v4) - exp4) * (float64(v4) - exp4)) / exp4
    chi = chi + ((float64(v5) - exp5) * (float64(v5) - exp5)) / exp5
    chi = chi + ((float64(v6) - exp6) * (float64(v6) - exp6)) / exp6
    p = regularizedGammaQ(3.0, chi / 2.0)
    result = makeResult("longest_run_m10000", chi, p, a)
  else:
    result = makeResult("longest_run_m" & $m, 0.0, 0.0, a)


proc maxCumulativeSum*(Bs: openArray[uint8], f: bool): int =
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


proc cumulativeSumsPValue*(z: float64, n: float64): float64 =
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
    a: float64 = defaultAlpha): NistResult =
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
