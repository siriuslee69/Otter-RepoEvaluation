## ================================================================
## | continuity_owl_read.nim  <-  owlkettle source, read into parts |
## |---------------------------------------------------------------|
## | The reading half of the owlkettle reader: what the source      |
## | text says, before anything is asked of it.                     |
## |                                                                |
## |   1. enums + fields   `View = enum vHome, vReport`             |
## |                       `view*: View`                            |
## |   2. builders         the routines that draw widgets, the      |
## |                       widgets in them, what they insert under  |
## |                       which condition, their style classes     |
## |   3. presses          `proc clicked()` blocks and the (field,  |
## |                       view) each one sets                      |
## |                                                                |
## | continuity_owl_model.nim joins these into one model;           |
## | continuity_owl.nim asks the model its questions.               |
## ================================================================

import std/[sets, strutils, tables]

import runePragmas
import ../repo_graph/types
import ./continuity_guard
import ./continuity_walk
import ./continuity_score

const
  clickProcs: array[4, string] = ["clicked", "activated", "toggled",
    "pressed"]
    ## The owlkettle events that mean "the user pressed this".

type
  ViewTypes* = object
    members*: Table[string, string]
    homes*: Table[string, string]
    fieldEnum*: Table[string, string]

  Inclusion* = object
    callee*: string
    guards*: seq[string]

  Builder* = object
    name*: string
    path*: string
    line*: int
    widgets*: int
    locals*: Table[string, string]
    includes*: seq[Inclusion]
    assigns*: HashSet[string]
    calls*: seq[string]
    kinds*: CountTable[string]
    classes*: seq[string]
    motion*: float

  Effect* = object
    field*: string
    member*: string

  PressSite* = object
    owner*: string
    path*: string
    line*: int
    control*: string
    classes*: seq[string]
    effect*: Effect

# --- 1. enums and fields ---------------------------------------------------------

proc cutComment(s: string): string {.role: sanitizer, tag: "stats".} =
  ## s: a line of Nim. The same line without its `#` comment.
  var
    at: int = s.find('#')
  result = (if at >= 0: s[0 ..< at] else: s)

proc leadingIdent*(s: string): string {.role: parser, tag: "stats".} =
  ## s: some text. The name it starts with, or "".
  var
    i: int = 0
  while i < s.len and (s[i].isAlphaNumeric() or s[i] == '_'):
    i = i + 1
  result = s[0 ..< i]

proc membersOf(text: string): seq[string] {.role: parser, tag: "stats".} =
  ## text: the part of an enum that lists its members, commas and all.
  result = @[]
  for part in text.split(','):
    if leadingIdent(part.strip()).len > 0:
      result.add(leadingIdent(part.strip()))

proc enumAt(L: seq[string], i: int): tuple[name: string, members: seq[string]]
    {.role: parser, tag: "stats".} =
  ## L: the lines of a file   i: one of them.
  ## The enum declared there (`View* = enum` and the lines under it), or an
  ## empty name when the line declares none.
  var
    t: string = cutComment(L[i]).strip()
    at: int = t.find("= enum")
    base: int = indentOf(L[i])
    j: int = i + 1
  result = (name: "", members: @[])
  if at <= 0:
    return
  result.name = leadingIdent(t)
  result.members = membersOf(t[at + 6 .. ^1])
  while j < L.len and (L[j].strip().len == 0 or indentOf(L[j]) > base):
    result.members.add(membersOf(cutComment(L[j]).strip()))
    j = j + 1

proc fieldsAt(t: string): seq[tuple[name, typeName: string]] {.role: parser,
    tag: "stats".} =
  ## t: one stripped line. `view*: View` gives (view, View);
  ## `a, b: View` gives both.
  var
    colon: int = t.find(':')
    names: string = ""
    typeName: string = ""
  result = @[]
  if colon <= 0 or t.startsWith("proc ") or '(' in t[0 ..< colon]:
    return
  names = t[0 ..< colon]
  typeName = leadingIdent(t[colon + 1 .. ^1].strip())
  for n in names.split(','):
    if leadingIdent(n.strip()).len > 0 and typeName.len > 0:
      result.add((name: leadingIdent(n.strip()), typeName: typeName))

proc noteEnum(T: var ViewTypes, name: string, members: seq[string])
    {.role: actor, tag: "stats".} =
  ## T: the views found so far   name: an enum   members: its members.
  ## The first member is the start; every member remembers its enum.
  T.homes[name] = members[0]
  for m in members:
    T.members[m] = name

