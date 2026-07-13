# ============================================================
# | NIST Eval Template Tests                                |
# | -> Non-overlapping and overlapping template matching    |
# ============================================================

import std/math

import ./constants
import ./math_utils
import ./types


proc buildTemplateList*(m, c: int): seq[int] =
  ## m: template size in bits.
  ## c: maximum number of templates to include (0 for default limit).
  var
    ts: seq[int] = @[]
    maxVal: int = 0
    v: int = 0
    limit: int = c
  if m <= 0:
    result = ts
  else:
    maxVal = 1 shl m
    if limit <= 0:
      if m == 9:
        limit = 148
      else:
        limit = 16
    if limit > maxVal - 1:
      limit = maxVal - 1
    v = 1
    while v < maxVal and ts.len < limit:
      ts.add(v)
      v = v + 1
    result = ts


proc nonOverlappingCount(Bs: openArray[uint8], t, m, o, b: int): int =
  ## Bs: input bit sequence (0/1).
  ## t: template bits as integer.
  ## m: template size in bits.
  ## o: block offset in bits.
  ## b: block size in bits.
  var
    pos: int = 0
    window: int = 0
    mask: int = 0
    j: int = 0
    count: int = 0
    idx: int = 0
  if m <= 0 or b < m:
    result = 0
  else:
    mask = (1 shl m) - 1
    pos = 0
    window = 0
    j = 0
    while j < m:
      window = (window shl 1) or int(Bs[o + j])
      j = j + 1
    while true:
      if window == t:
        count = count + 1
        pos = pos + m
        if pos > b - m:
          break
        window = 0
        j = 0
        while j < m:
          idx = o + pos + j
          window = (window shl 1) or int(Bs[idx])
          j = j + 1
      else:
        pos = pos + 1
        if pos > b - m:
          break
        idx = o + pos + m - 1
        window = ((window shl 1) and mask) or int(Bs[idx])
    result = count


proc nonOverlappingTemplateTests*(Bs: openArray[uint8], m, b, c: int,
    a: float64 = defaultAlpha): seq[NistResult] =
  ## Bs: input bit sequence (0/1).
  ## m: template size in bits.
  ## b: block size in bits.
  ## c: maximum number of templates to test (0 for default).
  ## a: alpha threshold.
  var
    rs: seq[NistResult] = @[]
    n: int = Bs.len
    nBlocks: int = 0
    templates: seq[int] = @[]
    tIndex: int = 0
    tpl: int = 0
    i: int = 0
    w: int = 0
    mu: float64 = 0.0
    variance: float64 = 0.0
    chi: float64 = 0.0
    p: float64 = 0.0
    name: string = ""
    expected: float64 = 0.0
  if m <= 0 or b <= 0 or b < m:
    result = rs
  else:
    nBlocks = n div b
    if nBlocks == 0:
      result = rs
    else:
      templates = buildTemplateList(m, c)
      if templates.len == 0:
        result = rs
      else:
        mu = float64(b - m + 1) / float64(1 shl m)
        variance = float64(b) * (1.0 / float64(1 shl m) -
          float64(2 * m - 1) / float64(1 shl (2 * m)))
        if variance <= 0.0:
          result = rs
        else:
          tIndex = 0
          while tIndex < templates.len:
            tpl = templates[tIndex]
            chi = 0.0
            i = 0
            while i < nBlocks:
              w = nonOverlappingCount(Bs, tpl, m, i * b, b)
              expected = mu
              chi = chi + ((float64(w) - expected) * (float64(w) - expected)) / variance
              i = i + 1
            p = regularizedGammaQ(float64(nBlocks) / 2.0, chi / 2.0)
            name = "non_overlapping_m" & $m & "_t" & $tIndex
            rs.add(makeResult(name, chi, p, a))
            tIndex = tIndex + 1
          result = rs


proc overlappingCount(Bs: openArray[uint8], m, o, b: int): int =
  ## Bs: input bit sequence (0/1).
  ## m: template size in bits.
  ## o: block offset in bits.
  ## b: block size in bits.
  var
    count: int = 0
    pos: int = 0
    run: int = 0
  if m <= 0 or b < m:
    result = 0
  else:
    pos = 0
    run = 0
    while pos < b:
      if Bs[o + pos] == 1'u8:
        run = run + 1
        if run >= m:
          count = count + 1
      else:
        run = 0
      pos = pos + 1
    result = count


proc overlappingTemplateTest*(Bs: openArray[uint8], m, b: int,
    a: float64 = defaultAlpha): NistResult =
  ## Bs: input bit sequence (0/1).
  ## m: template size in bits.
  ## b: block size in bits.
  ## a: alpha threshold.
  var
    n: int = Bs.len
    nBlocks: int = 0
    i: int = 0
    w: int = 0
    v0: int = 0
    v1: int = 0
    v2: int = 0
    v3: int = 0
    v4: int = 0
    v5: int = 0
    lambda: float64 = 0.0
    eta: float64 = 0.0
    pi0: float64 = 0.0
    pi1: float64 = 0.0
    pi2: float64 = 0.0
    pi3: float64 = 0.0
    pi4: float64 = 0.0
    pi5: float64 = 0.0
    chi: float64 = 0.0
    p: float64 = 0.0
    expEta: float64 = 0.0
  if m <= 0 or b <= 0 or b < m:
    result = makeResult("overlapping_template_m" & $m, 0.0, 0.0, a)
  else:
    nBlocks = n div b
    if nBlocks == 0:
      result = makeResult("overlapping_template_m" & $m, 0.0, 0.0, a)
    else:
      i = 0
      while i < nBlocks:
        w = overlappingCount(Bs, m, i * b, b)
        case w
        of 0:
          v0 = v0 + 1
        of 1:
          v1 = v1 + 1
        of 2:
          v2 = v2 + 1
        of 3:
          v3 = v3 + 1
        of 4:
          v4 = v4 + 1
        else:
          v5 = v5 + 1
        i = i + 1
      lambda = float64(b - m + 1) / float64(1 shl m)
      eta = lambda / 2.0
      expEta = exp(-eta)
      pi0 = expEta
      pi1 = expEta * eta
      pi2 = expEta * eta * eta / 2.0
      pi3 = expEta * eta * eta * eta / 6.0
      pi4 = expEta * eta * eta * eta * eta / 24.0
      pi5 = 1.0 - (pi0 + pi1 + pi2 + pi3 + pi4)
      chi = ((float64(v0) - float64(nBlocks) * pi0) *
        (float64(v0) - float64(nBlocks) * pi0)) / (float64(nBlocks) * pi0)
      chi = chi + ((float64(v1) - float64(nBlocks) * pi1) *
        (float64(v1) - float64(nBlocks) * pi1)) / (float64(nBlocks) * pi1)
      chi = chi + ((float64(v2) - float64(nBlocks) * pi2) *
        (float64(v2) - float64(nBlocks) * pi2)) / (float64(nBlocks) * pi2)
      chi = chi + ((float64(v3) - float64(nBlocks) * pi3) *
        (float64(v3) - float64(nBlocks) * pi3)) / (float64(nBlocks) * pi3)
      chi = chi + ((float64(v4) - float64(nBlocks) * pi4) *
        (float64(v4) - float64(nBlocks) * pi4)) / (float64(nBlocks) * pi4)
      chi = chi + ((float64(v5) - float64(nBlocks) * pi5) *
        (float64(v5) - float64(nBlocks) * pi5)) / (float64(nBlocks) * pi5)
      p = regularizedGammaQ(2.5, chi / 2.0)
      result = makeResult("overlapping_template_m" & $m, chi, p, a)
