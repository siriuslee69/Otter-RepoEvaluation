## ================================================================
## | continuity_owl.nim  <-  does a press hide its own button?      |
## |   (owlkettle, Nim)                                             |
## |---------------------------------------------------------------|
## | An owlkettle menu has no boxes to hide. It is drawn again from |
## | a state every time something changes:                          |
## |                                                                |
## |   button "Report"  --click-->  M.view = vReport                |
## |                                    │                           |
## |                                    ▼                           |
## |   menu(M) is drawn again:   if not bare: insert(headerBar(M))  |
## |                             bare = M.view in {vReport}         |
## |                                    │                           |
## |                                    ▼                           |
## |   headerBar is gone, and the "Report" button was in it.        |
## ================================================================
##
## So the reading goes the other way round from the web one:
##
##   1. enums + fields   `View = enum vHome, vReport`   `view*: View`
##   2. builders         every routine that draws widgets, the widgets in it,
##                       and which other builders it inserts under which
##                       `if` / `case` / early `return`   (continuity_walk)
##   3. presses          `proc clicked()` blocks, and the (field, view) they
##                       set: directly, or through a helper such as
##                       `M.toggleView(vReport)`
##   4. questions        for each press: with the field set to that view,
##                       is the builder holding the button still inserted?
##                       (continuity_guard) And at the start, with the field
##                       at the first member of its enum?
##
## The verdicts are the ones of continuity_types.nim. The "start" of an
## enum is its first member, the way Nim numbers it (`vHome` above).
##
## Not read (so it can miss a teleport, never invent one from nothing)
## -------------------------------------------------------------------
##   a button built by a helper that is handed the click as a parameter
##   a view picked by something other than an enum (a string, a number)
##   conditions on more than the view (they stay "unknown", which is
##     treated as "might hold": the check then says nothing)
##   a builder inserted from a routine that is not a builder

import std/[os, sets, strutils, tables]

import runePragmas
import ../repo_graph/types
import ../repo_graph/nim_parser
import ../repo_graph/io_utils
import ./continuity_types
import ./continuity_guard
import ./continuity_walk

const
  clickProcs: array[4, string] = ["clicked", "activated", "toggled",
    "pressed"]
    ## The owlkettle events that mean "the user pressed this".
  searchDepth: int = 10
    ## How many builders up a path is followed.

type
  ViewTypes = object
    members: Table[string, string]
    homes: Table[string, string]
    fieldEnum: Table[string, string]

  Inclusion = object
    callee: string
    guards: seq[string]

  Builder = object
    name: string
    path: string
    line: int
    widgets: int
    locals: Table[string, string]
    includes: seq[Inclusion]
    assigns: HashSet[string]
    calls: seq[string]

  Effect = object
    field: string
    member: string

  PressSite = object
    owner: string
    path: string
    line: int
    control: string
    effect: Effect

  Edge = object
    parent: string
    callee: string
    guards: seq[string]

  Model = object
    T: ViewTypes
    B: seq[Builder]
    byName: Table[string, int]
    funcs: Table[string, HelperFn]
    presses: seq[PressSite]
    sizes: Table[string, int]
    edges: seq[Edge]
    up: Table[string, seq[Edge]]
    memberSet: HashSet[string]
    fieldSet: HashSet[string]

# --- 1. enums and fields ---------------------------------------------------------

proc cutComment(s: string): string {.role: sanitizer, tag: "stats".} =
  ## s: a line of Nim. The same line without its `#` comment.
  var
    at: int = s.find('#')
  result = (if at >= 0: s[0 ..< at] else: s)

proc leadingIdent(s: string): string {.role: parser, tag: "stats".} =
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

proc noteFile(T: var ViewTypes, raw: var Table[string, string],
    L: seq[string]) {.role: actor, tag: "stats".} =
  ## T: the views found so far   raw: field -> its type name, every field
  ## L: the lines of one file. Adds the enums and the fields it declares.
  var
    e: tuple[name: string, members: seq[string]] = (name: "", members: @[])
  for i in 0 ..< L.len:
    e = enumAt(L, i)
    if e.name.len > 0 and e.members.len > 0:
      T.homes[e.name] = e.members[0]
      for m in e.members:
        T.members[m] = e.name
    for f in fieldsAt(cutComment(L[i]).strip()):
      raw[f.name] = f.typeName

