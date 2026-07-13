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
