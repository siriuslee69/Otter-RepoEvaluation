## ================================================================
## | continuity_owl_model.nim  <-  the menu as one model            |
## |---------------------------------------------------------------|
## | What continuity_owl_read.nim found, joined: every builder by   |
## | name, who inserts whom (and under which condition), how big    |
## | each builder is, what it holds by kind, and its transitions.   |
## |                                                                |
## |   menu ──▶ body ──▶ homeColumns          size 12               |
## |        └─▶ headerBar (if not bare)        size 12               |
## ================================================================

import std/[os, sets, tables]

import runePragmas
import ../repo_graph/types
import ../repo_graph/nim_parser
import ../repo_graph/io_utils
import ./continuity_guard
import ./continuity_style
import ./continuity_score
import ./continuity_owl_read
export continuity_owl_read

type
  Edge* = object
    parent*: string
    callee*: string
    guards*: seq[string]

  DropsAppears* = tuple[dropped, appears: seq[tuple[name: string, size: int]]]
    ## What setting one view takes off the screen and what it brings,
    ## as builders with their sizes.
  Model* = object
    T*: ViewTypes
    B*: seq[Builder]
    byName*: Table[string, int]
    funcs*: Table[string, HelperFn]
    presses*: seq[PressSite]
    sizes*: Table[string, int]
    edges*: seq[Edge]
    up*: Table[string, seq[Edge]]
    memberSet*: HashSet[string]
    fieldSet*: HashSet[string]
    rules*: seq[StyleRule]
    bags*: Table[string, CountTable[string]]
    motions*: Table[string, float]

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

proc countClass(T: var CountTable[string], M: Model, c: string)
    {.role: actor, tag: "stats".} =
  ## T: what has been counted   M: the menu's parts   c: a style class.
  ## Counts the class and the colours the style sheets give it.
  T.inc("c:" & c)
  for col in lookOf(M.rules, "", "", @[c]).colours:
    T.inc("k:" & col)

proc addBag(T: var CountTable[string], more: CountTable[string])
    {.role: actor, tag: "stats".} =
  ## T: what has been counted   more: another count. Adds it in.
  for key, n in more:
    T.inc(key, n)

proc bagOf(M: Model, name: string, seen: var HashSet[string]):
    CountTable[string] {.role: parser, tag: "stats".} =
  ## M: the menu's parts   name: a builder   seen: builders counted already.
  ## What it draws, counted by kind: its widget kinds, its style classes and
  ## their colours, and everything it inserts.
  var
    k: int = M.byName.getOrDefault(name, -1)
  result = initCountTable[string]()
  if k < 0 or name in seen:
    return
  seen.incl(name)
  for kind, n in M.B[k].kinds:
    result.inc("w:" & kind, n)
  for c in M.B[k].classes:
    countClass(result, M, c)
  for inc in M.B[k].includes:
    result.addBag(bagOf(M, inc.callee, seen))

proc motionOf(M: Model, name: string, seen: var HashSet[string]): float
    {.role: parser, tag: "stats".} =
  ## M: the menu's parts   name: a builder   seen: builders counted already.
  ## The longest transition it or anything it inserts sets; -1 when none.
  var
    k: int = M.byName.getOrDefault(name, -1)
  result = notMeasured
  if k < 0 or name in seen:
    return
  seen.incl(name)
  result = M.B[k].motion
  for inc in M.B[k].includes:
    result = max(result, motionOf(M, inc.callee, seen))

proc modelOf*(dir: string, files: seq[string], rules: seq[StyleRule]): Model
    {.role: truthBuilder, input: thirdParty, tag: "stats".} =
  ## dir: the repository   files: its Nim files   rules: its style sheets.
  ## Everything the questions need: views, builders, helpers, presses, sizes,
  ## and what each builder holds by kind.
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
    fieldSet: initHashSet[string](), rules: rules,
    bags: initTable[string, CountTable[string]](),
    motions: initTable[string, float]())
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
  for b in result.B:
    seen = initHashSet[string]()
    result.bags[b.name] = bagOf(result, b.name, seen)
    seen = initHashSet[string]()
    result.motions[b.name] = motionOf(result, b.name, seen)

