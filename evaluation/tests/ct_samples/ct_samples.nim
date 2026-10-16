# ============================================================
# | Otter ct samples -> three routines with known answers    |
# | -> compiled and checked by test_machine_code.nim         |
# ============================================================
#
#   earlyExitEqual      stops at the first different byte    -> BRANCH
#   xorAccumulateEqual  looks at every byte, decides at end  -> clean
#   secretLookup        reads table[secret]                  -> ADDRESS
#
# {.noinline.} keeps each one a routine of its own in the binary. The
# main block feeds them the command line, so the compiler cannot work
# the answers out ahead of time and drop the routines.

import std/os

import runePragmas

const
  table: array[256, byte] = block:
    var t: array[256, byte]
    for i in 0 .. 255: t[i] = byte((i * 7 + 3) and 255)
    t

proc earlyExitEqual(a, b: openArray[byte]): bool {.noinline,
    secret: "a|b", role: math.} =
  ## a, b: two secrets. Equal or not, but quicker when they differ early.
  var
    i: int = 0
  if a.len != b.len:
    return false
  while i < a.len:
    if a[i] != b[i]:
      return false
    i = i + 1
  result = true

proc xorAccumulateEqual(a, b: openArray[byte]): bool {.noinline,
    secret: "a|b", role: math.} =
  ## a, b: two secrets. Equal or not, in the same time either way: the
  ## differences are gathered into d and only d is looked at.
  var
    d: byte = 0
    i: int = 0
  if a.len != b.len:
    return false
  while i < a.len:
    d = d or (a[i] xor b[i])
    i = i + 1
  result = d == 0

proc secretLookup(x: byte): byte {.noinline, secret: "x", role: math.} =
  ## x: a secret byte. The table entry it picks; which cache line is
  ## touched depends on x.
  result = table[x]

when isMainModule:
  var
    s: string = if paramCount() > 0: paramStr(1) else: "otter"
  echo earlyExitEqual(s.toOpenArrayByte(0, s.len - 1), "otter".toOpenArrayByte(0, 4))
  echo xorAccumulateEqual(s.toOpenArrayByte(0, s.len - 1), "otter".toOpenArrayByte(0, 4))
  echo secretLookup(byte(s.len))
