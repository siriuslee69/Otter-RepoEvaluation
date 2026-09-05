# ============================================================
# | NIST Eval Suite                                         |
# | -> Aggregated test runner for byte streams              |
# ============================================================

import ./bits
import ./basic_tests
import ./constants
import ./excursions
import ./fft
import ./linear_complexity
import ./patterns
import ./rank
import ./templates
import ./types
import ./universal


proc universalBlockForBits(n: int): int =
  ## n: available bit count mapped to SP 800-22's largest valid L.
  const
    minimumBits: array[11, int] = [
      387_840, 904_960, 2_068_480, 4_654_080, 10_342_400,
      22_753_280, 49_643_520, 107_560_960, 231_669_760,
      496_435_200, 1_059_061_760
    ]
  var
    i: int = 0
  i = 0
  while i < minimumBits.len:
    if n >= minimumBits[i]:
      result = i + 6
    i = i + 1


proc nistParamsForBits*(n: int): NistParams =
  ## n: stream length in bits used to choose practical SP 800-22 parameters.
  result.alpha = defaultAlpha
  result.blockSize = 128
  result.patternSize = 10
  result.longRunBlock = 8
  if n >= 6_272:
    result.longRunBlock = 128
  if n >= 750_000:
    result.longRunBlock = 10_000
  result.rankRows = 32
  result.rankCols = 32
  result.spectralMaxBits = n
  result.templateSize = 9
  result.templateBlockSize = max(1_032, n div 8)
  result.templateCount = 16
  result.overlapTemplateSize = 9
  result.overlapTemplateBlock = 1_032
  result.linearComplexityBlock = 500
  result.universalBlockSize = universalBlockForBits(n)
  result.universalInitBlocks = 0


proc nistCoreSuiteFromBytes*(Bs: openArray[uint8],
    p: NistParams): seq[NistResult] =
  ## Bs: input bytes for the lower-cost core statistical diagnostics.
  ## p: parameters; template, universal, linear, and excursion fields are unused.
  var
    bits: seq[uint8] = @[]
    s: tuple[r1, r2: NistResult]
  bits = bitsFromBytes(Bs)
  result.add(monobitTest(bits, p.alpha))
  result.add(blockFrequencyTest(bits, p.blockSize, p.alpha))
  result.add(runsTest(bits, p.alpha))
  result.add(longestRunOfOnesTest(bits, p.longRunBlock, p.alpha))
  result.add(matrixRankTest(bits, p.rankRows, p.rankCols, p.alpha))
  result.add(spectralTest(bits, p.spectralMaxBits, p.alpha))
  result.add(approximateEntropyTest(bits, p.patternSize, p.alpha))
  s = serialTest(bits, p.patternSize, p.alpha)
  result.add(s.r1)
  result.add(s.r2)
  result.add(cumulativeSumsTest(bits, true, p.alpha))
  result.add(cumulativeSumsTest(bits, false, p.alpha))


proc nistSuiteFromBytes*(Bs: openArray[uint8], p: NistParams): seq[NistResult] =
  ## Bs: input bytes to run the NIST-style suite on.
  ## p: suite parameters.
  var
    bits: seq[uint8] = @[]
    rs: seq[NistResult] = @[]
    r: NistResult
    s: tuple[r1, r2: NistResult]
  bits = bitsFromBytes(Bs)
  r = monobitTest(bits, p.alpha)
  rs.add(r)
  r = blockFrequencyTest(bits, p.blockSize, p.alpha)
  rs.add(r)
  r = runsTest(bits, p.alpha)
  rs.add(r)
  r = longestRunOfOnesTest(bits, p.longRunBlock, p.alpha)
  rs.add(r)
  r = matrixRankTest(bits, p.rankRows, p.rankCols, p.alpha)
  rs.add(r)
  r = spectralTest(bits, p.spectralMaxBits, p.alpha)
  rs.add(r)
  rs.add(nonOverlappingTemplateTests(bits, p.templateSize, p.templateBlockSize,
    p.templateCount, p.alpha))
  r = overlappingTemplateTest(bits, p.overlapTemplateSize, p.overlapTemplateBlock, p.alpha)
  rs.add(r)
  r = universalTest(bits, p.universalBlockSize, p.universalInitBlocks, p.alpha)
  rs.add(r)
  r = linearComplexityTest(bits, p.linearComplexityBlock, p.alpha)
  rs.add(r)
  r = approximateEntropyTest(bits, p.patternSize, p.alpha)
  rs.add(r)
  s = serialTest(bits, p.patternSize, p.alpha)
  rs.add(s.r1)
  rs.add(s.r2)
  r = cumulativeSumsTest(bits, true, p.alpha)
  rs.add(r)
  r = cumulativeSumsTest(bits, false, p.alpha)
  rs.add(r)
  rs.add(randomExcursionsTests(bits, p.alpha))
  rs.add(randomExcursionsVariantTests(bits, p.alpha))
  result = rs
