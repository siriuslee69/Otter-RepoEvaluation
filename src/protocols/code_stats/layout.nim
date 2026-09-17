## ================================================================
## | layout.nim  <-  is a routine anywhere near the thing that     |
## |                 uses it?                                       |
## |----------------------------------------------------------------|
## | Every other check in here asks whether the code is RIGHT.      |
## | This one asks whether it is FINDABLE, which is a different     |
## | question and the one a maintainer meets first.                 |
## |                                                                |
## | Two findings, one idea: a file has an order, and the order is  |
## | either telling you something or it is not.                     |
## ================================================================
##
## ╭─ ❧ finding one: siblings that are not sitting together 🌊
##
## Three routines that build the same thing, or three steps one
## orchestrator calls in a row, belong within sight of each other.
## When they drift apart, nothing breaks and nobody notices, and the
## next person to look for "what are my options here" has to search
## instead of glancing:
##
##   line  223   initAmePskAuthentication          ─┐
##   line  ...   (fifteen hundred lines of other     │  all three build
##               things, none of them related)       │  one AmeAuthentication
##   line 1784   initAmePinnedAuthentication        ─┤
##   line 1792   initAmeCertificateAuthentication   ─┘
##
## That is a real one, found by hand in a real repository. The middle
## two sat under a heading that said "three authentication inputs"
## and held two of them. Nothing was wrong; it was just unfindable.
##
## Two grounds count as evidence that routines are siblings:
##
##   the same routine calls all of them     they are its steps
##   they all return the same type          they are alternatives
##
## The second is the one that catches constructors. `families.nim`
## answers a neighbouring question -- are these the SAME routine
## written out several times -- and deliberately does not care where
## they sit. This one only cares where they sit.
##
## ╭─ ❧ how scattered is scattered ⟡
##
## Distance alone says nothing: a long file can hold siblings at
## either end and still read well. What matters is how much OTHER
## material sits between them:
##
##   members occupy         24 lines
##   the span they cover  1560 lines
##   strangers between      41 routines
##
## So the test is a ratio, not a distance. Members that fill most of
## the span they cover are together, however long the span is.
##
## ╭─ ❧ finding two: a file that is already two files 🐦‍🔥
##
## A big file is not automatically a problem. A big file with a THIN
## WAIST is: somewhere in it there is a line where the top half stops
## being needed by the bottom half, and that line is where it wants
## to be cut.
##
##   routines above the cut:  50
##   routines below the cut:  30
##   routines above that the bottom half actually calls:  6
##                                                        ^^^
##                            everything else above is private
##                            business the bottom half never touches
##
## Six. That is a seam. Cutting there produces two files that share
## six names, and one import line carries them.
##
## A file that is genuinely one thing has no such line: wherever you
## cut it, the bottom half reaches back into most of the top half.
## That file is reported as nothing, correctly, however long it is.
##
## Nim declares before use, so "nothing above calls below" is true at
## almost every line and is worth nothing as a signal. The waist is
## the other direction -- how much of the top the bottom NEEDS -- and
## that is the number this measures.

import std/[algorithm, sets, strutils, tables]

import ../repo_graph/types as graph_types
import ../repo_graph/io_utils
import runePragmas

