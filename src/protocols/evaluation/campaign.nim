# ============================================================
# | Statistical Campaign                                    |
# | -> Pass-proportion bounds across repeated test windows  |
# ============================================================

import std/math
import ./types

proc evaluateFailureProportion*(name: string, failures, total: int,
    alpha: float64 = 0.01, z: float64 = 3.0): ProportionResult =
  ## name: test label. failures/total: repeated-window outcomes.
  ## alpha/z: expected failure probability and normal-bound multiplier.
  var
    sigma: float64 = 0.0
  result.name = name
  result.failures = failures
  result.total = total
  result.expected = alpha
  if total <= 0 or alpha <= 0.0 or alpha >= 1.0 or z <= 0.0:
    return
  result.observed = float64(failures) / float64(total)
  sigma = z * sqrt(alpha * (1.0 - alpha) / float64(total))
  result.lower = max(0.0, alpha - sigma)
  result.upper = min(1.0, alpha + sigma)
  result.passed = failures >= 0 and failures <= total and
    result.observed >= result.lower and result.observed <= result.upper
