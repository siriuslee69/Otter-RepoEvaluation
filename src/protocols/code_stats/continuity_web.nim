## ================================================================
## | continuity_web.nim  <-  does a press hide its own button?      |
## |   (html + css + js)                                            |
## |---------------------------------------------------------------|
## | A page is a tree of boxes. A click handler hides some boxes    |
## | and shows others. If the button that was pressed sits INSIDE   |
## | a big box the handler hides, the user's finger loses its own   |
## | button: the page teleports them. This reads the three files    |
## | together and says so.                                          |
## ================================================================
##
## The picture it builds
## ---------------------
##
##   index.html                         app.js
##   ┌ section#overview ──────────┐     document.getElementById('open')
##   │  ul ... 13 elements        │       .addEventListener('click', () => {
##   │  [button#open]  ───────────┼──────▶   overview.hidden = true;     <- hides the box
##   └────────────────────────────┘          settings.hidden = false;    <- shows another
##                                        });
##
##   pressed  = button#open                 (the receiver of the listener)
##   hidden   = section#overview, 13 elements
##   inside?  = yes, the button is one of the 13   ->  GOES: a teleport
##
## What is read
## ------------
##   html   every element: tag, id, classes, how many elements sit inside it,
##          whether it is hidden when the page opens, onclick="..." text
##   css    the classes a style sheet hides (ui_depth.hiddenClassesIn)
##   js     click / pointerdown / mousedown listeners, `.onclick = ...`,
##          `const x = document.getElementById('x')` names, and named
##          functions (one level deep, with their string arguments filled in)
##   hides  `.hidden = true`, `.style.display = 'none'`, `.classList.add('hidden')`,
##          `.setAttribute('hidden', ...)`, `.remove()`
##   shows  the same, the other way round
##   loops  `document.querySelectorAll('.page').forEach(p => p.hidden = true)`
##
## Not read (so it can miss a teleport, never invent one from nothing)
## -------------------------------------------------------------------
##   elements a script builds with createElement or innerHTML
##   a listener on the whole page that looks at `event.target`
##   a function whose name comes from a variable
##   a handler that decides at run time what to hide

import std/[os, sets, strutils, tables]

import runePragmas
import ../repo_graph/io_utils
import ./continuity_types
import ./continuity_page

const
  pressEvents: array[5, string] = ["click", "pointerdown", "mousedown",
    "pointerup", "mouseup"]
  identChars: set[char] = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '$', '.'}
  maxPressed: int = 20
    ## A listener put on every `.card` is judged by its first twenty.

type
  JsFunction = object
    params: seq[string]
    body: string

  WebContext = object
    E: seq[Element]
    vars: Table[string, string]
    funcs: Table[string, JsFunction]
    hideClasses: HashSet[string]

  Reach = object
    hide: seq[int]
    show: seq[int]

  Handler = object
    path: string
    line: int
    body: string
    pressed: seq[int]
    pages: seq[string]

# --- small text readers ---------------------------------------------------

proc skipQuoted(S: string, at: int): int {.role: parser, tag: "stats".} =
  ## S: script text   at: index of an opening quote.
  ## The index just after the matching closing quote.
  var
    q: char = S[at]
    i: int = at + 1
  while i < S.len and S[i] != q:
    if S[i] == '\\':
      i = i + 1
    i = i + 1
  result = min(i + 1, S.len)

proc bracketDelta(c: char): int {.role: helper, inline, tag: "stats".} =
  ## c: one character. +1 for an opening bracket, -1 for a closing one.
  result = 0
  if c in {'(', '{', '['}:
    result = 1
  if c in {')', '}', ']'}:
    result = -1

proc matchClose(S: string, open: int): int {.role: parser, tag: "stats".} =
  ## S: script text   open: index of ( { or [.
  ## The index of the bracket that closes it, or -1.
  var
    depth: int = 0
    i: int = open
  result = -1
  while i < S.len:
    if S[i] in {'\'', '"', '`'}:
      i = skipQuoted(S, i)
      continue
    depth = depth + bracketDelta(S[i])
    if depth == 0 and bracketDelta(S[i]) < 0:
      return i
    i = i + 1