const
  layoutStrangerFloor* = 4
    ## How many unrelated routines must sit between siblings before
    ## their being apart is worth mentioning. Below this a reader
    ## still sees them together on one screen-and-a-bit.
  layoutSpanRatio* = 3
    ## Members must occupy less than one part in this of the span
    ## they cover. Three siblings filling half the distance between
    ## the first and the last are not scattered, they are a section.
  layoutCutMinLines* = 700
    ## A file below this is not worth cutting however it is shaped.
    ## Almost any file has SOME thin point in it; the question is only
    ## worth asking once a file is long enough that finding your way
    ## around it has become work.
  layoutCutMinRoutines* = 12
  layoutCutBalance* = 30
    ## Each half must hold at least this percentage of the routines AND
    ## of the lines. Routines alone are not enough: nine small helpers
    ## at the top of a file are nine routines and a hundred lines, and
    ## lifting them out is not the repair anybody wanted.
  layoutWaistMax* = 12
    ## The most names the two halves may share and still be called a
    ## seam. Above this the halves are not really separable.
  layoutWaistPercent* = 40
    ## And the waist must be this small a SHARE of the routines above
    ## it. Twelve names is a thin waist in a file of thirty-six
    ## routines and a fat one in a file of fourteen -- the count alone
    ## cannot tell those apart, and the second is not a seam at all:
    ## the bottom half needs six of every seven routines above it.
  layoutAffixMin* = 4
    ## How many characters of a shared prefix or suffix count as the
    ## author naming a set. `initAmePskAuthentication` and its two
    ## siblings share both ends; four routines that merely happen to
    ## return bytes share neither, and are not alternatives.
  layoutCurrencyPercent* = 25
    ## A return type more than this share of a file's exported routines
    ## produce is the file's CURRENCY, not an identity. Half a wire
    ## module returns bytes; that says nothing about which routines
    ## belong together, and reporting it buries the cases that do.
  layoutCurrencyFloor* = 8
    ## Below this many exported routines the share above is not a
    ## ratio, it is a rounding error: three routines out of three is
    ## 100% and three out of four is 75%, and neither means the type
    ## is anybody's currency. A small file gets the affix test only.

type
  ## LayoutKind: which of the two questions this finding answers.
  LayoutKind* = enum
    lkScattered,   ## siblings that belong together and are not
    lkCleanCut     ## one file with a thin waist in it

  ## LayoutFinding: one place where the order of a file is not helping.
  ## line: where to look. For a cut, the line to cut AT.
  ## routines: the members, or for a cut the names the halves share.
  ## span/ownLines/strangers: the scatter measurement.
  ## above/below: routines each side of a cut.
  LayoutFinding* {.role: preparedData, tag: "stats",
      expectedCount: [0, 512], lifeCycle: lcJob.} = object
    kind*: LayoutKind
    path*: string
    line*: int
    routines*: seq[string]
    lines*: seq[int]
    span*: int
    ownLines*: int
    strangers*: int
    above*: int
    below*: int
    aboveLines*: int
    belowLines*: int
    evidence*: string
    remedy*: string
    severity*: int
      ## What this costs a reader, so the worst is reported first. For
      ## a scatter it is the unrelated routines in between; for a cut
      ## it is the lines the smaller half would take away. A cut and a
      ## scatter are not the same unit, which is why cuts sort ahead
      ## of scatters rather than being mixed in by number.

  LayoutReport* {.role: truthState, tag: "stats",
      expectedCount: 1, lifeCycle: lcJob.} = object
    items*: seq[LayoutFinding]
    total*: int
    scattered*: int
    cuts*: int
    error*: string

proc relTo(root, path: string): string {.role: sanitizer,
    tag: "stats".} =
  ## root: where the measurement was taken   path: one path from it.
  ## The path with the root cut off, so a finding names a file the way
  ## the person reading it would name it.
  var
    p: string = normalizeSlashes(path)
    r: string = normalizeSlashes(root)
  if r.endsWith("/"):
    r = r[0 ..< r.len - 1]
  if p.startsWith(r) and p.len > r.len:
    p = p[r.len .. ^1]
  result = p.strip(chars = {'/', '.'}, trailing = false)

proc byLine(a, b: FunctionInfo): int {.role: helper, tag: "stats".} =
  ## a/b: two routines ordered the way they appear in the file.
  result = cmp(a.lineStart, b.lineStart)

proc ownLineCount(A: openArray[FunctionInfo]): int {.role: math,
    tag: "stats".} =
  ## A: routines whose own lengths are added up, ignoring the gaps.
  for f in A:
    result = result + max(1, f.lineEnd - f.lineStart + 1)

proc strangersBetween(all: openArray[FunctionInfo],
    members: HashSet[string], firstLine, lastLine: int): int {.role: math,
    tag: "stats".} =
  ## all: every routine in the file, in any order.
  ## members: the names that belong to the group.
  ## firstLine/lastLine: the span the group covers.
  ## How many OTHER routines sit inside that span. This is the number
  ## that decides whether being apart matters: distance is cheap,
  ## unrelated material in between is what costs a reader.
  for f in all:
    if f.name in members:
      continue
    if f.lineStart > firstLine and f.lineStart < lastLine:
      result = result + 1

