## ================================================================
## | yields.nim  <-  every way a routine can end                   |
## |---------------------------------------------------------------|
## | A signature says what comes back when all goes well. It says   |
## | nothing about the other ways out, and those are the ones that  |
## | break a caller:                                                |
## |                                                                |
## |   proc loadWidth(p: string): int                               |
## |                              ^^^ this is one of four answers   |
## |                                                                |
## |   int          the width was read                              |
## |   IOError      the file was not there                          |
## |   ValueError   what was in it was not a number                 |
## |   RangeDefect  it was a number, and a silly one                |
## ================================================================
##
## Where an ending comes from
## --------------------------
## Four sources, and they are told apart because a reader can do
## something different about each:
##
##   raised here    `raise newException(IOError, ...)` in this body
##   from a callee  something this routine calls can end that way
##   from the       a name with a known ending: `readFile` raises
##   library        IOError, `parseInt` raises ValueError
##   stops          `doAssert`, `quit`. Not an exception at all: no
##                  caller can catch it, the program is over
##
## The last one matters most to somebody adding a call. An IOError can
## be handled two levels up. A `quit` two levels down cannot be.
##
## What catching does
## ------------------
## A `try` block subtracts. The subtraction is done where the call
## sits, not for the whole routine, because those are different:
##
##     proc pick(p: string): int =
##       result = loadWidth(p)        <- outside: everything escapes
##       try:
##         result = loadWidth(p)      <- inside: ValueError does not
##       except ValueError:
##         result = 80
##
## A routine whose every call sits inside `except CatchableError` is a
## **barrier**: nothing from below it reaches anybody above it. Knowing
## where the barriers are is the difference between handling an error
## once and handling it in nine places.
##
## Failure that is not a throw
## ---------------------------
## Some routines hand failure back as a value:
##
##     type Loaded = object
##       width*: int
##       error*: string    <- this is the other way out
##
## A caller that never looks at `error` is not told anything went
## wrong, and no compiler will point that out. So a return type
## carrying such a field is named as an ending in its own right.
##
## What this cannot see
## --------------------
## A raise reached through a variable holding a routine, or through a
## method chosen at run time, is invisible here. The library table is a
## list of names somebody wrote down, not an analysis of the standard
## library: a routine that raises and is not on the list is missed. The
## report says which findings rest on that table.