proc viewTypesOf(texts: seq[seq[string]]): ViewTypes {.role: truthBuilder,
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

proc callsIn(t: string): seq[string] {.role: parser, tag: "stats".} =
  ## t: one statement. The name in front of every `(`.
  var
    start: int = 0
  result = @[]
  for i in 0 ..< t.len:
    if t[i] == '(' and i > 0:
      start = i
      while start > 0 and (t[start - 1].isAlphaNumeric() or
          t[start - 1] == '_'):
        start = start - 1
      if start < i:
        result.add(t[start ..< i])

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

proc builderOf(f: FunctionInfo, names: HashSet[string], T: ViewTypes): Builder
    {.role: truthBuilder, tag: "stats".} =
  ## f: one routine   names: every builder's name   T: the views.
  ## What it draws and inserts, with the conditions over each insert.
  var
    local: tuple[name, expr: string] = (name: "", expr: "")
  result = Builder(name: f.name, path: f.sourcePath, line: f.lineStart,
    widgets: 0, locals: initTable[string, string](), includes: @[],
    assigns: assignedFields(f.bodyLines, T), calls: f.calls)
  for g in guardedLines(f.bodyLines):
    if isWidgetLine(g.text):
      result.widgets = result.widgets + 1
    local = localOf(g.text)
    if local.name.len > 0 and local.name notin result.locals:
      result.locals[local.name] = local.expr
    for c in callsIn(g.text):
      if c in names and c != f.name:
        result.includes.add(Inclusion(callee: c, guards: g.guards))

proc isBuilder(f: FunctionInfo): bool {.role: parser, tag: "stats".} =
  ## f: one routine. True when it draws widgets.
  result = f.returnType == "Widget"
  for line in f.bodyLines:
    if line.strip() == "gui:" or line.strip().endsWith(" gui:"):
      result = true

proc helperOf(f: FunctionInfo, T: ViewTypes): HelperFn {.role: parser,
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

proc closeAssigns(B: var seq[Builder], byName: Table[string, int])
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
      for m in membersIn(line[open + c.len .. ^1], T):
        result.add(effectsOfMember(T, B[k].assigns, m))

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
      control: labelFor(f.bodyLines, i), effect: e))

proc sitesOf(f: FunctionInfo, T: ViewTypes, B: seq[Builder],
    byName: Table[string, int]): seq[PressSite] {.role: parser,
    tag: "stats".} =
  ## f: one routine. Every (button, view it sets) pair written in it.
  result = @[]
  for i in 0 ..< f.bodyLines.len:
    if isClickProc(f.bodyLines[i].strip()):
      result.add(sitesOfHandler(f, i, T, B, byName))

# --- 4. the model and its questions --------------------------------------------------------

proc sizeOf(M: Model, name: string, seen: var HashSet[string]): int
    {.role: math, tag: "stats".} =
  ## M: the menu's parts   name: a builder   seen: builders counted already.
  ## Its widgets plus the widgets of every builder it inserts.
  var
    k: int = M.byName.getOrDefault(name, -1)
  result = 0
  if k < 0 or name in seen:
    return
  seen.incl(name)
  result = M.B[k].widgets
  for inc in M.B[k].includes:
    result = result + sizeOf(M, inc.callee, seen)

proc addEdges(M: var Model, b: Builder) {.role: actor, tag: "stats".} =
  ## M: the menu's parts   b: one builder. Notes every builder it inserts.
  var
    e: Edge = Edge()
  for inc in b.includes:
    e = Edge(parent: b.name, callee: inc.callee, guards: inc.guards)
    M.edges.add(e)
    if inc.callee notin M.up:
      M.up[inc.callee] = @[]
    M.up[inc.callee].add(e)

