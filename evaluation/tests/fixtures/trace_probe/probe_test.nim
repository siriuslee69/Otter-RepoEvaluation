import src/probe
var
  p: Poly
fill(p, 2000)
echo pure(1, 2), " ", noRaise(3), " ", unused(0), " ", tmpl(1)
try: discard bad(9)
except ValueError: echo "caught"
