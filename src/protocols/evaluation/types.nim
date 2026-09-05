# ============================================================
# | NIST Eval Types                                         |
# | -> Shared result types and parameter bundles            |
# ============================================================

type
  NistResult* = object
    name*: string
    statistic*: float64
    pValue*: float64
    passed*: bool

  NistParams* = object
    blockSize*: int
    patternSize*: int
    longRunBlock*: int
    alpha*: float64
    rankRows*: int
    rankCols*: int
    spectralMaxBits*: int
    templateSize*: int
    templateBlockSize*: int
    templateCount*: int
    overlapTemplateSize*: int
    overlapTemplateBlock*: int
    linearComplexityBlock*: int
    universalBlockSize*: int
    universalInitBlocks*: int

  TimingLeakageResult* = object
    name*: string
    fixedSamples*: int
    randomSamples*: int
    fixedMean*: float64
    randomMean*: float64
    firstOrderT*: float64
    secondOrderT*: float64
    maxAbsT*: float64
    approximateP*: float64
    threshold*: float64
    passed*: bool

  ProportionResult* = object
    name*: string
    failures*: int
    total*: int
    observed*: float64
    expected*: float64
    lower*: float64
    upper*: float64
    passed*: bool


proc makeResult*(n: string, s: float64, p: float64, a: float64): NistResult =
  ## n: test name.
  ## s: test statistic.
  ## p: p-value.
  ## a: alpha threshold.
  var
    t: NistResult
  t.name = n
  t.statistic = s
  t.pValue = p
  t.passed = p >= a
  result = t