proc modelOf(dir: string, files: seq[string]): Model {.role: truthBuilder,
    input: thirdParty, tag: "stats".} =
  ## dir: the repository   files: its Nim files.
  ## Everything the questions need: views, builders, helpers, presses, sizes.
  var
    texts: seq[seq[string]] = @[]
    F: seq[FunctionInfo] = parseNimFiles(dir, files)
    names: HashSet[string] = initHashSet[string]()
    h: HelperFn = HelperFn(param: "", expr: "")
    seen: HashSet[string] = initHashSet[string]()
  for p in files:
    texts.add(readLinesSafe(p))
  for k in 0 ..< F.len:
    F[k].sourcePath = normalizeSlashes(relativePath(F[k].sourcePath, dir))
  result = Model(T: viewTypesOf(texts), B: @[], byName: initTable[string, int](),
    funcs: initTable[string, HelperFn](), presses: @[],
    sizes: initTable[string, int](), edges: @[],
    up: initTable[string, seq[Edge]](), memberSet: initHashSet[string](),
    fieldSet: initHashSet[string]())
  for f in F:
    if isBuilder(f):
      names.incl(f.name)
  for f in F:
    result.B.add(builderOf(f, names, result.T))
    if f.name notin result.byName:
      result.byName[f.name] = result.B.high
    h = helperOf(f, result.T)
    if h.param.len > 0:
      result.funcs[f.name] = h
  closeAssigns(result.B, result.byName)
  for f in F:
    result.presses.add(sitesOf(f, result.T, result.B, result.byName))
  for b in result.B:
    result.addEdges(b)
  for m, _ in result.T.members:
    result.memberSet.incl(m)
  for f, _ in result.T.fieldEnum:
    result.fieldSet.incl(f)
  for b in result.B:
    seen = initHashSet[string]()
    result.sizes[b.name] = sizeOf(result, b.name, seen)

proc edgeTri(M: Model, e: Edge, assign: Table[string, string]): Tri
    {.role: parser, tag: "stats".} =
  ## M: the menu's parts   e: one "inserts" line   assign: which view each
  ## field is set to. Whether the insert happens, for that question.
  var
    env: GuardEnv = GuardEnv(members: M.memberSet, fields: M.fieldSet,
      assigned: assign, locals: initTable[string, string](), funcs: M.funcs)
  result = tTrue
  if e.parent in M.byName:
    env.locals = M.B[M.byName[e.parent]].locals
  for g in e.guards:
    result = triAnd(result, evalGuard(g, env))

proc climb(M: Model, name: string, trail: seq[Edge], seen: seq[string],
    O: var seq[seq[Edge]]) {.role: actor, tag: "stats".} =
  ## M: the menu's parts   name: a builder   trail: the inserts passed so far
  ## (nearest first)   seen: builders on the way   O: every finished trail.
  ## Walks upward, through every builder that inserts `name`, to the top.
  var
    ups: seq[Edge] = M.up.getOrDefault(name)
    open: seq[Edge] = @[]
  if trail.len >= searchDepth:
    return
  for e in ups:
    if e.parent notin seen:
      open.add(e)
  if open.len == 0:
    O.add(trail)
    return
  for e in open:
    climb(M, e.parent, trail & e, seen & e.parent, O)

proc topHidden(M: Model, trail: seq[Edge], assign: Table[string, string]): int
    {.role: parser, tag: "stats".} =
  ## M: the menu's parts   trail: inserts from the button's builder upward
  ## assign: which view each field is set to.
  ## The index of the highest insert on the trail that does not happen, or -1.
  result = -1
  for i in countdown(trail.high, 0):
    if edgeTri(M, trail[i], assign) == tFalse:
      return i

proc dropsAndAppears(M: Model, atHome, atV: Table[string, string]):
    tuple[dropped, appears: seq[tuple[name: string, size: int]]]
    {.role: parser, tag: "stats".} =
  ## M: the menu's parts   atHome, atV: two assumptions about the views.
  ## The big builders that stand at the start and are gone at atV, and the
  ## big builders that are not there at the start and are at atV.
  var
    home: Tri = tUnknown
    away: Tri = tUnknown
    size: int = 0
  result = (dropped: @[], appears: @[])
  for e in M.edges:
    home = edgeTri(M, e, atHome)
    away = edgeTri(M, e, atV)
    size = M.sizes.getOrDefault(e.callee)
    if size < bigSize:
      continue
    if home != tFalse and away == tFalse:
      result.dropped.add((name: e.callee, size: size))
    if home == tFalse and away != tFalse:
      result.appears.add((name: e.callee, size: size))

