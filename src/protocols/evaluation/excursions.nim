## Excursions <- walk bits as +1/-1 steps and count visits between returns to zero.
## A final unfinished cycle is counted too. State zero has no visit category.
## Counting is shared; the two reports score its cycle bins and visit totals.

import std/math
import runePragmas
import var_invariants
import ./constants
import ./math_utils
import ./types

const
  excursionStates = [-4, -3, -2, -1, 1, 2, 3, 4]
  variantStates = [-9, -8, -7, -6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6, 7, 8, 9]

proc recordVisit[N: static[int]](S: var array[N, int], s: int)
    {.inline, role: actor, needsRun: N mod 2 == 1.} =
  ## S: visits indexed around zero at N div 2; s: current walk position.
  const
    radius = N div 2
  if s == 0 or s < -radius or s > radius:
    return
  inc S[s + radius]

proc finishCycle(S: var array[9, array[6, int]], C: var array[9, int])
    {.role: actor.} =
  ## S: cycle histogram; C: this cycle's visits. Last bin means five or more.
  var
    i: int = 0
  while i < C.len:
    if i == 4:
      inc i
      continue
    inc S[i][min(C[i], 5)]
    C[i] = 0
    inc i

proc computeExcursionsCounts*(Bs: openArray[uint8], j: var int,
    Cs: var array[9, array[6, int]], Vs: var array[19, int]) {.role: math.} =
  ## Bs: bits; j: output cycles; Cs: per-cycle visit bins for states -4..4;
  ## Vs: total visits for -9..9. Both middle entries represent zero and stay empty.
  ## All outputs are reset, so repeated calls do not carry the last walk forward.
  var
    C: array[9, int] = default(array[9, int])
    i: int = 0
    s: int = 0
  j = 0
  Cs = default(array[9, array[6, int]])
  Vs = default(array[19, int])
  while i < Bs.len:
    s += (if Bs[i] == 1'u8: 1 else: -1)
    recordVisit(Vs, s)
    recordVisit(C, s)
    if s == 0:
      inc j
      finishCycle(Cs, C)
    inc i
  if s != 0:
    inc j
    finishCycle(Cs, C)

proc excursionResult(C: array[6, int], n, s: int, a: float64): NistResult
    {.role: math, needsRun: n > 0 and s != 0 and s >= -4 and s <= 4.} =
  ## C: one state's visit bins; n: cycles; s: nonzero state; a: pass threshold.
  var
    chi: float64 = chiSquare(C, excursionsPis[abs(s) - 1], n)
  result = makeResult("random_excursions_x" & $s, chi,
    regularizedGammaQ(2.5, chi / 2.0), a)

proc randomExcursionsTests*(Bs: openArray[uint8],
    a: float64 = defaultAlpha): seq[NistResult] {.role: math.} =
  ## Bs: bits; a: pass threshold. Return states -4..-1 and 1..4, in that order.
  var
    C: array[9, array[6, int]] = default(array[9, array[6, int]])
    V: array[19, int] = default(array[19, int])
    n: int = 0
  result = @[]
  computeExcursionsCounts(Bs, n, C, V)
  if n == 0:
    return
  for s in excursionStates:
    result.add(excursionResult(C[s + 4], n, s, a))

proc variantResult(v, n, s: int, a: float64): NistResult {.role: math,
    needsRun: n > 0 and s != 0 and s >= -9 and s <= 9.} =
  ## v: total visits; n: cycles; s: nonzero state; a: pass threshold.
  var
    delta: float64 = abs(v.float64 - n.float64)
    denominator: float64 = sqrt(2.0 * n.float64 * (4.0 * abs(s).float64 - 2.0))
  result = makeResult("random_excursions_variant_x" & $s, delta,
    erfc(delta / denominator), a)

proc randomExcursionsVariantTests*(Bs: openArray[uint8],
    a: float64 = defaultAlpha): seq[NistResult] {.role: math.} =
  ## Bs: bits; a: pass threshold. Return states -9..-1 and 1..9, in that order.
  var
    C: array[9, array[6, int]] = default(array[9, array[6, int]])
    V: array[19, int] = default(array[19, int])
    n: int = 0
  result = @[]
  computeExcursionsCounts(Bs, n, C, V)
  if n == 0:
    return
  for s in variantStates:
    result.add(variantResult(V[s + 9], n, s, a))
