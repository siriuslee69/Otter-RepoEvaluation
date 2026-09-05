# ============================================================
# | GF(2) Linear Algebra                                    |
# | -> Packed rank and nullity for invariant certificates   |
# ============================================================

import std/bitops

proc gf2WordCount*(columns: int): int =
  ## columns: matrix width in bits.
  if columns > 0:
    result = (columns + 63) div 64

proc gf2SetBit*(R: var seq[uint64], column: int) =
  ## R: packed row. column: bit position to set.
  if column < 0 or column >= R.len * 64:
    raise newException(ValueError, "GF(2) column is outside the packed row")
  R[column div 64] = R[column div 64] or (1'u64 shl (column mod 64))

proc gf2Bit(R: seq[uint64], column: int): bool {.inline.} =
  result = ((R[column div 64] shr (column mod 64)) and 1'u64) != 0'u64

proc xorRows(A: var seq[uint64], B: seq[uint64]) {.inline.} =
  var
    i: int = 0
  i = 0
  while i < A.len:
    A[i] = A[i] xor B[i]
    i = i + 1

proc findPivot(Rows: seq[seq[uint64]], start, column: int): int =
  var
    i: int = start
  result = -1
  while i < Rows.len:
    if gf2Bit(Rows[i], column):
      return i
    i = i + 1

proc eliminateColumn(Rows: var seq[seq[uint64]], pivot,
    column: int) =
  var
    i: int = 0
  i = 0
  while i < Rows.len:
    if i != pivot and gf2Bit(Rows[i], column):
      xorRows(Rows[i], Rows[pivot])
    i = i + 1

proc validateRows(Rows: seq[seq[uint64]], columns: int) =
  var
    i, words: int = 0
  words = gf2WordCount(columns)
  i = 0
  while i < Rows.len:
    if Rows[i].len != words:
      raise newException(ValueError, "GF(2) rows have inconsistent widths")
    i = i + 1

proc gf2Rank*(Rows: var seq[seq[uint64]], columns: int): int =
  ## Rows: packed matrix reduced in place. columns: meaningful bit width.
  var
    column, pivot, found: int = 0
  if columns <= 0:
    return
  validateRows(Rows, columns)
  column = 0
  pivot = 0
  while column < columns and pivot < Rows.len:
    found = findPivot(Rows, pivot, column)
    if found >= 0:
      swap(Rows[pivot], Rows[found])
      eliminateColumn(Rows, pivot, column)
      pivot = pivot + 1
    column = column + 1
  result = pivot

proc gf2Nullity*(Rows: var seq[seq[uint64]], columns: int): int =
  ## Rows/columns: packed matrix whose right-nullspace dimension is returned.
  result = columns - gf2Rank(Rows, columns)

proc gf2Parity*(A, B: openArray[uint64]): uint8 =
  ## A/B: equal-width packed vectors whose GF(2) dot product is returned.
  var
    i: int = 0
    parity: uint8 = 0'u8
  if A.len != B.len:
    raise newException(ValueError, "GF(2) vectors have different widths")
  i = 0
  while i < A.len:
    parity = parity xor uint8(countSetBits(A[i] and B[i]) and 1)
    i = i + 1
  result = parity