proc backDepth(c: char): int {.role: helper, inline, tag: "stats".} =
  ## c: one character, read from the right. +1 for a closing bracket.
  result = 0
  if c in {')', ']'}:
    result = 1
  if c in {'(', '['}:
    result = -1

proc receiverBefore(S: string, at: int): string {.role: parser,
    tag: "stats".} =
  ## S: script text   at: index of a `.` that follows a receiver.
  ## The receiver as written: `document.getElementById('x')`, `panel`.
  var
    i: int = at - 1
    depth: int = 0
  while i >= 0:
    if depth + backDepth(S[i]) < 0:
      break
    depth = depth + backDepth(S[i])
    if depth == 0 and backDepth(S[i]) == 0 and S[i] notin identChars:
      break
    i = i - 1
  result = S[i + 1 ..< max(at, i + 1)]

proc firstLiteral(S: string, start, limit: int): tuple[text: string,
    next: int] {.role: parser, tag: "stats".} =
  ## S: script text   start: where to look   limit: how far.
  ## The first quoted text at or after `start`, and the index after it.
  var
    i: int = start
    stop: int = 0
  result = (text: "", next: -1)
  while i < min(S.len, start + limit):
    if S[i] in {'\'', '"', '`'}:
      stop = skipQuoted(S, i)
      result = (text: S[i + 1 ..< stop - 1], next: stop)
      return
    i = i + 1

proc squeezed(S: string): string {.role: sanitizer, tag: "stats".} =
  ## S: a handler's body. The same text with no spaces, tabs or newlines,
  ## so `x.hidden = true` and `x.hidden=true` read the same.
  result = newStringOfCap(S.len)
  for c in S:
    if c notin {' ', '\t', '\n', '\r'}:
      result.add(c)

proc isIdent(S: string): bool {.role: parser, tag: "stats".} =
  ## S: some text. True when it is one plain name.
  result = S.len > 0 and S[0] notin {'0' .. '9'}
  for c in S:
    if c notin identChars or c == '.':
      result = false

proc findAll(S, key: string): seq[int] {.role: parser, tag: "stats".} =
  ## S: text   key: what to look for. Every index where it starts.
  var
    at: int = S.find(key)
  result = @[]
  while at >= 0:
    result.add(at)
    at = S.find(key, at + 1)

# --- the scripts: names, functions ---------------------------------------------

proc varsIn(js: string): Table[string, string] {.role: parser, tag: "stats".} =
  ## js: one script. `const x = document.getElementById('x');` gives
  ## x -> the text after the equals sign, for every one-line declaration.
  var
    t: string = ""
    eq: int = 0
  result = initTable[string, string]()
  for raw in js.splitLines():
    t = raw.strip()
    eq = t.find('=')
    if (t.startsWith("const ") or t.startsWith("let ") or
        t.startsWith("var ")) and eq > 0 and eq + 1 < t.len and
        t[eq + 1] != '=':
      result[t[t.find(' ') + 1 ..< eq].strip()] = t[eq + 1 .. ^1].strip()
        .strip(chars = {';'})

proc paramsOf(text: string): seq[string] {.role: parser, tag: "stats".} =
  ## text: what stands between the brackets of a parameter list.
  result = @[]
  for p in text.split(','):
    if p.strip().len > 0:
      result.add(p.strip())

proc bodyFrom(js: string, at: int): string {.role: parser, tag: "stats".} =
  ## js: one script   at: index to look from.
  ## The text inside the next `{ ... }`, or "" when a `;` comes first.
  var
    open: int = js.find('{', at)
    semi: int = js.find(';', at)
    stop: int = 0
  result = ""
  if open < 0 or (semi >= 0 and semi < open):
    return
  stop = matchClose(js, open)
  if stop > open:
    result = js[open + 1 ..< stop]

