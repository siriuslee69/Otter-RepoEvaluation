## ------------------------------------------------------------------
## Otter Evaluation Tests <- statistical math and stable benchmarks
## ------------------------------------------------------------------

import std/[sequtils, strutils, unittest]
import otter_repo_evaluation

suite "otter evaluation":
  # {.testKind: tkUnit.}
  test "binary matrix rank probabilities match reference values":
    var
      p32, p31, pRest: float64 = 0.0
    p32 = rankProbability(32, 32, 32)
    p31 = rankProbability(32, 32, 31)
    pRest = 1.0 - p32 - p31
    check abs(p32 - 0.2887880951538411) < 1.0e-12
    check abs(p31 - 0.5775761901732048) < 1.0e-12
    check abs(pRest - 0.1336357146729541) < 1.0e-12

  # {.testKind: tkUnit.}
  test "stable benchmark reports repeated samples":
    var
      A: array[1, BenchAlgo] = default(array[1, BenchAlgo])
      R: seq[StableBenchResult] = @[]
      value: int = 0
    A[0] = BenchAlgo(name: "increment", bytesPerOp: 4,
      run: proc() {.closure.} = value = value + 1)
    R = compareAlgorithmsStable(A, loops = 16, warmup = 2, samples = 3)
    check R.len == 1
    check R[0].samples == 3
    check R[0].loops == 16
    check R[0].bytesPerOp == 4
    check R[0].medianNs >= R[0].minNs
    check R[0].medianNs <= R[0].maxNs
    check formatStableBenchResults(R).contains("median_ns=")
    check value == 50

  # {.testKind: tkUnit.}
  test "core statistical preset runs eleven diagnostics":
    var
      B: seq[uint8] = @[]
      P: NistParams = default(NistParams)
      R: seq[NistResult] = @[]
      i: int = 0
      state: uint32 = 0x12345678'u32
    B.setLen(16_384)
    i = 0
    while i < B.len:
      state = state xor (state shl 13)
      state = state xor (state shr 17)
      state = state xor (state shl 5)
      B[i] = uint8(state)
      i = i + 1
    P = nistParamsForBits(B.len * 8)
    R = nistCoreSuiteFromBytes(B, P)
    check R.len == 11
    check P.longRunBlock == 128
    check P.rankRows == 32
    check P.rankCols == 32

  # {.testKind: tkUnit.}
  test "timing leakage helper reports first and second order Welch tests":
    var
      fixed = @[10.0, 11.0, 9.0, 10.0, 12.0, 8.0]
      random = @[10.0, 11.0, 9.0, 10.0, 12.0, 8.0]
      R: TimingLeakageResult = default(TimingLeakageResult)
    R = welchTimingLeakage("equal", fixed, random)
    check R.fixedSamples == fixed.len
    check R.randomSamples == random.len
    check R.firstOrderT == 0.0
    check R.secondOrderT == 0.0
    check R.passed

  # {.testKind: tkUnit.}
  test "campaign proportions use expected alpha confidence bounds":
    var
      good, bad: ProportionResult = default(ProportionResult)
    good = evaluateFailureProportion("good", 10, 1_000)
    bad = evaluateFailureProportion("bad", 100, 1_000)
    check good.passed
    check not bad.passed
    check good.lower < 0.01
    check good.upper > 0.01

  # {.testKind: tkUnit.}
  test "packed GF2 rank provides full-rank invariant certificates":
    var
      Rows: seq[seq[uint64]] = @[
        @[0b110'u64],
        @[0b011'u64],
        @[0b001'u64]
      ]
      Partial: seq[seq[uint64]] = @[
        @[0b110'u64],
        @[0b011'u64]
      ]
    check gf2Rank(Rows, 3) == 3
    check gf2Nullity(Partial, 3) == 1
    check gf2Parity(@[0b101'u64], @[0b110'u64]) == 1'u8

  # {.testKind: tkRegression, covers: "longestRunOfOnesTest".}
  test "longest-run tests refuse zero, negative, and unsupported block sizes":
    for m in [0, -1, 17]:
      check not longestRunOfOnesTest(@[0'u8, 1'u8], m).passed
      check longestRunOfOnesTest(@[0'u8, 1'u8], m).pValue == 0.0

  # {.testKind: tkRegression, covers: "longestRunOfOnesTest".}
  test "longest-run tail categories retain their reference probabilities":
    var
      B: seq[uint8] = @[]
      R: NistResult = NistResult()
      expected: float64 = 0.0
    for row in [(m: 8, first: 0.2148, last: 0.1875),
        (m: 128, first: 0.1174, last: 0.1124),
        (m: 10000, first: 0.0882, last: 0.0727)]:
      B = newSeq[uint8](row.m * 2)
      R = longestRunOfOnesTest(B, row.m)
      expected = 2.0 * (1.0 / row.first - 1.0)
      check abs(R.statistic - expected) < 1.0e-10
      B = newSeqWith(row.m * 2, 1'u8)
      R = longestRunOfOnesTest(B, row.m)
      expected = 2.0 * (1.0 / row.last - 1.0)
      check abs(R.statistic - expected) < 1.0e-10
