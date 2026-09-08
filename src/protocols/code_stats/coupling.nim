## ==============================================================
## | coupling.nim  <-  is every door guarded, and is every guard |
## |                   itself checked?                           |
## |------------------------------------------------------------|
## | Two questions, one after the other, because the second only |
## | matters if the first is answered yes.                       |
## |                                                             |
## | FIRST. Every routine that takes something in from outside — |
## | a person typing, a network, a file — is a door into the      |
## | program. The house rule is that a door is paired with a      |
## | sanitizer: something that looks at what came in and refuses  |
## | what it does not like. So for every door, is there one?      |
## |                                                             |
## |   readRequest  ─calls─►  sanitizeHeaders   ✓ guarded        |
## |   readConfig   ─calls─►  parseToml ─calls─► cleanValue  ✓   |
## |   readCookie   ─────────────────────────►  (nothing)   ✗    |
## |                                                             |
## | The guard does not have to be called directly. A door that   |
## | calls something that calls a sanitizer is still guarded, so  |
## | the calls are followed a few steps out. How many steps it    |
## | took is reported, because a guard three rooms away is easy   |
## | to remove by accident and nobody would notice.               |
## |                                                             |
## | SECOND. A sanitizer that is itself untested is not a guard,  |
## | it is a promise. And the *kind* of test matters more here    |
## | than almost anywhere else in a program:                      |
## |                                                             |
## |   an ordinary test    proves it works on what you expected  |
## |   an edge-case test   proves it works on empty, huge, zero,  |
## |                       and the shapes an attacker sends       |
## |   a regression test   proves the hole that was found once    |
## |                       has not quietly come back              |
## |                                                             |
## | A sanitizer with ordinary tests only is the common and       |
## | dangerous case: it is tested against the input somebody      |
## | already thought of, which is exactly the input that was      |
## | never the problem.                                           |
## ==============================================================

