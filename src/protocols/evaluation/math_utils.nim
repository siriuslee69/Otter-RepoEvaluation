## ============================================================
## | NIST Eval Math Utilities                                |
## | -> Gamma helpers and normal distribution utilities      |
## ============================================================

import runePragmas
import var_invariants

import std/math

const
  gammaItMax = 200
  gammaEps = 3.0e-7
  gammaFpMin = 1.0e-30

proc positiveProbabilities*(P: openArray[float64]): bool {.role: math.} =
  ## P: category probabilities. Each must be finite and in (0, 1].
  ## Callers choose the distribution; this does not check that its sum is one.
  result = P.len > 0
  for p in P:
    if not (p > 0.0 and p <= 1.0):
      return false

proc chiSquare*(C: openArray[int], P: openArray[float64], n: int): float64
    {.role: math,
    needsRun: C.len == P.len and n > 0 and positiveProbabilities(P).} =
  ## C: observed category counts; P: their probabilities; n: observations.
  ## Each term compares an observed count with n * probability.
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


proc normalCdf*(x: float64): float64 {.role: math.} =
  ## x: input value to evaluate the standard normal CDF at.
  result = 0.5 * erfc(-x / sqrt(2.0))


proc gammaSeries(a, x: float64): float64 {.role: math.} =
  var
    ap: float64 = a
    sum: float64 = 1.0 / a
    del: float64 = sum
    n: int = 1
  while n <= gammaItMax:
    ap = ap + 1.0
    del = del * x / ap
    sum = sum + del
    if abs(del) < abs(sum) * gammaEps:
      break
    n = n + 1
  result = sum * exp(-x + a * ln(x) - lgamma(a))


proc gammaContinuedFraction(a, x: float64): float64 {.role: math.} =
  var
    b: float64 = x + 1.0 - a
    c: float64 = 1.0 / gammaFpMin
    d: float64 = 1.0 / b
    h: float64 = d
    i: int = 1
    an: float64 = 0.0
    delta: float64 = 0.0
  while i <= gammaItMax:
    an = -float64(i) * (float64(i) - a)
    b = b + 2.0
    d = an * d + b
    if abs(d) < gammaFpMin:
      d = gammaFpMin
    c = b + an / c
    if abs(c) < gammaFpMin:
      c = gammaFpMin
    d = 1.0 / d
    delta = d * c
    h = h * delta
    if abs(delta - 1.0) < gammaEps:
      break
    i = i + 1
  result = exp(-x + a * ln(x) - lgamma(a)) * h


proc regularizedGammaQ*(a, x: float64): float64 {.role: math.} =
  ## a: shape parameter.
  ## x: input value to evaluate the upper regularized gamma at.
  var
    t: float64 = 0.0
  if x <= 0.0:
    result = 1.0
  elif x < a + 1.0:
    t = gammaSeries(a, x)
    result = 1.0 - t
  else:
    result = gammaContinuedFraction(a, x)
