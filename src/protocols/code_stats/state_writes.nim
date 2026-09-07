## ================================================================
## | state_writes.nim  <-  who may change an entry, and who loses  |
## |---------------------------------------------------------------|
## | A state object is a shared table of facts. Every routine that  |
## | writes one of its entries is making a claim about the world.   |
## | Two routines writing the same entry is not by itself wrong -   |
## | it is wrong only when the second claim lands before anybody    |
## | has read the first one. Then the first claim never existed as  |
## | far as the rest of the program is concerned.                   |
## ================================================================
##
## The three states an entry can be in
## -----------------------------------
##
##   Feed.volume        Feed.price          Feed.lastSeen
##   -----------        ----------          -------------
##   ingest  writes     ingest  writes      ingest  writes
##   accum   reads it   resample writes     resample writes
##           then       nobody reads        nobody reads it
##           writes     between them        ever
##
##   SAFE               LOST                DEAD
##   the old value      whatever ingest     every write is
##   is folded into     stored is gone      thrown away
##   the new one
##
## Blind and folding
## -----------------
## A **blind write** replaces an entry without reading it first:
##
##     S.price = p            <- blind: p is all that is left
##
## A **folding write** reads the entry and puts it back changed, so
## nothing that was there is lost:
##
##     S.volume = S.volume + 1    <- folding
##     S.history.add(row)         <- folding, the list keeps its items
##     S.history.setLen(0)        <- blind, the list is emptied
##
## Only two blind writers can lose information. One blind writer and
## one folding writer cannot: the folding one carries the other's work
## forward.
##
## How a loss is proven rather than guessed
## ----------------------------------------
## Two blind writers are a shape, not yet a bug - they may never run
## near each other. So a **witness** is looked for: some routine that
## calls one and then the other, with nothing in between that reads
## the entry. When a witness is found, the finding names the file and
## the two lines, and a person can check it in ten seconds. When none
## is found, the finding says so and is worded as a shape to watch.
##
##     runFeed:
##       ingest(S, 1.0)     <- writes price
##       resample(S)        <- writes price again      LOST
##       discard render(S)  <- reads it, too late
##
##     runSafe:
##       snapshot(S, 1)     <- writes depth
##       showDepth(S)       <- reads it                 fine
##       rebase(S, 2)       <- writes depth again
##
## When losing the old value is the point
## --------------------------------------
## A live feed often wants only the newest reading, and every older
## one is meant to fall on the floor. Say so on the entry and it stops
## being reported:
##
##     ticker*: string   ## otter:latest
##
## What this cannot see
## --------------------
## This reads text, not a running program. Two writers called from two
## different threads have no line order to check, so no witness will
## be found and the weaker wording is used. A state reached through a
## name this cannot tie back to its type - handed in as a `pointer`,
## or reached through a field of another object - is not counted.
##
## Only direct calls are read when looking for a witness. Two writers
## reached through a wrapper each - `open` calling `ingest`, `refresh`
## calling `resample` - come out as "nothing was seen calling two of
## them in a row", which is the careful answer rather than the
## complete one.

