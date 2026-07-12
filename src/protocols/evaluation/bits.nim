# ============================================================
# | NIST Eval Bit Utilities                                 |
# | -> Bit expansion, counting, and index helpers           |
# ============================================================

proc bitsFromBytes*(Bs: openArray[uint8]): seq[uint8] =
  ## Bs: input bytes to expand into MSB-first bit sequence.
  var
    ts: seq[uint8] = @[]
    i: int = 0
    j: int = 0
    l: int = Bs.len
    idx: int = 0
    b: uint8 = 0'u8
  ts.setLen(l * 8)
  while i < l:
    b = Bs[i]
    j = 7
    while j >= 0:
      ts[idx] = (b shr j) and 1'u8
      idx = idx + 1
      j = j - 1
    i = i + 1
  result = ts


proc countOnesBits*(Bs: openArray[uint8]): uint32 =
  ## Bs: input bit sequence (0/1).
  var
    i: int = 0
    l: int = Bs.len
    t: uint32 = 0'u32
  while i < l:
    t = t + uint32(Bs[i])
    i = i + 1
  result = t


proc countRunsBits*(Bs: openArray[uint8]): uint32 =
  ## Bs: input bit sequence (0/1).
  var
    i: int = 0
    l: int = Bs.len
    tRuns: uint32 = 0'u32
    tPrev: uint8 = 0'u8
  if l == 0:
    result = 0'u32
  else:
    tPrev = Bs[0]
    tRuns = 1'u32
    i = 1
    while i < l:
      if Bs[i] != tPrev:
        tRuns = tRuns + 1'u32
        tPrev = Bs[i]
      i = i + 1
    result = tRuns


proc largestPow2*(n: int): int =
  ## n: input value to clamp to the largest power of two <= n.
  var
    t: int = 1
  if n < 1:
    result = 0
  else:
    while (t shl 1) <= n:
      t = t shl 1
    result = t


proc bitReverse*(v, b: int): int =
  ## v: input index to reverse.
  ## b: number of bits to reverse.
  var
    r: int = 0
    i: int = 0
  r = 0
  i = 0
  while i < b:
    r = (r shl 1) or ((v shr i) and 1)
    i = i + 1
  result = r
