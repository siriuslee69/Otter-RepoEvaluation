## ==============================================================
## | shape.nim  <-  what a routine is built like                |
## |------------------------------------------------------------|
## | Two routines can be written by different people, in         |
## | different files, under different names, and still be the    |
## | same routine. This file finds those.                        |
## |                                                             |
## | It does it by measuring the *shape* of a routine rather     |
## | than reading what it says. Shape means things like:          |
## |                                                             |
## |     how long is it                                          |
## |     how many things does it take in                         |
## |     how many variables does it set up                       |
## |     how many loops, and how deeply are they stacked         |
## |     how many forks in the road (if / case)                  |
## |     what does it hand back                                  |
## |                                                             |
## | Those numbers are handed to Fylgia, which places each       |
## | routine in a room so that alike routines stand together     |
## | (see `vector_space.nim` for how the room works).            |
## |                                                             |
## |   parseTree ─► shapeOf ─► spaceOf ─┬─► duplicatesOf         |
## |                                    └─► cloudOf              |
## |                                                             |
## | A note on honesty: Nim's real compiler builds a tree of the |
## | program before running it, and comparing those trees would  |
## | be the exact way to do this. Otter reads source as lines,   |
## | not as a tree, so what follows is a close stand-in: every   |
## | line is boiled down to one letter for what it does, and     |
## | the resulting strings are compared. It catches renamed      |
## | copies and retyped copies, and it will not catch two        |
## | routines that reach the same result by different means.     |
## ==============================================================

