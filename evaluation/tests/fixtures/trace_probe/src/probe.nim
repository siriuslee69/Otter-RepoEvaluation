## probe.nim <- routines of every awkward kind, for test_tracing.nim
import runePragmas

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

var
  calls*: int = 0

proc counted*(x: int): int {.role: helper.} =
  ## x: input. Count this call so the trace wrapper cannot evaluate it twice.
  inc calls
  x + 1

proc explicitResult*(x: int): int {.role: helper.} =
  ## x: input. A statement body sets result directly.
  result = x + 4

proc explicitReturn*(x: int): int {.role: helper.} =
  ## x: input. An explicit return still reaches the exit trace.
  return x + 7

proc inferred*(x: int): auto {.role: helper.} =
  ## x: input. Let the compiler infer the value type.
  x + 10

proc genericValue*[T](x: T): T {.role: helper.} =
  ## x: value whose type is chosen when the routine is called.
  x

proc mixedReturn*(x: int): int {.role: helper.} =
  ## x: input. Exercise both an early return and a final implicit value.
  if x < 0:
    return 8
  x + 12
