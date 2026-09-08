## ================================================================
## | blast.nim  <-  what one change can reach                      |
## |---------------------------------------------------------------|
## | Before touching a routine, two questions decide whether the    |
## | change is safe, and neither can be answered by reading the     |
## | routine itself:                                                |
## |                                                                |
## |   who calls me?      -> whether tightening a check breaks      |
## |                         somebody, and whether somebody has     |
## |                         already checked what I am about to     |
## |                         check again                            |
## |   what flows in?     -> what the parameters actually hold,     |
## |                         rather than what their types allow     |
## ================================================================
##
## The two directions have their own depths on purpose
## ---------------------------------------------------
## They answer different questions and are worth different amounts,
## so one number for both would be the wrong number for one of them:
##
##   n   how far UP to walk, through callers, and their callers
##   m   how far DOWN to unwrap the arguments at each call site
##
##   myfunc(t(), x(a(b())))        m = 1  ->  t, x
##                                 m = 2  ->  t, x, a
##                                 m = 3  ->  t, x, a, b
##
## Going up is usually worth more than going down: a caller two hops
## away can still be broken by a stricter check, while an argument
## three levels inside an expression rarely tells you anything the
## first level did not. `n = 2, m = 1` is the useful default.
##
## What it is for
## --------------
## Two mistakes this is meant to stop, both of them the kind that is
## invisible from inside the routine being edited:
##
##   sanitising twice   a caller marked `sanitizer` already cleaned
##                      the value. Cleaning it again is not merely
##                      wasted work: a second pass over already-safe
##                      text can corrupt it.
##
##   guessing ranges    a parameter typed `int` that only ever
##                      receives 0, 1 and 2 at every call site in the
##                      tree is really an enum, and a new branch
##                      written for 4 is dead the day it is written.
##
## The second is why literal arguments are collected per position. It
## is evidence, not proof: a value arriving from a variable cannot be
## read this way, and the report says so rather than implying the
## list is complete.

