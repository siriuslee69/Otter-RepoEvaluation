## probe.nim <- routines of every awkward kind, for test_tracing.nim
type
  Poly* = object
    c*: array[4, int16]

proc red*(x: int16): int16 = (if x > 1664: x - 3329 else: x)
func pure*(a, b: uint32): uint32 = a xor b
proc noRaise*(x: int): int {.raises: [].} = x * 2
proc bad*(x: int): int =
  if x > 3: raise newException(ValueError, "too big: " & $x)
  x
proc fill*(P: var Poly, v: int16) =
  for i in 0 .. 3: P.c[i] = red(v)
proc unused*(_: int): int = 1
const table: array[2, int16] = [red(1), red(2000)]   # runs at compile time
template tmpl*(x: int): int = x + 1
