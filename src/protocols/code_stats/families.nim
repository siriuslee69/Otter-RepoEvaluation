## ================================================================
## | families.nim  <-  many routines that are one routine          |
## |---------------------------------------------------------------|
## | `shape.nim` answers "are these two the same routine twice?".   |
## | This file asks a different question:                           |
## |                                                                |
## |     are these SEVEN routines one routine with a knob on it?    |
## |                                                                |
## | The difference matters. A pair of duplicates is a copy-paste   |
## | to delete. A family of near-identical siblings sitting side    |
## | by side is a design that has not been finished: the thing they |
## | have in common has never been written down, so it is written   |
## | out once per case instead.                                     |
## ================================================================
##
## What a family looks like
## ------------------------
## Seven routines in one module, all built the same way, differing in
## one or two places:
##
##   makeHelloAm1c   ─┐
##   makeHelloAm1s    │  same skeleton, same inputs,
##   makeHelloAm1m    ├─ one decision differs
##   readHelloAm1c    │
##   readHelloAm1s   ─┘
##
## and the finished form, which is one routine plus a parameter:
##
##   makeHello(mode: AuthenticationMode)
##
## How the varying part is named
## -----------------------------
## Three shapes of difference, three different repairs. Which one it
## is can be read off without understanding the code:
##
##   what differs across the family     what it wants
##   ---------------------------------  --------------------------
##   only the types taken in            a generic
##   the same steps, different values   a parameter
##   whole steps present or absent      a set of switched-on terms
##
## The third is the one worth knowing about, because it is the one
## people miss. When siblings differ by whether a step happens at
## all, the family is a SUM whose terms are switched on and off:
##
##   x' = x + SUM over the terms that are on of  r * c * (t - x)
##
## A particle swarm is that line with two terms on. A genetic
## algorithm is the same line with a different term on. Neither is a
## special case of the other; both are subsets of one sum. A family
## detected as `term` is asking to be written that way.
##
## The measurement
## ---------------
## Each routine is already a point in a room of thirteen counts (see
## `shape.nim`). For a family, the useful number is not where the
## points are but how many DIRECTIONS they spread in:
##
##   thirteen counts, seven routines, and only ONE count differs
##   -> the family lies on a line
##   -> the line is the parameter nobody has written down yet
##
## Counting the directions that vary is the whole of it. A formal
## version would take the singular values of the centred matrix and
## call the answer its effective rank; counting the dimensions whose
## variance is not zero gives the same verdict here and can be
## checked by hand, which the other cannot.
##
##   varying directions   verdict
##   ------------------   ---------------------------------------
##   0                    the same routine written out N times
##   1                    one parameter is missing
##   2                    two parameters, or one parameter and a
##                        term that is sometimes absent
##   many                 not a family; they only look alike
##
## Only routines on the SAME level are compared - same module, same
## kind of declaration. A helper and the thing that calls it are not
## siblings however alike they look, and collapsing across levels
## produces advice nobody can act on.

import std/[algorithm, sets, strutils, tables]

import ./shape
import ../repo_graph/types as graphTypes
import otterPragmas

const
  minFamily*: int = 3
    ## Two alike routines are a duplicate pair, and `shape.nim`
    ## already reports those. Three is where a family starts, and
    ## where writing the general form pays for itself.
  minAgreement*: float = 0.82
    ## How much of the skeleton members must share. Below this they
    ## are merely routines of a similar size.
  maxVaryingDims*: int = 3
    ## Vary in more directions than this and the group is not one
    ## routine with knobs, it is several routines that happen to be
    ## the same length.
  minLines*: int = 4
    ## Shorter than this, every routine looks like every other, and
    ## collapsing three four-line routines saves nothing.
  familiesShown*: int = 20

