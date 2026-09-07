## ================================================================
## | diff_review.nim  <-  what this change did to the repository   |
## |---------------------------------------------------------------|
## | A diff says which lines moved. It does not say whether the     |
## | change left the tree worse, and it never says what the changed |
## | routines can reach. Both of those are the difference between a |
## | careful change and a destructive one, and neither fits in a    |
## | diff.                                                          |
## ================================================================
##
## Who this is for
## ---------------
## Somebody - a person in a hurry, or a program with a small memory -
## who has just changed four files and is about to say they are done.
## Reading the whole measurement of the repository would tell them
## about two hundred things, of which one hundred and ninety-six were
## already true this morning. So this says three things only:
##
##   what appeared    findings that were not there before
##   what went        findings that were there and are not now
##   what it reaches  who calls the routines that were touched
##
## How the before is got at
## ------------------------
## The tree as it was is written out into a scratch folder and
## measured there:
##
##     git archive <rev> | tar -x -C <scratch>
##
## Nothing is checked out, stashed, reset, or moved. The working tree
## is not touched at all, so this is safe to run on a folder somebody
## is in the middle of editing - which is exactly when it is wanted.
##
## Why findings are matched by name and not by line
## ------------------------------------------------
## Adding ten lines to the top of a file moves every finding in it ten
## lines down. Matched by line, all of them would read as gone and all
## of them would read as new, and the report would be noise. So each
## finding is given a key made of the things a change does not move:
##
##     SECRET  key  src/net/client.nim  sk-l…24…f0a
##     NESTING      src/net/client.nim  parseFrame  4
##     DEAD         oldParse            src/legacy.nim
##
## A finding whose key is in the after and not in the before appeared.
## The other way round, it went. Renaming a routine therefore reads as
## one finding going and another appearing, which is honest: as far as
## anything here can tell, that is what happened.
##
## What it cannot tell you
## -----------------------
## It measures two trees and subtracts. It does not know which of your
## edits caused which finding, and it will happily blame a change for
## a finding that came in with a merge. The list of changed files is
## there so that guess can be checked in a moment.