import std/[algorithm, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import ../repo_graph/io_utils
import ./state_writes
import otterPragmas

const
  maxChain*: int = 6
    ## How many routine names one path may name before it is cut. A
    ## longer chain is true but nobody reads it.

  maxRounds*: int = 12
    ## Passes over the call graph. Endings travel one hop per pass, so
    ## this is how deep an ending may come from. Routines that call
    ## each other in a ring would otherwise never settle.

  errorFields*: array[6, string] = [
    "error", "err", "ok", "success", "failed", "reason"
  ]
    ## Entry names that mean "this object may be carrying a failure".

  abortCalls*: array[6, string] = [
    "quit(", "doAssert", "assert ", "raiseAssert", "sysFatal", "abort("
  ]
    ## Ways of ending that no caller can catch.

type
  OutcomeKind* {.role: other, metaTags: {tagGraph}.} = enum
    okRaise,
      ## An exception. Somebody above may catch it.
    okAbort
      ## The program stops. Nobody above can do anything.

  Outcome* {.role: preparedData, metaTags: {tagGraph}.} = object
    ## One way a routine can end other than by returning.
    name*: string
      ## The exception, or what stops the program.
    kind*: OutcomeKind
    via*: seq[string]
      ## The routines it travels through, this one first.
    source*: string
      ## "raised here", "library" or "from a callee".

  YieldPaths* {.role: truthState, metaTags: {tagGraph}.} = object
    target*: string
    path*: string
    line*: int
    returnType*: string
    carriesError*: bool
    errorField*: string
      ## The entry of the returned object that holds a failure.
    outcomes*: seq[Outcome]
    caught*: seq[string]
      ## Exceptions this routine catches rather than passes on.
    barrier*: bool
      ## Every call it makes sits inside a catch-everything block.
    declared*: bool
      ## It states its own `{.raises: [...].}`, which is the truth and
      ## outranks anything read out of its body.
    notes*: seq[string]
    error*: string

  TryRegion* {.role: preparedData, metaTags: {tagGraph}.} = object
    ## One `try` block of one routine, by line index into its body.
    first*: int
    last*: int
    caught*: seq[string]
    catchAll*: bool

proc libraryRaisers*(): Table[string, string] {.role: configurator,
    metaTags: {tagGraph}.} =
  ## Names from the standard library whose ending is worth knowing,
  ## and what they end with.
  ##
  ## Written down rather than worked out. Nim can prove this properly
  ## with `{.raises.}`; this is a reading of text, so the honest thing
  ## is a short list of the names that come up, and to say in the
  ## report which findings rest on it.
  result = initTable[string, string]()
  for row in [
      ("readFile", "IOError"), ("writeFile", "IOError"),
      ("open", "IOError"), ("readLine", "IOError"),
      ("readAll", "IOError"), ("close", "IOError"),
      ("parseInt", "ValueError"), ("parseUInt", "ValueError"),
      ("parseFloat", "ValueError"), ("parseHexInt", "ValueError"),
      ("parseBiggestInt", "ValueError"), ("parseEnum", "ValueError"),
      ("parseJson", "JsonParsingError"), ("parseFile", "JsonParsingError"),
      ("createDir", "OSError"), ("removeFile", "OSError"),
      ("removeDir", "OSError"), ("copyFile", "OSError"),
      ("moveFile", "OSError"), ("setCurrentDir", "OSError"),
      ("execProcess", "OSError"), ("startProcess", "OSError"),
      ("waitForExit", "OSError"), ("getAppFilename", "OSError"),
      ("paramStr", "IndexDefect"), ("newHttpClient", "IOError")]:
    result[row[0]] = row[1]

proc typeNameOf(s: string): string {.role: parser, metaTags: {tagGraph}.} =
  ## s: text that begins with a type name.
  ## That name and nothing else, so `IOError, "gone"` yields `IOError`.
  var
    i: int = 0
    t: string = s.strip()
  result = ""
  while i < t.len and (t[i].isAlphaNumeric() or t[i] == '_'):
    i = i + 1
  result = t[0 ..< i]

proc tryRegionsOf*(f: FunctionInfo): seq[TryRegion] {.role: parser,
    metaTags: {tagGraph}.} =
  ## f: one routine.
  ##
  ## Where its `try` blocks are, by line index into its body, and what
  ## each of them catches. Read from the shape of the indentation,
  ## which is what a person reads too:
  ##
  ##   try:            <- opens at this indent
  ##     work()        <- covered
  ##   except IOError: <- still part of the block; names what it takes
  ##     ...
  ##   more()          <- back to the opening indent, so not covered
  var
    i: int = 0
    depth: int = 0
    open: bool = false
    r: TryRegion = TryRegion()
    s: string = ""
    at: int = 0
  result = @[]
  while i < f.bodyLines.len:
    s = bareCode(f.bodyLines[i]).strip()
    at = f.bodyLines[i].len - f.bodyLines[i].strip(leading = true,
      trailing = false).len
    if open and s.len > 0 and at <= depth and not (s.startsWith("except") or
        s.startsWith("finally")):
      result.add(r)
      open = false
    if s == "try:" or s.startsWith("try:"):
      r = TryRegion(first: i, last: f.bodyLines.len - 1, caught: @[],
        catchAll: false)
      depth = at
      open = true
      i = i + 1
      continue
    if open and s.startsWith("except"):
      r.last = i - 1
      if s == "except:" or "CatchableError" in s or "Exception" in s:
        r.catchAll = true
      for piece in s[6 .. ^1].strip(chars = {' ', ':'}).split(','):
        if typeNameOf(piece).len > 0 and typeNameOf(piece) notin r.caught:
          r.caught.add(typeNameOf(piece))
    i = i + 1
  if open:
    result.add(r)

proc regionAt(regions: seq[TryRegion], k: int): int {.role: parser,
    metaTags: {tagGraph}.} =
  ## regions: the try blocks of one routine   k: a line index.
  ## Which of them covers that line, or -1 when none does.
  result = -1
  for i in 0 ..< regions.len:
    if k >= regions[i].first and k <= regions[i].last:
      result = i

proc survives(regions: seq[TryRegion], k: int, name: string): bool
    {.role: parser, metaTags: {tagGraph}.} =
  ## regions: the try blocks   k: where the call or raise sits
  ## name: the exception. Whether it gets past the block around it.
  var
    at: int = regionAt(regions, k)
  result = true
  if at < 0:
    return
  if regions[at].catchAll:
    return false
  result = name notin regions[at].caught

proc callsOnLine*(s: string): seq[string] {.role: parser,
    metaTags: {tagGraph}.} =
  ## s: one line of code.
  ## Every name written with a bracket after it. `a.b(c(d))` yields
  ## `b` and `c`, because those are the two things being called.
  var
    i: int = 0
    start: int = 0
  result = @[]
  while i < s.len:
    if not (s[i].isAlphaNumeric() or s[i] == '_'):
      i = i + 1
      continue
    start = i
    while i < s.len and (s[i].isAlphaNumeric() or s[i] == '_'):
      i = i + 1
    if i < s.len and s[i] == '(' and not (start > 0 and s[start - 1] == '.'):
      result.add(s[start ..< i])
    elif i < s.len and s[i] == '(':
      result.add(s[start ..< i])

proc declaredRaises*(signature: string): tuple[stated: bool, names: seq[string]]
    {.role: parser, metaTags: {tagGraph}.} =
  ## signature: a routine declaration as written.
  ##
  ## What its own `{.raises: [...].}` says. That pragma is checked by
  ## the compiler, so where it exists it is the truth and nothing read
  ## out of the body may argue with it. `raises: []` means nothing at
  ## all escapes.
  var
    at: int = signature.find("raises:")
    close: int = 0
    inside: string = ""
  result = (stated: false, names: @[])
  if at < 0:
    return
  at = signature.find('[', at)
  if at < 0:
    return
  close = signature.find(']', at)
  if close < 0:
    return
  result.stated = true
  inside = signature[at + 1 ..< close]
  for piece in inside.split(','):
    if typeNameOf(piece).len > 0:
      result.names.add(typeNameOf(piece))

proc notRunLines*(f: FunctionInfo): HashSet[int] {.role: parser,
    metaTags: {tagGraph}.} =
  ## f: one routine.
  ##
  ## Which lines of its body do not run when the module is used as
  ## part of a program. Three kinds, and a check in any of them would
  ## send a reader looking for a crash that cannot happen:
  ##
  ##   static:                          runs while building
  ##     doAssert supportsCopyMem(T)    and fails the build, not the run
  ##
  ##   when nimvm:                      the same
  ##
  ##   when isMainModule:               runs only when the file is the
  ##     doAssert keystream == expected program being built, never when
  ##                                    it is imported
  ##
  ## The last one is here for a second reason. A `when isMainModule`
  ## block written at the foot of a file is read by the parser as part
  ## of the last routine above it, because nothing in it starts a new
  ## routine. Until that is fixed where it belongs, this keeps its
  ## contents from being reported as endings of a routine that has
  ## nothing to do with them.
  var
    i: int = 0
    depth: int = 0
    open: bool = false
    s: string = ""
    at: int = 0
  result = initHashSet[int]()
  while i < f.bodyLines.len:
    s = bareCode(f.bodyLines[i]).strip()
    at = f.bodyLines[i].len - f.bodyLines[i].strip(leading = true,
      trailing = false).len
    if open and s.len > 0 and at <= depth:
      open = false
    if s == "static:" or s == "when nimvm:" or s == "when isMainModule:":
      depth = at
      open = true
      i = i + 1
      continue
    if open:
      result.incl(i)
    i = i + 1

proc ownOutcomes*(f: FunctionInfo, lib: Table[string, string],
    known: HashSet[string]): seq[Outcome] {.role: truthBuilder,
    metaTags: {tagGraph}.} =
  ## f: one routine   lib: the library names with a known ending
  ## known: every routine name this repository declares.
  ##
  ## The ways this routine can end that are written in its own body:
  ## what it raises, what it calls that is known to raise, and what
  ## stops the program. A `try` around any of them subtracts, except
  ## around the ones that stop the program - a `quit` is not caught by
  ## anything, and reading it as caught would be the worst kind of
  ## wrong answer.
  var
    regions: seq[TryRegion] = tryRegionsOf(f)
    atBuild: HashSet[int] = notRunLines(f)
    s: string = ""
    at: int = 0
    n: string = ""
    k: int = 0
  result = @[]
  while k < f.bodyLines.len:
    if k in atBuild:
      k = k + 1
      continue
    s = bareCode(f.bodyLines[k])
    at = s.find("newException(")
    if at >= 0:
      n = typeNameOf(s[at + 13 .. ^1])
    elif s.strip().startsWith("raise "):
      n = typeNameOf(s.strip()[6 .. ^1])
    else:
      n = ""
    if n.len > 0 and survives(regions, k, n):
      result.add(Outcome(name: n, kind: okRaise, via: @[f.name],
        source: "raised here"))
    for word in abortCalls:
      if word notin s:
        continue
      result.add(Outcome(name: word.strip(chars = {'(', ' '}),
        kind: okAbort, via: @[f.name], source: "raised here"))
    for c in callsOnLine(s):
      if c in known or not lib.hasKey(c) or
          not survives(regions, k, lib[c]):
        continue
      result.add(Outcome(name: lib[c], kind: okRaise, via: @[f.name, c],
        source: "library"))
    k = k + 1

proc callSitesOf*(f: FunctionInfo, known: HashSet[string]):
    seq[tuple[name: string, at: int]] {.role: parser, metaTags: {tagGraph}.} =
  ## f: one routine   known: every routine name in the repository.
  ## Which of them it calls, and on which line of its body, because
  ## the line decides whether a `try` covers the call.
  var
    k: int = 0
  result = @[]
  while k < f.bodyLines.len:
    for c in callsOnLine(bareCode(f.bodyLines[k])):
      if c in known:
        result.add((name: c, at: k))
    k = k + 1

proc shorterFirst(a, b: Outcome): int {.role: helper, metaTags: {tagGraph}.} =
  ## Aborts before exceptions, then the shortest path, then by name.
  ## A reader deciding whether to add a call wants the ending nobody
  ## can catch at the top of the list.
  result = cmp(int(b.kind == okAbort), int(a.kind == okAbort))
  if result == 0:
    result = cmp(a.via.len, b.via.len)
  if result == 0:
    result = cmp(a.name, b.name)

proc siteLines(f: FunctionInfo, name: string): seq[int] {.role: parser,
    metaTags: {tagGraph}.} =
  ## f: one routine   name: something it calls.
  ## Which lines of its body call that. Empty when the call is there
  ## but not written out - through a macro, say - and the caller then
  ## has to assume the worst.
  var
    k: int = 0
  result = @[]
  while k < f.bodyLines.len:
    for c in callsOnLine(bareCode(f.bodyLines[k])):
      if c == name:
        result.add(k)
    k = k + 1

proc anySurvives(regions: seq[TryRegion], ats: seq[int], name: string): bool
    {.role: parser, metaTags: {tagGraph}.} =
  ## regions: the try blocks   ats: every line the call sits on
  ## name: the exception.
  ##
  ## One uncovered call site is enough. A routine that wraps a call in
  ## a `try` in one place and not in another still lets the exception
  ## out, and reporting otherwise would be the dangerous direction to
  ## be wrong in.
  result = ats.len == 0
  for at in ats:
    if survives(regions, at, name):
      return true

proc escapingOf*(g: RepoGraph): Table[string, seq[Outcome]]
    {.role: metaOrchestrator, metaTags: {tagGraph}.} =
  ## g: the whole graph.
  ##
  ## For every routine name, every way a call to it can end other than
  ## by returning. Worked out by passing endings up one hop at a time
  ## until nothing moves, because an ending three routines down is
  ## still an ending here, and that is exactly the part a person
  ## editing one file cannot see.
  ##
  ##   round 0   readFile raises IOError        <- from the library
  ##   round 1   readRaw does too               <- it calls readFile
  ##   round 2   loadWidth does too             <- it calls readRaw
  ##   round 3   nothing moved. Stop.
  ##
  ## The hops are taken along the call edges the graph already
  ## resolved, not along matching names. Names lie: a repository with
  ## its own `open` would otherwise be told that reading a file can
  ## fail the way decoding a McEliece key can, through a chain that
  ## does not exist. Only the last step - a name from the standard
  ## library - is matched by name, and a repository that defines that
  ## name itself takes it back.
  ##
  ## The answer is then folded together by name, because that is what
  ## somebody asks with. Two routines of one name are answered as one,
  ## which overstates rather than understates, and overstating is the
  ## safe direction for a question about how something can go wrong.
  var
    lib: Table[string, string] = libraryRaisers()
    known: HashSet[string] = initHashSet[string]()
    regions: Table[string, seq[TryRegion]] = initTable[string,
      seq[TryRegion]]()
    calls: Table[string, seq[string]] = initTable[string, seq[string]]()
    nameOf: Table[string, string] = initTable[string, string]()
    stated: Table[string, bool] = initTable[string, bool]()
    cur: Table[string, Table[string, Outcome]] = initTable[string,
      Table[string, Outcome]]()
    said: tuple[stated: bool, names: seq[string]] = (false, @[])
    ats: seq[int] = @[]
    moved: bool = true
    round: int = 0
  result = initTable[string, seq[Outcome]]()
  for f in g.functions:
    known.incl(f.name)
    nameOf[f.id] = f.name
    cur[f.id] = initTable[string, Outcome]()
    calls[f.id] = @[]
  for e in g.edges:
    if calls.hasKey(e.callerId) and cur.hasKey(e.calleeId):
      calls[e.callerId].add(e.calleeId)
  for f in g.functions:
    regions[f.id] = tryRegionsOf(f)
    said = declaredRaises(f.signature)
    stated[f.id] = said.stated
    for o in ownOutcomes(f, lib, known):
      if said.stated and o.kind == okRaise:
        continue
      if not cur[f.id].hasKey(o.name) or cur[f.id][o.name].via.len > o.via.len:
        cur[f.id][o.name] = o
    for n in said.names:
      cur[f.id][n] = Outcome(name: n, kind: okRaise, via: @[f.name],
        source: "raised here")
  while moved and round < maxRounds:
    moved = false
    for f in g.functions:
      for calleeId in calls[f.id]:
        ats = siteLines(f, nameOf[calleeId])
        for _, o in cur[calleeId]:
          if o.kind == okRaise and stated[f.id]:
            continue
          if o.kind == okRaise and not anySurvives(regions[f.id], ats, o.name):
            continue
          if f.name in o.via or o.via.len >= maxChain:
            continue
          if cur[f.id].hasKey(o.name) and
              cur[f.id][o.name].via.len <= o.via.len + 1:
            continue
          cur[f.id][o.name] = Outcome(name: o.name, kind: o.kind,
            via: @[f.name] & o.via,
            source: (if o.source == "library": "library" else: "from a callee"))
          moved = true
    round = round + 1
  for id, rows in cur:
    if not result.hasKey(nameOf[id]):
      result[nameOf[id]] = @[]
    for _, o in rows:
      result[nameOf[id]].add(o)
  for name in result.keys:
    result[name].sort(shorterFirst)

proc carrierFieldOf*(rootDir, tName: string): string {.role: parser,
    metaTags: {tagGraph}.} =
  ## rootDir: the repository   tName: a return type.
  ## The entry of that type that holds a failure, or "" when it has
  ## none. A type carrying one can report trouble without raising, and
  ## a caller that never reads that entry is never told.
  var
    bare: string = tName.strip()
  result = ""
  for wrapper in ["ref ", "var ", "seq[", "Option[", "lent "]:
    if bare.startsWith(wrapper):
      bare = bare[wrapper.len .. ^1].strip(chars = {']', ' '})
  if bare.len == 0:
    return
  for p in listNimFiles(rootDir, bIncludeTests = false):
    for st in objectTypesIn(p, readLinesSafe(p)):
      if st.name != bare:
        continue
      for e in st.entries:
        if e.field.toLowerAscii() in errorFields:
          return e.field

proc isBarrier(f: FunctionInfo, regions: seq[TryRegion],
    sites: seq[tuple[name: string, at: int]]): bool {.role: parser,
    metaTags: {tagGraph}.} =
  ## f: one routine   regions: its try blocks   sites: its calls.
  ##
  ## Whether nothing from below reaches anybody above. True when the
  ## routine calls something and every one of those calls sits inside
  ## a block that catches everything. Where the barriers are is the
  ## difference between handling an error once and handling it nine
  ## times.
  var
    at: int = 0
  result = sites.len > 0
  for site in sites:
    at = regionAt(regions, site.at)
    if at < 0 or not regions[at].catchAll:
      return false

proc yieldPathsOf*(g: RepoGraph, name: string,
    escaping: Table[string, seq[Outcome]]): YieldPaths
    {.role: metaOrchestrator, metaTags: {tagGraph}.} =
  ## g: the whole graph   name: the routine being asked about
  ## escaping: the answer for every routine, from `escapingOf`.
  ##
  ## The one call to make before writing a call to something somebody
  ## else wrote. It says what comes back, what can be thrown instead,
  ## and whether the thing can stop the program outright.
  var
    regions: seq[TryRegion] = @[]
    sites: seq[tuple[name: string, at: int]] = @[]
    known: HashSet[string] = initHashSet[string]()
    fromLibrary: bool = false
    hits: int = 0
  result = YieldPaths(target: name, path: "", line: 0, returnType: "",
    carriesError: false, errorField: "", outcomes: @[], caught: @[],
    barrier: false, declared: false, notes: @[], error: "")
  for f in g.functions:
    known.incl(f.name)
  for f in g.functions:
    if f.name != name:
      continue
    hits = hits + 1
    if hits > 1:
      continue
    result.path = f.sourcePath
    result.line = f.lineStart
    result.returnType = f.returnType
    result.declared = declaredRaises(f.signature).stated
    regions = tryRegionsOf(f)
    sites = callSitesOf(f, known)
    for r in regions:
      for c in r.caught:
        if c notin result.caught:
          result.caught.add(c)
      if r.catchAll and "everything" notin result.caught:
        result.caught = @["everything"]
    result.barrier = isBarrier(f, regions, sites)
  if hits == 0:
    result.error = "no routine named " & name
    return
  if hits > 1:
    result.notes.add($hits & " routines share this name, and the answer " &
      "is the union of all of them")
  if escaping.hasKey(name):
    result.outcomes = escaping[name]
  result.errorField = carrierFieldOf(g.rootDir, result.returnType)
  result.carriesError = result.errorField.len > 0
  for o in result.outcomes:
    if o.source == "library" or (o.via.len > 1 and o.source == "from a callee"):
      fromLibrary = true
  if fromLibrary:
    result.notes.add("endings marked [library] rest on a written-down " &
      "list of standard library names, not on reading that library")
  if result.declared:
    result.notes.add("this routine states its own `raises`, which the " &
      "compiler checks, so that list is the truth and nothing here " &
      "argues with it")

proc yieldLines*(r: YieldPaths): seq[string] {.role: dataWriter,
    metaTags: {tagGraph}.} =
  ## r: one answer, as plain lines. The value first, because that is
  ## the answer most of the time; then the endings that a signature
  ## does not mention, worst first.
  var
    row: string = ""
    aborts: int = 0
  result = @[]
  if r.error.len > 0:
    result.add("yields: " & r.error)
    return
  result.add(r.target & "  " & r.path & ":" & $r.line)
  row = "  yields on success: "
  if r.returnType.len > 0:
    row = row & r.returnType
  else:
    row = row & "nothing"
  result.add(row)
  if r.carriesError:
    result.add("    that type carries a `" & r.errorField & "` entry, so " &
      "failure can arrive as a value. A caller that never reads it is " &
      "never told.")
  for o in r.outcomes:
    if o.kind == okAbort:
      aborts = aborts + 1
  if r.outcomes.len == 0:
    result.add("  nothing else escapes it")
  else:
    result.add("  can end with:")
  for o in r.outcomes:
    row = "    " & o.name & "  "
    while row.len < 22:
      row = row & " "
    row = row & o.via.join(" -> ")
    if o.source == "library":
      row = row & "   [library]"
    if o.name.endsWith("Defect"):
      row = row & "   [a defect: a bug to fix, not a case to handle]"
    if o.kind == okAbort and o.name == "assert":
      row = row & "   STOPS THE PROGRAM - no caller can catch it," &
        " unless it is built with assertions off"
    elif o.kind == okAbort:
      row = row & "   STOPS THE PROGRAM - no caller can catch it"
    result.add(row)
  if r.caught.len > 0:
    result.add("  caught here rather than passed on: " & r.caught.join(", "))
  if r.barrier:
    result.add("  this is a barrier: every call it makes sits inside a " &
      "block that catches everything, so nothing from below reaches " &
      "anybody above")
  for note in r.notes:
    result.add("  note: " & note)

type
  AbortReach* {.role: preparedData, metaTags: {tagGraph}.} = object
    ## One routine that can stop the program because of something it
    ## calls, rather than because of anything written in it.
    routine*: string
    path*: string
    line*: int
    how*: string
      ## `quit`, `doAssert`, `assert`.
    via*: seq[string]

proc abortReachOf*(g: RepoGraph, escaping: Table[string, seq[Outcome]]):
    seq[AbortReach] {.role: truthBuilder, metaTags: {tagGraph}.} =
  ## g: the whole graph   escaping: the answer for every routine.
  ##
  ## The routines that can stop the program because of something two
  ## or three levels below them. Those are worth listing on their own,
  ## because they are the ones nobody can see:
  ##
  ##   an exception thrown three levels down can be caught here
  ##   a `quit` three levels down cannot be caught anywhere
  ##
  ## A routine whose own body says `quit` is not listed - that one is
  ## visible to anybody reading it.
  var
    seen: HashSet[string] = initHashSet[string]()
  result = @[]
  for f in g.functions:
    if f.name in seen or not escaping.hasKey(f.name):
      continue
    for o in escaping[f.name]:
      if o.kind != okAbort or o.via.len < 3:
        continue
      seen.incl(f.name)
      result.add(AbortReach(routine: f.name, path: f.sourcePath,
        line: f.lineStart, how: o.name, via: o.via))
      break
  result.sort(proc (a, b: AbortReach): int =
    result = cmp(b.via.len, a.via.len)
    if result == 0:
      result = cmp(a.routine, b.routine))
