# ============================================================
# | NIST Eval Excursions                                    |
# | -> Random excursions and variant tests                  |
# ============================================================

import std/math

import ./constants
import ./math_utils
import ./types


proc computeExcursionsCounts*(Bs: openArray[uint8], j: var int,
    Cs: var array[9, array[6, int]], Vs: var array[19, int]): void =
  ## Bs: input bit sequence (0/1).
  ## j: output cycle count.
  ## Cs: per-state visit counts for random excursions.
  ## Vs: per-state visit totals for excursions variant.
  var
    i: int = 0
    n: int = Bs.len
    s: int = 0
    cycleCounts: array[9, int]
    state: int = 0
    k: int = 0
  j = 0
  i = 0
  while i < 9:
    k = 0
    while k < 6:
      Cs[i][k] = 0
      k = k + 1
    cycleCounts[i] = 0
    i = i + 1
  i = 0
  while i < 19:
    Vs[i] = 0
    i = i + 1
  s = 0
  i = 0
  while i < n:
    if Bs[i] == 1'u8:
      s = s + 1
    else:
      s = s - 1
    if s != 0 and s >= -9 and s <= 9:
      Vs[s + 9] = Vs[s + 9] + 1
    if s != 0 and s >= -4 and s <= 4:
      cycleCounts[s + 4] = cycleCounts[s + 4] + 1
    if s == 0:
      j = j + 1
      state = 0
      while state < 9:
        if state != 4:
          k = cycleCounts[state]
          if k >= 5:
            Cs[state][5] = Cs[state][5] + 1
          else:
            Cs[state][k] = Cs[state][k] + 1
        cycleCounts[state] = 0
        state = state + 1
    i = i + 1
  if s != 0:
    j = j + 1
    state = 0
    while state < 9:
      if state != 4:
        k = cycleCounts[state]
        if k >= 5:
          Cs[state][5] = Cs[state][5] + 1
        else:
          Cs[state][k] = Cs[state][k] + 1
      cycleCounts[state] = 0
      state = state + 1


proc randomExcursionsTests*(Bs: openArray[uint8],
    a: float64 = defaultAlpha): seq[NistResult] =
  ## Bs: input bit sequence (0/1).
  ## a: alpha threshold.
  var
    rs: seq[NistResult] = @[]
    Cs: array[9, array[6, int]]
    Vs: array[19, int]
    j: int = 0
    state: int = 0
    idx: int = 0
    k: int = 0
    chi: float64 = 0.0
    p: float64 = 0.0
    nCycles: float64 = 0.0
  if Bs.len == 0:
    result = rs
  else:
    computeExcursionsCounts(Bs, j, Cs, Vs)
    if j == 0:
      result = rs
    else:
      nCycles = float64(j)
      state = -4
      while state <= 4:
        if state != 0:
          idx = abs(state) - 1
          chi = 0.0
          k = 0
          while k < 6:
            chi = chi + ((float64(Cs[state + 4][k]) - nCycles * excursionsPis[idx][k]) *
              (float64(Cs[state + 4][k]) - nCycles * excursionsPis[idx][k])) /
              (nCycles * excursionsPis[idx][k])
            k = k + 1
          p = regularizedGammaQ(2.5, chi / 2.0)
          rs.add(makeResult("random_excursions_x" & $state, chi, p, a))
        state = state + 1
      result = rs


proc randomExcursionsVariantTests*(Bs: openArray[uint8],
    a: float64 = defaultAlpha): seq[NistResult] =
  ## Bs: input bit sequence (0/1).
  ## a: alpha threshold.
  var
    rs: seq[NistResult] = @[]
    Cs: array[9, array[6, int]]
    Vs: array[19, int]
    j: int = 0
    state: int = 0
    idx: int = 0
    p: float64 = 0.0
    denom: float64 = 0.0
    diff: float64 = 0.0
    nCycles: float64 = 0.0
  if Bs.len == 0:
    result = rs
  else:
    computeExcursionsCounts(Bs, j, Cs, Vs)
    if j == 0:
      result = rs
    else:
      nCycles = float64(j)
      state = -9
      while state <= 9:
        if state != 0:
          idx = state + 9
          diff = abs(float64(Vs[idx]) - nCycles)
          denom = sqrt(2.0 * nCycles * (4.0 * float64(abs(state)) - 2.0))
          if denom <= 0.0:
            p = 0.0
          else:
            p = erfc(diff / denom)
          rs.add(makeResult("random_excursions_variant_x" & $state, diff, p, a))
        state = state + 1
      result = rs