proc noteFile(T: var ViewTypes, raw: var Table[string, string],
    L: seq[string]) {.role: actor, tag: "stats".} =
  ## T: the views found so far   raw: field -> its type name, every field
  ## L: the lines of one file. Adds the enums and the fields it declares.
  var
    e: tuple[name: string, members: seq[string]] = (name: "", members: @[])
  for i in 0 ..< L.len:
    e = enumAt(L, i)
    if e.name.len > 0 and e.members.len > 0:
      T.noteEnum(e.name, e.members)
    for f in fieldsAt(cutComment(L[i]).strip()):
      raw[f.name] = f.typeName

proc viewTypesOf*(texts: seq[seq[string]]): ViewTypes {.role: truthBuilder,
    tag: "stats".} =
  ## texts: the lines of every Nim file.
  ## Every enum (its members, and which one is first) and every state field
  ## whose type is one of them.
  var
    raw: Table[string, string] = initTable[string, string]()
  result = ViewTypes(members: initTable[string, string](),
    homes: initTable[string, string](), fieldEnum: initTable[string, string]())
  for L in texts:
    result.noteFile(raw, L)
  for name, typeName in raw:
    if typeName in result.homes:
      result.fieldEnum[name] = typeName

# --- 2. builders ---------------------------------------------------------------------

proc isWidgetLine(t: string): bool {.role: parser, tag: "stats".} =
  ## t: one stripped line. True when it names a widget: `Box:`, `Label`,
  ## `Overlay {.expand: true.}:`, `Button(...):`.
  var
    name: string = leadingIdent(t)
    rest: string = t[name.len .. ^1].strip()
  result = name.len > 0 and name[0].isUpperAscii() and
    name notin ["StyleClass", "Style"] and
    (rest == "" or rest == ":" or rest.startsWith("{") or
      (rest.startsWith("(") and rest.endsWith(":")))

proc nameBefore(t: string, i: int): string {.role: parser, tag: "stats".} =
  ## t: one statement   i: index of a `(`. The name written just in front of it.
  var
    start: int = i
  while start > 0 and (t[start - 1].isAlphaNumeric() or t[start - 1] == '_'):
    start = start - 1
  result = t[start ..< i]

proc callsIn(t: string): seq[string] {.role: parser, tag: "stats".} =
  ## t: one statement. The name in front of every `(`.
  var
    name: string = ""
  result = @[]
  for i in 0 ..< t.len:
    name = (if t[i] == '(' and i > 0: nameBefore(t, i) else: "")
    if name.len > 0:
      result.add(name)

proc localOf(t: string): tuple[name, expr: string] {.role: parser,
    tag: "stats".} =
  ## t: one stripped statement. `bare: bool = M.view in {vReport}` gives
  ## (bare, `M.view in {vReport}`); anything else gives an empty name.
  var
    at: int = t.find(" = ")
    lhs: string = ""
    rhs: string = ""
  result = (name: "", expr: "")
  if at <= 0:
    return
  lhs = t[0 ..< at].strip()
  for w in ["var ", "let ", "const "]:
    if lhs.startsWith(w):
      lhs = lhs[w.len .. ^1].strip()
  rhs = cutComment(t[at + 3 .. ^1]).strip()
  if leadingIdent(lhs.strip(chars = {'*'})).len > 0 and
      lhs[0].isLowerAscii() and lhs != "result" and rhs.len > 0 and
      not rhs.endsWith(":") and not lhs.contains('.'):
    result = (name: leadingIdent(lhs), expr: rhs)

proc assignedFields(L: seq[string], T: ViewTypes): HashSet[string]
    {.role: parser, tag: "stats".} =
  ## L: the body of a routine   T: the views.
  ## The state fields (of a view type) the routine writes to.
  var
    at: int = 0
    lhs: string = ""
  result = initHashSet[string]()
  for line in L:
    at = line.find(" = ")
    lhs = (if at > 0: line[0 ..< at].strip() else: "")
    if lhs.contains('.') and lhs.split('.')[^1] in T.fieldEnum:
      result.incl(lhs.split('.')[^1])

proc inclusionsIn(g: GuardedLine, names: HashSet[string], self: string):
    seq[Inclusion] {.role: parser, tag: "stats".} =
  ## g: one statement with its conditions   names: every builder's name
  ## self: the routine it stands in. The builders it inserts.
  result = @[]
  for c in callsIn(g.text):
    if c in names and c != self:
      result.add(Inclusion(callee: c, guards: g.guards))

