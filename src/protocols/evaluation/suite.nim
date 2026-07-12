# ============================================================
# | NIST Eval Suite                                         |
# | -> Aggregated test runner for byte streams              |
# ============================================================

import ./bits
import ./basic_tests
import ./excursions
import ./fft
import ./linear_complexity
import ./patterns
import ./rank
import ./templates
import ./types
import ./universal


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
