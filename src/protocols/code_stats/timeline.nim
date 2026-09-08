## ==============================================================
## | timeline.nim  <-  a repository seen from the side          |
## |------------------------------------------------------------|
## | Every other chart shows a repository as it is today. This    |
## | one shows how it got here, by asking git what the tree      |
## | looked like at a spread of past moments.                    |
## |                                                             |
## | Five lines are drawn on one pair of axes, so that they can  |
## | be read against each other:                                 |
## |                                                             |
## |   count                                                     |
## |     ^                                                       |
## |     |                    ______ tracked                     |
## |     |            _______/                                   |
## |     |      _____/        ______ src                          |
## |     |   __/       ______/                                    |
## |     |  /   ______/       ______ tests                        |
## |     +-------------------------------> time                   |
## |                                                             |
## | Read together they answer questions no single number can:   |
## | did the tests grow with the source, or did the source run   |
## | away from them? Did the repository get bigger, or only      |
## | busier?                                                     |
## |                                                             |
## | One honest limit. Git remembers what was *committed*. It    |
## | cannot say what ignored junk was lying in the folder three  |
## | years ago, so the "ignored" count is only ever filled in    |
## | for right now, and every past point says it does not know.  |
## ==============================================================

import std/[algorithm, os, osproc, sequtils, strutils, times]

import ../repo_graph/io_utils
import otterPragmas

const
  timelinePoints*: int = 48
    ## How many moments in the past are looked at. Each one costs a
    ## call to git, so this trades detail against the time a person is
    ## willing to wait. Evenly spread, plus always the first and last
    ## commit, so the ends of the story are never cut off.
  timelineMaxCommits*: int = 20000
    ## A history longer than this is read down to its newest stretch,
    ## so a very old repository cannot stall the measurement.

type
  TimelinePoint* {.role: preparedData, metaTags: {tagStats}.} = object
    ## What the repository looked like at one moment.
    ##
    ##   unix          when, in seconds since 1970
    ##   sha           the commit this was read from
    ##   srcFiles      files under `src/`
    ##   testFiles     files under `tests/`, or any `tests` folder
    ##   trackedFiles  every file git was keeping: this is the count
    ##                 with everything in `.gitignore` already left out
    ##   ignoredFiles  files present but deliberately not kept. Only
    ##                 known for `working tree` points; -1 means the
    ##                 question cannot be answered for that moment.
    ##   bytes         what all the tracked files weigh together
    ##   working       true for the one point that is the folder as it
    ##                 sits right now, rather than a past commit
    sha*: string
    subject*: string
    unix*: int64
    srcFiles*: int
    testFiles*: int
    trackedFiles*: int
    ignoredFiles*: int
    bytes*: int64
    working*: bool

  TimelineStats* {.role: truthState, metaTags: {tagStats}.} = object
    ## The whole story, oldest point first.
    points*: seq[TimelinePoint]
    commits*: int
    firstUnix*: int64
    lastUnix*: int64
    error*: string

proc gitOut*(dir: string, args: openArray[string]):
    tuple[text: string, ok: bool] {.role: dataFetcher, input: thirdParty,
    risk: low, metaTags: {tagStats}.} =
  ## dir <- the repository   args <- what to ask git
  ##
  ## Git is asked with `-C`, never by changing the working folder, so
  ## two measurements running at once cannot tread on each other.
  var
    parts: seq[string] = @["-C", dir]
    got: tuple[output: string, exitCode: int]
  result = (text: "", ok: false)
  for row in args:
    parts.add(row)
  try:
    got = execCmdEx("git " & parts.mapIt(quoteShell(it)).join(" "))
  except OSError, IOError:
    return
  result = (text: got.output, ok: got.exitCode == 0)