proc classesIn*(t: string): seq[string] {.role: parser, tag: "stats".} =
  ## t: one statement. The names written as `StyleClass("...")`.
  var
    at: int = t.find("StyleClass(\"")
    stop: int = 0
  result = @[]
  while at >= 0:
    stop = t.find('"', at + 12)
    if stop > at:
      result.add(t[at + 12 ..< stop])
    at = (if stop > at: t.find("StyleClass(\"", stop) else: -1)

const
  motionWords: array[6, string] = ["Revealer", "Crossfade", "Stack", "Motion",
    "transition", "Transition"]
    ## Words that say a view changes with a transition in the toolkit.
  motionNominal: float = 0.2
    ## The time taken for a transition whose length is not written in the
    ## source (GTK's own stack transition is about 200 ms).

proc mentionsMotion(line: string): bool {.role: parser, tag: "stats".} =
  ## line: one line. True when it names a transition widget or setting.
  result = false
  for w in motionWords:
    if w in line:
      result = true

proc digitsAfter(s: string): string {.role: parser, tag: "stats".} =
  ## s: some text. The digits it starts with (after leading spaces).
  var
    t: string = s.strip()
    i: int = 0
  while i < t.len and t[i] in {'0' .. '9'}:
    i = i + 1
  result = t[0 ..< i]

proc millisIn(line: string): int {.role: parser, tag: "stats".} =
  ## line: one line. The number after `durationMs =` (or `transitionDuration =`,
  ## `duration =`), in milliseconds; -1 when there is none.
  var
    at: int = -1
    eq: int = 0
    digits: string = ""
  result = -1
  for key in ["durationMs", "transitionDuration", "duration"]:
    at = max(at, line.find(key))
  eq = (if at >= 0: line.find('=', at) else: -1)
  digits = (if eq >= 0: digitsAfter(line[eq + 1 .. ^1]) else: "")
  if digits.len > 0 and digits.len < 7:
    result = parseInt(digits)

proc motionIn(L: seq[string]): float {.role: parser, tag: "stats".} =
  ## L: the body of a routine. The longest transition it sets, in seconds: the
  ## written length, or a nominal one when it only names a transition widget.
  ## -1 when it has none.
  var
    found: bool = false
    best: int = 0
  for line in L:
    found = found or mentionsMotion(line)
    best = max(best, millisIn(line))
  result = (if best > 0: best.float / 1000.0
    elif found: motionNominal else: notMeasured)

proc noteClasses(b: var Builder, t: string) {.role: actor, tag: "stats".} =
  ## b: a builder   t: one statement. Remembers each style class it names.
  for c in classesIn(t):
    if c notin b.classes:
      b.classes.add(c)

proc builderOf*(f: FunctionInfo, names: HashSet[string], T: ViewTypes): Builder
    {.role: truthBuilder, tag: "stats".} =
  ## f: one routine   names: every builder's name   T: the views.
  ## What it draws and inserts, with the conditions over each insert.
  var
    local: tuple[name, expr: string] = (name: "", expr: "")
  result = Builder(name: f.name, path: f.sourcePath, line: f.lineStart,
    widgets: 0, locals: initTable[string, string](), includes: @[],
    assigns: assignedFields(f.bodyLines, T), calls: f.calls,
    kinds: initCountTable[string](), classes: @[], motion: motionIn(f.bodyLines))
  for g in guardedLines(f.bodyLines):
    if isWidgetLine(g.text):
      result.widgets = result.widgets + 1
      result.kinds.inc(leadingIdent(g.text))
    result.noteClasses(g.text)
    local = localOf(g.text)
    if local.name.len > 0 and local.name notin result.locals:
      result.locals[local.name] = local.expr
    result.includes.add(inclusionsIn(g, names, f.name))

proc isBuilder*(f: FunctionInfo): bool {.role: parser, tag: "stats".} =
  ## f: one routine. True when it draws widgets.
  result = f.returnType == "Widget"
  for line in f.bodyLines:
    if line.strip() == "gui:" or line.strip().endsWith(" gui:"):
      result = true

proc helperOf*(f: FunctionInfo, T: ViewTypes): HelperFn {.role: parser,
    tag: "stats".} =
  ## f: one routine   T: the views.
  ## When it takes one view and answers with one expression
  ## (`result = v in {a, b}`): that expression. Otherwise an empty one.
  var
    first: string = ""
  result = HelperFn(param: "", expr: "")
  if f.sockets.len < 1 or f.sockets[0].typeName notin T.homes or
      f.bodyLines.len == 0:
    return
  first = f.bodyLines[0].strip()
  if first.startsWith("result = "):
    result = HelperFn(param: f.sockets[0].name, expr: first[9 .. ^1].strip())