proc arrowName(before: string): string {.role: parser, tag: "stats".} =
  ## before: the text in front of an arrow's parameters, as in
  ## `const open = async `. The name being defined, or "".
  var
    T: seq[string] = before.replace("=", " = ").splitWhitespace()
  result = ""
  if T.len > 0 and T[^1] == "async":
    T.setLen(T.len - 1)
  if T.len >= 2 and T[^1] == "=" and isIdent(T[^2]):
    result = T[^2]

proc arrowAt(js: string, at: int): tuple[name: string, fn: JsFunction]
    {.role: parser, tag: "stats".} =
  ## js: one script   at: index of a `=>`.
  ## The function it belongs to, when it is given a name.
  var
    head: string = js[max(0, at - 160) ..< at].strip()
    open: int = head.rfind('(')
    before: string = ""
    params: string = ""
  result = (name: "", fn: JsFunction(params: @[], body: ""))
  if head.len == 0:
    return
  if head.endsWith(")") and open >= 0:
    before = head[0 ..< open]
    params = head[open + 1 ..< head.high]
  else:
    params = head.splitWhitespace()[^1]
    before = head[0 ..< head.len - params.len]
  result.name = arrowName(before)
  result.fn = JsFunction(params: paramsOf(params), body: bodyFrom(js, at))

proc declaredFunctions(js: string): Table[string, JsFunction] {.role: parser,
    tag: "stats".} =
  ## js: one script. Every `function name(a, b) { ... }` and every
  ## `const name = (a, b) => { ... }`, by name.
  var
    open: int = 0
    stop: int = 0
    name: string = ""
    arrow: tuple[name: string, fn: JsFunction] = (name: "",
      fn: JsFunction(params: @[], body: ""))
  result = initTable[string, JsFunction]()
  for at in findAll(js, "function "):
    open = js.find('(', at)
    stop = js.find(')', open)
    name = js[at + 9 ..< max(at + 9, open)].strip()
    if open > 0 and stop > open and isIdent(name):
      result[name] = JsFunction(params: paramsOf(js[open + 1 ..< stop]),
        body: bodyFrom(js, stop))
  for at in findAll(js, "=>"):
    arrow = arrowAt(js, at)
    if isIdent(arrow.name):
      result[arrow.name] = arrow.fn

# --- selectors -> elements -----------------------------------------------------

proc selectorIn(expr: string, given: Table[string, string]): tuple[kind: char,
    name: string] {.role: parser, tag: "stats".} =
  ## expr: a receiver as written   given: names a caller filled in.
  ## ('i', id) for one element, ('c', class) for every element with it,
  ## (' ', "") when the text names neither.
  var
    lit: tuple[text: string, next: int] = firstLiteral(expr, 0, expr.len)
    piece: string = ""
    inner: string = ""
    open: int = expr.find("getElementById(")
  result = (kind: ' ', name: "")
  if open >= 0:
    inner = expr[open + 15 ..< max(open + 15, expr.find(')', open))]
    result = (kind: 'i', name: (if lit.text.len > 0: lit.text
      else: given.getOrDefault(inner)))
    return
  if "getElementsByClassName(" in expr and lit.text.len > 0:
    return (kind: 'c', name: lit.text)
  if lit.text.len == 0 or lit.text[0] notin {'#', '.'}:
    return
  for part in lit.text.split({' ', '>', '+', '~'}):
    if part.len > 0:
      piece = part
  if piece.len < 2:
    return
  result = (kind: (if piece[0] == '#': 'i' else: 'c'),
    name: piece[1 .. ^1].split({':', '[', '.', '#'})[0])

proc elementsOf(E: seq[Element], kind: char, name: string): seq[int]
    {.role: parser, tag: "stats".} =
  ## E: every element   kind, name: from selectorIn.
  result = @[]
  for i in 0 ..< E.len:
    if (kind == 'i' and E[i].id == name) or
        (kind == 'c' and name in E[i].classes):
      result.add(i)