type
  FamilyAxis* = enum
    faType,      ## only the types differ -> a generic
    faValue,     ## same steps, different values -> a parameter
    faTerm       ## steps present or absent -> a set of terms

  RoutineFamily* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One group of siblings that wants to be a single routine.
    level*: string
      ## The module they all sit in. The "same level" this is about.
    members*: seq[string]
      ## `name` of each member, in source order.
    paths*: seq[string]
    lines*: seq[int]
    axis*: FamilyAxis
    axisNames*: seq[string]
      ## Which of the thirteen counts actually vary, by name.
    varyingDims*: int
    agreement*: float
      ## How much of the skeleton the members share, 0..1.
    totalLines*: int
    collapsedLines*: int
      ## Roughly what would remain after collapsing: the largest
      ## member, plus a line per member for the parameter it becomes.
    score*: float
    remedy*: string
    evidence*: string
      ## Why these were called siblings. A dispatch names the routine
      ## that chose between them, which is the author saying so; the
      ## weaker answer is that they merely share a module.
    byDispatch*: bool

  FamilyReport* {.role: truthState, metaTags: {tagStats}.} = object
    families*: seq[RoutineFamily]
    total*: int
    routinesInFamilies*: int
    linesSaved*: int
    error*: string

proc skeletonAgreement*(a, b: string): float {.role: math,
    metaTags: {tagStats}.} =
  ## a, b: two routines boiled down to one letter per line.
  ##
  ## How much of the shorter one appears, in order, in the longer.
  ## Walking both at once is enough - the letters are already in
  ## source order, so a proper edit distance would cost more and say
  ## the same thing at this resolution.
  var
    i: int = 0
    j: int = 0
    same: int = 0
    longer: int = max(a.len, b.len)
  result = 0.0
  if longer == 0:
    return
  while i < a.len and j < b.len:
    if a[i] == b[j]:
      same = same + 1
      i = i + 1
      j = j + 1
      continue
    if a.len - i >= b.len - j:
      i = i + 1
      continue
    j = j + 1
  result = same.float / longer.float

proc countsOf(s: FunctionShape): array[13, int] {.role: parser,
    metaTags: {tagStats}.} =
  ## s: one measured routine. Its thirteen counts, in the order
  ## `shapeDims` names them, so a varying direction can be reported
  ## by name rather than by number.
  result = [s.lines, s.params, s.initVars, s.consts, s.loops,
    s.loopDepth, s.branches, s.calls, s.literals, s.assigns,
    s.returns, s.retKind, s.inputKind]

proc varyingAxes(A: seq[FunctionShape]): seq[string] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A: the members of one family.
  ## The names of the counts that are not the same for every member.
  ## `lines` is left out: a routine that does one thing differently is
  ## a different length for that reason, so it says nothing extra.
  var
    first: array[13, int] = default(array[13, int])
    row: array[13, int] = default(array[13, int])
    i: int = 0
  result = @[]
  if A.len == 0:
    return
  first = countsOf(A[0])
  i = 1
  while i < A.len:
    row = countsOf(A[i])
    for d in 0 ..< 13:
      if row[d] != first[d] and shapeDims[d] notin result and
          shapeDims[d] != "length":
        result.add(shapeDims[d])
    i = i + 1