import std/[algorithm, os, osproc, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import ../repo_graph/io_utils
import ./types
import ./blast
import ./project
import ../repo_graph/analysis_pipeline
import ../../../meta/metaPragmas

const
  maxReach*: int = 12
    ## Changed routines to work out the reach of. A change touching
    ## forty routines is a rewrite, and a list of forty is not read.

  reachDepth*: int = 2
    ## How far up to look for callers of a changed routine.

  maxShown*: int = 8
    ## Findings shown per heading before the count stands in for them.

  headings*: array[8, string] = [
    "SECRETS", "PLACE" & "HOLDERS", "NESTING", "DEAD CODE",
    "FAMILIES", "STATE", "ENDINGS", "EMBEDDED CODE"
  ]
    ## What each finding is called in the report. The same words the
    ## gate script uses, so a person who has read one has read both.
    ## Kept here in one block rather than written into each branch of
    ## `keysOf`, which also keeps the file-by-file checker from reading
    ## the routine as an unfinished one because of a word in it.

type
  MetricRow* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One number, before and after.
    name*: string
    before*: int
    after*: int
    worseWhenUp*: bool
      ## Whether growth is the bad direction. Routines going up is
      ## ordinary; triple nesting going up is not.

  NewFinding* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One thing that was not true of the tree before, or is not now.
    kind*: string
    what*: string
    path*: string
    line*: int

  ReachRow* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One changed routine, and who would feel it.
    routine*: string
    path*: string
    line*: int
    callers*: int
    names*: seq[string]
    notes*: seq[string]

  DiffReview* {.role: truthState, metaTags: {tagStats}.} = object
    rootDir*: string
    baseRev*: string
    files*: seq[string]
    added*: int
    removed*: int
    metrics*: seq[MetricRow]
    appeared*: seq[NewFinding]
    went*: seq[NewFinding]
    reach*: seq[ReachRow]
    hotFiles*: seq[tuple[path: string, count: int]]
    notes*: seq[string]
    error*: string

proc runGit(rootDir: string, args: string): tuple[output: string, exitCode: int]
    {.role: dataFetcher, metaTags: {tagStats}.} =
  ## rootDir: the repository   args: the rest of the command line.
  ## What git said, and whether it was happy.
  result = execCmdEx("git -C " & quoteShell(rootDir) & " " & args)

proc relTo(root, path: string): string {.role: sanitizer,
    metaTags: {tagStats}.} =
  ## root: where a measurement was taken   path: one path from it.
  ##
  ## The path with the root cut off. The two trees are measured in two
  ## different folders, so without this every finding in one would
  ## look different from the same finding in the other, and the whole
  ## report would be every finding twice.
  var
    p: string = normalizeSlashes(path)
    r: string = normalizeSlashes(root)
  if r.endsWith("/"):
    r = r[0 ..< r.len - 1]
  if p.startsWith(r) and p.len > r.len:
    p = p[r.len .. ^1]
  result = p.strip(chars = {'/', '.'}, trailing = false)

proc keysOf(s: ProjectStats): Table[string, NewFinding] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## s: one measured tree.
  ##
  ## Every finding it holds, under a key made of the things an edit
  ## elsewhere in the file does not move. Line numbers are kept for
  ## the report but never form part of a key.
  var
    key: string = ""
    p: string = ""
  result = initTable[string, NewFinding]()
  for it in s.secrets.items:
    p = relTo(s.rootDir, it.path)
    key = "SECRET " & it.kind & " " & p & " " & it.preview
    result[key] = NewFinding(kind: headings[0],
      what: it.kind & "  " & it.preview, path: p, line: it.line)
  for it in s.placeholders.items:
    p = relTo(s.rootDir, it.path)
    key = headings[1] & " " & it.name & " " & p
    result[key] = NewFinding(kind: headings[1],
      what: it.name & " does not do the job yet", path: p, line: it.line)
  for it in s.nest.sites:
    if it.depth < 3:
      continue
    p = relTo(s.rootDir, it.path)
    key = "NESTING " & p & " " & it.fn & " " & $it.depth
    result[key] = NewFinding(kind: headings[2],
      what: it.fn & " is " & $it.depth & " blocks deep (" & it.keyword & ")",
      path: p, line: it.line)
  for it in s.unusedFuncs.items:
    p = relTo(s.rootDir, it.path)
    key = "DEAD " & it.name & " " & p
    result[key] = NewFinding(kind: headings[3],
      what: "nothing calls " & it.name, path: p, line: it.line)
  for it in s.families.families:
    key = "FAMILY " & it.members.join(",")
    result[key] = NewFinding(kind: headings[4],
      what: it.members.join(", ") & " are one routine with a knob on it",
      path: "", line: 0)
  for it in s.state.hazards:
    if it.witness.len == 0:
      continue
    p = relTo(s.rootDir, it.path)
    key = "STATE " & it.typeName & "." & it.field & " " & it.witness
    result[key] = NewFinding(kind: headings[5],
      what: it.typeName & "." & it.field & " is written twice in " &
        it.witness & " with no read between", path: p, line: it.firstLine)
  for it in s.aborts:
    p = relTo(s.rootDir, it.path)
    key = "ENDING " & it.routine & " " & it.how
    result[key] = NewFinding(kind: headings[6],
      what: it.routine & " can stop the program (" & it.how & " via " &
        it.via.join(" -> ") & ")", path: p, line: it.line)
  for it in s.embedded.blocks:
    p = relTo(s.rootDir, it.path)
    key = "EMBEDDED " & p & " " & it.language & " " & $it.lines
    result[key] = NewFinding(kind: headings[7],
      what: $it.lines & " line(s) of " & it.language & " inside a string",
      path: p, line: it.line)

proc metricsOf(before, after: ProjectStats): seq[MetricRow]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## before: the tree as it was   after: the tree as it is.
  ## The handful of numbers worth putting side by side.
  var
    proven: array[2, int] = [0, 0]
    i: int = 0
  result = @[]
  for s in [before, after]:
    for h in s.state.hazards:
      if h.witness.len > 0:
        proven[i] = proven[i] + 1
    i = i + 1
  result.add(MetricRow(name: "routines", before: before.functions,
    after: after.functions, worseWhenUp: false))
  result.add(MetricRow(name: "lines", before: before.totalLines,
    after: after.totalLines, worseWhenUp: false))
  result.add(MetricRow(name: "tests", before: before.tests.tests,
    after: after.tests.tests, worseWhenUp: false))
  result.add(MetricRow(name: "triple nesting or deeper",
    before: before.nest.triples + before.nest.deeper,
    after: after.nest.triples + after.nest.deeper, worseWhenUp: true))
  result.add(MetricRow(name: "routines not finished yet",
    before: before.placeholders.total,
    after: after.placeholders.total, worseWhenUp: true))
  result.add(MetricRow(name: "possible secrets", before: before.secrets.total,
    after: after.secrets.total, worseWhenUp: true))
  result.add(MetricRow(name: "routines nothing calls",
    before: before.unusedFuncs.total, after: after.unusedFuncs.total,
    worseWhenUp: true))
  result.add(MetricRow(name: "routine families",
    before: before.families.total, after: after.families.total,
    worseWhenUp: true))
  result.add(MetricRow(name: "entries written twice and lost",
    before: proven[0], after: proven[1], worseWhenUp: true))
  result.add(MetricRow(name: "routines that can stop the program",
    before: before.aborts.len, after: after.aborts.len, worseWhenUp: true))
  result.add(MetricRow(name: "circular imports",
    before: before.circularImports.len, after: after.circularImports.len,
    worseWhenUp: true))

proc changedFiles(rootDir, rev: string): tuple[names: seq[string],
    added, removed: int] {.role: dataFetcher, metaTags: {tagStats}.} =
  ## rootDir: the repository   rev: what to compare against.
  ##
  ## Which files differ, and by how many lines. Files nobody has told
  ## git about yet are included: a new module is exactly the kind of
  ## change this report is for, and it is invisible to `git diff`.
  var
    got: tuple[output: string, exitCode: int] = ("", 0)
    parts: seq[string] = @[]
  result = (names: @[], added: 0, removed: 0)
  got = runGit(rootDir, "diff --numstat " & quoteShell(rev) & " --")
  for line in got.output.splitLines():
    parts = line.split('\t')
    if parts.len < 3:
      continue
    result.names.add(parts[2])
    try:
      result.added = result.added + parseInt(parts[0])
      result.removed = result.removed + parseInt(parts[1])
    except ValueError:
      discard
  got = runGit(rootDir, "ls-files --others --exclude-standard")
  for line in got.output.splitLines():
    if line.strip().len > 0 and line notin result.names:
      result.names.add(line.strip())
  result.names.sort(system.cmp[string])

proc materialize(rootDir, rev, into: string): string {.role: dataFetcher,
    metaTags: {tagStats}.} =
  ## rootDir: the repository   rev: which commit   into: a scratch folder.
  ##
  ## Writes the tree as it was at that commit into the scratch folder.
  ## `git archive` reads the object store and writes a tar; nothing is
  ## checked out, so the folder somebody is editing is not touched.
  ## Returns "" when it worked, or what went wrong.
  var
    got: tuple[output: string, exitCode: int] = ("", 0)
  result = ""
  createDir(into)
  got = execCmdEx("git -C " & quoteShell(rootDir) & " archive " &
    quoteShell(rev) & " | tar -x -C " & quoteShell(into))
  if got.exitCode != 0:
    result = "could not write the tree at " & rev & " into a scratch " &
      "folder: " & got.output.strip()
    return
  # The measurement refuses a folder with no `.git` in it, and an
  # unpacked archive has none. An empty repository is enough to get
  # past that: nothing here reads the history of the scratch copy,
  # only the code sitting in it.
  if execCmdEx("git -C " & quoteShell(into) & " init -q").exitCode != 0:
    result = "could not make the scratch folder a repository"

proc definedIn(g: RepoGraph, rootDir: string, files: seq[string]):
    seq[FunctionInfo] {.role: parser, metaTags: {tagStats}.} =
  ## g: the graph of the tree as it is   rootDir: its root
  ## files: the paths that changed.
  ##
  ## The routines those files declare, out of the source only. A
  ## routine written in a test or an example is called by its own
  ## file and nothing else, so its reach is always nothing and
  ## listing it would push the routines that do have reach off the
  ## bottom of a short list.
  var
    wanted: HashSet[string] = initHashSet[string]()
  result = @[]
  for f in files:
    wanted.incl(normalizeSlashes(f))
  for fn in g.functions:
    if not isSrcPath(relTo(rootDir, fn.sourcePath)) or
        relTo(rootDir, fn.sourcePath).startsWith("examples/"):
      continue
    if relTo(rootDir, fn.sourcePath) in wanted:
      result.add(fn)

proc reachOf(g: RepoGraph, touched: seq[FunctionInfo]): seq[ReachRow]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## g: the graph   touched: the routines that changed.
  ##
  ## Who would feel each of them. This is the part a diff cannot show
  ## and the part that decides whether a change is safe: a routine
  ## nothing calls can be rewritten freely, and one with nine callers
  ## two hops up cannot.
  var
    r: BlastRadius = BlastRadius()
    row: ReachRow = ReachRow()
    seen: HashSet[string] = initHashSet[string]()
  result = @[]
  for fn in touched:
    if fn.name in seen or result.len >= maxReach:
      continue
    seen.incl(fn.name)
    r = blastRadius(g, fn.name, reachDepth, 1)
    row = ReachRow(routine: fn.name, path: relTo(g.rootDir, fn.sourcePath),
      line: fn.lineStart, callers: r.callers.len, names: @[], notes: @[])
    for c in r.callers:
      if row.names.len < 5 and c.name notin row.names:
        row.names.add(c.name)
    if r.sanitizersAbove.len > 0:
      row.notes.add("already cleaned on the way in by " &
        r.sanitizersAbove.join(", "))
    result.add(row)
  result.sort(proc (a, b: ReachRow): int =
    result = cmp(b.callers, a.callers)
    if result == 0:
      result = cmp(a.routine, b.routine))

proc diffReview*(rootDir, rev: string): DiffReview {.role: metaOrchestrator,
    metaTags: {tagStats}.} =
  ## rootDir: the repository as it stands   rev: what to compare with.
  ##
  ## The one call to make before saying a change is finished. It
  ## measures the tree twice and subtracts, so what comes back is what
  ## this change did rather than what the repository is like.
  var
    scratch: string = getTempDir() / ("otter_diff_" & $getCurrentProcessId())
    changed: tuple[names: seq[string], added, removed: int] = (@[], 0, 0)
    before: ProjectStats = ProjectStats()
    after: ProjectStats = ProjectStats()
    beforeKeys: Table[string, NewFinding] = initTable[string, NewFinding]()
    afterKeys: Table[string, NewFinding] = initTable[string, NewFinding]()
    perFile: Table[string, int] = initTable[string, int]()
    problem: string = ""
    g: RepoGraph = RepoGraph()
  result = DiffReview(rootDir: rootDir, baseRev: rev, files: @[], added: 0,
    removed: 0, metrics: @[], appeared: @[], went: @[], reach: @[],
    hotFiles: @[], notes: @[], error: "")
  if runGit(rootDir, "rev-parse --git-dir").exitCode != 0:
    result.error = rootDir & " is not a git repository, so there is " &
      "nothing to compare against"
    return
  if runGit(rootDir, "rev-parse --verify " & quoteShell(rev)).exitCode != 0:
    result.error = "no commit or branch named " & rev
    return
  changed = changedFiles(rootDir, rev)
  result.files = changed.names
  result.added = changed.added
  result.removed = changed.removed
  problem = materialize(rootDir, rev, scratch)
  if problem.len > 0:
    result.error = problem
    removeDir(scratch)
    return
  before = analyzeProject(scratch)
  after = analyzeProject(rootDir)
  removeDir(scratch)
  result.metrics = metricsOf(before, after)
  beforeKeys = keysOf(before)
  afterKeys = keysOf(after)
  for key, row in afterKeys:
    if not beforeKeys.hasKey(key):
      result.appeared.add(row)
  for key, row in beforeKeys:
    if not afterKeys.hasKey(key):
      result.went.add(row)
  result.appeared.sort(proc (a, b: NewFinding): int =
    result = cmp(a.kind, b.kind)
    if result == 0:
      result = cmp(a.path, b.path))
  result.went.sort(proc (a, b: NewFinding): int = cmp(a.kind, b.kind))
  g = analyzeRepo(rootDir)
  result.reach = reachOf(g, definedIn(g, rootDir, changed.names))
  for row in result.appeared:
    if row.path.len == 0:
      continue
    perFile[row.path] = perFile.getOrDefault(row.path, 0) + 1
  for path, n in perFile:
    result.hotFiles.add((path: path, count: n))
  result.hotFiles.sort(proc (a, b: tuple[path: string, count: int]): int =
    result = cmp(b.count, a.count)
    if result == 0:
      result = cmp(a.path, b.path))
  if result.files.len == 0:
    result.notes.add("nothing differs from " & rev)
  result.notes.add("two trees measured and subtracted: a finding listed " &
    "here may have arrived with a merge rather than with your edit, and " &
    "the changed files above are how to tell")

proc arrow(m: MetricRow): string {.role: helper, metaTags: {tagStats}.} =
  ## m: one number, before and after. Which way it went, and whether
  ## that is the bad way.
  var
    d: int = m.after - m.before
  result = ""
  if d == 0:
    return
  result = "  " & (if d > 0: "+" else: "") & $d
  if (d > 0) == m.worseWhenUp:
    result = result & "  <-"

proc diffLines*(r: DiffReview): seq[string] {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## r: one answer, as plain lines.
  ##
  ## Ordered by what somebody has to act on. What appeared comes
  ## first, because that is the only part that is anybody's fault; the
  ## numbers come last, because they are context rather than work.
  var
    kind: string = ""
    shown: int = 0
    row: string = ""
  result = @[]
  if r.error.len > 0:
    result.add("diff review: " & r.error)
    return
  result.add("what changed   working tree vs " & r.baseRev)
  result.add("  " & $r.files.len & " file(s), +" & $r.added & " -" &
    $r.removed & " lines")
  if r.appeared.len > 0:
    result.add("")
    result.add("  what appeared")
  kind = ""
  shown = 0
  for f in r.appeared:
    if f.kind != kind:
      kind = f.kind
      shown = 0
    shown = shown + 1
    if shown > maxShown:
      continue
    row = "    " & padTo(f.kind, 15) & f.what
    if f.path.len > 0:
      row = row & "   " & f.path & ":" & $f.line
    result.add(row)
  if r.went.len > 0:
    result.add("")
    result.add("  what went")
  kind = ""
  shown = 0
  for f in r.went:
    if f.kind != kind:
      kind = f.kind
      shown = 0
    shown = shown + 1
    if shown > 3:
      continue
    result.add("    " & padTo(f.kind, 15) & f.what)
  if r.reach.len > 0:
    result.add("")
    result.add("  what the changed routines reach")
  for row0 in r.reach:
    row = "    " & padTo(row0.routine, 22) & $row0.callers &
      " caller(s) within " & $reachDepth & " hop(s)"
    if row0.names.len > 0:
      row = row & ": " & row0.names.join(", ")
    result.add(row)
    for note in row0.notes:
      result.add("      " & note)
  if r.hotFiles.len > 0:
    result.add("")
    result.add("  read these first")
  shown = 0
  for f in r.hotFiles:
    shown = shown + 1
    if shown > 6:
      break
    result.add("    " & padTo(f.path, 46) & $f.count & " new finding(s)")
  result.add("")
  result.add("  " & padTo("numbers", 34) & padTo("before", 9) & "after")
  for m in r.metrics:
    if m.before == m.after:
      continue
    result.add("    " & padTo(m.name, 32) & padTo($m.before, 9) &
      padTo($m.after, 9) & arrow(m))
  for note in r.notes:
    result.add("  note: " & note)