proc forEachSource(C: WebContext, S: string, at: int,
    given: Table[string, string]): tuple[kind: char, name: string]
    {.role: parser, tag: "stats".} =
  ## C: the page and its names   S: a body   at: where a loop's variable is used
  ## given: names a caller filled in.
  ## What the nearest `.forEach(x => ...)  before `at` loops over.
  var
    k: int = S.rfind(".forEach(", last = at)
    src: string = ""
  result = (kind: ' ', name: "")
  if k < 0:
    return
  src = receiverBefore(S, k)
  result = selectorIn(src, given)
  if result.kind == ' ':
    result = selectorIn(C.vars.getOrDefault(src), given)

proc resolve(C: WebContext, S: string, at: int, expr: string,
    given: Table[string, string]): seq[int] {.role: parser, tag: "stats".} =
  ## C: the page and its names   S: the text the receiver stands in
  ## at: where   expr: the receiver   given: names a caller filled in.
  ## The elements the receiver stands for. A name made by an earlier
  ## `const`, or the variable of a `.forEach(x => ...)`, is followed.
  var
    sel: tuple[kind: char, name: string] = selectorIn(expr, given)
    t: string = expr
  result = @[]
  for _ in 0 ..< 3:
    if sel.kind == ' ' and t in C.vars:
      t = C.vars[t]
      sel = selectorIn(t, given)
  if sel.kind == ' ' and isIdent(t):
    sel = forEachSource(C, S, at, given)
  if sel.kind != ' ':
    result = elementsOf(C.E, sel.kind, sel.name)

# --- what a body hides and shows -------------------------------------------------

const
  opMarks: array[9, string] = [".hidden=true", ".hidden=false",
    ".style.display=", ".classList.add(", ".classList.remove(",
    ".classList.toggle(", ".setAttribute(", ".removeAttribute(", ".remove()"]

proc opAt(C: WebContext, S, key: string, at: int): tuple[hide, show: bool]
    {.role: parser, tag: "stats".} =
  ## C: the page   S: one squeezed body   key: what was found   at: where.
  ## Whether that statement hides its receiver, shows it, or both.
  var
    arg: string = firstLiteral(S, at + key.len, 24).text
  result = (hide: false, show: false)
  case key
  of ".hidden=true":
    result.hide = true
  of ".hidden=false":
    result.show = true
  of ".style.display=":
    result = (hide: arg == "none", show: arg != "none")
  of ".classList.add(":
    result.hide = arg in C.hideClasses
  of ".classList.remove(":
    result.show = arg in C.hideClasses
  of ".classList.toggle(":
    result = (hide: arg in C.hideClasses, show: arg in C.hideClasses)
  of ".setAttribute(":
    result.hide = arg == "hidden"
  of ".removeAttribute(":
    result.show = arg == "hidden"
  else:
    result.hide = not S[max(0, at - 9) ..< at].endsWith("classList")

proc keyedAt(S, key: string): seq[tuple[key: string, at: int]]
    {.role: parser, tag: "stats".} =
  ## S: text   key: what to look for. Every place it stands, with the key.
  result = @[]
  for at in findAll(S, key):
    result.add((key: key, at: at))

proc addUnique(S: var seq[int], more: seq[int]) {.role: helper,
    tag: "stats".} =
  ## S: a list of element numbers   more: more of them. S without repeats.
  for m in more:
    if m notin S:
      S.add(m)

proc mergeReach(R: var Reach, more: Reach) {.role: helper, tag: "stats".} =
  ## R: what has been found   more: what a callee hides and shows.
  R.hide.addUnique(more.hide)
  R.show.addUnique(more.show)

proc opsReach(C: WebContext, S: string, given: Table[string, string]): Reach
    {.role: parser, tag: "stats".} =
  ## C: the page and its names   S: one squeezed body
  ## given: names a caller filled in.
  ## The elements the statements of the body hide and show. Calls are not followed.
  var
    op: tuple[hide, show: bool] = (hide: false, show: false)
    found: seq[int] = @[]
    marks: seq[tuple[key: string, at: int]] = @[]
  result = Reach(hide: @[], show: @[])
  for key in opMarks:
    marks.add(keyedAt(S, key))
  for m in marks:
    op = opAt(C, S, m.key, m.at)
    found = resolve(C, S, m.at, receiverBefore(S, m.at), given)
    if op.hide:
      result.hide.addUnique(found)
    if op.show:
      result.show.addUnique(found)