proc scatterOf(all: seq[FunctionInfo], members: seq[FunctionInfo],
    evidence: string): LayoutFinding {.role: truthBuilder, tag: "stats".} =
  ## all: every routine in the file.
  ## members: the siblings, already known to be siblings.
  ## evidence: why they are siblings, in the words a reader wants.
  ## A finding with `strangers` of zero means they are together and
  ## the caller should drop it.
  var
    sorted: seq[FunctionInfo] = members
    names: HashSet[string] = initHashSet[string]()
  sorted.sort(byLine)
  for f in sorted:
    names.incl(f.name)
    result.routines.add(f.name)
    result.lines.add(f.lineStart)
  result.kind = lkScattered
  result.path = sorted[0].sourcePath
  result.line = sorted[0].lineStart
  result.span = sorted[^1].lineEnd - sorted[0].lineStart + 1
  result.ownLines = ownLineCount(sorted)
  result.strangers = strangersBetween(all, names, sorted[0].lineStart,
    sorted[^1].lineStart)
  result.severity = result.strangers
  result.evidence = evidence
  result.remedy = "move these together. They are " &
    $result.ownLines & " lines spread over " & $result.span &
    ", with " & $result.strangers & " unrelated routine(s) in between."

proc isScattered(f: LayoutFinding): bool {.role: parser, tag: "stats".} =
  ## f: one candidate. Both tests must pass: enough other material in
  ## between to make a reader search, and members that fill little
  ## enough of their span that they are not simply a long section.
  result = f.strangers >= layoutStrangerFloor and
    f.ownLines * layoutSpanRatio < f.span

proc calleesInFile(f: FunctionInfo,
    here: Table[string, FunctionInfo]): seq[FunctionInfo] {.role: parser,
    tag: "stats".} =
  ## f: one routine. here: every routine in its file, by name.
  ## The ones it calls that live in the same file, each counted once.
  var
    seen: HashSet[string] = initHashSet[string]()
  for name in f.calls:
    if name in seen or not here.hasKey(name) or name == f.name:
      continue
    seen.incl(name)
    result.add(here[name])

proc scatteredByCaller(all: seq[FunctionInfo],
    here: Table[string, FunctionInfo]): seq[LayoutFinding] {.
    role: truthBuilder, tag: "stats".} =
  ## all/here: one file's routines, in order and by name.
  ## Steps one routine calls, sitting nowhere near each other or it.
  var
    callees: seq[FunctionInfo] = @[]
    found: LayoutFinding = default(LayoutFinding)
  for f in all:
    callees = calleesInFile(f, here)
    if callees.len < 3:
      continue
    found = scatterOf(all, callees,
      "all called by `" & f.name & "`, which reads as its steps")
    if isScattered(found):
      result.add(found)

proc sharedAffix(A: openArray[FunctionInfo]): bool {.role: parser,
    tag: "stats".} =
  ## A: candidate siblings.
  ##
  ## Did somebody NAME these as a set? Alternatives are recognised by
  ## their names long before anybody reads their bodies:
  ##
  ##   initAmePskAuthentication          shared prefix `initAme`
  ##   initAmePinnedAuthentication       shared suffix `Authentication`
  ##   initAmeCertificateAuthentication  -> a set, named as one
  ##
  ##   serverIdentityBlockBytes          nothing in common at either
  ##   encodeAmeIdentityCertificate      end -> four routines that
  ##   amePskExchangeBinder              happen to return bytes
  ##
  ## Sharing a return type alone is too weak: a byte buffer is a
  ## medium, not an identity, and every encoder in a file returns one.
  var
    prefix: int = 0
    suffix: int = 0
    shortest: int = 0
    i: int = 0
    same: bool = true
  if A.len < 2:
    return false
  shortest = A[0].name.len
  for f in A:
    if f.name.len < shortest:
      shortest = f.name.len
  while i < shortest and same:
    for f in A:
      if f.name[i] != A[0].name[i]:
        same = false
    if same:
      prefix = i + 1
    i = i + 1
  same = true
  i = 0
  while i < shortest and same:
    for f in A:
      if f.name[f.name.len - 1 - i] != A[0].name[A[0].name.len - 1 - i]:
        same = false
    if same:
      suffix = i + 1
    i = i + 1
  result = prefix >= layoutAffixMin or suffix >= layoutAffixMin

