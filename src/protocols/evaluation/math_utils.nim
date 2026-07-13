# ============================================================
# | NIST Eval Math Utilities                                |
# | -> Gamma helpers and normal distribution utilities      |
# ============================================================

import std/math

const
  gammaItMax = 200
  gammaEps = 3.0e-7
  gammaFpMin = 1.0e-30


proc normalCdf*(x: float64): float64 =
  ## x: input value to evaluate the standard normal CDF at.
  result = 0.5 * erfc(-x / sqrt(2.0))


proc gammaSeries(a, x: float64): float64 =
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


proc gammaContinuedFraction(a, x: float64): float64 =
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


proc regularizedGammaQ*(a, x: float64): float64 =
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