proc callArgs(S, name: string): seq[string] {.role: parser, tag: "stats".} =
  ## S: one squeezed body   name: a function.
  ## The first string argument of every call to it ("" when there is none).
  var
    close: int = 0
    open: int = 0
  result = @[]
  for at in findAll(S, name & "("):
    open = at + name.len
    close = matchClose(S, open)
    if (at == 0 or S[at - 1] notin identChars) and close > open:
      result.add(firstLiteral(S, open, close - open).text)

proc calleeReach(C: WebContext, S, name: string, fn: JsFunction): Reach
    {.role: parser, tag: "stats".} =
  ## C: the page and its names   S: one squeezed body
  ## name, fn: a function the page declares.
  ## What the body's calls to it hide and show, with the call's string
  ## argument put in place of the function's first parameter.
  var
    given: Table[string, string] = initTable[string, string]()
  result = Reach(hide: @[], show: @[])
  for arg in callArgs(S, name):
    given = initTable[string, string]()
    if fn.params.len > 0 and arg.len > 0:
      given[fn.params[0]] = arg
    result.mergeReach(opsReach(C, squeezed(fn.body), given))

proc reachOf(C: WebContext, body: string): Reach {.role: parser,
    tag: "stats".} =
  ## C: the page and its names   body: one handler's text.
  ## The elements it hides and the elements it shows, own statements first,
  ## then the functions it calls (one level deep).
  var
    S: string = squeezed(body)
  result = opsReach(C, S, initTable[string, string]())
  for name, fn in C.funcs:
    result.mergeReach(calleeReach(C, S, name, fn))

# --- handlers ---------------------------------------------------------------------

proc leadingName(t: string): string {.role: parser, tag: "stats".} =
  ## t: some text. The plain name it starts with, or "".
  var
    i: int = 0
  while i < t.len and t[i] in identChars and t[i] != '.':
    i = i + 1
  result = t[0 ..< i]

proc callbackBody(C: WebContext, js: string, a, b: int): string
    {.role: parser, tag: "stats".} =
  ## C: the page and its names   js: one script   a, b: the span that holds a
  ## callback. The text it runs: a block, an expression, or a named function's body.
  var
    t: string = js[a ..< min(js.len, b)].strip()
    name: string = leadingName(t)
    arrow: int = t.find("=>")
    at: int = 0
  result = ""
  if name.len > 0 and name notin ["function", "async"] and
      not t[name.len .. ^1].strip().startsWith("=>"):
    result = C.funcs.getOrDefault(name).body
    return
  if arrow >= 0 and name != "function":
    at = arrow + 2
  else:
    at = max(0, t.find(')'))
  if t[at .. ^1].strip().startsWith("{"):
    result = bodyFrom(t, at)
  else:
    result = t[at .. ^1].strip()

proc listenersIn(C: WebContext, s: Script): seq[Handler]
    {.role: parser, tag: "stats".} =
  ## C: the page and its names   s: one script.
  ## Every `x.addEventListener('click', ...)`.
  var
    js: string = s.text
    lit: tuple[text: string, next: int] = (text: "", next: -1)
    close: int = 0
    comma: int = 0
  result = @[]
  for at in findAll(js, ".addEventListener("):
    lit = firstLiteral(js, at + 18, 24)
    close = matchClose(js, at + 17)
    comma = js.find(',', max(0, lit.next))
    if lit.text in pressEvents and close > 0 and comma > 0 and comma < close:
      result.add(Handler(path: s.path, line: s.line + js[0 ..< at].count('\n'),
        pages: s.pages,
        body: callbackBody(C, js, comma + 1, close),
        pressed: resolve(C, js, at, receiverBefore(js, at),
          initTable[string, string]())))

