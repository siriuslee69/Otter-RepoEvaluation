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
## The reading goes the other way round from the web one, in three files:
##
##   continuity_owl_read.nim    enums + fields, builders, click handlers
##   continuity_owl_model.nim   one model: who inserts whom, sizes, kinds
##   continuity_owl.nim         (this file) the questions asked of the model:
##                              with the field set to that view, is the builder
##                              holding the button still inserted? (continuity_guard)
##                              And at the start, with the field at the first
##                              member of its enum?
##
## The verdicts are the ones of continuity_types.nim, and each press that has an
## old and a new builder gets the three metrics of continuity_score.nim.
## The "start" of an enum is its first member, the way Nim numbers it.
##
## Not read (so it can miss a teleport, never invent one from nothing)
## -------------------------------------------------------------------
##   a button built by a helper that is handed the click as a parameter
##   a view picked by something other than an enum (a string, a number)
##   conditions on more than the view (they stay "unknown", which is
##     treated as "might hold": the check then says nothing)
##   a builder inserted from a routine that is not a builder
##   style rules that live in Nim strings instead of .css files (the colour
##     and the transition of such a rule are then not measured)

import std/[os, strutils, tables]

import runePragmas
import ../repo_graph/io_utils
import ./continuity_types
import ./continuity_guard
import ./continuity_page
import ./continuity_style
import ./continuity_score
import ./continuity_owl_model

const
  searchDepth: int = 10
    ## How many builders up a path is followed.

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
  if trail.len >= searchDepth or O.len >= maxTrails:
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
    DropsAppears {.role: parser, tag: "stats".} =
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

proc climbOne(M: Model, cur: string, depth: var Table[string, int],
    queue: var seq[string]) {.role: actor, tag: "stats".} =
  ## M: the menu's parts   cur: a builder   depth: steps up from the start
  ## queue: builders still to visit. Adds every builder that inserts `cur`.
  for e in M.up.getOrDefault(cur):
    if e.parent notin depth:
      depth[e.parent] = depth[cur] + 1
      queue.add(e.parent)

proc upDepths(M: Model, name: string): Table[string, int] {.role: parser,
    tag: "stats".} =
  ## M: the menu's parts   name: a builder.
  ## Every builder above it (one that inserts it, or inserts one that does)
  ## and how many steps up that is.
  var
    queue: seq[string] = @[name]
    i: int = 0
  result = {name: 0}.toTable
  while i < queue.len and queue.len < 500:
    climbOne(M, queue[i], result, queue)
    i = i + 1

proc hopsBuilders(M: Model, a, b: string): int {.role: parser, tag: "stats".} =
  ## M: the menu's parts   a, b: two builders. The steps from a up to a builder
  ## that holds both and down to b: 2 for neighbours, 10 when nothing holds both.
  var
    da: Table[string, int] = upDepths(M, a)
    db: Table[string, int] = upDepths(M, b)
  result = 10
  for k, d in da:
    if k in db:
      result = min(result, d + db[k])

proc looksOf(M: Model, classes: seq[string]): Look {.role: parser,
    tag: "stats".} =
  ## M: the menu's parts   classes: style class names.
  ## What the style sheets say about the classes taken together.
  result = emptyLook(M.rules.len > 0)
  for c in classes:
    result = mergeLook(result, lookOf(M.rules, "", "", @[c]))

proc addNew(R: var seq[string], more: seq[string]) {.role: helper,
    tag: "stats".} =
  ## R: a list of names   more: more names. R without repeats.
  for m in more:
    if m notin R:
      R.add(m)

proc faceClasses(M: Model, name: string): seq[string] {.role: parser,
    tag: "stats".} =
  ## M: the menu's parts   name: a builder. The style classes it names and the
  ## ones its direct inserts name: where a panel draws the edge it shows.
  var
    k: int = M.byName.getOrDefault(name, -1)
    j: int = 0
  result = @[]
  if k < 0:
    return
  result = M.B[k].classes
  for inc in M.B[k].includes:
    j = M.byName.getOrDefault(inc.callee, -1)
    if j >= 0:
      result.addNew(M.B[j].classes)