import std/[algorithm, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import ../repo_graph/io_utils
import ../../../meta/metaPragmas

const
  latestMarker*: string = "otter:latest"
    ## Written on an entry whose older values are meant to be dropped.

  foldingCalls*: array[7, string] = [
    ".add(", ".incl(", ".insert(", ".mgetOrPut(",
    ".addLast(", ".addFirst(", ".push("
  ]
    ## Calls that put something into an entry and leave what was there.

  replacingCalls*: array[5, string] = [
    ".setLen(", ".clear(", ".reset(", ".del(", ".delete("
  ]
    ## Calls that take the entry back to empty, losing what it held.

  stateRoles*: array[2, string] = ["truthstate", "memory"]
    ## The two type roles the conventions give to shared, written state.

  resetWords*: array[8, string] = [
    "clear", "reset", "wipe", "zero", "erase", "destroy", "free", "dispose"
  ]
    ## A routine named for taking a value away is not losing anything
    ## when the next writer replaces what it left. Throwing the old
    ## value out was the whole job:
    ##
    ##   clear(S)      <- puts zeroes in, on purpose
    ##   init(S, key)  <- puts the real thing in
    ##
    ## Reading that pair as a loss would report every wipe-then-fill
    ## routine in a cryptography library, which is most of them.

type
  FieldTraffic* {.role: truthState, metaTags: {tagGraph, tagState}.} = object
    ## One entry of a state object, and everyone who touches it.
    field*: string
    typeName*: string
    line*: int
    blindWriters*: seq[string]
      ## Replace the entry without reading it. Two of these can lose work.
    foldingWriters*: seq[string]
      ## Read it, then write it back. These never lose anything.
    readers*: seq[string]
      ## Read it and do not write it.
    allowed*: bool
      ## The entry says only its newest value matters.
    hazard*: bool
      ## Two of its blind writers were found landing one after the
      ## other with no read in between.

  StateHazard* {.role: preparedData, metaTags: {tagGraph, tagState}.} = object
    ## Two blind writers of one entry, and the proof if there is one.
    typeName*: string
    field*: string
    first*: string
    second*: string
    witness*: string
      ## The routine that calls both in a row. Empty when none was found.
    path*: string
    firstLine*: int
    secondLine*: int

  StateType* {.role: truthState, metaTags: {tagGraph, tagState}.} = object
    name*: string
    path*: string
    line*: int
    role*: string
    entries*: seq[FieldTraffic]
    wholeWriters*: seq[string]
      ## Routines that replace the entire object at once.

  StateHolder* {.role: preparedData, metaTags: {tagGraph, tagState}.} = object
    ## One routine that holds a state object, and the names it holds it
    ## under. Two sets rather than one because the two questions have
    ## different answers: `writes` is strict, `reads` is generous.
    f*: FunctionInfo
    writes*: HashSet[string]
    reads*: HashSet[string]

  Pairing* {.role: preparedData, metaTags: {tagGraph, tagState}.} = object
    ## Two blind writers found next to each other in one routine.
    found*: bool
    guarded*: bool
      ## Something between them reads the entry, so nothing was lost.
    a*: int
    b*: int
    first*: string
    second*: string

  StateSources* {.role: rawData, metaTags: {tagGraph, tagState}.} = object
    ## What one walk of the files turns up: the object types, and the
    ## names declared at module level in each file.
    states*: seq[StateType]
    globals*: Table[string, seq[tuple[name, typ: string]]]

  StateReport* {.role: truthState, metaTags: {tagGraph, tagState}.} = object
    rootDir*: string
    states*: seq[StateType]
    hazards*: seq[StateHazard]
    unread*: seq[string]
      ## "Type.field" for every entry written by somebody and read by
      ## nobody. Every one of those writes is thrown away.
    notes*: seq[string]
    error*: string

proc isIdentChar(c: char): bool {.inline.} =
  result = c.isAlphaNumeric() or c == '_'

proc isResetter*(name: string): bool {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## name: a routine.
  ## Whether it is named for emptying a value rather than for setting
  ## one. Judged by the name because that is what a person judges it
  ## by, and because a routine that writes only zeroes is not always
  ## written as zeroes.
  var
    t: string = name.toLowerAscii()
  result = false
  for w in resetWords:
    if w in t:
      return true

proc codeOf*(s: string): string {.role: sanitizer,
    metaTags: {tagGraph, tagState}.} =
  ## s: one line of Nim. The same line with any trailing comment cut
  ## off, so that a field named in a comment is not read as a write.
  ## A `#` inside a string stays, because it is not a comment there.
  var
    inStr: bool = false
    i: int = 0
  result = s
  while i < s.len:
    if s[i] == '"' and (i == 0 or s[i - 1] != '\\'):
      inStr = not inStr
    if s[i] == '#' and not inStr:
      return s[0 ..< i]
    i = i + 1

proc withoutStrings*(s: string): string {.role: sanitizer,
    metaTags: {tagGraph, tagState}.} =
  ## s: one line of code, its comment already cut off.
  ## The same line with the inside of every double-quoted string
  ## blanked out. A name written inside a string is a word, not a
  ## reference, and reading it as one invents findings:
  ##
  ##   row.startsWith("doAssert false")   <- does not assert anything
  ##   S.name = "price is high"           <- does not write S.price
  var
    i: int = 0
    inStr: bool = false
  result = s
  while i < s.len:
    if s[i] == '"' and (i == 0 or s[i - 1] != '\\'):
      inStr = not inStr
      i = i + 1
      continue
    if inStr:
      result[i] = ' '
    i = i + 1

proc bareCode*(s: string): string {.role: sanitizer,
    metaTags: {tagGraph, tagState}.} =
  ## s: one line as written. What is left once the comment and the
  ## inside of every string are gone: only the code that does
  ## something. This is what every scanner in this file and the next
  ## one reads, so none of them can be fooled by prose.
  result = withoutStrings(codeOf(s))

proc rootIdentAt(s: string, at: int): string {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## s: one line   at: the index of a dot.
  ## The name the dotted chain starts from: in `a.b.field` the answer
  ## is `a`, because `a` is the variable that holds the object. A
  ## chain starting from a call - `getFeed().price` - yields "" and is
  ## therefore never counted.
  var
    i: int = at - 1
    chain: string = ""
    dot: int = 0
  result = ""
  while i >= 0 and (isIdentChar(s[i]) or s[i] == '.'):
    i = i - 1
  if i + 1 > at - 1:
    return
  chain = s[i + 1 .. at - 1]
  dot = chain.find('.')
  if dot < 0:
    result = chain
  else:
    result = chain[0 ..< dot]

proc skipSubscript(s: string): tuple[rest: string, stepped: bool]
    {.role: parser, metaTags: {tagGraph, tagState}.} =
  ## s: whatever follows an entry name.
  ## Steps over `[...]` so that `S.rows[i] = v` is judged on its `=`
  ## rather than on its bracket. Writing one slot of a list is a
  ## folding write: every other slot survives it.
  var
    rest: string = s.strip()
    d: int = 0
    i: int = 0
  result = (rest: rest, stepped: false)
  while rest.len > 0 and rest[0] == '[':
    d = 0
    i = 0
    while i < rest.len:
      if rest[i] == '[':
        d = d + 1
      if rest[i] == ']':
        d = d - 1
        if d == 0:
          break
      i = i + 1
    if i >= rest.len:
      return
    rest = rest[i + 1 .. ^1].strip()
    result = (rest: rest, stepped: true)

proc useKind*(after: string): int {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## after: the text that follows an entry name on its line.
  ## 0 read, 1 blind write, 2 folding write. Reading is the default,
  ## because mentioning a value without an assignment near it is what
  ## reading looks like.
  var
    step: tuple[rest: string, stepped: bool] = skipSubscript(after)
    rest: string = step.rest
  result = 0
  for c in foldingCalls:
    if rest.startsWith(c):
      return 2
  for c in replacingCalls:
    if rest.startsWith(c):
      if step.stepped:
        return 2
      return 1
  if rest.startsWith("==") or rest.startsWith("=~"):
    return 0
  if rest.len >= 2 and rest[0] in {'+', '-', '*', '/', '&'} and rest[1] == '=':
    return 2
  if rest.startsWith("="):
    if step.stepped:
      return 2
    return 1

proc fieldUses*(line: string, recvs: HashSet[string], field: string):
    tuple[writes, folds, reads: int] {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## line: one line of a routine   recvs: names holding the state
  ## field: the entry being asked about.
  ##
  ## `S.price = S.price + 1` has two mentions on one line: the first
  ## is a write and the second is a read, so both are counted and the
  ## routine comes out as a folding writer.
  var
    s: string = bareCode(line)
    needle: string = "." & field
    at: int = 0
    from0: int = 0
    after: int = 0
    kind: int = 0
  result = (writes: 0, folds: 0, reads: 0)
  while from0 <= s.len - needle.len:
    at = s.find(needle, from0)
    if at < 0:
      return
    from0 = at + needle.len
    after = at + needle.len
    if after < s.len and isIdentChar(s[after]):
      continue
    if rootIdentAt(s, at) notin recvs:
      continue
    kind = useKind(s[after .. ^1])
    if kind == 1:
      result.writes = result.writes + 1
    elif kind == 2:
      result.folds = result.folds + 1
    else:
      result.reads = result.reads + 1

proc paramText(signature: string): string {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## signature: a routine declaration as written.
  ## What sits between its outermost parentheses, or "" when it takes
  ## nothing.
  var
    at: int = signature.find('(')
    d: int = 0
    i: int = 0
  result = ""
  if at < 0:
    return
  i = at
  while i < signature.len:
    if signature[i] == '(':
      d = d + 1
    if signature[i] == ')':
      d = d - 1
      if d == 0:
        return signature[at + 1 ..< i]
    i = i + 1
  result = signature[at + 1 .. ^1]

proc wholeWord(hay, needle: string): bool {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## hay: any text   needle: a name.
  ## Whether the name stands there on its own. `Feed` is inside
  ## `FeedRow`, and treating that as a match would tie two different
  ## types together.
  var
    at: int = 0
    from0: int = 0
  result = false
  while from0 <= hay.len - needle.len:
    at = hay.find(needle, from0)
    if at < 0:
      return
    from0 = at + needle.len
    if at > 0 and isIdentChar(hay[at - 1]):
      continue
    if at + needle.len < hay.len and isIdentChar(hay[at + needle.len]):
      continue
    return true

proc namesTypedAs(text, tName: string, bSharedOnly: bool): seq[string]
    {.role: parser, metaTags: {tagGraph, tagState}.} =
  ## text: the parameters of a routine   tName: the state type
  ## bSharedOnly: keep only the ones the routine can write through.
  ##
  ## `(a, b: int, S: var Feed)` is read as two groups, so only `S`
  ## comes back. The `bSharedOnly` switch is the difference between the
  ## two questions this module asks:
  ##
  ##   S: var Feed    the caller's object. Writing it changes the world.
  ##   S: ptr Feed    same.        S: ref Feed   same.
  ##   S: Feed        a copy, and Nim will not let it be assigned at
  ##                  all. Reading it is still reading shared state.
  var
    pending: seq[string] = @[]
    piece: string = ""
    colon: int = 0
    typ: string = ""
    shared: bool = false
    n: string = ""
  result = @[]
  for raw in text.split(','):
    piece = raw.strip()
    if piece.len == 0:
      continue
    colon = piece.find(':')
    if colon < 0:
      pending.add(piece)
      continue
    pending.add(piece[0 ..< colon].strip())
    typ = piece[colon + 1 .. ^1].strip()
    shared = typ.startsWith("var ") or typ.startsWith("ptr ") or
      typ.startsWith("ref ")
    typ = typ.replace("var ", "").replace("ptr ", "").replace("ref ", "")
    typ = typ.replace("sink ", "").replace("lent ", "").split('=')[0].strip()
    if typ == tName and (shared or not bSharedOnly):
      for p in pending:
        n = p.split(';')[^1].strip()
        if n.len > 0 and n notin result:
          result.add(n)
    pending = @[]

proc localsTypedAs(f: FunctionInfo, tName: string,
    containers: HashSet[string]): seq[string] {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## f: one routine   tName: the state type
  ## containers: field names known to hold a list of them.
  ##
  ## Names inside the routine that plausibly hold one of these. Three
  ## ways they arise, and the third is the one that matters most on a
  ## real repository:
  ##
  ##   var s: Feed            written out
  ##   s = Feed(price: 1.0)   built from the type's own constructor
  ##   for e in g.edges       taken one at a time out of a list of them
  ##
  ## Without the third, every routine that walks a list of records
  ## looks as though it never reads one, and each of their entries is
  ## reported as written and never read. That was the first thing this
  ## got wrong when it was pointed at a real tree.
  var
    s: string = ""
    at: int = 0
    n: string = ""
    tail: string = ""
  result = @[]
  for raw in f.bodyLines:
    s = bareCode(raw).strip()
    if s.startsWith("for ") and " in " in s:
      tail = s[s.find(" in ") + 4 .. ^1].strip(chars = {' ', ':'})
      n = tail.split({'.', '(', '[', ' '})[^1]
      if tail.split('.')[^1].split({'(', '[', ' '})[0] notin containers:
        continue
      n = s[4 ..< s.find(" in ")].strip().split(',')[^1].strip()
      if n.len > 0 and n notin result:
        result.add(n)
      continue
    at = s.find(": " & tName)
    if at < 0:
      at = s.find("= " & tName & "(")
      if at < 0:
        continue
    n = s[0 ..< at].strip()
    for prefix in ["var ", "let ", "const ", "result ", "discard "]:
      if n.startsWith(prefix):
        n = n[prefix.len .. ^1].strip()
    n = n.split(',')[0].strip()
    if n.len > 0 and n.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_'}) and
        n notin result:
      result.add(n)

proc writeReceivers*(f: FunctionInfo, tName: string,
    globals: HashSet[string]): HashSet[string] {.role: truthBuilder,
    metaTags: {tagGraph, tagState}.} =
  ## f: one routine   tName: the state type
  ## globals: module-level names of that type in this routine's file.
  ##
  ## Which names this routine can write and have somebody else notice.
  ## Being strict here is the whole difference between a report worth
  ## reading and one that is ignored:
  ##
  ##   proc build(): Socket =      result.name = "x"   <- its own object
  ##     ...                       nobody else can see it, so this is
  ##                               not a second writer of Socket.name
  ##
  ##   proc fill(S: var Feed) =    S.price = 1.0       <- the caller's
  ##                               object. This one counts.
  ##
  ## Counting local building as writing turned every "make one and fill
  ## it in" routine in a tree into a writer of every entry, and buried
  ## the four findings that were real under sixty that were not.
  result = initHashSet[string]()
  for n in namesTypedAs(paramText(f.signature), tName, bSharedOnly = true):
    result.incl(n)
  for n in globals:
    result.incl(n)

proc readReceivers*(f: FunctionInfo, tName: string, globals,
    containers: HashSet[string]): HashSet[string] {.role: truthBuilder,
    metaTags: {tagGraph, tagState}.} =
  ## f: one routine   tName: the state type   globals: as above
  ## containers: field names holding a list of them.
  ##
  ## Which names this routine might read one through. Generous on
  ## purpose, and the opposite of `writeReceivers` for a reason: a
  ## reader that is counted by mistake only ever silences a finding,
  ## while a writer counted by mistake invents one. Silence is the
  ## cheaper mistake.
  result = writeReceivers(f, tName, globals)
  for n in namesTypedAs(paramText(f.signature), tName, bSharedOnly = false):
    result.incl(n)
  for n in localsTypedAs(f, tName, containers):
    result.incl(n)
  if wholeWord(f.returnType, tName) or wholeWord(f.signature, tName):
    result.incl("result")

proc replacesWholeObject(f: FunctionInfo, recvs: HashSet[string],
    tName: string): bool {.role: parser, metaTags: {tagGraph, tagState}.} =
  ## f: one routine   recvs: names it can write   tName: their type.
  ## Whether the routine puts a freshly built object over the top of
  ## one somebody else holds. That touches every entry at once, which
  ## is why it is reported apart from the per-entry counts.
  var
    s: string = ""
  result = false
  for raw in f.bodyLines:
    s = bareCode(raw).strip()
    for r in recvs:
      if s.startsWith(r & " = " & tName & "(") or
          s.startsWith(r & " = default(" & tName):
        return true
proc declaredTypeName(s: string): string {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## s: a stripped line that declares an object type.
  ## Its name, without the export star, the generic brackets or the
  ## pragma that may follow it.
  var
    t: string = s
    i: int = 0
  result = ""
  while i < t.len and (isIdentChar(t[i])):
    i = i + 1
  if i == 0:
    return
  result = t[0 ..< i]

proc typeRoleOf(s: string): string {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## s: a line that may carry `{.role: truthState.}`, either as a real
  ## pragma or written inside a comment, which is how the conventions
  ## ask for roles in files that cannot hold pragmas.
  var
    at: int = s.find("role:")
    t: string = ""
    i: int = 0
  result = ""
  if at < 0:
    return
  t = s[at + 5 .. ^1].strip()
  while i < t.len and isIdentChar(t[i]):
    i = i + 1
  result = t[0 ..< i].toLowerAscii()

proc fieldOf(s: string): tuple[name, typ: string] {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## s: one stripped line inside an object body.
  ## The entry it declares and what that entry holds, or two empty
  ## strings when the line declares no entry. The discriminant of a
  ## variant object - `case kind*: Colour of` - is an entry like any
  ## other, so the leading word is stepped over.
  var
    t: string = s
    colon: int = 0
    n: string = ""
  result = (name: "", typ: "")
  if t.startsWith("case "):
    t = t[5 .. ^1].strip()
  colon = t.find(':')
  if colon <= 0:
    return
  n = t[0 ..< colon].strip()
  if n.endsWith("*"):
    n = n[0 ..< n.len - 1]
  if n.len == 0 or not n.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_'}):
    return
  if n[0] notin {'a'..'z', 'A'..'Z', '_'}:
    return
  result = (name: n, typ: t[colon + 1 .. ^1].split('=')[0].strip(
    chars = {' ', ',', ';'}))

proc indentOf(s: string): int {.inline.} =
  result = 0
  while result < s.len and s[result] == ' ':
    result = result + 1

proc objectTypesIn*(path: string, lines: seq[string]): seq[StateType]
    {.role: parser, metaTags: {tagGraph, tagState}.} =
  ## path: the file   lines: its contents.
  ##
  ## Every object type declared in the file, with its entries in the
  ## order they were written. A type is not a routine, so the call
  ## graph does not carry one; this reads the declaration as text.
  ##
  ##   type
  ##     Feed* = object      <- indent 2, the block opens here
  ##       price*: float     <- indent 4, an entry
  ##       volume*: int      <- indent 4, an entry
  ##     Other* = object     <- indent 2 again, so Feed is finished
  var
    i: int = 0
    openIndent: int = -1
    open: bool = false
    s: string = ""
    st: StateType = StateType()
    got: tuple[name, typ: string] = ("", "")
  result = @[]
  while i < lines.len:
    s = bareCode(lines[i]).strip()
    if open and s.len > 0 and indentOf(lines[i]) <= openIndent:
      result.add(st)
      open = false
    if ("= object" in s or "= ref object" in s) and not s.startsWith("#"):
      st = StateType(name: declaredTypeName(s), path: path, line: i + 1,
        role: typeRoleOf(lines[i]), entries: @[], wholeWriters: @[])
      openIndent = indentOf(lines[i])
      open = st.name.len > 0
      i = i + 1
      continue
    if not open:
      i = i + 1
      continue
    if st.role.len == 0 and lines[i].strip().startsWith("##"):
      st.role = typeRoleOf(lines[i])
    got = fieldOf(s)
    if got.name.len > 0 and not s.startsWith("##"):
      st.entries.add(FieldTraffic(field: got.name, typeName: got.typ,
        line: i + 1, blindWriters: @[], foldingWriters: @[], readers: @[],
        allowed: latestMarker in lines[i]))
    i = i + 1
  if open:
    result.add(st)

proc globalsIn(lines: seq[string]): seq[tuple[name, typ: string]]
    {.role: parser, metaTags: {tagGraph, tagState}.} =
  ## lines: one file.
  ##
  ## The names declared at the very left of the file, outside every
  ## routine. Those are the objects that any routine in the module can
  ## write without being handed them, which is the oldest way for two
  ## routines to lose each other's work:
  ##
  ##   var                      <- a block at indent 0
  ##     cache*: Feed = Feed()  <- writable from anywhere in the file
  var
    i: int = 0
    inBlock: bool = false
    s: string = ""
    got: tuple[name, typ: string] = ("", "")
  result = @[]
  while i < lines.len:
    s = bareCode(lines[i]).strip()
    if indentOf(lines[i]) == 0 and s.len > 0:
      inBlock = (s == "var")
      if s.startsWith("var "):
        got = fieldOf(s[4 .. ^1])
        if got.name.len > 0:
          result.add(got)
      i = i + 1
      continue
    if not inBlock or s.len == 0 or s.startsWith("#"):
      i = i + 1
      continue
    got = fieldOf(s)
    if got.name.len > 0:
      result.add(got)
    i = i + 1

proc statesIn(rootDir: string): StateSources
    {.role: dataFetcher, metaTags: {tagGraph, tagState}.} =
  ## rootDir: the repository.
  ## Every object type it declares that has at least one entry - a type
  ## with none has nothing to lose - and, per file, the names declared
  ## at module level.
  var
    lines: seq[string] = @[]
    globals: seq[tuple[name, typ: string]] = @[]
  result = StateSources(states: @[],
    globals: initTable[string, seq[tuple[name, typ: string]]]())
  for p in listNimFiles(rootDir, bIncludeTests = false):
    lines = readLinesSafe(p)
    for st in objectTypesIn(p, lines):
      if st.entries.len > 0:
        result.states.add(st)
    globals = globalsIn(lines)
    if globals.len > 0:
      result.globals[p] = globals

proc containersOf(states: seq[StateType], tName: string): HashSet[string]
    {.role: truthBuilder, metaTags: {tagGraph, tagState}.} =
  ## states: every type in the repository   tName: the state type.
  ##
  ## Entry names anywhere in the tree that hold a list of these, so
  ## that `for e in g.edges` can be read as "e is a CallEdge". Without
  ## it every routine that walks a list of records looks as though it
  ## never reads one.
  result = initHashSet[string]()
  for st in states:
    for e in st.entries:
      if e.typeName != tName and wholeWord(e.typeName, tName):
        result.incl(e.field)

proc globalsAt(globals: Table[string, seq[tuple[name, typ: string]]],
    path, tName: string): HashSet[string] {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## globals: every module-level name, by file   path: one file
  ## tName: the state type. The ones in that file holding one.
  result = initHashSet[string]()
  if not globals.hasKey(path):
    return
  for g in globals[path]:
    if g.typ == tName:
      result.incl(g.name)

proc mightHold(text, tName: string, containers: HashSet[string]): bool
    {.role: parser, metaTags: {tagGraph, tagState}.} =
  ## text: one routine, signature and body together   tName: a type
  ## containers: entry names holding a list of them.
  ##
  ## A cheap "no" before the careful work. On a tree with four hundred
  ## types and two thousand routines the careful work would otherwise
  ## run eight hundred thousand times, and it does not need to: a
  ## routine that never writes the type's name, and never walks a list
  ## of them, cannot be holding one.
  result = false
  if wholeWord(text, tName):
    return true
  for c in containers:
    if wholeWord(text, c):
      return true

proc holdersOf(g: RepoGraph, texts: seq[string], tName: string,
    states: seq[StateType],
    globals: Table[string, seq[tuple[name, typ: string]]]): seq[StateHolder]
    {.role: truthBuilder, metaTags: {tagGraph, tagState}.} =
  ## g: the whole graph   texts: each routine as one string
  ## tName: a state type   states: every type
  ## globals: module-level names by file.
  ##
  ## Only the routines that hold one of these objects can touch its
  ## entries, and on any real repository that is a handful out of
  ## hundreds. Finding them once, before the entries are walked, is
  ## what keeps this from reading every routine once per entry.
  var
    containers: HashSet[string] = containersOf(states, tName)
    mine: HashSet[string] = initHashSet[string]()
    writes: HashSet[string] = initHashSet[string]()
    reads: HashSet[string] = initHashSet[string]()
    i: int = 0
  result = @[]
  while i < g.functions.len:
    if not mightHold(texts[i], tName, containers):
      i = i + 1
      continue
    mine = globalsAt(globals, g.functions[i].sourcePath, tName)
    writes = writeReceivers(g.functions[i], tName, mine)
    reads = readReceivers(g.functions[i], tName, mine, containers)
    if writes.len + reads.len > 0:
      result.add(StateHolder(f: g.functions[i], writes: writes,
        reads: reads))
    i = i + 1

proc fillTraffic(st: var StateType, holders: seq[StateHolder])
    {.role: truthBuilder,
    metaTags: {tagGraph, tagState}.} =
  ## st: one state type, filled in place   holders: its routines.
  ##
  ## A routine that both writes and reads an entry is a folding writer
  ## whichever order the two happen in. That is deliberately generous:
  ## calling a routine a folding writer says "this one cannot lose
  ## anything", and being generous there means the findings that are
  ## left are the ones worth reading.
  var
    w: tuple[writes, folds, reads: int] = (0, 0, 0)
    r: tuple[writes, folds, reads: int] = (0, 0, 0)
    one: tuple[writes, folds, reads: int] = (0, 0, 0)
    k: int = 0
  for h in holders:
    if replacesWholeObject(h.f, h.writes, st.name):
      st.wholeWriters.add(h.f.name)
  while k < st.entries.len:
    for h in holders:
      w = (writes: 0, folds: 0, reads: 0)
      r = (writes: 0, folds: 0, reads: 0)
      for raw in h.f.bodyLines:
        one = fieldUses(raw, h.writes, st.entries[k].field)
        w.writes = w.writes + one.writes
        w.folds = w.folds + one.folds
        one = fieldUses(raw, h.reads, st.entries[k].field)
        r.folds = r.folds + one.folds
        r.reads = r.reads + one.reads
      if w.folds > 0 or (w.writes > 0 and r.reads + r.folds > 0):
        st.entries[k].foldingWriters.add(h.f.name)
      elif w.writes > 0:
        st.entries[k].blindWriters.add(h.f.name)
      elif r.reads > 0 or r.folds > 0:
        st.entries[k].readers.add(h.f.name)
    k = k + 1

proc absLine(f: FunctionInfo, k: int): int {.inline.} =
  ## f: one routine   k: an index into its body.
  ## Which line of the file that is. The parser keeps the body without
  ## its header, and records where the routine ends, so counting back
  ## from the end is the one arithmetic that stays right when a header
  ## is wrapped over three lines.
  result = f.lineEnd - f.bodyLines.len + k + 1

proc callOffsets(f: FunctionInfo, names: seq[string]):
    seq[tuple[at: int, name: string]] {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## f: one routine   names: the routines being looked for.
  ## Where in this body each of them is called, in the order written.
  var
    s: string = ""
    at: int = 0
    k: int = 0
  result = @[]
  while k < f.bodyLines.len:
    s = bareCode(f.bodyLines[k])
    for n in names:
      at = s.find(n & "(")
      if at < 0:
        continue
      if at > 0 and isIdentChar(s[at - 1]):
        continue
      result.add((at: k, name: n))
    k = k + 1

proc readsBetween(f: FunctionInfo, recvs: HashSet[string], field: string,
    readers: seq[string], i, j: int): bool {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## f: the routine holding both calls   recvs: names holding the state
  ## field: the entry   readers: routines known to read it
  ## i, j: the two call lines.
  ##
  ## Whether anything between the two writes looks at the entry, either
  ## by naming it outright or by calling somebody who does. If it does,
  ## the first value reached a reader and nothing was lost.
  var
    k: int = i + 1
    s: string = ""
    at: int = 0
  result = false
  while k < j:
    s = bareCode(f.bodyLines[k])
    if fieldUses(s, recvs, field).reads > 0:
      return true
    for n in readers:
      at = s.find(n & "(")
      if at < 0:
        continue
      if at > 0 and isIdentChar(s[at - 1]):
        continue
      return true
    k = k + 1

proc firstUnguarded(h: StateHolder, e: FieldTraffic,
    readers: seq[string]): Pairing {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## h: one routine that holds the state   e: the entry
  ## readers: routines known to read it.
  ##
  ## Walks this routine's calls to the entry's blind writers, in the
  ## order written, and reports the first neighbouring pair. `guarded`
  ## says a read sits between them, which is the whole difference
  ## between a loss and a perfectly ordinary sequence.
  var
    offsets: seq[tuple[at: int, name: string]] = callOffsets(h.f,
      e.blindWriters)
    k: int = 0
  result = Pairing(found: false, guarded: false, a: 0, b: 0, first: "",
    second: "")
  if offsets.len < 2:
    return
  while k + 1 < offsets.len:
    if offsets[k].name == offsets[k + 1].name:
      k = k + 1
      continue
    result = Pairing(found: true,
      guarded: readsBetween(h.f, h.reads, e.field, readers, offsets[k].at,
        offsets[k + 1].at),
      a: absLine(h.f, offsets[k].at), b: absLine(h.f, offsets[k + 1].at),
      first: offsets[k].name, second: offsets[k + 1].name)
    if not result.guarded:
      return
    k = k + 1

proc witnessFor(holders: seq[StateHolder], st: StateType,
    e: FieldTraffic): tuple[haz: StateHazard, guarded: bool]
    {.role: truthBuilder,
    metaTags: {tagGraph, tagState}.} =
  ## holders: the routines that hold this state   st: the type
  ## e: one of its entries.
  ##
  ## Three answers are possible, and telling them apart is the point:
  ##
  ##   proven    somebody calls one writer then the other with no read
  ##             between them. The file and the two lines are named.
  ##   guarded   somebody calls both, but reads the entry in between.
  ##             Nothing is lost, so this is not reported at all.
  ##   unseen    nothing calls two of them. A shape to watch.
  ##
  ## Without the middle answer every ordinary read-then-replace loop
  ## would be reported, and the report would be ignored.
  ##
  ## Only holders are searched, and that loses nothing: a routine that
  ## calls two writers of this state has to have got the state from
  ## somewhere, so it holds one too.
  var
    readers: seq[string] = e.readers & e.foldingWriters
    got: Pairing = Pairing()
    anyGuarded: bool = false
  result = (haz: StateHazard(typeName: st.name, field: e.field,
    first: e.blindWriters[0], second: e.blindWriters[1], witness: "",
    path: st.path, firstLine: 0, secondLine: 0), guarded: false)
  for h in holders:
    got = firstUnguarded(h, e, readers)
    if not got.found:
      continue
    if got.guarded:
      anyGuarded = true
      continue
    result.haz.witness = h.f.name
    result.haz.path = h.f.sourcePath
    result.haz.first = got.first
    result.haz.second = got.second
    result.haz.firstLine = got.a
    result.haz.secondLine = got.b
    return
  result.guarded = anyGuarded

proc allResetters(names: seq[string]): bool {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## names: the blind writers of one entry.
  ## Whether every one of them is there to empty it. A field written
  ## only by wipe routines is not a field whose writes are thrown
  ## away: throwing the value away is what those routines are for.
  result = names.len > 0
  for n in names:
    if not isResetter(n):
      return false

proc anyResetter(names: seq[string]): bool {.role: parser,
    metaTags: {tagGraph, tagState}.} =
  ## names: the blind writers of one entry.
  ## Whether one of them is there to empty the entry. If so the pair is
  ## not a loss in either order: emptying then filling is a sequence,
  ## and filling then emptying is a wipe.
  result = false
  for n in names:
    if isResetter(n):
      return true

proc collectFindings(holders: seq[StateHolder], at: int, r: var StateReport)
    {.role: truthBuilder, metaTags: {tagGraph, tagState}.} =
  ## holders: the routines that hold this state   at: which state of
  ## the report   r: the report, added to.
  ##
  ## An entry nobody reads is the stronger statement: every write to it
  ## is thrown away, so also saying that its writers overwrite each
  ## other adds nothing a person can act on. The two findings are
  ## therefore exclusive, and the dead one wins.
  var
    got: tuple[haz: StateHazard, guarded: bool] = (StateHazard(), false)
    k: int = 0
  while k < r.states[at].entries.len:
    if r.states[at].entries[k].allowed or
        r.states[at].entries[k].blindWriters.len +
        r.states[at].entries[k].foldingWriters.len == 0:
      k = k + 1
      continue
    if r.states[at].entries[k].readers.len == 0 and
        r.states[at].entries[k].foldingWriters.len == 0 and
        not allResetters(r.states[at].entries[k].blindWriters):
      r.unread.add(r.states[at].name & "." & r.states[at].entries[k].field)
      k = k + 1
      continue
    if r.states[at].entries[k].blindWriters.len < 2 or
        anyResetter(r.states[at].entries[k].blindWriters):
      k = k + 1
      continue
    got = witnessFor(holders, r.states[at], r.states[at].entries[k])
    if not got.guarded:
      r.hazards.add(got.haz)
      r.states[at].entries[k].hazard = true
    k = k + 1

proc isState(st: StateType): bool {.inline.} =
  ## st: one type. Whether it was declared to be shared, written state.
  result = st.role in stateRoles

proc stateWritesOf*(g: RepoGraph, focus: string = ""): StateReport
    {.role: metaOrchestrator, metaTags: {tagGraph, tagState}.} =
  ## g: the whole graph   focus: one type name, or "" for all of them.
  ##
  ## The one call to make before adding a routine that writes shared
  ## state. Types carrying `{.role: truthState.}` or `{.role: memory.}`
  ## come first, because those are the ones the conventions say are
  ## written from many places; the rest follow so that a repository
  ## which tags nothing still gets an answer.
  var
    found: StateSources = StateSources()
    holders: seq[StateHolder] = @[]
    st: StateType = StateType()
    texts: seq[string] = @[]
    touched: int = 0
  result = StateReport(rootDir: g.rootDir, states: @[], hazards: @[],
    unread: @[], notes: @[], error: "")
  found = statesIn(g.rootDir)
  for f in g.functions:
    texts.add(f.signature & "\n" & f.bodyLines.join("\n"))
  if found.states.len == 0:
    result.error = "no object types found below " & g.rootDir
    return
  for candidate in found.states:
    if focus.len > 0 and candidate.name != focus:
      continue
    st = candidate
    holders = holdersOf(g, texts, st.name, found.states, found.globals)
    if holders.len == 0:
      continue
    fillTraffic(st, holders)
    touched = 0
    for e in st.entries:
      touched = touched + e.blindWriters.len + e.foldingWriters.len
    if touched == 0 and st.wholeWriters.len == 0:
      continue
    result.states.add(st)
    collectFindings(holders, result.states.len - 1, result)
  result.states.sort(proc (a, b: StateType): int =
    result = cmp(int(isState(b)), int(isState(a)))
    if result == 0:
      result = cmp(a.name, b.name))
  if focus.len > 0 and result.states.len == 0:
    result.error = "no type named " & focus & " is written anywhere"
  result.notes.add("only routines handed the state as `var`, `ptr` or " &
    "`ref`, or reaching it as a module-level name, count as writing it; " &
    "a routine building its own copy is not writing anybody's state")

proc padTo(s: string, n: int): string {.inline.} =
  result = s
  while result.len < n:
    result = result & " "

proc entryLine(e: FieldTraffic): string {.role: dataWriter,
    metaTags: {tagGraph, tagState}.} =
  ## e: one entry. Its row of the table, and the one word that says
  ## what is wrong with it, if anything is.
  var
    flag: string = ""
  if e.allowed:
    flag = "  (" & latestMarker & ")"
  elif e.readers.len == 0 and e.foldingWriters.len == 0 and
      not allResetters(e.blindWriters):
    flag = "  ! never read"
  elif e.hazard:
    flag = "  ! overwrite"
  result = "    " & padTo(e.field, 14) &
    padTo(e.blindWriters.join(", "), 26) &
    padTo(e.foldingWriters.join(", "), 20) &
    padTo(e.readers.join(", "), 16) & flag

proc hazardLines(h: StateHazard): seq[string] {.role: dataWriter,
    metaTags: {tagGraph, tagState}.} =
  ## h: one pair of blind writers. Said in the order a person needs it:
  ## what is lost, then where to look, then what to do about it.
  result = @[]
  result.add("  ! " & h.typeName & "." & h.field & " - " & h.first &
    " and " & h.second & " each replace it without reading it first.")
  if h.witness.len > 0:
    result.add("    " & h.witness & " calls " & h.first & " (" & h.path &
      ":" & $h.firstLine & ") then " & h.second & " (:" & $h.secondLine &
      ") and nothing reads " & h.field & " in between, so what " &
      h.first & " stored is gone.")
  else:
    result.add("    Nothing was seen calling two of them in a row, so " &
      "this is a shape to watch rather than a proven loss. Two threads " &
      "have no line order to check and land here too.")
  result.add("    If only the newest value matters, write `## " &
    latestMarker & "` on the entry.")

proc stateLines*(r: StateReport): seq[string] {.role: dataWriter,
    metaTags: {tagGraph, tagState}.} =
  ## r: one answer, as plain lines. The table first, because the
  ## question "who may change this" is asked far more often than the
  ## question "what is broken".
  result = @[]
  if r.error.len > 0:
    result.add("state writes: " & r.error)
    return
  for st in r.states:
    result.add("")
    result.add(st.name & "  (" & (if st.role.len > 0: st.role else: "no role") &
      ")  " & st.path & ":" & $st.line & "   " & $st.entries.len & " entrie(s)")
    result.add("    " & padTo("entry", 14) & padTo("replaced by", 26) &
      padTo("folded by", 20) & padTo("read by", 16) & "")
    for e in st.entries:
      if e.blindWriters.len + e.foldingWriters.len + e.readers.len == 0:
        continue
      result.add(entryLine(e))
    if st.wholeWriters.len > 0:
      result.add("    the whole object is replaced by: " &
        st.wholeWriters.join(", "))
  if r.hazards.len > 0:
    result.add("")
  for h in r.hazards:
    for line in hazardLines(h):
      result.add(line)
  if r.unread.len > 0:
    result.add("")
    result.add("  written, and never read: " & r.unread.join(", "))
    result.add("    Every one of those writes is thrown away. Either " &
      "something is meant to read it, or the entry can go.")
  for note in r.notes:
    result.add("  note: " & note)