proc assignedIn(C: WebContext, s: Script): seq[Handler]
    {.role: parser, tag: "stats".} =
  ## C: the page and its names   s: one script.
  ## Every `x.onclick = ...`.
  var
    js: string = s.text
    start: int = 0
  result = @[]
  for at in findAll(js, ".onclick"):
    start = js.find('=', at)
    if start > 0 and start - at < 12:
      result.add(Handler(path: s.path, line: s.line + js[0 ..< at].count('\n'),
        pages: s.pages,
        body: callbackBody(C, js, start + 1, start + 2000),
        pressed: resolve(C, js, at, receiverBefore(js, at),
          initTable[string, string]())))

proc attributeHandlers(C: WebContext): seq[Handler] {.role: parser,
    tag: "stats".} =
  ## C: the page. A Handler for every element written with `onclick="..."`.
  result = @[]
  for i in 0 ..< C.E.len:
    if C.E[i].onclick.len > 0:
      result.add(Handler(path: C.E[i].path, line: C.E[i].line,
        body: C.E[i].onclick, pressed: @[i], pages: @[C.E[i].path]))

# --- one press, one answer ---------------------------------------------------------

proc roomTaker(C: WebContext, shown: seq[int], x: int): int
    {.role: parser, tag: "stats".} =
  ## C: the page   shown: what the press shows   x: what it hides.
  ## The first shown element that is neither inside x nor around it, and
  ## is not tiny. -1 when nothing takes the room.
  result = -1
  for y in shown:
    if y != x and not isInside(C.E, y, x) and not isInside(C.E, x, y) and
        C.E[y].size >= 3:
      return y

proc verdictOf(C: WebContext, R: Reach, p, x: int): tuple[v: ContinuityVerdict,
    taker: int] {.role: parser, tag: "stats".} =
  ## C: the page   R: what the press hides and shows   p: the pressed
  ## button   x: one element it hides. Where the button stands to it.
  result = (v: cvStays, taker: -1)
  if not isInside(C.E, p, x):
    return
  if isFloating(C.E[x].id & " " & C.E[x].classes.join(" ")):
    result.v = cvClose
  elif C.E[x].size < bigSize:
    result.v = cvSmall
  elif not onScreenAtStart(C.E, p):
    result.v = cvReturn
  else:
    result.taker = roomTaker(C, R.show, x)
    result.v = (if result.taker >= 0: cvGoes else: cvClose)

proc pressFor(C: WebContext, H: Handler, R: Reach, p, x: int):
    ContinuityPress {.role: truthBuilder, tag: "stats".} =
  ## C: the page   H: the handler   R: what it hides and shows
  ## p: the pressed button   x: one element it hides.
  var
    got: tuple[v: ContinuityVerdict, taker: int] = verdictOf(C, R, p, x)
  result = ContinuityPress(kind: "web", path: H.path, line: H.line,
    control: nameOf(C.E[p]), action: "hides " & nameOf(C.E[x]),
    hidden: nameOf(C.E[x]), hiddenAt: C.E[x].path & ":" & $C.E[x].line,
    hiddenSize: C.E[x].size, replacedBy: "", verdict: got.v)
  if got.taker >= 0:
    result.replacedBy = nameOf(C.E[got.taker])

proc pressesFor(C: WebContext, H: Handler, R: Reach, p: int):
    seq[ContinuityPress] {.role: parser, tag: "stats".} =
  ## C: the page   H: the handler   R: what it hides and shows
  ## p: one pressed button. One answer for every element the press hides
  ## that is big, or that holds the button.
  result = @[]
  for x in R.hide:
    if C.E[x].size >= bigSize or isInside(C.E, p, x):
      result.add(pressFor(C, H, R, p, x))

proc onlyIn(C: WebContext, I: seq[int], pages: seq[string]): seq[int]
    {.role: helper, tag: "stats".} =
  ## C: the page and its names   I: element numbers   pages: the pages one
  ## script belongs to (none: every page). The elements that stand on them.
  result = @[]
  for i in I:
    if pages.len == 0 or C.E[i].path in pages:
      result.add(i)