proc scatteredByReturn(all: seq[FunctionInfo]): seq[LayoutFinding] {.
    role: truthBuilder, tag: "stats".} =
  ## all: one file's routines.
  ##
  ## Alternatives: several exported routines that all build the same
  ## thing. A reader meeting one of them wants to see the others, and
  ## scattering them is exactly what prevents that.
  ##
  ## The trap here is the file's CURRENCY. A wire module where half
  ## the routines return bytes is not a module full of alternatives;
  ## it is a module that deals in bytes. So a type too many routines
  ## share is skipped -- it cannot tell anybody apart.
  var
    byType: Table[string, seq[FunctionInfo]] = initTable[string,
      seq[FunctionInfo]]()
    found: LayoutFinding = default(LayoutFinding)
    exported: int = 0
    currency: int = 0
  for f in all:
    if not f.isExported or f.returnType.len == 0:
      continue
    exported = exported + 1
    if f.returnType in ["void", "bool", "int", "string", "float",
        "auto", "untyped", "typed"]:
      continue
    if not byType.hasKey(f.returnType):
      byType[f.returnType] = @[]
    byType[f.returnType].add(f)
  currency = (exported * layoutCurrencyPercent) div 100
  if exported < layoutCurrencyFloor:
    currency = exported
  for t, group in byType:
    if group.len < 3 or group.len > currency:
      continue
    if not sharedAffix(group):
      continue
    found = scatterOf(all, group, "all build a `" & t & "`")
    if isScattered(found):
      result.add(found)

proc waistAt(all: seq[FunctionInfo], k: int,
    here: HashSet[string]): seq[string] {.role: math, tag: "stats".} =
  ## all: one file's routines, in source order.
  ## k: the cut point. Routines 0 ..< k are above it.
  ## here: every name defined in this file.
  ## Which names ABOVE the cut the half BELOW it still needs. That set
  ## is what the two files would have to share, so its size is the
  ## whole cost of cutting here.
  var
    aboveNames: HashSet[string] = initHashSet[string]()
    needed: HashSet[string] = initHashSet[string]()
    i: int = 0
  while i < k:
    aboveNames.incl(all[i].name)
    i = i + 1
  i = k
  while i < all.len:
    for name in all[i].calls:
      if name in aboveNames and name in here:
        needed.incl(name)
    i = i + 1
  for name in needed:
    result.add(name)
  result.sort()

proc lineSpanOf(A: openArray[FunctionInfo]): int {.role: math,
    tag: "stats".} =
  ## A: a run of routines whose first-to-last line count is returned.
  if A.len == 0:
    return 0
  result = A[^1].lineEnd - A[0].lineStart + 1

proc cutIn(all: seq[FunctionInfo], fileLines: int): LayoutFinding {.
    role: truthBuilder, tag: "stats".} =
  ## all: one file's routines, in source order.
  ## fileLines: how long the file is.
  ## The thinnest waist in the file, if there is one worth reporting.
  ## `result.kind` stays at its default unless a cut was found, which
  ## is what the caller tests.
  var
    here: HashSet[string] = initHashSet[string]()
    waist: seq[string] = @[]
    best: seq[string] = @[]
    bestAt: int = -1
    minRoutines: int = 0
    minLines: int = 0
    k: int = 0
  minRoutines = (all.len * layoutCutBalance) div 100
  minLines = (fileLines * layoutCutBalance) div 100
  if minRoutines < 2:
    minRoutines = 2
  for f in all:
    here.incl(f.name)
  k = minRoutines
  while k <= all.len - minRoutines:
    if lineSpanOf(all[0 ..< k]) < minLines or
        lineSpanOf(all[k .. ^1]) < minLines:
      k = k + 1
      continue
    waist = waistAt(all, k, here)
    if bestAt < 0 or waist.len < best.len:
      best = waist
      bestAt = k
    k = k + 1
  if bestAt < 0 or best.len > layoutWaistMax:
    return
  if best.len * 100 > bestAt * layoutWaistPercent:
    return
  result.kind = lkCleanCut
  result.path = all[0].sourcePath
  result.line = all[bestAt].lineStart
  result.routines = best
  result.above = bestAt
  result.below = all.len - bestAt
  result.aboveLines = lineSpanOf(all[0 ..< bestAt])
  result.belowLines = lineSpanOf(all[bestAt .. ^1])
  result.span = fileLines
  result.severity = min(result.aboveLines, result.belowLines)
  result.evidence = "only " & $best.len & " of the " & $result.above &
    " routine(s) above are needed below"
  result.remedy = "cut at line " & $result.line & ": " &
    $result.above & " routine(s) and about " & $result.aboveLines &
    " lines above, " & $result.below & " and about " &
    $result.belowLines & " below."

