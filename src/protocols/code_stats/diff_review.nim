## ================================================================
## | diff_review.nim  <-  what this change did, and where to look  |
## |---------------------------------------------------------------|
## | A diff says which lines moved. It does not say whether any of  |
## | them is a problem, and it never says who calls the routines    |
## | that moved. Both are the difference between a careful change   |
## | and a destructive one, and neither fits in a diff.             |
## ================================================================
##
## Who this is for
## ---------------
## Somebody - a person in a hurry, or a program with a small memory -
## who has just changed four files and is about to say they are done.
## The whole measurement of a repository would tell them two hundred
## things, of which a hundred and ninety-six were already true this
## morning. This is a guide, not a measurement, so it says four:
##
##   on lines you changed    findings sitting on a line the diff touched
##   elsewhere in your files findings in the same files, further off
##   what you may have cut   routines whose last caller you removed
##   what this reaches       who calls the routines you changed
##
## Every finding carries the command that found it, so the next step
## is a copy and a paste rather than a hunt.
##
## The tree is measured once
## -------------------------
## An earlier version of this unpacked the tree as it used to be into
## a scratch folder and measured that too, then subtracted. It gave a
## true before-and-after and cost twice the time, a `tar`, and a
## scratch copy of the whole repository - to answer a question that is
## really "where should I look first".
##
## So the diff itself decides what is yours:
##
##     git diff --unified=0 <rev>
##       @@ -88,3 +88,7 @@        <- lines 88..94 of the file as it is
##
## A finding on one of those lines is yours. A finding elsewhere in a
## file you touched is worth a glance. Everything else is the
## repository, not the change.
##
## The one thing this cannot see, and what is done about it
## -------------------------------------------------------
## Measuring one tree cannot notice a finding your change caused
## somewhere else - you deleted the last call to `oldParse`, and now
## `oldParse` is dead weight in a file you never opened.
##
## That case is caught without a second measurement, because the diff
## already holds the answer. The lines you **removed** name what they
## called, and any of those names that nothing in the tree calls any
## more is a routine you have just orphaned. It is the far-reaching
## consequence that a diff hides best, and it costs one pass over the
## text of the diff.
##
## Other kinds of knock-on - a number that drifted, a family that grew
## a fifth member - are not seen here. `stats` still answers those.