proc pressesOf(C: WebContext, H: Handler): seq[ContinuityPress]
    {.role: parser, tag: "stats".} =
  ## C: the page and its names   H: one handler.
  ## Every answer for the buttons it is put on (the first twenty), counting
  ## only the elements of the pages its script belongs to.
  var
    R: Reach = reachOf(C, H.body)
    P: seq[int] = onlyIn(C, H.pressed, H.pages)
  result = @[]
  R = Reach(hide: onlyIn(C, R.hide, H.pages), show: onlyIn(C, R.show, H.pages))
  for p in P[0 ..< min(P.len, maxPressed)]:
    result.add(pressesFor(C, H, R, p))

# --- the whole tree ------------------------------------------------------------------

proc noteNames(C: var WebContext, text: string) {.role: actor, tag: "stats".} =
  ## C: the names so far   text: one script.
  ## Adds its `const` names and its functions. The first one seen wins.
  for k, v in varsIn(text):
    if k notin C.vars:
      C.vars[k] = v
  for k, f in declaredFunctions(text):
    if k notin C.funcs:
      C.funcs[k] = f

proc contextOf(dir: string, files: seq[string]): tuple[C: WebContext,
    scripts: seq[Script]] {.role: truthBuilder, input: thirdParty,
    tag: "stats".} =
  ## dir: the repository   files: every source file in it.
  ## The pages and what the scripts name, plus the text of every script. A
  ## script file knows which pages load it; one no page loads belongs to all.
  var
    hidden: HashSet[string] = hiddenByStyles(files)
    page: tuple[E: seq[Element], scripts: seq[Script], srcs: seq[string]] =
      (E: @[], scripts: @[], srcs: @[])
    refs: Table[string, seq[string]] = initTable[string, seq[string]]()
    rel: string = ""
  result.C = WebContext(E: @[], vars: initTable[string, string](),
    funcs: initTable[string, JsFunction](), hideClasses: hidden)
  result.scripts = @[]
  for w in hideWords:
    result.C.hideClasses.incl(w)
  for p in files:
    rel = normalizeSlashes(relativePath(p, dir))
    if extensionOf(p) in ["html", "htm"]:
      page = pageOf(readText(p), rel, hidden)
      result.C.E.addPage(page.E)
      result.scripts.add(page.scripts)
      refs.noteRefs(rel, page.srcs)
  for p in files:
    rel = normalizeSlashes(relativePath(p, dir))
    if extensionOf(p) in ["js", "mjs"]:
      result.scripts.add(Script(path: rel, line: 1, text: readText(p),
        pages: refs.getOrDefault(rel)))
  sizesOf(result.C.E)
  for s in result.scripts:
    result.C.noteNames(s.text)

proc handlersOf(C: WebContext, scripts: seq[Script]): seq[Handler]
    {.role: parser, tag: "stats".} =
  ## C: the page and its names   scripts: every script.
  ## Every click handler: listeners, `.onclick =` and `onclick="..."`.
  result = attributeHandlers(C)
  for s in scripts:
    result.add(listenersIn(C, s))
    result.add(assignedIn(C, s))

proc webPressesOf*(dir: string, files: seq[string]): tuple[
    presses: seq[ContinuityPress], handlers: int]
    {.role: metaOrchestrator, input: thirdParty, tag: "stats".} =
  ## dir: the repository   files: every source file in it.
  ## Every click handler of every page, and for each button it is put
  ## on, what the press hides and where the button stands to it.
  var
    ctx: tuple[C: WebContext, scripts: seq[Script]] = contextOf(dir, files)
    H: seq[Handler] = @[]
  result = (presses: @[], handlers: 0)
  if ctx.C.E.len == 0:
    return
  H = handlersOf(ctx.C, ctx.scripts)
  result.handlers = H.len
  for h in H:
    result.presses.add(pressesOf(ctx.C, h))