import std/[algorithm, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import otterPragmas

const
  guardHops*: int = 3
    ## How many calls out to look for a sanitizer. Past three the link
    ## is too far away to be relied on, and saying "guarded" about it
    ## would be worse than saying nothing.
  couplingShown*: int = 60
    ## How many doors travel to a window. The rest are counted.
  sanitizerWords*: array[6, string] = [
    "sanitize", "sanitise", "validate", "clean", "escape", "scrub"
  ]
    ## Names that say a routine cleans what it was handed. Used only
    ## when nothing declared a role, so a repository that follows the
    ## convention is never second-guessed.

type
  GuardKind* {.role: other, metaTags: {tagStats}.} = enum
    ## How a door came to be guarded.
    ##
    ##   gkSelf     the door cleans what it takes in itself
    ##   gkDirect   it calls a sanitizer
    ##   gkIndirect a sanitizer sits further down what it calls
    ##   gkNone     nothing found: this door is open
    gkSelf, gkDirect, gkIndirect, gkNone

  InputGuard* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One door, and what guards it.
    ##
    ##   hops   0 when the door cleans its own input, 1 when it calls
    ##          the sanitizer, more when the guard is further away
    name*: string
    path*: string
    role*: string
    kind*: string
    guard*: string
    via*: seq[string]
      ## The route from the door to its guard, named, so a person can
      ## check the claim rather than take it on trust.
    line*: int
    hops*: int
    guarded*: bool

  SanitizerTests* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One guard, and what proves it works.
    ##
    ##   verdict  "unchecked", "shallow", or "solid"
    name*: string
    path*: string
    verdict*: string
    line*: int
    tests*: int
    edge*: bool
    regression*: bool
    bugfix*: bool
    guards*: int
      ## How many doors lean on this one guard. A guard holding up six
      ## doors with no edge-case test is the first thing to fix.

  CouplingStats* {.role: truthState, metaTags: {tagStats}.} = object
    ## Both answers, for one repository.
    inputs*: seq[InputGuard]
    sanitizers*: seq[SanitizerTests]
    inputCount*: int
    guardedCount*: int
    openCount*: int
    sanitizerCount*: int
    uncheckedCount*: int
    shallowCount*: int
    solidCount*: int
    edgeCovered*: int
    regressionCovered*: int

proc guardName*(k: GuardKind): string {.role: helper,
    metaTags: {tagStats}.} =
  ## k <- how a door is guarded, as a word for a window.
  case k
  of gkSelf: result = "cleans its own"
  of gkDirect: result = "calls a guard"
  of gkIndirect: result = "guard further down"
  of gkNone: result = "open"

proc declaredRole*(f: FunctionInfo): string {.role: parser,
    metaTags: {tagStats}.} =
  ## f <- one routine. What its `role` pragma says, lowered, or "".
  var
    t: string = ""
  result = ""
  for row in f.pragmaTags:
    t = row.strip().toLowerAscii()
    if t.startsWith("role:"):
      return t[5 .. ^1].strip()

proc isSanitizer*(f: FunctionInfo): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## f <- one routine. Whether it cleans what it is handed.
  ##
  ## A declared role is believed outright. Only when nothing was
  ## declared is the name read, so a repository that follows the
  ## convention is never argued with.
  var
    t: string = declaredRole(f)
    n: string = f.name.toLowerAscii()
  result = false
  if t.len > 0:
    return t in ["sanitizer", "decryptor", "sanitiser"]
  for word in sanitizerWords:
    if n.startsWith(word) or n.contains(word):
      return true

proc isDoor*(f: FunctionInfo): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## f <- one routine. Whether something from outside comes in here.
  ##
  ## A routine that is itself a sanitizer is not counted as a door: it
  ## is the guard, and asking whether the guard is guarded is a
  ## question with no useful answer.
  var
    t: string = declaredRole(f)
  result = false
  if isSanitizer(f):
    return false
  if f.userInputDeclared or f.handlesUserInput:
    return true
  result = t in ["datafetcher", "data_fetcher", "input"]

proc findGuard*(id: string, M: Table[string, seq[string]],
    guards: HashSet[string], names: Table[string, string], hops: int):
    tuple[found: bool, at: string, route: seq[string]] {.role: parser,
    metaTags: {tagStats}.} =
  ## id <- the door   M <- who calls whom   guards <- every sanitizer
  ## names <- what each id is called   hops <- how far out to look
  ##
  ## Walks outwards a layer at a time and stops at the first guard
  ## found, so the route reported is the shortest one there is.
  var
    now: seq[string] = @[id]
    next: seq[string] = @[]
    seen: HashSet[string] = initHashSet[string]()
    came: Table[string, string] = initTable[string, string]()
    step: int = 0
    at: string = ""
  result = (found: false, at: "", route: @[])
  seen.incl(id)
  while step < hops and now.len > 0:
    next = @[]
    for caller in now:
      for callee in M.getOrDefault(caller, @[]):
        if seen.containsOrIncl(callee):
          continue
        came[callee] = caller
        if callee in guards:
          # Walk the route back to the door, then turn it round.
          at = callee
          result.route = @[]
          while at.len > 0:
            result.route.add(names.getOrDefault(at, at))
            if at == id or not came.hasKey(at):
              break
            at = came[at]
          result.route.reverse()
          return (found: true, at: names.getOrDefault(callee, callee),
            route: result.route)
        next.add(callee)
    now = next
    step = step + 1

proc verdictOf*(tests: int, edge, regression: bool): string
    {.role: parser, metaTags: {tagStats}.} =
  ## tests <- how many tests reach this guard
  ## edge, regression <- whether any of them is of that kind
  ##
  ##   unchecked  nothing tests it at all
  ##   shallow    tested, but only against what was expected
  ##   solid      tested against the ends of the range, or pinned
  ##              against a hole that was found once
  result = "solid"
  if tests == 0:
    return "unchecked"
  if not edge and not regression:
    return "shallow"

proc byHops(a, b: InputGuard): int {.role: helper, metaTags: {tagStats}.} =
  ## a, b <- two doors. Open ones first, then the ones whose guard is
  ## furthest away, because both are things to go and look at.
  result = cmp(a.guarded, b.guarded)
  if result == 0:
    result = cmp(b.hops, a.hops)
  if result == 0:
    result = cmp(a.path, b.path)

proc byRisk(a, b: SanitizerTests): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b <- two guards. Least proven first, and among those the one
  ## holding up the most doors.
  var
    ra: int = 0
    rb: int = 0
  ra = 2
  rb = 2
  if a.verdict == "unchecked":
    ra = 0
  elif a.verdict == "shallow":
    ra = 1
  if b.verdict == "unchecked":
    rb = 0
  elif b.verdict == "shallow":
    rb = 1
  result = cmp(ra, rb)
  if result == 0:
    result = cmp(b.guards, a.guards)
  if result == 0:
    result = cmp(a.name, b.name)

proc couplingOf*(A: seq[FunctionInfo], E: seq[CallEdge], root: string,
    hits: CountTable[string], edge, regress, bug: HashSet[string]):
    CouplingStats {.role: orchestrator, metaTags: {tagStats}.} =
  ## A <- every routine   E <- every call between them
  ## root <- the repository folder
  ## hits <- how many tests reach each routine, by name
  ## edge, regress, bug <- routine names reached by a test of that kind
  ##
  ##   doors ─► find a guard ─► how far away was it
  ##   guards ─► what tests reach it ─► of which kinds
  var
    M: Table[string, seq[string]] = initTable[string, seq[string]]()
    names: Table[string, string] = initTable[string, string]()
    guards: HashSet[string] = initHashSet[string]()
    known: HashSet[string] = initHashSet[string]()
    leaning: CountTable[string] = initCountTable[string]()
    got: tuple[found: bool, at: string, route: seq[string]]
    kind: GuardKind = gkNone
    rows: seq[InputGuard] = @[]
    guardRows: seq[SanitizerTests] = @[]
    rel: string = ""
    n: int = 0
  result = CouplingStats(inputs: @[], sanitizers: @[], inputCount: 0,
    guardedCount: 0, openCount: 0, sanitizerCount: 0,
    uncheckedCount: 0, shallowCount: 0, solidCount: 0,
    edgeCovered: 0, regressionCovered: 0)
  if A.len == 0:
    return
  for row in A:
    known.incl(row.id)
    names[row.id] = row.name
    M[row.id] = @[]
    if isSanitizer(row):
      guards.incl(row.id)
  for row in E:
    if row.callerId in known and row.calleeId in known:
      M[row.callerId].add(row.calleeId)

  # ---- first question: is every door guarded ----
  for row in A:
    if not isDoor(row):
      continue
    result.inputCount = result.inputCount + 1
    rel = row.sourcePath
    if root.len > 0 and rel.startsWith(root):
      rel = rel[root.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    got = findGuard(row.id, M, guards, names, guardHops)
    kind = gkNone
    if got.found:
      kind = gkDirect
      if got.route.len > 2:
        kind = gkIndirect
    rows.add(InputGuard(name: row.name, path: rel,
      role: roleToString(row.role), kind: guardName(kind),
      guard: got.at, via: got.route, line: row.lineStart,
      hops: max(0, got.route.len - 1), guarded: got.found))
    if got.found:
      result.guardedCount = result.guardedCount + 1
      leaning.inc(got.at)
    else:
      result.openCount = result.openCount + 1

  # ---- second question: is every guard itself checked ----
  for row in A:
    if row.id notin guards:
      continue
    result.sanitizerCount = result.sanitizerCount + 1
    # The walk over the tests keys everything by a routine.s id, not
    # by its name. Two routines in different modules may share a name,
    # and looking these up by name would credit one with the other.s
    # tests -- which, for a guard, is exactly the wrong answer.
    n = hits.getOrDefault(row.id)
    rel = row.sourcePath
    if root.len > 0 and rel.startsWith(root):
      rel = rel[root.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    guardRows.add(SanitizerTests(name: row.name, path: rel,
      verdict: verdictOf(n, row.id in edge, row.id in regress),
      line: row.lineStart, tests: n, edge: row.id in edge,
      regression: row.id in regress, bugfix: row.id in bug,
      guards: leaning.getOrDefault(row.name)))
  for row in guardRows:
    case row.verdict
    of "unchecked":
      result.uncheckedCount = result.uncheckedCount + 1
    of "shallow":
      result.shallowCount = result.shallowCount + 1
    else:
      result.solidCount = result.solidCount + 1
    if row.edge:
      result.edgeCovered = result.edgeCovered + 1
    if row.regression:
      result.regressionCovered = result.regressionCovered + 1
  rows.sort(byHops)
  guardRows.sort(byRisk)
  if rows.len > couplingShown:
    rows.setLen(couplingShown)
  if guardRows.len > couplingShown:
    guardRows.setLen(couplingShown)
  result.inputs = rows
  result.sanitizers = guardRows