proc takeAssigns(B: var seq[Builder], byName: Table[string, int], i: int)
    {.role: actor, tag: "stats".} =
  ## B: every routine   byName: where each one is   i: one of them.
  ## It writes every view field that a routine it calls writes.
  var
    k: int = 0
  for c in B[i].calls:
    k = byName.getOrDefault(c, -1)
    if k >= 0 and k != i:
      B[i].assigns.incl(B[k].assigns)

proc closeAssigns*(B: var seq[Builder], byName: Table[string, int])
    {.role: actor, tag: "stats".} =
  ## B: every routine   byName: where each one is.
  ## A routine that calls a routine that writes a view field writes it too.
  ## Three rounds reach a helper behind a helper.
  for _ in 0 ..< 3:
    for i in 0 ..< B.len:
      takeAssigns(B, byName, i)

# --- 3. presses ------------------------------------------------------------------------

proc directEffect(line: string, T: ViewTypes): Effect {.role: parser,
    tag: "stats".} =
  ## line: one statement   T: the views.
  ## `M.view = vX` gives (view, vX); any other line gives an empty field.
  var
    at: int = line.find(" = ")
    lhs: string = ""
    field: string = ""
    rhs: string = ""
  result = Effect(field: "", member: "")
  if at <= 0:
    return
  lhs = line[0 ..< at].strip()
  field = lhs.split('.')[^1]
  rhs = leadingIdent(line[at + 3 .. ^1].strip())
  if lhs.contains('.') and field in T.fieldEnum and
      T.members.getOrDefault(rhs) == T.fieldEnum[field]:
    result = Effect(field: field, member: rhs)

proc membersIn(text: string, T: ViewTypes): seq[string] {.role: parser,
    tag: "stats".} =
  ## text: the arguments of a call   T: the views. The view members named in it.
  var
    word: string = ""
  result = @[]
  for w in text.split({'(', ')', ',', ' ', '{', '}'}):
    word = w.split('.')[^1]
    if word in T.members:
      result.add(word)

proc effectsOfMember(T: ViewTypes, assigns: HashSet[string], m: string):
    seq[Effect] {.role: parser, tag: "stats".} =
  ## T: the views   assigns: the view fields a routine writes   m: a member
  ## it is given. The fields of that member's enum the routine can set.
  result = @[]
  for f in assigns:
    if T.fieldEnum[f] == T.members[m]:
      result.add(Effect(field: f, member: m))

proc effectsOfCall(T: ViewTypes, assigns: HashSet[string], args: string):
    seq[Effect] {.role: parser, tag: "stats".} =
  ## T: the views   assigns: the view fields a routine writes   args: the text
  ## after its `(`. What the call sets: every member in the arguments, in each
  ## field of its enum the routine writes.
  result = @[]
  for m in membersIn(args, T):
    result.add(effectsOfMember(T, assigns, m))

proc effectsOfLine(line: string, T: ViewTypes, B: seq[Builder],
    byName: Table[string, int]): seq[Effect] {.role: parser, tag: "stats".} =
  ## line: one statement of a click handler   T: the views
  ## B: every routine   byName: where each one is.
  ## What it sets: `M.view = vX`, or a call to a routine that writes a view
  ## field and is given a member as an argument.
  var
    k: int = 0
    open: int = 0
    e: Effect = directEffect(line, T)
  result = @[]
  if e.field.len > 0:
    result.add(e)
  for c in callsIn(line):
    k = byName.getOrDefault(c, -1)
    open = line.find(c & "(")
    if k >= 0 and open >= 0:
      result.add(effectsOfCall(T, B[k].assigns, line[open + c.len .. ^1]))

proc effectsIn(text: string, T: ViewTypes, B: seq[Builder],
    byName: Table[string, int]): seq[Effect] {.role: parser, tag: "stats".} =
  ## text: the lines of one click handler. Every (field, view) it sets.
  result = @[]
  for line in text.splitLines():
    result.add(effectsOfLine(line, T, B, byName))

proc isClickProc(t: string): bool {.role: parser, tag: "stats".} =
  ## t: one stripped line. True for `proc clicked(...)` and its kin.
  result = t.startsWith("proc ") and leadingIdent(t[5 .. ^1]) in clickProcs