proc treeCounts*(dir, sha: string): TimelinePoint {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## dir <- the repository   sha <- which commit to read
  ##
  ## One call to git lists every file that commit held, together with
  ## what each weighs, so all four counts come off one answer:
  ##
  ##   100644 blob a1b2c3...    1432<TAB>src/main.nim
  ##   ^mode  ^kind ^contents   ^size    ^path
  var
    got: tuple[text: string, ok: bool]
    at: int = 0
    path: string = ""
    head: string = ""
    fields: seq[string] = @[]
  result = TimelinePoint(sha: sha, subject: "", unix: 0, srcFiles: 0,
    testFiles: 0, trackedFiles: 0, ignoredFiles: -1, bytes: 0,
    working: false)
  got = gitOut(dir, ["ls-tree", "-r", "--long", sha])
  if not got.ok:
    return
  for line in got.text.splitLines():
    if line.len == 0:
      continue
    at = line.find('\t')
    if at < 0:
      continue
    head = line[0 ..< at]
    path = line[at + 1 .. ^1].replace('\\', '/')
    fields = head.splitWhitespace()
    if fields.len < 4 or fields[1] != "blob":
      continue
    result.trackedFiles = result.trackedFiles + 1
    try:
      result.bytes = result.bytes + parseBiggestInt(fields[3])
    except ValueError:
      discard
    if isTestPath(path):
      result.testFiles = result.testFiles + 1
    elif isSrcPath(path):
      result.srcFiles = result.srcFiles + 1

proc ignoredNow*(dir: string): int {.role: dataFetcher,
    metaTags: {tagStats}.} =
  ## dir <- the repository. How many files are sitting in the folder
  ## right now that git has been told to leave alone. This is the one
  ## number that only has an answer for the present moment.
  var
    got: tuple[text: string, ok: bool]
  result = 0
  got = gitOut(dir, ["ls-files", "--others", "--ignored",
    "--exclude-standard"])
  if not got.ok:
    return
  for line in got.text.splitLines():
    if line.strip().len > 0:
      result = result + 1

proc workingPoint*(dir: string): TimelinePoint {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## dir <- the repository, as the folder stands this second, changes
  ## and all. This is the only point that can count ignored files.
  var
    got: tuple[text: string, ok: bool]
    path: string = ""
    full: string = ""
  result = TimelinePoint(sha: "working", subject: "working tree",
    unix: 0, srcFiles: 0, testFiles: 0, trackedFiles: 0,
    ignoredFiles: 0, bytes: 0, working: true)
  result.unix = getTime().toUnix()
  got = gitOut(dir, ["ls-files"])
  if not got.ok:
    return
  for line in got.text.splitLines():
    path = line.strip().replace('\\', '/')
    if path.len == 0:
      continue
    result.trackedFiles = result.trackedFiles + 1
    if isTestPath(path):
      result.testFiles = result.testFiles + 1
    elif isSrcPath(path):
      result.srcFiles = result.srcFiles + 1
    full = dir / path
    try:
      if fileExists(full):
        result.bytes = result.bytes + getFileSize(full)
    except OSError, IOError:
      discard
  result.ignoredFiles = ignoredNow(dir)

proc sampleAt*(n, want, i: int): bool {.inline, role: math,
    metaTags: {tagStats}.} =
  ## n <- how many commits there are   want <- how many are wanted
  ## i <- which commit this is, counted from the newest
  ##
  ## Picks an even spread. The first and the last are always taken, so
  ## the beginning and the end of the story are never lost to rounding.
  result = false
  if n <= want:
    return true
  if i == 0 or i == n - 1:
    return true
  result = (i * want) div n != ((i - 1) * want) div n

proc byUnix(a, b: TimelinePoint): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b <- two moments, oldest first, so a chart reads left to right.
  result = cmp(a.unix, b.unix)

proc timelineOf*(dir: string, want: int = timelinePoints): TimelineStats
    {.role: orchestrator, input: thirdParty, risk: low, speed: long,
    metaTags: {tagStats}.} =
  ## dir <- the repository   want <- how many moments to read
  ##
  ##   git log ─► pick a spread ─► git ls-tree per pick ─► points
  ##
  ## Only the first parent of each merge is followed, so a busy branch
  ## that was merged once does not appear as a hundred separate moments
  ## in the history of the main line.
  var
    got: tuple[text: string, ok: bool]
    rows: seq[string] = @[]
    fields: seq[string] = @[]
    point: TimelinePoint
    at: int = 0
    n: int = 0
  result = TimelineStats(points: @[], commits: 0, firstUnix: 0,
    lastUnix: 0, error: "")
  if dir.len == 0 or not dirExists(dir):
    result.error = "no such folder: " & dir
    return
  if not dirExists(dir / ".git") and not fileExists(dir / ".git"):
    result.error = "not a git repository, so it has no history to read"
    return
  got = gitOut(dir, ["log", "--first-parent",
    "--max-count=" & $timelineMaxCommits, "--format=%H%x1f%at%x1f%s"])
  if not got.ok:
    result.error = "git could not read the history of this folder"
    return
  for line in got.text.splitLines():
    if line.strip().len > 0:
      rows.add(line)
  result.commits = rows.len
  if rows.len == 0:
    result.error = "this repository has no commits yet"
    return
  n = rows.len
  while at < n:
    if not sampleAt(n, want, at):
      at = at + 1
      continue
    fields = rows[at].split('\x1f')
    if fields.len < 3:
      at = at + 1
      continue
    point = treeCounts(dir, fields[0])
    point.subject = fields[2]
    try:
      point.unix = parseBiggestInt(fields[1])
    except ValueError:
      point.unix = 0
    if point.unix > 0:
      result.points.add(point)
    at = at + 1
  result.points.add(workingPoint(dir))
  result.points.sort(byUnix)
  if result.points.len > 0:
    result.firstUnix = result.points[0].unix
    result.lastUnix = result.points[^1].unix

proc timelineLines*(S: TimelineStats): seq[string] {.role: helper,
    metaTags: {tagStats}.} =
  ## S <- one repository's history, put into lines a terminal can show.
  var
    row: TimelinePoint
  result = @[]
  if S.error.len > 0:
    result.add("History: " & S.error)
    return
  result.add("History: " & $S.commits & " commits, " & $S.points.len &
    " moments read")
  if S.points.len == 0:
    return
  row = S.points[0]
  result.add("  first: " & $row.trackedFiles & " files, " &
    $row.srcFiles & " src, " & $row.testFiles & " tests")
  row = S.points[^1]
  result.add("  now:   " & $row.trackedFiles & " files, " &
    $row.srcFiles & " src, " & $row.testFiles & " tests, " &
    $(row.bytes div 1024) & " KiB")
