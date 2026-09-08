## ==============================================================
## | unused.nim  <-  routines nothing calls, and why             |
## |------------------------------------------------------------|
## | "Nothing calls this" is already known elsewhere in Otter,   |
## | as a list of names. A bare list is not much use, because    |
## | the same sentence covers two opposite situations:           |
## |                                                             |
## |   a leftover   two hundred lines that used to be the heart  |
## |                of the program before it was rebuilt, and    |
## |                that nobody dared delete                     |
## |                                                             |
## |   a beginning  four lines somebody wrote last week for a    |
## |                feature that is not finished                 |
## |                                                             |
## | One is dead weight to be cut. The other is work in hand,    |
## | and cutting it would throw away somebody's afternoon. The   |
## | thing that tells them apart is size, so size is measured    |
## | and reported next to every name:                            |
## |                                                             |
## |   lines                                                     |
## |     ^                                                       |
## |  200|  #   <- leftover: big, finished, and abandoned        |
## |     |  #                                                    |
## |   20|  #  #     #                                           |
## |    4|  #  #  #  #  #   <- beginnings: small and thin        |
## |     +----------------------                                 |
## |                                                             |
## | A third case has to be kept out of both. A routine that is  |
## | exported from a library is *supposed* to have no caller     |
## | inside its own repository: its callers are other people.    |
## | Those are reported apart, so a library does not read as      |
## | being entirely dead.                                        |
## ==============================================================

import std/[algorithm, sets, strutils]

import ../repo_graph/types as graphTypes
import otterPragmas

const
  leftoverLines*: int = 25
    ## From this many lines up, an uncalled routine is treated as
    ## something that was once finished rather than something just
    ## begun. Chosen to sit above a typical helper and below a
    ## typical rewritten subsystem.
  unusedShownHere*: int = 60
    ## How many travel to a window. The rest are counted.

type
  UnusedKind* {.role: other, metaTags: {tagStats}.} = enum
    ## Why this routine has no caller.
    ##
    ##   ukLeftover  big enough to have been finished once
    ##   ukPrepared  small: begun, not yet wired up
    ##   ukPublic    exported, so its callers are elsewhere
    ukLeftover, ukPrepared, ukPublic

  UnusedFunc* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One routine nothing calls, with enough beside it to decide
    ## what should happen to it.
    name*: string
    path*: string
    module*: string
    declKind*: string
    kind*: string
    hint*: string
    line*: int
    lines*: int
    exported*: bool

  UnusedReport* {.role: truthState, metaTags: {tagStats}.} = object
    ## Every uncalled routine in one repository, sorted worst first.
    ##
    ##   leftoverLines  how much dead weight there is, added up. This
    ##                  is the number that says whether a clean-up is
    ##                  worth an afternoon.
    items*: seq[UnusedFunc]
    total*: int
    leftoverCount*: int
    preparedCount*: int
    publicCount*: int
    leftoverLines*: int

proc kindName*(k: UnusedKind): string {.role: helper,
    metaTags: {tagStats}.} =
  ## k <- why a routine has no caller, as a word for a window.
  case k
  of ukLeftover: result = "leftover"
  of ukPrepared: result = "prepared"
  of ukPublic: result = "public"

proc hintFor*(k: UnusedKind, lines: int): string {.role: helper,
    metaTags: {tagStats}.} =
  ## k <- what sort it is   lines <- how long it is
  ## What a person should do about it, in plain words.
  case k
  of ukLeftover:
    result = "Big enough to have worked once. Check the history " &
      "before deleting: this is usually what an old design left " &
      "behind."
  of ukPrepared:
    result = "Small and unwired. Most likely a feature somebody " &
      "started. Deleting it throws away work in hand."
  of ukPublic:
    result = "Exported, so anything outside this repository may be " &
      "calling it. Nothing here can see those callers."

proc classify*(f: FunctionInfo, isLibrary: bool): UnusedKind
    {.role: parser, metaTags: {tagStats}.} =
  ## f <- one uncalled routine   isLibrary <- whether this repository
  ## is something other repositories import
  var
    lines: int = f.lineEnd - f.lineStart + 1
  result = ukPrepared
  if f.isExported and isLibrary:
    return ukPublic
  if lines >= leftoverLines:
    return ukLeftover

proc looksLikeLibrary*(A: seq[FunctionInfo]): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## A <- every routine in the tree.
  ##
  ## A repository is taken to be a library when most of what it
  ## declares is exported. A program keeps its insides to itself; a
  ## library exists to be called from outside.
  var
    shared: int = 0
    total: int = 0
  result = false
  for row in A:
    if row.declKind == "template" or row.declKind == "macro":
      continue
    total = total + 1
    if row.isExported:
      shared = shared + 1
  if total < 8:
    return false
  result = shared.float / total.float >= 0.5

proc bySizeThenName(a, b: UnusedFunc): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b <- two uncalled routines, the heaviest dead weight first.
  result = cmp(b.lines, a.lines)
  if result == 0:
    result = cmp(a.path, b.path)
  if result == 0:
    result = cmp(a.name, b.name)

proc unusedReportOf*(A: seq[FunctionInfo], calledNames: HashSet[string],
    root: string): UnusedReport {.role: orchestrator,
    metaTags: {tagStats}.} =
  ## A <- every routine in the tree
  ## calledNames <- every name something in the tree calls, lowered
  ## root <- the repository folder, cut off the front of each path
  var
    rows: seq[UnusedFunc] = @[]
    isLib: bool = false
    kind: UnusedKind = ukPrepared
    rel: string = ""
    n: int = 0
  result = UnusedReport(items: @[], total: 0, leftoverCount: 0,
    preparedCount: 0, publicCount: 0, leftoverLines: 0)
  isLib = looksLikeLibrary(A)
  for f in A:
    if f.name.toLowerAscii() in calledNames:
      continue
    # A pragma template is applied by name, never called, and would
    # otherwise fill this list.
    if "pragma" in f.pragmaTags:
      continue
    kind = classify(f, isLib)
    rel = f.sourcePath
    if root.len > 0 and rel.startsWith(root):
      rel = rel[root.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    n = f.lineEnd - f.lineStart + 1
    if n < 1:
      n = 1
    rows.add(UnusedFunc(name: f.name, path: rel, module: f.modulePath,
      declKind: f.declKind, kind: kindName(kind),
      hint: hintFor(kind, n), line: f.lineStart, lines: n,
      exported: f.isExported))
  rows.sort(bySizeThenName)
  result.total = rows.len
  for row in rows:
    case row.kind
    of "leftover":
      result.leftoverCount = result.leftoverCount + 1
      result.leftoverLines = result.leftoverLines + row.lines
    of "prepared":
      result.preparedCount = result.preparedCount + 1
    else:
      result.publicCount = result.publicCount + 1
  if rows.len > unusedShownHere:
    rows.setLen(unusedShownHere)
  result.items = rows
