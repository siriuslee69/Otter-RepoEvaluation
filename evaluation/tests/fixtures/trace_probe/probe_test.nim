## Trace worker <- exercise the probe routines and catch one expected failure.
import src/probe
var
  p: Poly = default(Poly)
fill(p, 2000)
echo pure(1, 2), " ", noRaise(3), " ", unused(0), " ", tmpl(1)
try: discard bad(9)
except ValueError: echo "caught"