proc afterHeader(t: string): string {.role: parser, tag: "stats".} =
  ## t: `proc clicked() = M.view = vX`. What follows the `=` of the header.
  var
    close: int = t.find(')')
    eq: int = (if close >= 0: t.find('=', close) else: -1)
  result = (if eq >= 0: t[eq + 1 .. ^1].strip() else: "")

proc handlerAt(L: seq[string], i: int): string {.role: parser, tag: "stats".} =
  ## L: the lines of a routine   i: the line of a `proc clicked`.
  ## The text of that handler: the rest of its line and the lines under it.
  var
    base: int = indentOf(L[i])
    j: int = i + 1
  result = afterHeader(L[i].strip()) & "\n"
  while j < L.len and (L[j].strip().len == 0 or indentOf(L[j]) > base):
    result.add(L[j] & "\n")
    j = j + 1

proc quotedIn(t: string): string {.role: parser, tag: "stats".} =
  ## t: `text = "Report"`. What stands inside the quotes, when the line holds
  ## nothing but that one quoted text (`"a" & b` is not a name).
  var
    a: int = t.find('"')
    b: int = t.find('"', a + 1)
  result = (if a >= 0 and b == t.high and t[a + 1 ..< b].strip().len > 1:
    t[a + 1 ..< b].strip() else: "")

proc styleIn(t: string): string {.role: parser, tag: "stats".} =
  ## t: one stripped line. `style = [StyleClass("wl-chip")]` gives `wl-chip`.
  var
    a: int = t.find("StyleClass(\"")
    b: int = (if a >= 0: t.find('"', a + 12) else: -1)
  result = (if a >= 0 and b > a: t[a + 12 ..< b] else: "")

proc labelFor(L: seq[string], i: int): string {.role: parser, tag: "stats".} =
  ## L: the lines of a routine   i: the line of a `proc clicked`.
  ## The button's name: the `text = "..."` or `tooltip = "..."` beside it;
  ## else the widget's name and its first style class (`Button .wl-chip`).
  var
    base: int = indentOf(L[i])
    k: int = i - 1
    t: string = ""
    named: string = ""
    style: string = ""
  while k >= 0 and (L[k].strip().len == 0 or indentOf(L[k]) >= base):
    t = L[k].strip()
    if (t.startsWith("text = ") or t.startsWith("tooltip = ")) and
        named.len == 0:
      named = quotedIn(t)
    if t.startsWith("style = ") and style.len == 0:
      style = styleIn(t)
    k = k - 1
  result = "\"" & named & "\""
  if named.len == 0:
    result = (if k >= 0: leadingIdent(L[k].strip()) else: "button") &
      (if style.len > 0: " ." & style else: "")

proc classesFor(L: seq[string], i: int): seq[string] {.role: parser,
    tag: "stats".} =
  ## L: the lines of a routine   i: the line of a `proc clicked`.
  ## The style classes written beside the handler, in the same widget.
  var
    base: int = indentOf(L[i])
    k: int = i - 1
    t: string = ""
  result = @[]
  while k >= 0 and (L[k].strip().len == 0 or indentOf(L[k]) >= base):
    t = L[k].strip()
    if t.startsWith("style = "):
      result.add(classesIn(t))
    k = k - 1

proc sitesOfHandler(f: FunctionInfo, i: int, T: ViewTypes, B: seq[Builder],
    byName: Table[string, int]): seq[PressSite] {.role: parser,
    tag: "stats".} =
  ## f: one routine   i: the line (in its body) of a click handler
  ## T: the views   B: every routine   byName: where each one is.
  ## One PressSite for every view the handler sets.
  result = @[]
  for e in effectsIn(handlerAt(f.bodyLines, i), T, B, byName):
    result.add(PressSite(owner: f.name, path: f.sourcePath,
      line: f.lineEnd - f.bodyLines.len + 1 + i,
      control: labelFor(f.bodyLines, i), classes: classesFor(f.bodyLines, i),
      effect: e))

proc sitesOf*(f: FunctionInfo, T: ViewTypes, B: seq[Builder],
    byName: Table[string, int]): seq[PressSite] {.role: parser,
    tag: "stats".} =
  ## f: one routine. Every (button, view it sets) pair written in it.
  result = @[]
  for i in 0 ..< f.bodyLines.len:
    if isClickProc(f.bodyLines[i].strip()):
      result.add(sitesOfHandler(f, i, T, B, byName))

