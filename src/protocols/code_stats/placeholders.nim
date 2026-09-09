## ==============================================================
## | placeholders.nim  <-  routines that do not do anything yet |
## |------------------------------------------------------------|
## | A placeholder is a routine that exists so the rest of the   |
## | program can be written around it, but that does not do its  |
## | job yet. They are useful while building and dangerous once  |
## | forgotten, because everything that calls one quietly gets   |
## | an answer that was never worked out.                        |
## |                                                             |
## | There is no single certain test for this, so several weak   |
## | ones are added up into a percentage:                        |
## |                                                             |
## |   said so in a pragma ........................ certain      |
## |   body is empty or only `discard` ............ very likely  |
## |   body only raises "not implemented" ......... very likely  |
## |   hands back the same answer whatever comes in  likely      |
## |   a comment says TODO / FIXME / stub ......... likely       |
## |   nothing in the tree ever calls it .......... weak         |
## |                                                             |
## | Only the pragma is certain. Everything else is a hint, and  |
## | a hint is shown as the percentage it earned rather than as  |
## | a verdict, so a person can judge the borderline ones.       |
## |                                                             |
## | One trap worth naming. "Hands back the same answer whatever |
## | comes in" is the strongest of the guessed signals, but it   |
## | must not be applied to a routine whose whole job is to      |
## | change something handed to it:                              |
## |                                                             |
## |   proc fill(S: var seq[int]) =    <- returns nothing, and   |
## |     S.add(1)                         changes S. NOT a       |
## |                                      placeholder.           |
## ==============================================================

import std/[algorithm, sets, strutils]

import ../repo_graph/types as graphTypes
import runePragmas

const
  placeholderFloor*: float = 0.45
    ## Under this a routine is not reported at all. Below roughly a
    ## half the signals are too weak to put in front of a person.
  placeholderShown*: int = 60
    ## How many travel to a window. The rest are counted.
  todoWords*: array[8, string] = [
    "todo", "fixme", "not implemented", "notimplemented",
    "unimplemented", "placeholder", "stub", "for now"
  ]
    ## Words people write when they mean "come back to this". Matched
    ## in comments only, never in code, so a routine that legitimately
    ## handles a string called "stub" is not accused.
  emptyWords*: array[4, string] = ["discard", "nil", "void", "pass"]
    ## Bodies that amount to doing nothing.

type
  PlaceholderKind* {.role: other, tag: "stats".} = enum
    ## Why one routine was flagged. The first that fits, in order of
    ## how much it can be trusted.
    ##
    ##   pkDeclared    a pragma says so
    ##   pkEmpty       there is no body to speak of
    ##   pkRaises      it only refuses to work
    ##   pkConstant    the answer never depends on what came in
    ##   pkNoted       a comment says it is unfinished
    ##   pkUncalled    nothing calls it, and it is thin
    pkDeclared, pkEmpty, pkRaises, pkConstant, pkNoted, pkUncalled

  PlaceholderInfo* {.role: preparedData, tag: "stats".} = object
    ## One routine that looks unfinished, and how sure we are.
    ##
    ##   score    0..1. 1.0 only ever means a pragma said so.
    ##   reasons  every signal that fired, in plain words, so the
    ##            number can be argued with rather than believed.
    name*: string
    path*: string
    module*: string
    kind*: string
    stage*: string
    reasons*: seq[string]
    line*: int
    lines*: int
    score*: float
    declared*: bool
    called*: bool

  PlaceholderReport* {.role: truthState, tag: "stats".} = object
    ## What the whole repository looks like on this measure.
    items*: seq[PlaceholderInfo]
    total*: int
    declaredCount*: int
    guessedCount*: int
    uncalledCount*: int

proc kindName*(k: PlaceholderKind): string {.role: helper,
    tag: "stats".} =
  ## k <- why a routine was flagged, as a word for a window.
  case k
  of pkDeclared: result = "declared"
  of pkEmpty: result = "empty"
  of pkRaises: result = "refuses"
  of pkConstant: result = "constant"
  of pkNoted: result = "noted"
  of pkUncalled: result = "uncalled"

proc declaredStage*(f: FunctionInfo): string {.role: parser,
    tag: "stats".} =
  ## f <- one routine. What its `stage` pragma says, or "".
  ##
  ## Read out of the pragma text rather than from a compiled value,
  ## because Otter reads other people's repositories as plain text and
  ## never builds them.
  var
    t: string = ""
  result = ""
  for row in f.pragmaTags:
    t = row.strip().toLowerAscii()
    if t.startsWith("stage:"):
      return t[6 .. ^1].strip()
    if t == "deprecated" or t.startsWith("deprecated:"):
      return "deprecated"

