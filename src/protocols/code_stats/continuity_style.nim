## ================================================================
## | continuity_style.nim  <-  what a style sheet says about one    |
## |   element: its colours and its times                          |
## |---------------------------------------------------------------|
## | Two of the three continuity metrics are decided in the style   |
## | sheet, not in the page:                                        |
## |                                                                |
## |   .opener-green { background: var(--green); }                  |
## |   .panel-green  { border-left: 4px solid var(--green);         |
## |                   transition: opacity 0.15s; }                 |
## |                                                                |
## |   colours  the button and its panel both say `green`  -> joined|
## |   time     0.15 s                                      -> move |
## |                                                                |
## | A rule is read for one thing only: the last box of its         |
## | selector (`.menu .panel-green` counts as `.panel-green`).      |
## | Rules with a pseudo class (`:hover`) are left out: they say    |
## | what happens under the pointer, not what the thing looks like. |
## ================================================================
##
## Colours are kept as plain words so two spellings of one colour meet:
##
##   var(--green)    ->  var:green   and, when `--green: #2e8b57` is written
##                                    anywhere, also  #2e8b57
##   #2E8B57         ->  #2e8b57
##   rgb(46, 139, 87) -> rgb(46,139,87)
##   green           ->  green
##
## Only the fill and the edges count (background, border, outline): the
## colour of text says nothing about what a thing is joined to.
##
## Not read: @media blocks, inherited colours, a colour set by a script,
## a transition set in a script. A look that comes back with no colour or
## no time may therefore be a thing the style sheet does not describe.

import std/[sets, strutils, tables]

import runePragmas
import ./ui_depth

const
  colourWords*: array[16, string] = ["red", "green", "blue", "orange",
    "yellow", "purple", "pink", "white", "black", "gray", "grey", "teal",
    "cyan", "magenta", "brown", "navy"]
    ## Plain colour names, read as colours when they stand in a fill or an edge.
  colourProps*: array[3, string] = ["background", "border", "outline"]
    ## The properties whose colours count.
  timeProps*: array[4, string] = ["transition", "transition-duration",
    "animation", "animation-duration"]
    ## The properties whose times count.
  maxRules*: int = 20_000
    ## A style sheet is read for at most this many rules.

type
  StyleRule* {.role: preparedData, tag: "stats".} = object
    tag*: string
    id*: string
    classes*: seq[string]
    colours*: HashSet[string]
    seconds*: float

  Look* {.role: preparedData, tag: "stats".} = object
    ## What the style sheets say about one thing.
    known*: bool
      ## True when any style sheet was read. A look with `known` false says
      ## nothing; one with `known` true and no colours says "no colour".
    colours*: HashSet[string]
    seconds*: float
      ## The longest transition or animation; 0 when there is none.

proc emptyLook*(known: bool): Look {.role: helper, tag: "stats".} =
  ## known: whether a style sheet was read at all. A look with nothing in it.
  result = Look(known: known, colours: initHashSet[string](), seconds: 0.0)

proc customProps(plain: string): Table[string, string] {.role: parser,
    tag: "stats".} =
  ## plain: a style sheet without comments.
  ## Every `--name: value` written in it, name without the dashes.
  var
    at: int = plain.find("--")
    stop: int = 0
    colon: int = 0
  result = initTable[string, string]()
  while at >= 0 and result.len < maxRules:
    colon = plain.find(':', at)
    stop = plain.find(';', at)
    if stop < 0:
      stop = plain.find('}', at)
    if colon > at and stop > colon and colon - at < 40:
      result[plain[at + 2 ..< colon].strip()] = plain[colon + 1 ..< stop].strip()
    at = plain.find("--", at + 2)

proc normalisedColour(t: string): string {.role: sanitizer, tag: "stats".} =
  ## t: a colour as written. The plain spelling used for comparing.
  result = t.strip().toLowerAscii().replace(" ", "")

proc coloursIn(value: string, props: Table[string, string]): HashSet[string]
    {.role: parser, tag: "stats".} =
  ## value: what stands after the colon of one fill or edge property
  ## props: the `--name: value` pairs of the sheet.
  ## The colours it names, each in the plain spelling above.
  var
    low: string = value.toLowerAscii()
    at: int = 0
    stop: int = 0
    name: string = ""
  result = initHashSet[string]()
  at = low.find("var(--")
  while at >= 0:
    stop = low.find(')', at)
    name = low[at + 6 ..< (if stop > at: stop else: low.len)].split(',')[0].strip()
    result.incl("var:" & name)
    if name in props:
      result.incl(normalisedColour(props[name]))
    at = low.find("var(--", at + 6)
  at = low.find('#')
  while at >= 0:
    stop = at + 1
    while stop < low.len and low[stop] in {'0' .. '9', 'a' .. 'f'}:
      stop = stop + 1
    if stop - at in [4, 7, 9]:
      result.incl(low[at ..< stop])
    at = low.find('#', at + 1)
  for fn in ["rgba(", "rgb(", "hsl(", "hsla("]:
    at = low.find(fn)
    stop = (if at >= 0: low.find(')', at) else: -1)
    if at >= 0 and stop > at:
      result.incl(normalisedColour(low[at .. stop]))
  for w in low.split({' ', ',', '(', ')'}):
    if w in colourWords:
      result.incl(w)

proc numberOf(s: string): float {.role: parser, tag: "stats".} =
  ## s: some text. The number it holds, or 0 when it holds none.
  result = 0.0
  try:
    result = parseFloat(s)
  except ValueError:
    result = 0.0

