## Trace worker <- exercise the probe routines and catch one expected failure.
import src/probe
var
  p: Poly = default(Poly)
fill(p, 2000)
echo pure(1, 2), " ", noRaise(3), " ", unused(0), " ", tmpl(1)
try: discard bad(9)
except ValueError: echo "caught"
doAssert counted(4) == 5
doAssert calls == 1
doAssert explicitResult(3) == 7
doAssert explicitReturn(2) == 9
doAssert inferred(3) == 13
doAssert genericValue(7'u32) == 7'u32
doAssert mixedReturn(-1) == 8
doAssert mixedReturn(2) == 14
