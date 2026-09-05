# ============================================================
# | Timing Leakage                                           |
# | -> First/second-order Welch tests for fixed/random data  |
# ============================================================

import std/math
import ./types

type
  SampleStats = object
    count: int
    mean: float64
    variance: float64

proc sampleStats(X: openArray[float64]): SampleStats =
  var
    i: int = 0
    delta, m2: float64 = 0.0
  i = 0
  while i < X.len:
    result.count = result.count + 1
    delta = X[i] - result.mean
    result.mean = result.mean + delta / float64(result.count)
    m2 = m2 + delta * (X[i] - result.mean)
    i = i + 1
  if result.count > 1:
    result.variance = m2 / float64(result.count - 1)

proc centeredSquareStats(X: openArray[float64], mean: float64): SampleStats =
  var
    i: int = 0
    value, delta, m2: float64 = 0.0
  i = 0
  while i < X.len:
    value = (X[i] - mean) * (X[i] - mean)
    result.count = result.count + 1
    delta = value - result.mean
    result.mean = result.mean + delta / float64(result.count)
    m2 = m2 + delta * (value - result.mean)
    i = i + 1
  if result.count > 1:
    result.variance = m2 / float64(result.count - 1)

proc welchT(A, B: SampleStats): float64 =
  var
    denominator: float64 = 0.0
  if A.count <= 1 or B.count <= 1:
    return
  denominator = sqrt(A.variance / float64(A.count) +
    B.variance / float64(B.count))
  if denominator > 0.0:
    result = (A.mean - B.mean) / denominator

proc welchTimingLeakage*(name: string, fixed, random: openArray[float64],
    threshold: float64 = 4.5): TimingLeakageResult =
  ## name: measured operation. fixed/random: interleaved timing classes.
  ## threshold: absolute t-value boundary, conventionally 4.5 for dudect-style checks.
  var
    A, B, A2, B2: SampleStats
  A = sampleStats(fixed)
  B = sampleStats(random)
  A2 = centeredSquareStats(fixed, A.mean)
  B2 = centeredSquareStats(random, B.mean)
  result.name = name
  result.fixedSamples = A.count
  result.randomSamples = B.count
  result.fixedMean = A.mean
  result.randomMean = B.mean
  result.firstOrderT = welchT(A, B)
  result.secondOrderT = welchT(A2, B2)
  result.maxAbsT = max(abs(result.firstOrderT), abs(result.secondOrderT))
  result.approximateP = erfc(result.maxAbsT / sqrt(2.0))
  result.threshold = threshold
  result.passed = result.maxAbsT < threshold