import std/[algorithm, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import otterPragmas

# Fylgia holds the room-and-distance maths, and is reached by a path
# relative to *this file* rather than through the module search path.
# That matters because Guldur compiles this file without Otter's own
# `config.nims` ever running, so anything the search path was told
# would be missing there. A relative path resolves the same way no
# matter which repository started the build.
#
#   submodules/Fylgia-Utils   the pinned copy, when Otter builds alone
#   ../Fylgia-Utils           a sibling clone, used while several of
#                             these repositories are worked on at once
when defined(otterFylgiaSubmodule):
  import "../../../submodules/Fylgia-Utils/src/protocols/math/vector_space"
else:
  import "../../../../Fylgia-Utils/src/protocols/math/vector_space"

const
  shapeDims*: array[13, string] = [
    "length", "inputs", "set up vars", "constants", "loops",
    "loop depth", "forks", "calls", "literals", "assignments",
    "hand-backs", "what it returns", "kinds of input"
  ]
    ## The measurements taken of every routine, in the order they are
    ## written into a vector. Renaming one of these renames a label on
    ## a chart; reordering them silently changes every distance, so
    ## they are written once, here.
  skeletonCap*: int = 160
    ## Longest boiled-down routine kept. Past this the shape is
    ## already decided and the comparison only gets slower.
  duplicateFloor*: float = 0.72
    ## A pair scoring under this is not reported. Set by hand against
    ## this repository: at 0.72 renamed copies show up and merely
    ## similar helpers do not.
  prefilterFloor*: float = 0.55
    ## Pairs further apart than this in the room are never compared
    ## line by line. This is what keeps a big repository from taking
    ## minutes: the cheap test throws out almost every pair first.
  duplicatesShown*: int = 40
    ## How many pairs travel to a window. The rest are counted.
  shapeFloorLines*: int = 5
    ## A routine boiling down to fewer letters than this is too small
    ## to have a shape worth comparing. Two three-line comparators are
    ## always "the same routine" and saying so is noise, not a finding.
  cloudRadius*: float = 0.18
    ## How far a clump reaches in the room. Wider than this and most
    ## of a repository lands in one clump, which tells nobody anything.
  cloudFloorMembers*: int = 3
    ## Fewer routines than this is not a clump, it is a coincidence.

type
  FunctionShape* {.role: truthState, metaTags: {tagStats}.} = object
    ## One routine, measured. Everything here is a plain count so that
    ## a person can check any of it by hand against the source.
    id*: string
    name*: string
    path*: string
    module*: string
    declKind*: string
    returnType*: string
    skeleton*: string
      ## The routine with every line replaced by one letter for what
      ## that line does. See `skeletonOf`.
    paramSig*: string
      ## The types taken in, in order, lowered. Two routines with the
      ## same shape but a different `paramSig` are the generics
      ## candidates: same work, different base type.
    line*: int
    lines*: int
    params*: int
    initVars*: int
    consts*: int
    loops*: int
    loopDepth*: int
    branches*: int
    calls*: int
    literals*: int
    assigns*: int
    returns*: int
    retKind*: int
    inputKind*: int
    exported*: bool
    isTest*: bool

  DuplicatePair* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Two routines that look like the same routine twice.
    ##
    ##   score      how alike, 0..1, the number to trust
    ##   closeness  how near they stand in the room
    ##   shapeMatch how much of their line-by-line shape lines up
    ##   nameMatch  how much of their names overlap
    ##   hint       what could be done about it, in plain words
    aId*: string
    aName*: string
    aPath*: string
    bId*: string
    bName*: string
    bPath*: string
    hint*: string
    aLine*: int
    bLine*: int
    score*: float
    closeness*: float
    shapeMatch*: float
    nameMatch*: float
    sameModule*: bool
    sameParams*: bool

  CloudPoint* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One routine as a dot to draw.
    id*: string
    name*: string
    path*: string
    role*: string
    x*: float
    y*: float
    lines*: int

  CloudGroup* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One clump of routines in the cloud. A routine may appear in
    ## more than one clump when it sits in the overlap.
    id*: string
    label*: string
    x*: float
    y*: float
    radius*: float
    members*: seq[string]

  ShapeReport* {.role: truthState, metaTags: {tagStats}.} = object
    ## Everything this file works out about one repository.
    dims*: seq[string]
    shapes*: seq[FunctionShape]
    duplicates*: seq[DuplicatePair]
    duplicateCount*: int
    points*: seq[CloudPoint]
    groups*: seq[CloudGroup]

proc lowerType*(s: string): string {.role: sanitizer, metaTags: {tagStats}.} =
  ## s <- a type as it was written. Stripped down to the bare name, so
  ## that `var seq[string]` and `seq[ string ]` read the same.
  result = s.strip().toLowerAscii()
  result = result.replace("var ", "").replace("ref ", "")
  result = result.replace("ptr ", "").replace("lent ", "")
  result = result.replace("openarray", "seq").replace("openArray", "seq")
  result = result.replace(" ", "")

proc returnKind*(s: string): int {.role: parser, metaTags: {tagStats}.} =
  ## s <- what a routine hands back.
  ##
  ##   0 nothing       1 a number        2 a piece of text
  ##   3 a list        4 a yes/no        5 something built here
  var
    t: string = lowerType(s)
  result = 5
  if t.len == 0 or t == "void":
    result = 0
  elif t == "bool":
    result = 4
  elif t.startsWith("int") or t.startsWith("uint") or
      t.startsWith("float") or t == "byte" or t == "char":
    result = 1
  elif t == "string" or t == "cstring":
    result = 2
  elif t.startsWith("seq") or t.startsWith("array") or
      t.startsWith("table") or t.startsWith("hashset"):
    result = 3

proc inputKindOf*(A: seq[FunctionSocket]): int {.role: parser,
    metaTags: {tagStats}.} =
  ## A <- the connections of one routine.
  ##
  ## One number standing for the mixture taken in, so that a routine
  ## reading numbers and one reading whole objects do not land in the
  ## same spot merely because they take the same count of things.
  ##
  ##   0 takes nothing   1 plain values   2 lists   3 things it changes
  ##
  ## The types are read off the sockets and not off `params`, because
  ## `params` holds only the names a routine gave its arguments; the
  ## types live on the sockets beside them.
  var
    t: string = ""
    hasList: bool = false
    hasVar: bool = false
    n: int = 0
  result = 0
  for row in A:
    if row.direction == sdOutput:
      continue
    n = n + 1
    if row.direction == sdVarInput:
      hasVar = true
    t = lowerType(row.typeName)
    if t.startsWith("seq") or t.startsWith("array") or
        t.startsWith("table") or t.startsWith("hashset"):
      hasList = true
  if n == 0:
    return
  result = 1
  if hasList:
    result = 2
  if hasVar:
    result = 3

proc paramTypesOf*(A: seq[FunctionSocket]): string {.role: parser,
    metaTags: {tagStats}.} =
  ## A <- the connections of one routine.
  ##
  ## Only the types taken in survive, joined by commas: `int,string`.
  ## What the routine hands back is left out, so that two routines
  ## taking the same things are seen as taking the same things even
  ## when they return different ones.
  var
    parts: seq[string] = @[]
  for row in A:
    if row.direction == sdOutput:
      continue
    parts.add(lowerType(row.typeName))
  result = parts.join(",")

proc lineLetter*(s: string): char {.role: parser, metaTags: {tagStats}.} =
  ## s <- one line of a routine's body.
  ##
  ## Boils that line down to one letter for what it does. This is what
  ## makes two copies of the same routine comparable even after every
  ## name in one of them has been changed:
  ##
  ##   F for-loop     W while-loop   I if        E else / elif
  ##   C case         O of           R hands a value back
  ##   V sets up a variable          A changes a variable
  ##   K calls something else        T try       X raise
  ##   .  anything else worth a line
  var
    t: string = s.strip()
  result = '.'
  if t.len == 0 or t.startsWith("#"):
    return '\0'
  if t.startsWith("for "):
    return 'F'
  if t.startsWith("while "):
    return 'W'
  if t.startsWith("elif ") or t.startsWith("else"):
    return 'E'
  if t.startsWith("if "):
    return 'I'
  if t.startsWith("case "):
    return 'C'
  if t.startsWith("of "):
    return 'O'
  if t.startsWith("try") or t.startsWith("except") or t.startsWith("finally"):
    return 'T'
  if t.startsWith("raise ") or t.startsWith("quit"):
    return 'X'
  if t.startsWith("return") or t.startsWith("result"):
    return 'R'
  if t.startsWith("var ") or t.startsWith("let ") or t.startsWith("const "):
    return 'V'
  if '=' in t and not ("==" in t):
    return 'A'
  if '(' in t:
    return 'K'

proc skeletonOf*(A: seq[string]): string {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A <- a routine's body, line by line. The whole routine as a short
  ## string of letters, blank and comment lines dropped.
  var
    c: char = '.'
  result = ""
  for row in A:
    c = lineLetter(row)
    if c != '\0':
      result.add(c)
    if result.len >= skeletonCap:
      return

proc countIndentOf(s: string): int {.inline, role: helper,
    metaTags: {tagStats}.} =
  ## s <- one line. How far it is pushed in from the left.
  result = 0
  while result < s.len and s[result] == ' ':
    result = result + 1

proc shapeOf*(f: FunctionInfo, root: string): FunctionShape
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## f <- one parsed routine   root <- the repository folder
  ##
  ## Everything is counted in one walk over the body, because two
  ## walks over the same lines is two chances to disagree.
  var
    t: string = ""
    base: int = -1
    indent: int = 0
    depth: int = 0
    inLoop: seq[int] = @[]
    seen: HashSet[string] = initHashSet[string]()
    rel: string = f.sourcePath
  if root.len > 0 and rel.startsWith(root):
    rel = rel[root.len .. ^1]
  if rel.startsWith("/"):
    rel = rel[1 .. ^1]
  result = FunctionShape(id: f.id, name: f.name, path: rel,
    module: f.modulePath, declKind: f.declKind, returnType: f.returnType,
    skeleton: skeletonOf(f.bodyLines),
    paramSig: paramTypesOf(f.sockets),
    line: f.lineStart, lines: f.lineEnd - f.lineStart + 1,
    params: f.params.len, initVars: 0, consts: 0, loops: 0, loopDepth: 0,
    branches: 0, calls: 0, literals: 0, assigns: 0, returns: 0,
    retKind: returnKind(f.returnType), inputKind: inputKindOf(f.sockets),
    exported: f.isExported, isTest: false)
  if result.lines < 1:
    result.lines = 1
  for row in f.bodyLines:
    t = row.strip()
    if t.len == 0 or t.startsWith("#"):
      continue
    indent = countIndentOf(row)
    if base < 0:
      base = indent
    # A loop closes as soon as a later line is no longer pushed in
    # past the line the loop itself started on.
    while inLoop.len > 0 and indent <= inLoop[^1]:
      discard inLoop.pop()
    if t.startsWith("for ") or t.startsWith("while "):
      result.loops = result.loops + 1
      inLoop.add(indent)
      depth = inLoop.len
      if depth > result.loopDepth:
        result.loopDepth = depth
    if t.startsWith("if ") or t.startsWith("elif ") or
        t.startsWith("case ") or t.startsWith("of ") or
        t.startsWith("when "):
      result.branches = result.branches + 1
    if t.startsWith("var ") or t.startsWith("let "):
      result.initVars = result.initVars + 1
    if t.startsWith("const "):
      result.consts = result.consts + 1
    if t.startsWith("return") or t.startsWith("result"):
      result.returns = result.returns + 1
    if '=' in t and not ("==" in t) and not t.startsWith("var ") and
        not t.startsWith("let ") and not t.startsWith("const "):
      result.assigns = result.assigns + 1
    if '"' in t or t.contains("0x"):
      result.literals = result.literals + 1
  for row in f.calls:
    if not seen.containsOrIncl(row.toLowerAscii()):
      result.calls = result.calls + 1
  result.isTest = "/tests/" in ("/" & rel) or rel.startsWith("tests/") or
    f.name.toLowerAscii().startsWith("test")

proc vectorOf*(s: FunctionShape): seq[float] {.role: parser,
    metaTags: {tagStats}.} =
  ## s <- one measured routine, as the list of numbers the room wants.
  ## The order here must match `shapeDims`.
  result = @[s.lines.float, s.params.float, s.initVars.float,
    s.consts.float, s.loops.float, s.loopDepth.float, s.branches.float,
    s.calls.float, s.literals.float, s.assigns.float, s.returns.float,
    s.retKind.float, s.inputKind.float]

proc spaceOf*(A: seq[FunctionShape]): VectorSpace {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A <- every measured routine. The room, already rescaled so that
  ## a line count cannot drown out a loop count.
  result = newVectorSpace(shapeDims)
  for row in A:
    result.addPoint(row.id, row.name, vectorOf(row))
  result.rescale()

proc sequenceMatch*(a, b: string): float {.role: math,
    metaTags: {tagStats}.} =
  ## a, b <- two boiled-down routines.
  ##
  ## How much of the two runs in the same order, 0..1. This is the
  ## longest run of letters that appears in both without reordering,
  ## measured against the longer of the two:
  ##
  ##   a = V I R K R
  ##   b = V I K R
  ##        \ \   \
  ##   both  V I   R   -> 3 shared of 5 longest -> 0.60
  var
    prev: seq[int] = @[]
    cur: seq[int] = @[]
    i: int = 0
    j: int = 0
    n: int = 0
  result = 0.0
  if a.len == 0 or b.len == 0:
    return
  j = 0
  while j <= b.len:
    prev.add(0)
    cur.add(0)
    j = j + 1
  i = 1
  while i <= a.len:
    j = 1
    while j <= b.len:
      if a[i - 1] == b[j - 1]:
        cur[j] = prev[j - 1] + 1
      else:
        cur[j] = max(prev[j], cur[j - 1])
      j = j + 1
    j = 0
    while j <= b.len:
      prev[j] = cur[j]
      j = j + 1
    i = i + 1
  n = max(a.len, b.len)
  result = prev[b.len].float / n.float

proc nameMatch*(a, b: string): float {.role: math, metaTags: {tagStats}.} =
  ## a, b <- two routine names.
  ##
  ## Names are cut at every capital letter and underscore first, so
  ## `parseUserName` and `parse_user_id` are seen to share two words
  ## of three rather than being called wholly different.
  var
    A: HashSet[string] = initHashSet[string]()
    B: HashSet[string] = initHashSet[string]()
    word: string = ""
    both: int = 0
    either: int = 0
  result = 0.0
  for ch in a:
    if ch == '_' or ch.isUpperAscii():
      if word.len > 0:
        A.incl(word.toLowerAscii())
      word = ""
    if ch != '_':
      word.add(ch)
  if word.len > 0:
    A.incl(word.toLowerAscii())
  word = ""
  for ch in b:
    if ch == '_' or ch.isUpperAscii():
      if word.len > 0:
        B.incl(word.toLowerAscii())
      word = ""
    if ch != '_':
      word.add(ch)
  if word.len > 0:
    B.incl(word.toLowerAscii())
  if A.len == 0 or B.len == 0:
    return
  both = (A * B).len
  either = (A + B).len
  if either > 0:
    result = both.float / either.float

proc hintFor*(a, b: FunctionShape, sameParams: bool): string
    {.role: helper, metaTags: {tagStats}.} =
  ## a, b <- the two routines of one reported pair.
  ## What a person could do about it, said plainly.
  result = "Two routines built alike. Worth a look."
  if sameParams and a.module == b.module:
    result = "Same shape, same types, same module. One of these can " &
      "almost certainly go, and its callers point at the other."
    return
  if not sameParams and a.module == b.module:
    result = "Same shape, different types, same module. This is the " &
      "case a generic routine was made for: write it once with the " &
      "type as a parameter."
    return
  if sameParams:
    result = "Same shape and same types in two different modules. If " &
      "both are kept, they will drift apart. Move one into a shared " &
      "module."
    return
  result = "Same shape, different types, different modules. A generic " &
    "routine in a shared module would cover both."

proc byScore(a, b: DuplicatePair): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b <- two reported pairs, best match first.
  result = cmp(b.score, a.score)
  if result == 0:
    result = cmp(a.aId, b.aId)

proc duplicatesOf*(A: seq[FunctionShape], S: VectorSpace):
    tuple[pairs: seq[DuplicatePair], total: int] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A <- every measured routine   S <- the room they were placed in
  ##
  ## Every pair is looked at, but only cheaply: two routines standing
  ## far apart in the room are dropped before their lines are ever
  ## compared. What survives is scored three ways and mixed:
  ##
  ##   half   how near they stand         (all the counts at once)
  ##   a third how much of their shape lines up (the letters)
  ##   a sixth how much of their names overlap
  ##
  ## Names count for little on purpose: a copied routine is usually
  ## renamed, and two routines sharing a word are usually unrelated.
  var
    found: seq[DuplicatePair] = @[]
    row: DuplicatePair
    close: float = 0.0
    shape: float = 0.0
    names: float = 0.0
    score: float = 0.0
    same: bool = false
    i: int = 0
    j: int = 0
  result = (pairs: @[], total: 0)
  if A.len != S.points.len:
    return
  while i < A.len:
    j = i + 1
    while j < A.len:
      close = likeness(S.points[i], S.points[j])
      if close < prefilterFloor:
        j = j + 1
        continue
      # A one-line routine has no shape worth comparing; two of them
      # would otherwise score a perfect match against each other.
      if A[i].skeleton.len < shapeFloorLines or A[j].skeleton.len < shapeFloorLines:
        j = j + 1
        continue
      shape = sequenceMatch(A[i].skeleton, A[j].skeleton)
      names = nameMatch(A[i].name, A[j].name)
      score = close * 0.5 + shape * 0.34 + names * 0.16
      if score >= duplicateFloor:
        same = A[i].paramSig == A[j].paramSig
        row = DuplicatePair(aId: A[i].id, aName: A[i].name,
          aPath: A[i].path, bId: A[j].id, bName: A[j].name,
          bPath: A[j].path, hint: hintFor(A[i], A[j], same),
          aLine: A[i].line, bLine: A[j].line, score: score,
          closeness: close, shapeMatch: shape, nameMatch: names,
          sameModule: A[i].module == A[j].module, sameParams: same)
        found.add(row)
      j = j + 1
    i = i + 1
  found.sort(byScore)
  result.total = found.len
  if found.len > duplicatesShown:
    found.setLen(duplicatesShown)
  result.pairs = found

proc cloudOf*(A: seq[FunctionShape], S: VectorSpace, R: Table[string, string]):
    tuple[points: seq[CloudPoint], groups: seq[CloudGroup]]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## A <- every measured routine   S <- the room
  ## R <- what each routine's role is, by id, for colouring the dots
  ##
  ## The room has thirteen directions and a screen has two, so the two
  ## directions along which the routines differ most are the ones
  ## drawn. Clumps are then grown in the full room, not on the flat
  ## picture, so two dots that only look close because of the
  ## flattening are not reported as a group.
  var
    flat: seq[array[2, float]] = @[]
    nodes: seq[CloudNode] = @[]
    i: int = 0
  result = (points: @[], groups: @[])
  if A.len == 0 or A.len != S.points.len:
    return
  flat = flatten(S)
  while i < A.len:
    result.points.add(CloudPoint(id: A[i].id, name: A[i].name,
      path: A[i].path, role: R.getOrDefault(A[i].id, "unknown"),
      x: flat[i][0], y: flat[i][1], lines: A[i].lines))
    i = i + 1
  nodes = cloudNodes(S, cloudRadius, cloudFloorMembers)
  for node in nodes:
    result.groups.add(CloudGroup(id: node.id, label: node.label,
      x: node.x, y: node.y, radius: node.radius,
      members: node.memberIds))

proc shapeReport*(A: seq[FunctionInfo], root: string): ShapeReport
    {.role: orchestrator, metaTags: {tagStats}.} =
  ## A <- every routine in the tree   root <- the repository folder
  ## The whole of what this file has to say about one repository.
  var
    shapes: seq[FunctionShape] = @[]
    space: VectorSpace
    dupes: tuple[pairs: seq[DuplicatePair], total: int]
    cloud: tuple[points: seq[CloudPoint], groups: seq[CloudGroup]]
    roles: Table[string, string] = initTable[string, string]()
  result = ShapeReport(dims: @[], shapes: @[], duplicates: @[],
    duplicateCount: 0, points: @[], groups: @[])
  for name in shapeDims:
    result.dims.add(name)
  if A.len == 0:
    return
  for row in A:
    shapes.add(shapeOf(row, root))
    roles[row.id] = roleToString(row.role)
  space = spaceOf(shapes)
  dupes = duplicatesOf(shapes, space)
  cloud = cloudOf(shapes, space, roles)
  result.shapes = shapes
  result.duplicates = dupes.pairs
  result.duplicateCount = dupes.total
  result.points = cloud.points
  result.groups = cloud.groups