import std/[algorithm, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import otterPragmas

const
  defaultCallerDepth*: int = 2
  defaultFeederDepth*: int = 1
  maxNodes*: int = 200
    ## A routine everything calls would otherwise return the whole
    ## repository, which answers nothing.

type
  BlastNode* {.role: preparedData, metaTags: {tagGraph}.} = object
    ## One routine reached from the target, and how far away it is.
    name*: string
    path*: string
    line*: int
    depth*: int
    role*: string

  ArgumentEvidence* {.role: preparedData, metaTags: {tagGraph}.} = object
    ## What was actually written at a given argument position, across
    ## every call site that could be read.
    position*: int
    literals*: seq[string]
    fromVariables*: int
      ## How many call sites passed something this cannot read. A high
      ## count means the literals below are a small part of the story.

  BlastRadius* {.role: truthState, metaTags: {tagGraph}.} = object
    target*: string
    kind*: string
      ## "routine" or "type".
    path*: string
    line*: int
    callerDepth*: int
    feederDepth*: int
    callers*: seq[BlastNode]
    feeders*: seq[BlastNode]
    sanitizersAbove*: seq[string]
      ## Callers that declare the `sanitizer` role. Clean once.
    arguments*: seq[ArgumentEvidence]
    producers*: seq[BlastNode]
      ## For a type: routines that hand one back.
    consumers*: seq[BlastNode]
      ## For a type: routines that take one in.
    notes*: seq[string]
    error*: string

proc balancedFrom(s: string, at: int): string {.role: parser,
    metaTags: {tagGraph}.} =
  ## s: one line   at: the index of an opening bracket.
  ## What sits inside that bracket, up to its match. An unclosed
  ## bracket - a call split across lines - yields the rest of the line,
  ## which is the honest partial answer.
  var
    depth: int = 0
    i: int = at
  result = ""
  while i < s.len:
    if s[i] == '(':
      depth = depth + 1
      if depth == 1:
        i = i + 1
        continue
    if s[i] == ')':
      depth = depth - 1
      if depth == 0:
        return
    result.add(s[i])
    i = i + 1

proc callsAtDepth(s: string, m: int): seq[tuple[name: string, depth: int]]
    {.role: parser, metaTags: {tagGraph}.} =
  ## s: the inside of one argument list   m: how deep to unwrap.
  ##
  ## Every name followed by a bracket, tagged with how many brackets it
  ## sits inside. Depth 1 is an argument written as a call; depth 2 is
  ## an argument of that call.
  var
    word: string = ""
    depth: int = 0
    i: int = 0
  result = @[]
  while i < s.len:
    if s[i].isAlphaNumeric() or s[i] == '_':
      word.add(s[i])
      i = i + 1
      continue
    if s[i] == '(':
      if word.len > 1 and not word[0].isDigit() and depth < m:
        result.add((name: word, depth: depth + 1))
      depth = depth + 1
      word = ""
      i = i + 1
      continue
    if s[i] == ')':
      depth = depth - 1
    word = ""
    i = i + 1

proc splitArgs(s: string): seq[string] {.role: parser,
    metaTags: {tagGraph}.} =
  ## s: the inside of one argument list.
  ## The arguments, split on the commas that sit at the top level, so
  ## that `f(a, g(b, c))` is two arguments rather than three.
  var
    depth: int = 0
    cur: string = ""
    i: int = 0
  result = @[]
  while i < s.len:
    if s[i] == '(' or s[i] == '[':
      depth = depth + 1
    if s[i] == ')' or s[i] == ']':
      depth = depth - 1
    if s[i] == ',' and depth == 0:
      result.add(cur.strip())
      cur = ""
      i = i + 1
      continue
    cur.add(s[i])
    i = i + 1
  if cur.strip().len > 0:
    result.add(cur.strip())

proc isLiteral(s: string): bool {.role: parser, metaTags: {tagGraph}.} =
  ## s: one argument as written. Whether it is a value typed in on the
  ## spot rather than a name standing for one.
  var t: string = s.strip()
  result = false
  if t.len == 0:
    return
  if t[0] == '"' or t[0] == '\'':
    return true
  if t[0].isDigit() or (t[0] == '-' and t.len > 1 and t[1].isDigit()):
    return true
  result = t in ["true", "false", "nil", "@[]"]

proc roleName(f: FunctionInfo): string {.role: helper,
    metaTags: {tagGraph}.} =
  ## f: one routine. The role it DECLARES, and only if it declares
  ## none, the one Otter guessed. The difference matters here: acting
  ## on a guess that a routine sanitises is how a real check gets
  ## removed.
  ##
  ## The pragma tag is read before `declaredRole` on purpose.
  ## `FunctionRole` has no member for several roles the conventions
  ## define - `sanitizer` and `dataWriter` among them - so a routine
  ## marked `{.role: sanitizer.}` arrives here as `unknown` with the
  ## truth still sitting in its tags. Reading the tag costs nothing and
  ## does not wait on that enum being widened.
  for tag in f.pragmaTags:
    if tag.startsWith("role:"):
      return tag[5 .. ^1]
  if f.declaredRole != frUnknown:
    return roleToString(f.declaredRole)
  result = roleToString(f.role)

proc callersOf(g: RepoGraph, targetIds: HashSet[string], n: int):
    seq[BlastNode] {.role: truthBuilder, metaTags: {tagGraph}.} =
  ## g: the whole graph   targetIds: every routine of the wanted name
  ## n: how many hops up to walk.
  ##
  ## Breadth first, so a routine reached two ways is recorded at the
  ## shorter distance. That matters: distance is the whole point, and
  ## the nearest caller is the one most likely to break.
  var
    byId = initTable[string, FunctionInfo]()
    seen: HashSet[string] = targetIds
    frontier: HashSet[string] = targetIds
    nextUp: HashSet[string] = initHashSet[string]()
    depth: int = 1
  result = @[]
  for f in g.functions:
    byId[f.id] = f
  while depth <= n and frontier.len > 0 and result.len < maxNodes:
    nextUp = initHashSet[string]()
    for e in g.edges:
      if e.calleeId notin frontier or e.callerId in seen:
        continue
      nextUp.incl(e.callerId)
    for id in nextUp:
      seen.incl(id)
      if not byId.hasKey(id):
        continue
      result.add(BlastNode(name: byId[id].name, path: byId[id].sourcePath,
        line: byId[id].lineStart, depth: depth, role: roleName(byId[id])))
    frontier = nextUp
    depth = depth + 1

proc feedersOf(g: RepoGraph, name: string, m: int):
    tuple[nodes: seq[BlastNode], args: seq[ArgumentEvidence]]
    {.role: truthBuilder, metaTags: {tagGraph}.} =
  ## g: the whole graph   name: the routine being asked about
  ## m: how far to unwrap each argument.
  ##
  ## Every call site is read as written. This is text, not a parsed
  ## tree: a call split over two lines is read as far as its first
  ## line goes, and the report says how many arguments could not be
  ## read rather than pretending they were not there.
  var
    nodes: seq[BlastNode] = @[]
    seenNode: HashSet[string] = initHashSet[string]()
    perPos = initTable[int, ArgumentEvidence]()
    inside: string = ""
    args: seq[string] = @[]
    at: int = 0
    key: string = ""
    row: ArgumentEvidence = ArgumentEvidence()
    i: int = 0
  result = (nodes: @[], args: @[])
  for f in g.functions:
    for line in f.bodyLines:
      at = line.find(name & "(")
      if at < 0:
        continue
      # A name ending in the wanted one is a different name.
      if at > 0 and (line[at - 1].isAlphaNumeric() or line[at - 1] == '_'):
        continue
      inside = balancedFrom(line, at + name.len)
      for c in callsAtDepth(inside, m):
        key = c.name & ":" & $c.depth
        if key in seenNode:
          continue
        seenNode.incl(key)
        nodes.add(BlastNode(name: c.name, path: f.sourcePath,
          line: f.lineStart, depth: c.depth, role: ""))
      args = splitArgs(inside)
      i = 0
      while i < args.len:
        if not perPos.hasKey(i):
          perPos[i] = ArgumentEvidence(position: i, literals: @[],
            fromVariables: 0)
        row = perPos[i]
        if isLiteral(args[i]):
          if args[i] notin row.literals:
            row.literals.add(args[i])
        else:
          row.fromVariables = row.fromVariables + 1
        perPos[i] = row
        i = i + 1
  result.nodes = nodes
  for pos, row in perPos:
    result.args.add(row)
  result.args.sort(proc (a, b: ArgumentEvidence): int =
    cmp(a.position, b.position))

proc typeRadius(g: RepoGraph, name: string): tuple[producers,
    consumers: seq[BlastNode]] {.role: truthBuilder, metaTags: {tagGraph}.} =
  ## g: the whole graph   name: a type.
  ##
  ## A type has no callers, so the two directions become: who makes one
  ## and who takes one. Both are read from signatures, which is where a
  ## type is visible without following any value.
  var
    wanted: string = name.toLowerAscii()
    paramText: string = ""
    tail: string = ""
    at: int = 0
  result = (producers: @[], consumers: @[])
  for f in g.functions:
    # `params` holds the names only - `@["plain", "s"]` - so the types
    # have to come from the declaration as written.
    at = f.signature.find('(')
    paramText = ""
    tail = f.returnType.toLowerAscii()
    if at >= 0:
      paramText = balancedFrom(f.signature, at).toLowerAscii()
      # A declaration wrapped over several lines leaves `returnType`
      # empty, so what follows the parameters is read instead.
      if tail.len == 0 and at + paramText.len + 2 <= f.signature.len:
        tail = f.signature[at + paramText.len + 2 .. ^1].toLowerAscii()
    if wanted in tail:
      result.producers.add(BlastNode(name: f.name, path: f.sourcePath,
        line: f.lineStart, depth: 1, role: roleName(f)))
    if at >= 0 and wanted in paramText:
      result.consumers.add(BlastNode(name: f.name, path: f.sourcePath,
        line: f.lineStart, depth: 1, role: roleName(f)))

proc blastRadius*(g: RepoGraph, name: string,
    n: int = defaultCallerDepth,
    m: int = defaultFeederDepth): BlastRadius {.role: metaOrchestrator,
    metaTags: {tagGraph}.} =
  ## g: the whole graph   name: a routine or a type
  ## n: how far up, through callers   m: how far down, into arguments.
  ##
  ## The one call a person - or a smaller agent - makes before editing
  ## something they did not write.
  var
    ids: HashSet[string] = initHashSet[string]()
    got: tuple[nodes: seq[BlastNode], args: seq[ArgumentEvidence]] = (nodes: @[], args: @[])
    types: tuple[producers, consumers: seq[BlastNode]] = (producers: @[], consumers: @[])
    hits: int = 0
  result = BlastRadius(target: name, kind: "routine", path: "", line: 0,
    callerDepth: n, feederDepth: m, callers: @[], feeders: @[],
    sanitizersAbove: @[], arguments: @[], producers: @[], consumers: @[],
    notes: @[], error: "")
  for f in g.functions:
    if f.name != name:
      continue
    ids.incl(f.id)
    hits = hits + 1
    if result.path.len == 0:
      result.path = f.sourcePath
      result.line = f.lineStart
  if hits > 1:
    result.notes.add($hits & " routines share this name; every one of " &
      "them is included, so a caller listed here may reach a different one")
  if hits == 0:
    types = typeRadius(g, name)
    if types.producers.len == 0 and types.consumers.len == 0:
      result.error = "no routine and no type named " & name
      return
    result.kind = "type"
    result.producers = types.producers
    result.consumers = types.consumers
    result.notes.add("read from signatures: a value held in a field or " &
      "built through a template is not counted")
    return
  result.callers = callersOf(g, ids, n)
  got = feedersOf(g, name, m)
  result.feeders = got.nodes
  result.arguments = got.args
  # A feeder is only a name until it is matched back to a routine, and
  # its role is the reason to look it up: a sanitiser feeding this call
  # is the clearest sign that cleaning here would be the second pass.
  for i in 0 ..< result.feeders.len:
    for f in g.functions:
      if f.name == result.feeders[i].name:
        result.feeders[i].role = roleName(f)
        result.feeders[i].path = f.sourcePath
        result.feeders[i].line = f.lineStart
        break
  for c in result.callers:
    if c.role == "sanitizer" and c.name notin result.sanitizersAbove:
      result.sanitizersAbove.add(c.name)
  for c in result.feeders:
    if c.role == "sanitizer" and c.name notin result.sanitizersAbove:
      result.sanitizersAbove.add(c.name)
  if result.sanitizersAbove.len > 0:
    result.notes.add("already sanitised on the way in by " &
      result.sanitizersAbove.join(", ") &
      "; cleaning the same value twice can corrupt it")
  if result.callers.len >= maxNodes:
    result.notes.add("the walk stopped at " & $maxNodes &
      " routines; this one is called from nearly everywhere")

proc blastLines*(r: BlastRadius): seq[string] {.role: dataWriter,
    metaTags: {tagGraph}.} =
  ## r: one answer. The same answer as plain lines, because the reader
  ## is as often a person deciding whether to touch something as it is
  ## a program.
  var
    depth: int = 0
    row: string = ""
  result = @[]
  if r.error.len > 0:
    result.add("blast radius: " & r.error)
    return
  result.add(r.target & "  (" & r.kind & ")  " & r.path & ":" & $r.line)
  if r.kind == "type":
    result.add("  handed back by " & $r.producers.len &
      " routine(s), taken in by " & $r.consumers.len)
    for p in r.producers:
      result.add("    makes  " & p.name & "  " & p.path & ":" & $p.line)
    for c in r.consumers:
      result.add("    takes  " & c.name & "  " & c.path & ":" & $c.line)
    for note in r.notes:
      result.add("  note: " & note)
    return
  result.add("  callers, up to " & $r.callerDepth & " hop(s): " &
    $r.callers.len)
  depth = 1
  while depth <= r.callerDepth:
    for c in r.callers:
      if c.depth != depth:
        continue
      result.add("    " & repeat("  ", depth - 1) & "^" & $depth & "  " &
        c.name & "  [" & c.role & "]  " & c.path & ":" & $c.line)
    depth = depth + 1
  result.add("  feeds in, unwrapped " & $r.feederDepth & " level(s): " &
    $r.feeders.len)
  depth = 1
  while depth <= r.feederDepth:
    for f in r.feeders:
      if f.depth != depth:
        continue
      result.add("    " & repeat("  ", depth - 1) & "v" & $depth & "  " &
        f.name & "()  [" & f.role & "]  " & f.path)
    depth = depth + 1
  if r.arguments.len > 0:
    result.add("  what arrives, per argument, as written at the call sites:")
  for a in r.arguments:
    row = "    arg " & $a.position & "  "
    if a.literals.len > 0:
      row = row & "written out: " & a.literals.join(", ")
    else:
      row = row & "never written out"
    if a.fromVariables > 0:
      row = row & "   (" & $a.fromVariables &
        " call site(s) passed a name this cannot read)"
    result.add(row)
  for note in r.notes:
    result.add("  note: " & note)