proc axisOf(A: seq[FunctionShape]): FamilyAxis {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A: the members of one family. Which of the three differences this
  ## family has, and so which repair it wants.
  ##
  ##   skeletons the same, inputs differ   -> a generic
  ##   skeletons differ in length          -> terms come and go
  ##   otherwise                           -> a value differs
  var
    sameSkeleton: bool = true
    sameParams: bool = true
    sameLength: bool = true
    i: int = 1
  result = faValue
  while i < A.len:
    if A[i].skeleton != A[0].skeleton:
      sameSkeleton = false
    if A[i].paramSig != A[0].paramSig:
      sameParams = false
    if A[i].skeleton.len != A[0].skeleton.len:
      sameLength = false
    i = i + 1
  if sameSkeleton and not sameParams:
    return faType
  if not sameLength:
    return faTerm
  result = faValue

proc remedyFor(a: FamilyAxis, n: int): string {.role: helper,
    metaTags: {tagStats}.} =
  ## a: what varies   n: how many members.
  ##
  ## What to write instead. Each answer names the mechanism, because
  ## "these are similar" is not advice and "make it generic" is not
  ## either.
  case a
  of faType:
    result = "write one generic routine. Only the types taken in " &
      "differ, so the body is already shared; give it a type parameter " &
      "and let the " & $n & " call sites keep their names as aliases " &
      "if they read better."
  of faValue:
    result = "write one routine taking a parameter that names which " &
      "of the " & $n & " cases is meant. An enum with " & $n &
      " values, and a table or case that turns it into the numbers " &
      "each version hard-codes today."
  of faTerm:
    result = "write one routine over a SET of switched-on terms; each " &
      "of the " & $n & " is one subset. The steps that come and go " &
      "become terms of one sum, and a term is switched off by giving " &
      "it a coefficient of zero rather than by branching around it: " &
      "x' = x + SUM over k of c_k * f_k(x), with c_k = 0 for the terms " &
      "a case does not use. Switch them at runtime with a set field, " &
      "or at compile time with a static set so the unused terms are " &
      "not in the binary at all."

proc scoreOf(n: int, agreement: float, varying: int): float {.role: math,
    metaTags: {tagStats}.} =
  ## n: members   agreement: shared skeleton   varying: directions.
  ##
  ## Three things make a family worth collapsing, and all three have
  ## to hold at once, so they are multiplied rather than added:
  ##
  ##   more members         more copies of the same thought
  ##   more agreement       they really are one routine
  ##   fewer directions     the difference fits in few parameters
  var
    size: float = 0.0
    tight: float = 0.0
  result = 0.0
  size = min(n.float / 6.0, 1.0)
  tight = 1.0 - (varying.float / (maxVaryingDims.float + 1.0))
  if tight < 0.0:
    tight = 0.0
  result = size * agreement * tight

proc indentOf(s: string): int {.role: parser, metaTags: {tagStats}.} =
  ## s: one line. How far it is pushed in from the left.
  result = 0
  while result < s.len and s[result] == ' ':
    result = result + 1

proc calledNamesIn(s: string): seq[string] {.role: parser,
    metaTags: {tagStats}.} =
  ## s: one line of a body. Every name that is followed by an opening
  ## bracket, which is what a call looks like without parsing one.
  var
    word: string = ""
    i: int = 0
  result = @[]
  while i < s.len:
    if s[i].isAlphaNumeric() or s[i] == '_':
      word.add(s[i])
      i = i + 1
      continue
    if s[i] == '(' and word.len > 1 and not word[0].isDigit():
      result.add(word)
    word = ""
    i = i + 1

proc dispatchPeers*(f: FunctionInfo): seq[seq[string]] {.role: parser,
    metaTags: {tagStats}.} =
  ## f: one routine.
  ##
  ## The strongest evidence that two routines are siblings is not that
  ## they sit in one folder. It is that something CHOSE BETWEEN them:
  ##
  ##   case mode
  ##   of amClassic: buildClassicHello(s)     <- these three were
  ##   of amShared:  buildSharedHello(s)         written to be
  ##   of amMutual:  buildMutualHello(s)         interchangeable
  ##
  ## Whoever wrote that decided the three are alternatives for one job.
  ## Same folder is a guess about intent; a dispatch is a statement of
  ## it, made by the author.
  ##
  ## Branches are found by indentation, which is what Nim uses anyway.
  ## A branch marker at the depth of its `case` or `if` opens a new
  ## alternative; every call below it belongs to that alternative.
  var
    openIndent: int = -1
    branchCalls: seq[string] = @[]
    group: seq[string] = @[]
    ind: int = 0
    t: string = ""
  result = @[]
  for line in f.bodyLines:
    t = line.strip()
    if t.len == 0 or t.startsWith("#"):
      continue
    ind = indentOf(line)
    if t.startsWith("case ") or t == "case" or t.startsWith("if "):
      if group.len >= 2:
        result.add(group)
      openIndent = ind
      group = @[]
      branchCalls = @[]
      continue
    if openIndent < 0:
      continue
    if ind <= openIndent and not (t.startsWith("of ") or
        t.startsWith("elif ") or t.startsWith("else")):
      # The construct ended.
      if branchCalls.len >= 1 and branchCalls[0] notin group:
        group.add(branchCalls[0])
      if group.len >= 2:
        result.add(group)
      group = @[]
      branchCalls = @[]
      openIndent = -1
      continue
    if ind == openIndent and (t.startsWith("of ") or
        t.startsWith("elif ") or t.startsWith("else")):
      # One alternative closes, the next opens. An alternative that
      # made exactly one call is the interesting kind: it stands for
      # that call and nothing else.
      if branchCalls.len >= 1 and branchCalls[0] notin group:
        group.add(branchCalls[0])
      branchCalls = @[]
      continue
    branchCalls.add(calledNamesIn(t))
  if branchCalls.len >= 1 and branchCalls[0] notin group:
    group.add(branchCalls[0])
  if group.len >= 2:
    result.add(group)

proc levelOf(s: FunctionShape): string {.role: parser,
    metaTags: {tagStats}.} =
  ## s: one routine. What counts as its level: the module it sits in,
  ## together with the kind of declaration it is. Two routines are
  ## siblings only if both match.
  result = s.module & "|" & s.declKind

proc familyIn(A: seq[FunctionShape], level: string): seq[RoutineFamily]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## A: every routine on one level   level: what to call it.
  ##
  ## Seeds a family on each routine not yet spoken for and gathers
  ## everything on the level that agrees with it. Greedy on purpose:
  ## a routine belongs to the first family that claims it, which keeps
  ## one sprawling group from swallowing two real ones.
  var
    taken: HashSet[string] = initHashSet[string]()
    group: seq[FunctionShape] = @[]
    fam: RoutineFamily = RoutineFamily()
    axes: seq[string] = @[]
    agree: float = 0.0
    total: float = 0.0
    biggest: int = 0
    i: int = 0
    j: int = 0
  result = @[]
  while i < A.len:
    if A[i].id in taken or A[i].lines < minLines:
      i = i + 1
      continue
    group = @[A[i]]
    total = 0.0
    j = 0
    while j < A.len:
      if j == i or A[j].id in taken or A[j].lines < minLines:
        j = j + 1
        continue
      agree = skeletonAgreement(A[i].skeleton, A[j].skeleton)
      if agree >= minAgreement:
        group.add(A[j])
        total = total + agree
      j = j + 1
    i = i + 1
    if group.len < minFamily:
      continue
    axes = varyingAxes(group)
    if axes.len > maxVaryingDims:
      continue
    for row in group:
      taken.incl(row.id)
    fam = RoutineFamily(level: level, members: @[], paths: @[],
      lines: @[], axis: axisOf(group), axisNames: axes,
      varyingDims: axes.len,
      agreement: total / (group.len - 1).float,
      totalLines: 0, collapsedLines: 0, score: 0.0, remedy: "",
      evidence: "they share a module and a shape", byDispatch: false)
    biggest = 0
    for row in group:
      fam.members.add(row.name)
      fam.paths.add(row.path)
      fam.lines.add(row.line)
      fam.totalLines = fam.totalLines + row.lines
      if row.lines > biggest:
        biggest = row.lines
    fam.collapsedLines = biggest + group.len
    fam.remedy = remedyFor(fam.axis, group.len)
    fam.score = scoreOf(group.len, fam.agreement, fam.varyingDims)
    result.add(fam)

proc byScore(a, b: RoutineFamily): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b: two families, the most worthwhile first.
  result = cmp(b.score, a.score)
  if result == 0:
    result = cmp(b.totalLines, a.totalLines)
  if result == 0:
    result = cmp(a.level, b.level)

proc familyFromNames(byName: Table[string, FunctionShape],
    names: seq[string], chooser, level: string): tuple[ok: bool,
    fam: RoutineFamily] {.role: truthBuilder, metaTags: {tagStats}.} =
  ## byName: every routine, by name   names: the ones chosen between
  ## chooser: the routine that chose   level: what to call the group.
  ##
  ## A dispatch already says these belong together, so agreement is
  ## checked but not required to seed the group: the author's statement
  ## outranks the measurement. The measurement still decides whether
  ## collapsing them is worth advising.
  var
    group: seq[FunctionShape] = @[]
    axes: seq[string] = @[]
    total: float = 0.0
    biggest: int = 0
    i: int = 1
  result = (ok: false, fam: RoutineFamily())
  for n in names:
    if byName.hasKey(n):
      group.add(byName[n])
  # Two is enough HERE, though not for a group found by shared module.
  # A dispatch between exactly two routines is the commonest form of
  # the thing worth catching: one decision, two ways of doing the job,
  # and the decision is the parameter waiting to be written down.
  if group.len < 2:
    return
  while i < group.len:
    total = total + skeletonAgreement(group[0].skeleton, group[i].skeleton)
    i = i + 1
  total = total / (group.len - 1).float
  if total < minAgreement:
    return
  axes = varyingAxes(group)
  if axes.len > maxVaryingDims:
    return
  result.fam = RoutineFamily(level: level, members: @[], paths: @[],
    lines: @[], axis: axisOf(group), axisNames: axes,
    varyingDims: axes.len, agreement: total, totalLines: 0,
    collapsedLines: 0, score: 0.0, remedy: "",
    evidence: "chosen between inside " & chooser, byDispatch: true)
  for row in group:
    result.fam.members.add(row.name)
    result.fam.paths.add(row.path)
    result.fam.lines.add(row.line)
    result.fam.totalLines = result.fam.totalLines + row.lines
    if row.lines > biggest:
      biggest = row.lines
  result.fam.collapsedLines = biggest + group.len
  result.fam.remedy = remedyFor(result.fam.axis, group.len)
  # A dispatch is harder evidence than a shared folder, so the group is
  # worth more than its shape alone would say.
  result.fam.score = min(scoreOf(group.len, total,
    result.fam.varyingDims) + 0.2, 1.0)
  result.ok = true

proc familiesOf*(A: seq[FunctionShape],
    F: seq[FunctionInfo] = @[]): FamilyReport {.role: metaOrchestrator,
    metaTags: {tagStats}.} =
  ## A: every measured routine   F: the same routines with their bodies.
  ##
  ## Two passes, strongest evidence first. A dispatch is the author
  ## saying "these are alternatives"; a shared module is only Otter
  ## guessing it. Anything claimed by a dispatch is not offered again.
  var
    levels = initTable[string, seq[FunctionShape]]()
    byName = initTable[string, FunctionShape]()
    claimed: HashSet[string] = initHashSet[string]()
    key: string = ""
    found: seq[RoutineFamily] = @[]
    got: tuple[ok: bool, fam: RoutineFamily] = (ok: false, fam: RoutineFamily())
    fresh: seq[FunctionShape] = @[]
  result = FamilyReport(families: @[], total: 0, routinesInFamilies: 0,
    linesSaved: 0, error: "")
  for row in A:
    if row.isTest:
      continue
    byName[row.name] = row
    key = levelOf(row)
    if not levels.hasKey(key):
      levels[key] = @[]
    levels[key].add(row)
  for f in F:
    for names in dispatchPeers(f):
      got = familyFromNames(byName, names, f.name, f.modulePath)
      if not got.ok:
        continue
      for m in got.fam.members:
        claimed.incl(m)
      found.add(got.fam)
  for name, rows in levels:
    fresh = @[]
    for row in rows:
      if row.name notin claimed:
        fresh.add(row)
    found.add(familyIn(fresh, name))
  found.sort(byScore)
  result.total = found.len
  for fam in found:
    result.routinesInFamilies = result.routinesInFamilies + fam.members.len
    result.linesSaved = result.linesSaved + fam.totalLines - fam.collapsedLines
  if found.len > familiesShown:
    found.setLen(familiesShown)
  result.families = found
