## ------------------------------------------------------------------
## Otter Evaluation Tests <- statistical math and stable benchmarks
## ------------------------------------------------------------------

import std/[complex, json, math, os, sequtils, strutils, unittest]
import runePragmas
import var_invariants
import otter_repo_evaluation
import ../../src/protocols/evaluation/fft

proc pairRank(v: int): int {.role: math.} =
  ## v: two three-bit rows. Two nonzero unequal vectors are independent over GF(2).
  var
    a: int = v and 7
    b: int = v shr 3
  if a == 0 and b == 0: return 0
  if a == 0 or b == 0 or a == b: return 1
  result = 2

proc pairBits(v: int): seq[uint8] {.role: truthBuilder.} =
  ## v: packed pair of three-bit rows; return six consecutive matrix bits.
  var
    i: int = 0
  result = newSeq[uint8](6)
  while i < result.len:
    result[i] = uint8((v shr i) and 1)
    inc i

suite "otter evaluation":
  # {.testKind: tkRegression, covers: "fftRadix2".}
  test "radix two transform preserves complex butterfly results":
    var
      X: seq[Complex64] = @[complex64(1, 0), complex64(2, 0),
        complex64(3, 0), complex64(4, 0)]
      Y: seq[Complex64] = fftRadix2(X)
      expected: seq[Complex64] = @[complex64(10, 0), complex64(-2, 2),
        complex64(-2, 0), complex64(-2, -2)]
    check Y.len == expected.len
    for i in 0 ..< expected.len:
      check abs(Y[i].re - expected[i].re) < 1.0e-12
      check abs(Y[i].im - expected[i].im) < 1.0e-12
    check fftRadix2(@[]).len == 0
    check fftRadix2(@[complex64(7, -3)]) == @[complex64(7, -3)]

  # {.testKind: tkRegression, covers: "universalTest".}
  test "universal test measures repeated block distances":
    var
      B: seq[uint8] = @[0'u8, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1,
        0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1]
      r: NistResult = universalTest(B, 6, 2)
    check abs(r.statistic - 1.0) < 1.0e-12
    check r.pValue >= 0.0 and r.pValue <= 1.0
    check universalTest(B, 5, 2).pValue == 0.0
    check universalTest(B, 6, 4).pValue == 0.0

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

  # {.testKind: tkRegression, covers: "nonOverlappingTemplateTests|overlappingTemplateTest|randomExcursionsTests|randomExcursionsVariantTests|matrixRankTest".}
  test "statistical refactors preserve the recorded results on a fixed bit stream":
    var
      B: seq[uint8] = newSeq[uint8](257)
      state: uint32 = 0x716bc241'u32
      i: int = 0
      R: seq[NistResult] = @[]
      path: string = currentSourcePath().parentDir / "fixtures" / "statistics" /
        "evaluation_reference.json"
      expected: JsonNode = parseFile(path)
    while i < B.len:
      state = state xor (state shl 13)
      state = state xor (state shr 17)
      state = state xor (state shl 5)
      B[i] = uint8(state and 1)
      inc i
    R.add(nonOverlappingTemplateTests(B, 3, 16, 4))
    R.add(overlappingTemplateTest(B, 3, 32))
    R.add(randomExcursionsTests(B))
    R.add(randomExcursionsVariantTests(B))
    R.add(matrixRankTest(B, 4, 4))
    check R.len == expected.len
    i = 0
    while i < min(R.len, expected.len):
      check R[i].name == expected[i]["name"].getStr()
      check abs(R[i].statistic - expected[i]["statistic"].getFloat()) <=
        1.0e-10 * max(1.0, abs(expected[i]["statistic"].getFloat()))
      check abs(R[i].pValue - expected[i]["pValue"].getFloat()) < 1.0e-10
      check R[i].passed == expected[i]["passed"].getBool()
      inc i

  # {.testKind: tkEdgeCase, covers: "buildTemplateList|nonOverlappingTemplateTests|overlappingTemplateTest".}
  test "invalid and unrepresentable template dimensions yield finite failures":
    var
      B: seq[uint8] = newSeq[uint8](128)
    check buildTemplateList(0, 1).len == 0
    check buildTemplateList(sizeof(int) * 8, 1).len == 0
    check buildTemplateList(int.high, 1).len == 0
    check nonOverlappingTemplateTests(B, int.high, int.high, 1).len == 0
    check nonOverlappingTemplateTests(B, 3, 0, 1).len == 0
    check nonOverlappingTemplateTests(B, 3, 129, 1).len == 0
    check overlappingTemplateTest(B, 3, 0).pValue == 0.0
    check overlappingTemplateTest(B, 0, 16).pValue == 0.0
    check overlappingTemplateTest(B, int.high, int.high).pValue == 0.0
    B = newSeq[uint8](2048)
    check overlappingTemplateTest(B, 1200, 2048).statistic == 0.0
    check overlappingTemplateTest(B, 1200, 2048).pValue == 0.0

  # {.testKind: tkRegression, covers: "nonOverlappingTemplateTests".}
  test "wide representable templates avoid a doubled-width integer shift":
    when sizeof(int) >= 8:
      var
        R: seq[NistResult] = nonOverlappingTemplateTests(newSeq[uint8](128), 40, 64, 1)
      check R.len == 1
      check R[0].statistic > 0.0
      check R[0].statistic < Inf
      check R[0].pValue >= 0.0 and R[0].pValue <= 1.0

  # {.testKind: tkUnit, covers: "buildTemplateList".}
  test "pattern enumeration keeps its positive order and default limits":
    check buildTemplateList(2, 10) == @[1, 2, 3]
    check buildTemplateList(9, 0).len == 148
    check buildTemplateList(8, 0).len == 16
    check buildTemplateList(3, 2) == @[1, 2]

  # {.testKind: tkRegression, covers: "nonOverlappingTemplateTests|overlappingTemplateTest".}
  test "a final partial block does not change template results":
    var
      B: seq[uint8] = pairBits(13) & pairBits(54) & pairBits(21) & pairBits(38)
      short: seq[NistResult] = nonOverlappingTemplateTests(B, 3, 12, 3)
      extra: seq[NistResult] = nonOverlappingTemplateTests(B & @[1'u8], 3, 12, 3)
    check short == extra
    check overlappingTemplateTest(B, 2, 12) == overlappingTemplateTest(B & @[1'u8], 2, 12)

  # {.testKind: tkRegression, covers: "computeExcursionsCounts".}
  test "cycle bins include the unfinished tail and reset reused outputs":
    var
      C: array[9, array[6, int]] = default(array[9, array[6, int]])
      V: array[19, int] = default(array[19, int])
      n: int = 17
    C[0][0] = 99
    V[0] = 99
    computeExcursionsCounts(@[1'u8, 1, 0, 0, 0, 1, 1], n, C, V)
    check n == 3
    check C[5] == [1, 1, 1, 0, 0, 0]
    check C[6] == [2, 1, 0, 0, 0, 0]
    check C[3] == [2, 1, 0, 0, 0, 0]
    check C[4] == default(array[6, int])
    check C[0] == [3, 0, 0, 0, 0, 0]
    check V[10] == 3
    check V[11] == 1
    check V[8] == 1
    check V[9] == 0
    check V[0] == 0
    computeExcursionsCounts(@[], n, C, V)
    check n == 0
    check C == default(array[9, array[6, int]])
    check V == default(array[19, int])
    check randomExcursionsTests(@[]).len == 0
    check randomExcursionsVariantTests(@[]).len == 0

  # {.testKind: tkEdgeCase, covers: "computeExcursionsCounts".}
  test "a cycle with at least five visits lands in the final bin":
    var
      C: array[9, array[6, int]] = default(array[9, array[6, int]])
      V: array[19, int] = default(array[19, int])
      n: int = 0
    computeExcursionsCounts(@[1'u8, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0], n, C, V)
    check n == 1
    check C[5] == [0, 0, 0, 0, 0, 1]
    check C[6] == [0, 0, 0, 0, 0, 1]

  # {.testKind: tkProperty, covers: "binaryMatrixRank".}
  test "all 64 two-row binary matrices have the expected independent row count":
    for v in 0 ..< 64:
      check binaryMatrixRank(pairBits(v), 2, 3, 0) == pairRank(v)

  # {.testKind: tkEdgeCase, covers: "binaryMatrixRank|matrixRankTest".}
  test "matrix bounds and packed-word crossings are checked":
    var
      B: seq[uint8] = newSeq[uint8](132)
    B[65] = 1
    B[66] = 1
    check binaryMatrixRank(B, 2, 65, 1) == 2
    check binaryMatrixRank(B, 0, 65, 1) == 0
    check binaryMatrixRank(B, 2, 65, -1) == 0
    check binaryMatrixRank(B, 2, 65, 3) == 0
    check binaryMatrixRank(B, int.high, int.high, 0) == 0
    check matrixRankTest(B, int.high, int.high).pValue == 0.0
    check matrixRankTest(B, 1, 1).pValue == 0.0

  # {.testKind: tkRegression, covers: "rankProbability".}
  test "large rank exponents remain finite":
    var
      p: float64 = rankProbability(1024, 1024, 1024)
    check p > 0.28 and p < 0.30
    check rankProbability(0, 2, 1) == 0.0
    check rankProbability(2, 3, 3) == 0.0

  # {.testKind: tkEdgeCase, covers: "chiSquare|positiveProbabilities".}
  test "the shared score checks category widths and positive finite probabilities":
    check chiSquare([2, 2], [0.5, 0.5], 4) == 0.0
    check chiSquare([4, 0], [0.5, 0.5], 4) == 4.0
    check not positiveProbabilities([0.0, 1.0])
    check not positiveProbabilities([NaN])
    check not positiveProbabilities([Inf])
    expect ContractDefect:
      discard chiSquare([1], [0.5, 0.5], 1)
    expect ContractDefect:
      discard chiSquare([1, 0], [1.0, 0.0], 1)