proc codeLines*(A: seq[string]): seq[string] {.role: sanitizer,
    tag: "stats".} =
  ## A <- a routine's body. Only the lines that are code: blanks and
  ## comment-only lines are dropped, and a trailing comment is cut off
  ## the end of a line that also holds code.
  var
    t: string = ""
    at: int = 0
    quoted: bool = false
    i: int = 0
  result = @[]
  for row in A:
    t = row.strip()
    if t.len == 0 or t.startsWith("#"):
      continue
    # A `#` inside quotes is part of the text, not a comment.
    quoted = false
    at = -1
    i = 0
    while i < t.len:
      if t[i] == '"':
        quoted = not quoted
      elif t[i] == '#' and not quoted:
        at = i
        break
      i = i + 1
    if at >= 0:
      t = t[0 ..< at].strip()
    if t.len > 0:
      result.add(t)

proc commentText*(f: FunctionInfo): string {.role: sanitizer,
    tag: "stats".} =
  ## f <- one routine. Everything a person wrote about it in words,
  ## lowered and run together, for the TODO search.
  var
    parts: seq[string] = @[]
  for row in f.docCommentLines:
    parts.add(row)
  for row in f.leadingCommentLines:
    parts.add(row)
  for row in f.innerCommentLines:
    parts.add(row)
  result = parts.join(" ").toLowerAscii()

proc mentionsAny*(s: string, A: openArray[string]): bool {.role: parser,
    tag: "stats".} =
  ## s <- text already lowered   A <- words looked for
  result = false
  for word in A:
    if word in s:
      return true

proc paramNames*(A: seq[string]): seq[string] {.role: parser,
    tag: "stats".} =
  ## A <- parameters as written, such as `count: int`. Just the names.
  ## `a, b: int` declares two names on one line, so commas are split
  ## as well as the colon.
  var
    head: string = ""
    at: int = 0
  result = @[]
  for row in A:
    at = row.rfind(':')
    head = row
    if at >= 0:
      head = row[0 ..< at]
    for piece in head.split(','):
      if piece.strip().len > 0:
        result.add(piece.strip())

proc usesAnyName*(A: seq[string], N: seq[string]): bool {.role: parser,
    tag: "stats".} =
  ## A <- a routine's code lines   N <- the names it takes in
  ##
  ## Whether the body ever mentions one of the things handed to it. A
  ## name only counts when it stands alone: `n` must not match inside
  ## `count`, or every routine would look like it used everything.
  var
    at: int = 0
    before: char = ' '
    after: char = ' '
  result = false
  if N.len == 0:
    return
  for row in A:
    for name in N:
      if name.len == 0:
        continue
      at = 0
      while at >= 0 and at < row.len:
        at = row.find(name, at)
        if at < 0:
          break
        before = ' '
        after = ' '
        if at > 0:
          before = row[at - 1]
        if at + name.len < row.len:
          after = row[at + name.len]
        if not (before.isAlphaNumeric() or before == '_') and
            not (after.isAlphaNumeric() or after == '_'):
          return true
        at = at + name.len

proc touchesVarParam*(A: seq[FunctionSocket]): bool {.role: parser,
    tag: "stats".} =
  ## A <- one routine's connections. Whether any of what it takes in
  ## is something it is expected to change rather than only read.
  result = false
  for row in A:
    if row.direction == sdVarInput:
      return true

proc onlyRefuses*(A: seq[string]): bool {.role: parser,
    tag: "stats".} =
  ## A <- a routine's code lines. Whether the whole body is one
  ## refusal: `raise newException(...)` or `quit "..."` and no more.
  var
    n: int = 0
  result = false
  if A.len == 0 or A.len > 3:
    return
  for row in A:
    if row.startsWith("raise ") or row.startsWith("quit") or
        row.startsWith("doAssert false"):
      n = n + 1
    elif not row.startsWith("##") and not row.startsWith("discard"):
      return false
  result = n > 0

proc isDeclarationOnly*(f: FunctionInfo, A: seq[string]): bool
    {.role: parser, tag: "stats".} =
  ## f <- one routine   A <- its code lines
  ##
  ## Two kinds of routine are *supposed* to have nothing in them, and
  ## neither is a placeholder. Both are let through untouched:
  ##
  ##   template role*(x: MetaRole) {.pragma.}   <- declares a pragma
  ##   proc later(a: int): int                  <- promises a routine
  ##                                               written further down
  ##
  ## Without this guard a repository's own pragma file reads as forty
  ## placeholders, which buries every real one.
  var
    t: string = ""
  result = false
  for row in f.pragmaTags:
    t = row.strip().toLowerAscii()
    if t == "pragma":
      return true
  result = A.len == 0

proc isEmptyBody*(A: seq[string]): bool {.role: parser,
    tag: "stats".} =
  ## A <- a routine's code lines. Whether it says, in so many words,
  ## to do nothing. An empty list is *not* one of these: see
  ## `isDeclarationOnly` for why.
  var
    t: string = ""
  result = true
  if A.len == 0:
    return false
  for row in A:
    t = row.strip().toLowerAscii()
    if t.startsWith("##"):
      continue
    if t notin emptyWords and not t.startsWith("discard"):
      return false