proc mergeScattered(A: seq[LayoutFinding]): seq[LayoutFinding] {.
    role: truthBuilder, tag: "stats".} =
  ## A: every scattered finding from one file.
  ##
  ## Four orchestrators calling the same five helpers is ONE thing out
  ## of place, not four. They are merged by the members they name, and
  ## the evidence says how many callers agreed -- which is stronger
  ## evidence, not weaker: five routines that four different callers
  ## all reach for really do belong together.
  var
    byMembers: Table[string, LayoutFinding] = initTable[string,
      LayoutFinding]()
    agreed: Table[string, int] = initTable[string, int]()
    key: string = ""
  for f in A:
    key = f.path & "|" & f.routines.join(",")
    if byMembers.hasKey(key):
      agreed[key] = agreed[key] + 1
      continue
    byMembers[key] = f
    agreed[key] = 1
  for key, f in byMembers:
    result.add(f)
    if agreed[key] < 2:
      continue
    result[^1].evidence = f.evidence & ", and by " &
      $(agreed[key] - 1) & " other routine(s)"

proc worstFirst(a, b: LayoutFinding): int {.role: helper,
    tag: "stats".} =
  ## a/b: two findings ordered so a reader shown only the first few is
  ## shown the ones that matter. Cuts come first: lifting half a file
  ## out is a bigger repair than moving three routines together.
  if a.kind != b.kind:
    return cmp(ord(a.kind), ord(b.kind)) * -1
  result = cmp(b.severity, a.severity)

proc layoutOf*(A: seq[FunctionInfo], root: string = ""): LayoutReport {.
    role: orchestrator, tag: "stats".} =
  ## A: every routine the repository declares.
  ## root: where the measurement was taken, so findings name files the
  ##   short way. Empty leaves paths exactly as they came in.
  ##
  ## Both findings are per-file and need nothing but the routines
  ## themselves: where each one starts, where it ends, what it calls
  ## and what it returns. No file is read a second time.
  var
    perFile: Table[string, seq[FunctionInfo]] = initTable[string,
      seq[FunctionInfo]]()
    here: Table[string, FunctionInfo] = initTable[string, FunctionInfo]()
    ordered: seq[FunctionInfo] = @[]
    cut: LayoutFinding = default(LayoutFinding)
    fileLines: int = 0
  result.items = @[]
  for f in A:
    if f.sourcePath.len == 0:
      continue
    if not perFile.hasKey(f.sourcePath):
      perFile[f.sourcePath] = @[]
    perFile[f.sourcePath].add(f)
  for path, group in perFile:
    ordered = group
    ordered.sort(byLine)
    here = initTable[string, FunctionInfo]()
    for f in ordered:
      here[f.name] = f
    for found in mergeScattered(scatteredByCaller(ordered, here) &
        scatteredByReturn(ordered)):
      result.items.add(found)
    fileLines = lineSpanOf(ordered)
    if fileLines < layoutCutMinLines or ordered.len < layoutCutMinRoutines:
      continue
    cut = cutIn(ordered, fileLines)
    if cut.kind == lkCleanCut:
      result.items.add(cut)
  if root.len > 0:
    for i in 0 ..< result.items.len:
      result.items[i].path = relTo(root, result.items[i].path)
  result.items.sort(worstFirst)
  for f in result.items:
    if f.kind == lkScattered:
      result.scattered = result.scattered + 1
    else:
      result.cuts = result.cuts + 1
  result.total = result.items.len