proc biggest(R: seq[tuple[name: string, size: int]]): tuple[name: string,
    size: int] {.role: parser, tag: "stats".} =
  ## R: names with sizes. The one with the most widgets, or an empty name.
  result = (name: "", size: 0)
  for r in R:
    if r.size > result.size:
      result = r

proc assignments(M: Model, s: PressSite): tuple[home, away: Table[string,
    string]] {.role: parser, tag: "stats".} =
  ## M: the menu's parts   s: one press. The view each field has at the
  ## start (its enum's first member) and after the press.
  result = (home: initTable[string, string](),
    away: initTable[string, string]())
  result.home[s.effect.field] = M.T.homes[M.T.fieldEnum[s.effect.field]]
  result.away[s.effect.field] = s.effect.member

proc judge(M: Model, s: PressSite): tuple[ok: bool, p: ContinuityPress]
    {.role: parser, tag: "stats".} =
  ## M: the menu's parts   s: one click handler that sets a view.
  ## Where the button stands to what its press hides. Not ok when the press
  ## hides nothing big at all.
  var
    A: tuple[home, away: Table[string, string]] = assignments(M, s)
    trails: seq[seq[Edge]] = @[]
    goneAll: bool = true
    shownHome: bool = false
    wrapper: string = ""
    DA: tuple[dropped, appears: seq[tuple[name: string, size: int]]] =
      dropsAndAppears(M, A.home, A.away)
    seen: seq[string] = @[s.owner]
    top: int = -1
    big: tuple[name: string, size: int] = (name: "", size: 0)
    repl: tuple[name: string, size: int] = biggest(DA.appears)
  climb(M, s.owner, @[], seen, trails)
  for t in trails:
    top = topHidden(M, t, A.away)
    if top < 0:
      goneAll = false
    elif wrapper.len == 0:
      wrapper = t[top].callee
    if topHidden(M, t, A.home) < 0:
      shownHome = true
  result.p = ContinuityPress(kind: "owl", path: s.path, line: s.line,
    control: s.control, action: "sets " & s.effect.field & " = " &
    s.effect.member, hidden: "", hiddenAt: "", hiddenSize: 0, replacedBy: "",
    verdict: cvStays)
  result.ok = true
  if not goneAll:
    big = biggest(DA.dropped)
    result.ok = big.name.len > 0
    wrapper = big.name
  elif not shownHome:
    result.p.verdict = cvReturn
  elif M.sizes.getOrDefault(wrapper) < bigSize:
    result.p.verdict = cvSmall
  else:
    result.p.verdict = (if repl.name.len > 0: cvGoes else: cvClose)
    result.p.replacedBy = repl.name
  result.p.hidden = wrapper
  result.p.hiddenSize = M.sizes.getOrDefault(wrapper)
  if wrapper in M.byName:
    result.p.hiddenAt = M.B[M.byName[wrapper]].path & ":" &
      $M.B[M.byName[wrapper]].line

# --- the whole tree ------------------------------------------------------------------------------

proc mentionsOwlkettle(files: seq[string]): bool {.role: dataFetcher,
    tag: "stats".} =
  ## files: the Nim files. True when any of them is written for owlkettle.
  result = false
  for p in files:
    if "owlkettle" in readFile(p):
      return true

proc owlPressesOf*(dir: string, files: seq[string]): tuple[
    presses: seq[ContinuityPress], handlers: int]
    {.role: metaOrchestrator, input: thirdParty, tag: "stats".} =
  ## dir: the repository   files: every source file in it.
  ## Every owlkettle click handler that sets a view, and for each: whether its
  ## button is still inserted once the view is set.
  var
    nim: seq[string] = @[]
    M: Model = Model()
    j: tuple[ok: bool, p: ContinuityPress] = (ok: false,
      p: ContinuityPress())
  result = (presses: @[], handlers: 0)
  for p in files:
    if extensionOf(p) == "nim":
      nim.add(p)
  if nim.len == 0 or not mentionsOwlkettle(nim):
    return
  M = modelOf(dir, nim)
  result.handlers = M.presses.len
  for s in M.presses:
    j = judge(M, s)
    if j.ok:
      result.presses.add(j.p)
