# ============================================================
# | NIST Eval Rank Test                                     |
# | -> Binary matrix rank computations                      |
# ============================================================

import std/math

import ./constants
import ./math_utils
import ./types


proc lnPow2MinusPow2(a, b: int): float64 =
  ## a: exponent for first power of two.
  ## b: exponent for second power of two.
  var
    ln2: float64 = ln(2.0)
    t: float64 = 0.0
  if a <= b:
    result = -Inf
  else:
    t = exp(float64(a - b) * ln2) - 1.0
    if t <= 0.0:
      result = -Inf
    else:
      result = float64(b) * ln2 + ln(t)


proc rankProbability*(r, c, k: int): float64 =
  ## r: matrix rows.
  ## c: matrix cols.
  ## k: target rank.
  var
    rows: int = r
    cols: int = c
    i: int = 0
    logNum: float64 = 0.0
    logDen: float64 = 0.0
    logAll: float64 = 0.0
    ln2: float64 = ln(2.0)
    t: int = 0
  if rows <= 0 or cols <= 0 or k < 0 or k > rows or k > cols:
    result = 0.0
  else:
    if rows > cols:
      t = rows
      rows = cols
      cols = t
    i = 0
    while i < k:
      logNum = logNum + lnPow2MinusPow2(rows, i) + lnPow2MinusPow2(cols, i)
      logDen = logDen + lnPow2MinusPow2(k, i)
      i = i + 1
    logNum = logNum + float64((rows - k) * (cols - k)) * ln2
    logAll = float64(rows * cols) * ln2 + logDen
    result = exp(logNum - logAll)


proc binaryMatrixRank*(Bs: openArray[uint8], r, c, o: int): int =
  ## Bs: input bit sequence (0/1).
  ## r: matrix rows.
  ## c: matrix cols.
  ## o: starting offset in bits.
  var
    ms: seq[seq[uint8]] = @[]
    i: int = 0
    j: int = 0
    row: int = 0
    col: int = 0
    pivot: int = 0
    rank: int = 0
    t: seq[uint8] = @[]
  ms.setLen(r)
  i = 0
  while i < r:
    ms[i] = newSeq[uint8](c)
    j = 0
    while j < c:
      ms[i][j] = Bs[o + i * c + j]
      j = j + 1
    i = i + 1
  row = 0
  col = 0
  while row < r and col < c:
    pivot = row
    while pivot < r and ms[pivot][col] == 0'u8:
      pivot = pivot + 1
    if pivot < r:
      if pivot != row:
        t = ms[row]
        ms[row] = ms[pivot]
        ms[pivot] = t
      i = row + 1
      while i < r:
        if ms[i][col] == 1'u8:
          j = col
          while j < c:
            ms[i][j] = ms[i][j] xor ms[row][j]
            j = j + 1
        i = i + 1
      row = row + 1
      rank = rank + 1
    col = col + 1
  result = rank


proc matrixRankTest*(Bs: openArray[uint8], r, c: int,
    a: float64 = defaultAlpha): NistResult =
  ## Bs: input bit sequence (0/1).
  ## r: matrix rows.
  ## c: matrix cols.
  ## a: alpha threshold.
  var
    n: int = Bs.len
    rows: int = r
    cols: int = c
    m: int = 0
    nBlocks: int = 0
    i: int = 0
    offset: int = 0
    rank: int = 0
    f1: int = 0
    f2: int = 0
    f3: int = 0
    p1: float64 = 0.0
    p2: float64 = 0.0
    p3: float64 = 0.0
    chi: float64 = 0.0
    p: float64 = 0.0
    t: int = 0
  if rows <= 0 or cols <= 0:
    result = makeResult("rank", 0.0, 0.0, a)
  else:
    if rows > cols:
      t = rows
      rows = cols
      cols = t
    m = rows * cols
    nBlocks = n div m
    if nBlocks == 0:
      result = makeResult("rank", 0.0, 0.0, a)
    else:
      offset = 0
      i = 0
      while i < nBlocks:
        rank = binaryMatrixRank(Bs, rows, cols, offset)
        if rank == rows:
          f1 = f1 + 1
        elif rank == rows - 1:
          f2 = f2 + 1
        else:
          f3 = f3 + 1
        offset = offset + m
        i = i + 1
      p1 = rankProbability(rows, cols, rows)
      p2 = rankProbability(rows, cols, rows - 1)
      p3 = 1.0 - p1 - p2
      if p1 <= 0.0 or p2 <= 0.0 or p3 <= 0.0:
        result = makeResult("rank", 0.0, 0.0, a)
      else:
        chi = ((float64(f1) - float64(nBlocks) * p1) * (float64(f1) - float64(nBlocks) * p1)) /
          (float64(nBlocks) * p1)
        chi = chi + ((float64(f2) - float64(nBlocks) * p2) * (float64(f2) - float64(nBlocks) * p2)) /
          (float64(nBlocks) * p2)
        chi = chi + ((float64(f3) - float64(nBlocks) * p3) * (float64(f3) - float64(nBlocks) * p3)) /
          (float64(nBlocks) * p3)
        p = regularizedGammaQ(1.0, chi / 2.0)
        result = makeResult("rank", chi, p, a)