proc secondsOfPress(M: Model, s: PressSite, old, new: string): float
    {.role: parser, tag: "stats".} =
  ## M: the menu's parts   s: a press   old, new: the builders that go and come.
  ## The longest transition the style sheets or the toolkit's motion widgets
  ## give the pressed button, the old builder or the new one; -1 when neither
  ## a style sheet nor a motion widget was found.
  var
    css: float = max(looksOf(M, s.classes).seconds,
      max(looksOf(M, faceClasses(M, old)).seconds,
        looksOf(M, faceClasses(M, new)).seconds))
    motion: float = max(M.motions.getOrDefault(old, notMeasured),
      max(M.motions.getOrDefault(new, notMeasured),
        M.motions.getOrDefault(s.owner, notMeasured)))
  result = notMeasured
  if M.rules.len > 0 or motion >= 0.0:
    result = max(css, motion)

proc partsOf(M: Model, s: PressSite, old, new, root: string, teleport: bool):
    ScoreParts {.role: parser, tag: "stats".} =
  ## M: the menu's parts   s: a press   old, new: the builders that go and come
  ## root: the builder that holds the whole screen   teleport: the button goes.
  ## What the three metrics are made of for this press.
  var
    button: Look = looksOf(M, s.classes)
    panel: Look = looksOf(M, faceClasses(M, new))
  result = noParts()
  result.kept = keptOf(M.sizes.getOrDefault(old), M.sizes.getOrDefault(root))
  result.alike = likeness(M.bags.getOrDefault(old), M.bags.getOrDefault(new))
  result.joined = joinedOf(button.colours, panel.colours, button.known)
  result.near = nearOf(hopsBuilders(M, s.owner, new))
  result.seconds = secondsOfPress(M, s, old, new)
  result.teleport = teleport

proc judge(M: Model, s: PressSite, DA: DropsAppears): tuple[ok: bool,
    p: ContinuityPress] {.role: parser, tag: "stats".} =
  ## M: the menu's parts   s: one click handler that sets a view
  ## DA: what the view it sets drops and brings (from dropsAndAppears).
  ## Where the button stands to what its press hides. Not ok when the press
  ## hides nothing big at all.
  var
    A: tuple[home, away: Table[string, string]] = assignments(M, s)
    trails: seq[seq[Edge]] = @[]
    goneAll: bool = true
    shownHome: bool = false
    wrapper: string = ""
    seen: seq[string] = @[s.owner]
    top: int = -1
    big: tuple[name: string, size: int] = (name: "", size: 0)
    repl: tuple[name: string, size: int] = biggest(DA.appears)
    root: string = s.owner
  climb(M, s.owner, @[], seen, trails)
  if trails.len > 0 and trails[0].len > 0:
    root = trails[0][^1].parent
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
  if result.ok and repl.name.len > 0 and wrapper.len > 0 and
      result.p.verdict in {cvGoes, cvStays}:
    result.p.replacedBy = repl.name
    result.p.scored = true
    result.p.score = scoreOf(partsOf(M, s, wrapper, repl.name, root,
      result.p.verdict == cvGoes))

# --- the whole tree ------------------------------------------------------------------------------

proc fileMentions(p: string): bool {.role: dataFetcher, tag: "stats".} =
  ## p: one Nim file. True when it names owlkettle; false when it cannot be read.
  result = false
  try:
    result = "owlkettle" in readFile(p)
  except OSError, IOError:
    result = false

proc mentionsOwlkettle(files: seq[string]): bool {.role: dataFetcher,
    tag: "stats".} =
  ## files: the Nim files. True when any of them is written for owlkettle.
  result = false
  for p in files:
    if fileMentions(p):
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
    cache: Table[string, DropsAppears] = initTable[string, DropsAppears]()
    key: string = ""
    A: tuple[home, away: Table[string, string]] = (
      home: initTable[string, string](), away: initTable[string, string]())
  result = (presses: @[], handlers: 0)
  for p in files:
    if extensionOf(p) == "nim" and getFileSize(p) <= maxFileBytes:
      nim.add(p)
  if nim.len == 0 or not mentionsOwlkettle(nim):
    return
  M = modelOf(dir, nim, styleRulesOf(files))
  result.handlers = M.presses.len
  for s in M.presses:
    key = s.effect.field & ":" & s.effect.member
    if key notin cache:
      A = assignments(M, s)
      cache[key] = dropsAndAppears(M, A.home, A.away)
    j = judge(M, s, cache[key])
    if j.ok:
      result.presses.add(j.p)