proc secondsIn(value: string): float {.role: parser, tag: "stats".} =
  ## value: what stands after the colon of a transition or animation property.
  ## The longest time written in it, in seconds (`150ms` is 0.15).
  var
    t: float = 0.0
    num: string = ""
  result = 0.0
  for w in value.toLowerAscii().split({' ', ',', ')', '('}):
    num = (if w.endsWith("ms"): w[0 ..< w.len - 2]
      elif w.endsWith("s"): w[0 ..< w.len - 1] else: "")
    t = 0.0
    if num.len > 0 and num[0] in {'0' .. '9', '.'}:
      t = numberOf(num) / (if w.endsWith("ms"): 1000.0 else: 1.0)
    result = max(result, t)

proc isColourProp(prop: string): bool {.role: parser, tag: "stats".} =
  ## prop: a property name. True for the fills and edges that carry colour.
  result = false
  for p in colourProps:
    if prop.startsWith(p):
      result = true

proc declarationRule(body: string, props: Table[string, string]):
    tuple[colours: HashSet[string], seconds: float] {.role: parser,
    tag: "stats".} =
  ## body: the text between the braces of one rule   props: the sheet's
  ## `--name: value` pairs. What the rule says about colours and times.
  var
    prop: string = ""
    value: string = ""
    colon: int = 0
  result = (colours: initHashSet[string](), seconds: 0.0)
  for d in body.split(';'):
    colon = d.find(':')
    prop = (if colon > 0: d[0 ..< colon].strip().toLowerAscii() else: "")
    value = (if colon > 0: d[colon + 1 .. ^1] else: "")
    if isColourProp(prop):
      result.colours.incl(coloursIn(value, props))
    if prop in timeProps:
      result.seconds = max(result.seconds, secondsIn(value))

proc noteWord(R: var StyleRule, word: string, kind: char) {.role: actor,
    tag: "stats".} =
  ## R: a rule being read   word: a name   kind: what it was written after
  ## (`t` nothing, `#` an id, `.` a class). Files it under tag, id or class.
  if word.len == 0:
    return
  case kind
  of 't':
    R.tag = word.toLowerAscii()
  of '#':
    R.id = word
  else:
    R.classes.add(word)

proc compoundOf(part: string): StyleRule {.role: parser, tag: "stats".} =
  ## part: one comma-free selector. The last box of it as a rule with no
  ## colours yet: its tag, its id and its classes. Selectors with a pseudo
  ## class or an attribute test give an empty rule (tag, id and classes all empty).
  var
    last: string = ""
    word: string = ""
    kind: char = 't'
  result = StyleRule(tag: "", id: "", classes: @[],
    colours: initHashSet[string](), seconds: 0.0)
  for w in part.split({' ', '>', '+', '~', '\t', '\n'}):
    if w.len > 0:
      last = w
  if ':' in last or '[' in last or last == "*":
    return
  for c in last & ".":
    if c in {'.', '#'}:
      result.noteWord(word, kind)
      kind = c
      word = ""
    else:
      word.add(c)

proc addRules(R: var seq[StyleRule], selector: string, colours: HashSet[string],
    seconds: float) {.role: actor, tag: "stats".} =
  ## R: the rules so far   selector: what stood in front of one `{`
  ## colours, seconds: what its body says. One rule for every comma part that
  ## names a tag, an id or a class.
  var
    rule: StyleRule = StyleRule()
  for part in selector.split(','):
    rule = compoundOf(part.strip())
    rule.colours = colours
    rule.seconds = seconds
    if rule.tag.len + rule.id.len + rule.classes.len > 0:
      R.add(rule)

proc styleRulesIn*(css: string): seq[StyleRule] {.role: parser,
    tag: "stats".} =
  ## css: one style sheet. Every rule that names a tag, an id or a class,
  ## with the colours of its fills and edges and the longest time in it.
  var
    plain: string = withoutAtRules(withoutComments(css))
    props: Table[string, string] = customProps(plain)
    at: int = 0
    close: int = 0
    i: int = 0
    body: tuple[colours: HashSet[string], seconds: float] = (
      colours: initHashSet[string](), seconds: 0.0)
  result = @[]
  while i < plain.len and result.len < maxRules:
    at = plain.find('{', i)
    close = (if at >= 0: plain.find('}', at) else: -1)
    if at < 0 or close < 0:
      break
    body = declarationRule(plain[at + 1 ..< close], props)
    if not plain[i ..< at].strip().startsWith("@"):
      result.addRules(plain[i ..< at], body.colours, body.seconds)
    i = close + 1

proc matches(r: StyleRule, tag, id: string, classes: seq[string]): bool
    {.role: parser, tag: "stats".} =
  ## r: a rule   tag, id, classes: one thing. True when every box the rule
  ## names (tag, id, each class) is one the thing has.
  result = (r.tag.len == 0 or r.tag == tag) and (r.id.len == 0 or r.id == id)
  for c in r.classes:
    if c notin classes:
      result = false

proc lookOf*(R: seq[StyleRule], tag, id: string, classes: seq[string]): Look
    {.role: parser, tag: "stats".} =
  ## R: every rule of every style sheet   tag, id, classes: one thing.
  ## What the sheets say about it: the colours of every rule that fits it and
  ## the longest time among them.
  result = emptyLook(R.len > 0)
  for r in R:
    if r.matches(tag, id, classes):
      result.colours.incl(r.colours)
      result.seconds = max(result.seconds, r.seconds)

proc mergeLook*(a, b: Look): Look {.role: helper, tag: "stats".} =
  ## a, b: two looks. Both together: all colours, the longest time.
  result = emptyLook(a.known or b.known)
  result.colours.incl(a.colours)
  result.colours.incl(b.colours)
  result.seconds = max(a.seconds, b.seconds)