proc handsBackConstant*(f: FunctionInfo, A: seq[string],
    N: seq[string]): bool {.role: parser, tag: "stats".} =
  ## f <- one routine   A <- its code lines   N <- the names it takes in
  ##
  ## Whether every answer it gives is written into the source rather
  ## than worked out:
  ##
  ##   proc widthOf(s: string): int =   <- `s` never used below,
  ##     result = 80                       so 80 is all it ever says
  ##
  ## Two things have to be true, and both matter. The routine must not
  ## use anything handed to it, *and* it must not call anything else.
  ## The second is what separates a real placeholder from a routine
  ## that takes nothing in but still does honest work:
  ##
  ##   proc webRoot(): string =                 <- takes nothing in,
  ##     result = currentSourcePath().parentDir    but the answer is
  ##                                               worked out at run
  ##                                               time. NOT constant.
  ##
  ## Without the second test every no-argument routine in a tree gets
  ## flagged, which is most of the small ones.
  var
    gives: bool = false
    t: string = ""
  result = false
  if A.len == 0 or A.len > 6:
    return
  if f.calls.len > 0:
    return
  for row in A:
    t = row.strip()
    if t.startsWith("result") or t.startsWith("return"):
      gives = true
  if not gives:
    return
  result = not usesAnyName(A, N)

proc scoreOf*(f: FunctionInfo, called: bool):
    tuple[score: float, kind: PlaceholderKind, reasons: seq[string]]
    {.role: truthBuilder, tag: "stats".} =
  ## f <- one routine   called <- whether anything in the tree calls it
  ##
  ## Every signal that fires adds to the score. They are added rather
  ## than one being picked, so a routine that is empty *and* uncalled
  ## *and* marked TODO ends up higher than one that is merely empty.
  var
    code: seq[string] = codeLines(f.bodyLines)
    names: seq[string] = paramNames(f.params)
    words: string = commentText(f)
    stage: string = declaredStage(f)
    mutates: bool = touchesVarParam(f.sockets)
    score: float = 0.0
    kind: PlaceholderKind = pkUncalled
    reasons: seq[string] = @[]
  result = (score: 0.0, kind: pkUncalled, reasons: @[])
  if stage.len > 0 and stage != "stdone" and stage != "done":
    return (1.0, pkDeclared, @["a pragma says this is " & stage])
  if isDeclarationOnly(f, code):
    return
  if isEmptyBody(code):
    score = score + 0.7
    kind = pkEmpty
    reasons.add("the body does nothing")
  elif onlyRefuses(code):
    score = score + 0.7
    kind = pkRaises
    reasons.add("the body only refuses to work")
  elif handsBackConstant(f, code, names) and not mutates:
    score = score + 0.55
    kind = pkConstant
    reasons.add("hands back the same answer whatever comes in")
  if mentionsAny(words, todoWords):
    score = score + 0.3
    if score <= 0.3:
      kind = pkNoted
    reasons.add("a comment marks it unfinished")
  if not called and f.declKind != "method" and code.len <= 12:
    score = score + 0.15
    reasons.add("nothing in this tree calls it")
  if score > 0.99:
    score = 0.99
  result = (score: score, kind: kind, reasons: reasons)

proc byScoreThenSize(a, b: PlaceholderInfo): int {.role: helper,
    tag: "stats".} =
  ## a, b <- two flagged routines, surest first and biggest after.
  result = cmp(b.score, a.score)
  if result == 0:
    result = cmp(b.lines, a.lines)
  if result == 0:
    result = cmp(a.path, b.path)

proc placeholdersOf*(A: seq[FunctionInfo], calledNames: HashSet[string],
    root: string): PlaceholderReport {.role: orchestrator,
    tag: "stats".} =
  ## A <- every routine in the tree
  ## calledNames <- every name that something in the tree calls, lowered
  ## root <- the repository folder, cut off the front of each path
  var
    rows: seq[PlaceholderInfo] = @[]
    got: tuple[score: float, kind: PlaceholderKind, reasons: seq[string]]
    called: bool = false
    rel: string = ""
  result = PlaceholderReport(items: @[], total: 0, declaredCount: 0,
    guessedCount: 0, uncalledCount: 0)
  for f in A:
    called = f.name.toLowerAscii() in calledNames
    got = scoreOf(f, called)
    if got.score < placeholderFloor:
      continue
    rel = f.sourcePath
    if root.len > 0 and rel.startsWith(root):
      rel = rel[root.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    rows.add(PlaceholderInfo(name: f.name, path: rel,
      module: f.modulePath, kind: kindName(got.kind),
      stage: declaredStage(f), reasons: got.reasons,
      line: f.lineStart, lines: max(1, f.lineEnd - f.lineStart + 1),
      score: got.score, declared: got.kind == pkDeclared,
      called: called))
  rows.sort(byScoreThenSize)
  result.total = rows.len
  for row in rows:
    if row.declared:
      result.declaredCount = result.declaredCount + 1
    else:
      result.guessedCount = result.guessedCount + 1
    if not row.called:
      result.uncalledCount = result.uncalledCount + 1
  if rows.len > placeholderShown:
    rows.setLen(placeholderShown)
  result.items = rows