import std/[algorithm, os, osproc, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import ../repo_graph/io_utils
import ../repo_graph/nim_parser
import ../repo_graph/analysis_pipeline
import ./types
import ./project
import ./blast
import ../../../meta/metaPragmas

const
  maxReach*: int = 12
    ## Changed routines to work out the reach of. A change touching
    ## forty routines is a rewrite, and a list of forty is not read.

  reachDepth*: int = 2
    ## How far up to look for callers of a changed routine.

  maxShown*: int = 10
    ## Findings shown per heading before the count stands in for them.

  maxFiles*: int = 8
    ## Files named in the closing list.

  headings*: array[8, string] = [
    "SECRETS", "PLACE" & "HOLDERS", "NESTING", "DEAD CODE",
    "FAMILIES", "STATE", "ENDINGS", "EMBEDDED CODE"
  ]
    ## What each finding is called. The same words the gate script
    ## uses, so a person who has read one has read both. Kept in one
    ## block rather than written into each branch, which also keeps the
    ## file-by-file checker from reading the routine that builds them
    ## as an unfinished one because of a word in it.

type
  Hunk* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One run of lines the diff touched, in the file as it is now.
    path*: string
    first*: int
    last*: int

  Finding* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One thing worth looking at, and how to look at it again.
    kind*: string
    what*: string
    path*: string
    line*: int
    command*: string
      ## The command that found this, ready to run.

  ReachRow* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One changed routine, and who would feel it.
    routine*: string
    path*: string
    line*: int
    callers*: int
    names*: seq[string]
    notes*: seq[string]
    command*: string

  DiffReview* {.role: truthState, metaTags: {tagStats}.} = object
    rootDir*: string
    baseRev*: string
    files*: seq[string]
    hunks*: int
    added*: int
    removed*: int
    yours*: seq[Finding]
      ## On a line the change touched.
    nearby*: seq[Finding]
      ## Elsewhere in a file the change touched.
    orphaned*: seq[Finding]
      ## Routines whose last caller the change removed.
    reach*: seq[ReachRow]
    hotFiles*: seq[tuple[path: string, yours, nearby: int]]
    notes*: seq[string]
    error*: string

proc runGit(rootDir: string, args: string): tuple[output: string,
    exitCode: int] {.role: dataFetcher, metaTags: {tagStats}.} =
  ## rootDir: the repository   args: the rest of the command line.
  ## What git said, and whether it was happy.
  result = execCmdEx("git -C " & quoteShell(rootDir) & " " & args)

proc relTo(root, path: string): string {.role: sanitizer,
    metaTags: {tagStats}.} =
  ## root: where the measurement was taken   path: one path from it.
  ## The path with the root cut off, so it matches what git prints.
  var
    p: string = normalizeSlashes(path)
    r: string = normalizeSlashes(root)
  if r.endsWith("/"):
    r = r[0 ..< r.len - 1]
  if p.startsWith(r) and p.len > r.len:
    p = p[r.len .. ^1]
  result = p.strip(chars = {'/', '.'}, trailing = false)

proc parseHunkHeader*(s, path: string): Hunk {.role: parser,
    metaTags: {tagStats}.} =
  ## s: a line like `@@ -12,3 +40,5 @@`   path: the file it is in.
  ##
  ## The run of lines it names in the file as it is now. A count of
  ## zero means lines were only removed there, and the join is still
  ## worth pointing at, so it keeps a single line.
  var
    at: int = s.find('+')
    tail: string = ""
    parts: seq[string] = @[]
    start: int = 0
    count: int = 1
  result = Hunk(path: path, first: 0, last: -1)
  if at < 0:
    return
  tail = s[at + 1 .. ^1].split(' ')[0]
  parts = tail.split(',')
  try:
    start = parseInt(parts[0])
    if parts.len > 1:
      count = parseInt(parts[1])
  except ValueError:
    return
  if count < 1:
    count = 1
  result = Hunk(path: path, first: start, last: start + count - 1)

proc changedLines(rootDir, rev: string): tuple[hunks: seq[Hunk],
    files: seq[string], added, removed: int, cut: seq[string]]
    {.role: dataFetcher, metaTags: {tagStats}.} =
  ## rootDir: the repository   rev: what to compare against.
  ##
  ## Which lines differ, which files, and the text of every line the
  ## change removed. `--unified=0` asks for no context, so each hunk
  ## names only lines that really moved rather than the three either
  ## side of them.
  ##
  ## Files nobody has told git about yet count as changed in full: a
  ## new module is exactly the kind of change this is for, and it is
  ## invisible to `git diff`.
  var
    got: tuple[output: string, exitCode: int] = ("", 0)
    path: string = ""
    n: int = 0
  result = (hunks: @[], files: @[], added: 0, removed: 0, cut: @[])
  got = runGit(rootDir, "diff --unified=0 " & quoteShell(rev) & " --")
  for line in got.output.splitLines():
    if line.startsWith("+++ b/"):
      path = line[6 .. ^1]
      if path notin result.files:
        result.files.add(path)
      continue
    if line.startsWith("@@"):
      if path.len > 0:
        result.hunks.add(parseHunkHeader(line, path))
      continue
    if line.startsWith("+") and not line.startsWith("+++"):
      result.added = result.added + 1
      continue
    if line.startsWith("-") and not line.startsWith("---"):
      result.removed = result.removed + 1
      result.cut.add(line[1 .. ^1])
  got = runGit(rootDir, "ls-files --others --exclude-standard")
  for line in got.output.splitLines():
    path = line.strip()
    if path.len == 0 or path in result.files:
      continue
    result.files.add(path)
    n = readLinesSafe(rootDir / path).len
    result.added = result.added + n
    result.hunks.add(Hunk(path: path, first: 1, last: max(1, n)))
  result.files.sort(system.cmp[string])

proc findingsOf(s: ProjectStats, root: string): seq[Finding]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## s: the measured tree   root: how to write it in a command.
  ##
  ## Every finding the measurement holds, flattened into one list with
  ## the command that found it beside each. The command matters as
  ## much as the finding: a reader who has to work out how to look
  ## again mostly does not look again.
  var
    stats: string = "otter-repo-graph stats " & root
  result = @[]
  for it in s.secrets.items:
    result.add(Finding(kind: headings[0], what: it.kind & "  " & it.preview,
      path: relTo(s.rootDir, it.path), line: it.line,
      command: stats & " --json   (.secrets)"))
  for it in s.placeholders.items:
    result.add(Finding(kind: headings[1],
      what: it.name & " does not do the job yet",
      path: relTo(s.rootDir, it.path), line: it.line,
      command: stats & " --json   (.placeholders)"))
  for it in s.nest.sites:
    if it.depth < 3:
      continue
    result.add(Finding(kind: headings[2],
      what: it.fn & " is " & $it.depth & " blocks deep (" & it.keyword & ")",
      path: relTo(s.rootDir, it.path), line: it.line,
      command: stats & " --json   (.nest.sites)"))
  for it in s.unusedFuncs.items:
    result.add(Finding(kind: headings[3], what: "nothing calls " & it.name,
      path: relTo(s.rootDir, it.path), line: it.line,
      command: stats & " --json   (.unusedFuncs)"))
  for it in s.families.families:
    result.add(Finding(kind: headings[4],
      what: it.members.join(", ") & " are one routine with a knob on it",
      path: relTo(s.rootDir, it.paths[0]), line: it.lines[0],
      command: stats & " --json   (.families)"))
  for it in s.state.hazards:
    if it.witness.len == 0:
      continue
    result.add(Finding(kind: headings[5],
      what: it.typeName & "." & it.field & " is written twice in " &
        it.witness & " with no read between",
      path: relTo(s.rootDir, it.path), line: it.firstLine,
      command: "otter-repo-graph state " & root & " " & it.typeName))
  for it in s.aborts:
    result.add(Finding(kind: headings[6],
      what: it.routine & " can stop the program (" & it.how & " via " &
        it.via.join(" -> ") & ")",
      path: relTo(s.rootDir, it.path), line: it.line,
      command: "otter-repo-graph yields " & root & " " & it.routine))
  for it in s.embedded.blocks:
    result.add(Finding(kind: headings[7],
      what: $it.lines & " line(s) of " & it.language & " inside a string",
      path: relTo(s.rootDir, it.path), line: it.line,
      command: stats & " --json   (.embedded)"))

proc touched(hunks: seq[Hunk], path: string, line: int): bool
    {.role: parser, metaTags: {tagStats}.} =
  ## hunks: the runs of lines the change touched   path, line: a finding.
  ## Whether that finding sits on one of them.
  result = false
  for h in hunks:
    if h.path == path and line >= h.first and line <= h.last:
      return true

proc orphansOf(g: RepoGraph, cut: seq[string], root: string): seq[Finding]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## g: the tree as it is   cut: the text of every removed line
  ## root: how to write the repository in a command.
  ##
  ## Routines the change may have orphaned. The removed lines say what
  ## they called; anything they called that nothing calls any more is
  ## a routine left with no way in. This is the far-reaching effect a
  ## diff hides best - it lands in a file the author never opened -
  ## and the diff itself is enough to find it.
  var
    called: HashSet[string] = initHashSet[string]()
    gone: seq[string] = @[]
    seen: HashSet[string] = initHashSet[string]()
  result = @[]
  for f in g.functions:
    for name in f.calls:
      called.incl(name.toLowerAscii())
  for name in extractCalls(cut):
    if name.toLowerAscii() notin called and name notin gone:
      gone.add(name)
  for f in g.functions:
    if f.name notin gone or f.name in seen:
      continue
    seen.incl(f.name)
    result.add(Finding(kind: headings[3],
      what: "you removed the last call to " & f.name,
      path: relTo(g.rootDir, f.sourcePath), line: f.lineStart,
      command: "otter-repo-graph blast " & root & " " & f.name))

proc definedIn(g: RepoGraph, files: seq[string]): seq[FunctionInfo]
    {.role: parser, metaTags: {tagStats}.} =
  ## g: the tree as it is   files: the paths that changed.
  ##
  ## The routines those files declare, out of the source only. A
  ## routine written in a test or an example is called by its own file
  ## and nothing else, so its reach is always nothing and listing it
  ## would push the ones that do have reach off a short list.
  var
    wanted: HashSet[string] = initHashSet[string]()
    rel: string = ""
  result = @[]
  for f in files:
    wanted.incl(normalizeSlashes(f))
  for fn in g.functions:
    rel = relTo(g.rootDir, fn.sourcePath)
    if not isSrcPath(rel) or rel.startsWith("examples/"):
      continue
    if rel in wanted:
      result.add(fn)

proc reachOf(g: RepoGraph, touchedFns: seq[FunctionInfo], root: string):
    seq[ReachRow] {.role: truthBuilder, metaTags: {tagStats}.} =
  ## g: the tree   touchedFns: the routines that changed
  ## root: how to write the repository in a command.
  ##
  ## Who would feel each of them. This is the part a diff cannot show
  ## and the part that decides whether a change is safe: a routine
  ## nothing calls can be rewritten freely, one with nine callers two
  ## hops up cannot.
  var
    r: BlastRadius = BlastRadius()
    row: ReachRow = ReachRow()
    seen: HashSet[string] = initHashSet[string]()
  result = @[]
  for fn in touchedFns:
    if fn.name in seen or result.len >= maxReach:
      continue
    seen.incl(fn.name)
    r = blastRadius(g, fn.name, reachDepth, 1)
    row = ReachRow(routine: fn.name, path: relTo(g.rootDir, fn.sourcePath),
      line: fn.lineStart, callers: r.callers.len, names: @[], notes: @[],
      command: "otter-repo-graph blast " & root & " " & fn.name)
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
  ## The one call to make before saying a change is finished. One
  ## measurement of the tree as it is, with the diff deciding which
  ## part of it is anybody's fault.
  var
    changed: tuple[hunks: seq[Hunk], files: seq[string], added,
      removed: int, cut: seq[string]] = (@[], @[], 0, 0, @[])
    s: ProjectStats = ProjectStats()
    g: RepoGraph = RepoGraph()
    inFiles: HashSet[string] = initHashSet[string]()
    perFile: Table[string, tuple[yours, nearby: int]] = initTable[string,
      tuple[yours, nearby: int]]()
    row: tuple[yours, nearby: int] = (0, 0)
  result = DiffReview(rootDir: rootDir, baseRev: rev, files: @[], hunks: 0,
    added: 0, removed: 0, yours: @[], nearby: @[], orphaned: @[], reach: @[],
    hotFiles: @[], notes: @[], error: "")
  if runGit(rootDir, "rev-parse --git-dir").exitCode != 0:
    result.error = rootDir & " is not a git repository, so there is " &
      "nothing to compare against"
    return
  if runGit(rootDir, "rev-parse --verify " & quoteShell(rev)).exitCode != 0:
    result.error = "no commit or branch named " & rev
    return
  changed = changedLines(rootDir, rev)
  result.files = changed.files
  result.hunks = changed.hunks.len
  result.added = changed.added
  result.removed = changed.removed
  for f in changed.files:
    inFiles.incl(f)
  s = analyzeProject(rootDir)
  if s.error.len > 0:
    result.error = s.error
    return
  g = analyzeRepo(rootDir)
  for f in findingsOf(s, rootDir):
    if f.path.len == 0 or f.path notin inFiles:
      continue
    if touched(changed.hunks, f.path, f.line):
      result.yours.add(f)
    else:
      result.nearby.add(f)
  result.orphaned = orphansOf(g, changed.cut, rootDir)
  result.reach = reachOf(g, definedIn(g, changed.files), rootDir)
  result.yours.sort(proc (a, b: Finding): int =
    result = cmp(a.kind, b.kind)
    if result == 0:
      result = cmp(a.path, b.path))
  result.nearby.sort(proc (a, b: Finding): int = cmp(a.kind, b.kind))
  for f in result.yours:
    row = perFile.getOrDefault(f.path, (0, 0))
    perFile[f.path] = (yours: row.yours + 1, nearby: row.nearby)
  for f in result.nearby:
    row = perFile.getOrDefault(f.path, (0, 0))
    perFile[f.path] = (yours: row.yours, nearby: row.nearby + 1)
  for path, counts in perFile:
    result.hotFiles.add((path: path, yours: counts.yours,
      nearby: counts.nearby))
  result.hotFiles.sort(proc (a, b: tuple[path: string, yours,
      nearby: int]): int =
    result = cmp(b.yours, a.yours)
    if result == 0:
      result = cmp(b.nearby, a.nearby)
    if result == 0:
      result = cmp(a.path, b.path))
  if result.files.len == 0:
    result.notes.add("nothing differs from " & rev)
  result.notes.add("one measurement of the tree as it is: a number " &
    "that drifted somewhere you did not touch is not shown here, and " &
    "`stats` still answers that")

proc findingBlock(rows: seq[Finding], title: string, cap: int): seq[string]
    {.role: dataWriter, metaTags: {tagStats}.} =
  ## rows: what to show   title: the heading   cap: how many fit.
  ## One heading and its findings, each with the command that found it
  ## on the line below.
  var
    shown: int = 0
  result = @[]
  if rows.len == 0:
    return
  result.add("")
  result.add("  " & title)
  for f in rows:
    shown = shown + 1
    if shown > cap:
      result.add("    ... and " & $(rows.len - cap) & " more")
      return
    result.add("    " & padTo(f.kind, 15) & f.what)
    result.add("    " & padTo("", 15) & f.path & ":" & $f.line &
      "   " & f.command)

proc diffLines*(r: DiffReview): seq[string] {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## r: one answer, as plain lines.
  ##
  ## Ordered by how likely a line is to be the reader's own doing.
  ## What sits on a line they changed comes first; what merely shares
  ## a file with it comes after; the repository at large does not come
  ## at all.
  var
    row: string = ""
    shown: int = 0
  result = @[]
  if r.error.len > 0:
    result.add("diff review: " & r.error)
    return
  result.add("what changed   working tree vs " & r.baseRev)
  result.add("  " & $r.files.len & " file(s), " & $r.hunks & " hunk(s), +" &
    $r.added & " -" & $r.removed & " lines")
  for line in findingBlock(r.yours, "on lines you changed", maxShown):
    result.add(line)
  for line in findingBlock(r.orphaned,
      "what you may have cut off", maxShown):
    result.add(line)
  for line in findingBlock(r.nearby,
      "elsewhere in the files you changed", maxShown):
    result.add(line)
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
  if r.reach.len > 0:
    result.add("    " & padTo("", 22) & r.reach[0].command &
      "   (for any one of them)")
  if r.hotFiles.len > 0:
    result.add("")
    result.add("  read these first")
  shown = 0
  for f in r.hotFiles:
    shown = shown + 1
    if shown > maxFiles:
      break
    result.add("    " & padTo(f.path, 46) & $f.yours & " on your lines, " &
      $f.nearby & " nearby")
  if r.yours.len + r.orphaned.len == 0 and r.files.len > 0:
    result.add("")
    result.add("  nothing on the lines you changed")
  for note in r.notes:
    result.add("  note: " & note)
