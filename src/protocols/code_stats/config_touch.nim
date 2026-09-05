## ==============================================================
## | config_touch.nim  <-  which settings actually do anything   |
## |------------------------------------------------------------|
## | A configuration object is a promise: every switch on it is  |
## | supposed to change what the program does. Over time some of |
## | those promises quietly stop being kept. A switch is added,  |
## | the code that read it is rewritten, and the switch stays    |
## | in the file forever, doing nothing, while somebody keeps    |
## | setting it and wondering why nothing changes.               |
## |                                                             |
## | This file goes through every routine and writes down which  |
## | settings each one reads and which it writes:                |
## |                                                             |
## |   setting          read by      written by                  |
## |   ---------------  -----------  ----------------            |
## |   maxRetries       4 routines   1 routine                   |
## |   useCache         0 routines   2 routines   <- does nothing|
## |   verbose          7 routines   0 routines                  |
## |                                                             |
## | From that table four kinds of trouble fall out:             |
## |                                                             |
## |   does nothing   written, never read. Setting it is a lie.  |
## |   never set      read, never written, and no default. It    |
## |                  will be whatever zero happens to mean.     |
## |   contested      written from several places. Which one     |
## |                  wins depends on the order things run in.   |
## |   refused pair   the code itself says these two must not    |
## |                  both be on.                                |
## |                                                             |
## | The last one is worth explaining, because "which settings   |
## | conflict" has no general answer. A program cannot be asked  |
## | what its settings mean. What it *can* be asked is where it  |
## | already refuses a combination out loud:                     |
## |                                                             |
## |   if cfg.quiet and cfg.verbose:                             |
## |     raise newException(ValueError, "pick one")              |
## |                                                             |
## | That is a conflict the authors wrote down themselves, and   |
## | those are found exactly. Everything else is reported as     |
## | the weaker "contested" rather than guessed at.              |
## ==============================================================

import std/[algorithm, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import ../repo_graph/io_utils
import ../../../.iron/metaPragmas

const
  configEndings*: array[6, string] = [
    "config", "settings", "options", "preferences", "opts", "prefs"
  ]
    ## What a settings type's name *ends* with. The ending is what is
    ## checked, not merely that the word appears somewhere, because
    ## `ConfigReport` and `ConfigField` are reports about settings and
    ## are not themselves settings. Getting this wrong turns every
    ## record in a repository into a configuration object.
  configNames*: array[4, string] = ["cfg", "conf", "config", "settings"]
    ## Names a variable holding settings usually goes by, used when a
    ## routine takes settings without saying so in a type.
  refusalWords*: array[6, string] = [
    "raise", "quit", "error", "abort", "invalid", "cannot"
  ]
    ## What a routine says when it will not accept a combination.
  fieldsShown*: int = 80
    ## How many settings travel to a window. The rest are counted.
  touchersShown*: int = 12
    ## How many routine names are listed per setting before the rest
    ## are only counted. A setting read in forty places is a fact;
    ## forty names on screen is a wall.

type
  ConfigField* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One setting, and everything that touches it.
    ##
    ##   readers   routines that look at it
    ##   writers   routines that change it
    ##   verdict   "fine", "does nothing", "never set", "contested"
    name*: string
    typeName*: string
    fieldType*: string
    verdict*: string
    path*: string
    readers*: seq[string]
    writers*: seq[string]
    line*: int
    readCount*: int
    writeCount*: int
    hasDefault*: bool

  ConfigConflict* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Two settings that cannot both be trusted at once.
    ##
    ##   kind    "refused"    the code refuses this pair out loud
    ##           "contested"  both written from several places
    ##   detail  the line that says so, or why it was inferred
    a*: string
    b*: string
    kind*: string
    detail*: string
    path*: string
    line*: int
    certainty*: float

  ConfigReport* {.role: truthState, metaTags: {tagStats}.} = object
    ## What every configuration object in one repository looks like.
    types*: seq[string]
    fields*: seq[ConfigField]
    conflicts*: seq[ConfigConflict]
    fieldCount*: int
    deadCount*: int
    unsetCount*: int
    contestedCount*: int
    touchingFunctions*: int

proc isConfigType*(name: string, decl: string = ""): bool
    {.role: parser, metaTags: {tagStats}.} =
  ## name <- a type's name   decl <- the whole line it was declared on
  ##
  ## A type counts as settings when it says so with the `configurator`
  ## role, or when its name ends the way settings types are named:
  ##
  ##   OtterUiConfig  {.role: configurator.}   yes, both ways
  ##   AppSettings                             yes, by its ending
  ##   ConfigReport                            no, this is a report
  ##                                           *about* settings
  var
    t: string = name.toLowerAscii()
  result = false
  if "configurator" in decl.toLowerAscii():
    return true
  for row in configEndings:
    if t.endsWith(row):
      return true
  result = t in ["cfg", "conf"]

proc identAt*(line: string, at: int): string {.role: parser,
    metaTags: {tagStats}.} =
  ## line <- one line   at <- where a name starts
  ## The whole name beginning there, letters, digits and underscores.
  var
    i: int = at
  result = ""
  while i < line.len and (line[i].isAlphaNumeric() or line[i] == '_'):
    result.add(line[i])
    i = i + 1

proc scanConfigTypes*(rootDir: string, files: seq[string]):
    tuple[types: seq[string], fields: seq[ConfigField]]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## rootDir <- the repository   files <- every source file
  ##
  ## Walks each file looking for a `type` block, then for a settings
  ## object inside it, then for the names declared under that object:
  ##
  ##   type
  ##     Settings* = object      <- a settings object, by its name
  ##       maxRetries*: int      <- one setting
  ##       useCache*: bool = true <- one setting, with a default
  ##
  ## Indentation decides where the object ends, the same way it does
  ## for the compiler.
  var
    lines: seq[string] = @[]
    t: string = ""
    rel: string = ""
    current: string = ""
    fieldName: string = ""
    fieldType: string = ""
    indentType: int = -1
    indentField: int = -1
    indent: int = 0
    at: int = 0
    inType: bool = false
    seen: HashSet[string] = initHashSet[string]()
  result = (types: @[], fields: @[])
  for path in files:
    if not (path.endsWith(".nim") or path.endsWith(".nims")):
      continue
    rel = normalizeSlashes(path)
    if rootDir.len > 0 and rel.startsWith(normalizeSlashes(rootDir)):
      rel = rel[rootDir.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    lines = readLinesSafe(path)
    inType = false
    current = ""
    indentType = -1
    indentField = -1
    at = 0
    while at < lines.len:
      t = lines[at].strip()
      indent = lines[at].len - lines[at].strip(leading = true,
        trailing = false).len
      at = at + 1
      if t.len == 0 or t.startsWith("#"):
        continue
      if t == "type" or t.startsWith("type "):
        inType = true
        indentType = indent
        current = ""
        continue
      if inType and indent <= indentType and t != "type":
        inType = false
        current = ""
      if not inType:
        continue
      # `Settings* = object` or `Settings* {.role: configurator.} = object`
      if ("= object" in t or "= ref object" in t or "= tuple" in t) and
          '=' in t:
        current = t[0 ..< t.find('=')].strip()
        if '*' in current:
          current = current[0 ..< current.find('*')].strip()
        if '{' in current:
          current = current[0 ..< current.find('{')].strip()
        current = current.strip()
        indentField = indent
        if isConfigType(current, t) and current notin seen:
          seen.incl(current)
          result.types.add(current)
        continue
      if current.len == 0 or current notin result.types:
        continue
      if indent <= indentField:
        current = ""
        continue
      # A field line: `name*: type` or `name*: type = default`
      if ':' notin t:
        continue
      fieldName = t[0 ..< t.find(':')].strip()
      if '*' in fieldName:
        fieldName = fieldName[0 ..< fieldName.find('*')].strip()
      if fieldName.len == 0 or ' ' in fieldName or ',' in fieldName:
        continue
      if not (fieldName[0].isAlphaAscii() or fieldName[0] == '_'):
        continue
      fieldType = t[t.find(':') + 1 .. ^1].strip()
      result.fields.add(ConfigField(name: fieldName, typeName: current,
        fieldType: fieldType.split('=')[0].strip(), verdict: "fine",
        path: rel, readers: @[], writers: @[], line: at,
        readCount: 0, writeCount: 0, hasDefault: '=' in fieldType))

proc receiversIn*(f: FunctionInfo, typeName: string): HashSet[string]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## f <- one routine   typeName <- the settings type being tracked
  ##
  ## The local names inside this routine that actually hold settings.
  ##
  ## This is the difference between a useful answer and a useless one.
  ## Settings objects have ordinary field names — `name`, `line`,
  ## `kind` — and a search for a bare `.name` matches every object in
  ## a repository. So the thing in front of the dot has to be checked
  ## too, and only these names count:
  ##
  ##   proc run(cfg: OtterUiConfig) =    <- `cfg` holds settings
  ##     var local: OtterUiConfig = ...  <- so does `local`
  ##     echo other.name                 <- `other` does not; skipped
  var
    head: string = ""
    at: int = 0
    t: string = ""
  result = initHashSet[string]()
  # A routine that *builds* settings writes them into `result`:
  #
  #   proc loadConfig(dir: string): AppSettings =
  #     result.repoRoot = dir       <- this is how settings get set
  #
  # Miss this and every setting in a repository reads as "never set",
  # because the builder is usually the only place that sets them.
  if typeName.len > 0 and typeName in f.returnType:
    result.incl("result")
  # The types are read off the sockets. `f.params` holds only the
  # names a routine gave its arguments, with no types on them at all.
  for row in f.sockets:
    if row.direction == sdOutput:
      continue
    if typeName.len > 0 and typeName in row.typeName:
      result.incl(row.name)
  for line in f.bodyLines:
    t = line.strip()
    if not (t.startsWith("var ") or t.startsWith("let ") or
        t.startsWith("const ")):
      continue
    at = t.find(':')
    if at < 0 or typeName notin t[at + 1 .. ^1]:
      continue
    head = t[t.find(' ') + 1 ..< at].strip()
    if head.len > 0 and ' ' notin head:
      result.incl(head)
  # A routine that never names the type may still be handed settings
  # under one of the usual names.
  for row in configNames:
    for line in f.bodyLines:
      if (row & ".") in line.toLowerAscii():
        result.incl(row)

proc touchesIn*(line, field: string, R: HashSet[string]):
    tuple[read: bool, write: bool] {.role: parser,
    metaTags: {tagStats}.} =
  ## line <- one line of a routine   field <- a setting's name
  ## R <- the names in this routine that actually hold settings
  ##
  ## Whether that line looks at the setting, changes it, or neither:
  ##
  ##   cfg.useCache = true   -> written
  ##   if cfg.useCache:      -> read
  ##   var useCache = true   -> neither, this is somebody's own name
  ##   other.useCache        -> neither, `other` is not settings
  var
    at: int = 0
    after: int = 0
    tail: string = ""
    owner: string = ""
    start: int = 0
  result = (read: false, write: false)
  if field.len == 0 or R.len == 0:
    return
  at = 0
  while at >= 0 and at < line.len:
    at = line.find(field, at)
    if at < 0:
      return
    after = at + field.len
    # Must be reached through a dot, and must be the whole name.
    if at == 0 or line[at - 1] != '.':
      at = after
      continue
    if after < line.len and (line[after].isAlphaNumeric() or
        line[after] == '_'):
      at = after
      continue
    # Walk back over the name in front of the dot and check it.
    start = at - 1
    while start > 0 and (line[start - 1].isAlphaNumeric() or
        line[start - 1] == '_'):
      start = start - 1
    owner = line[start ..< at - 1]
    if owner notin R:
      at = after
      continue
    tail = line[after .. ^1].strip()
    if tail.startsWith("=") and not tail.startsWith("=="):
      result.write = true
    else:
      result.read = true
    at = after

proc builtIn*(line, typeName, field: string): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## line <- one line of a routine   typeName <- the settings type
  ## field <- a setting's name
  ##
  ## Whether this line sets the setting by building the whole object
  ## at once, rather than by assigning to it afterwards:
  ##
  ##   OtterUiConfig(repoRoot: dir, title: "Otter")
  ##                 ^^^^^^^^ set here, and never with an `=`
  ##
  ## Without this every setting in a repository that builds its
  ## settings in one go reads as "never set", which is both wrong and
  ## the exact opposite of the truth.
  var
    at: int = 0
    start: int = 0
    owner: string = ""
  result = false
  at = line.find(typeName & "(")
  if at < 0:
    return
  start = line.find(field & ":", at)
  if start < 0:
    return
  # The name must stand alone, not be the tail of a longer one.
  if start > 0 and (line[start - 1].isAlphaNumeric() or
      line[start - 1] == '_' or line[start - 1] == '.'):
    return
  result = true

proc addName*(A: var seq[string], name: string) {.role: actor,
    metaTags: {tagStats}.} =
  ## A <- a list of routine names   name <- one to add if it is new
  for row in A:
    if row == name:
      return
  A.add(name)

proc verdictOf*(f: ConfigField): string {.role: parser,
    metaTags: {tagStats}.} =
  ## f <- one setting, once everything touching it has been counted.
  result = "fine"
  if f.readCount == 0 and f.writeCount > 0:
    result = "does nothing"
  elif f.readCount == 0 and f.writeCount == 0:
    result = "untouched"
  elif f.writeCount == 0 and not f.hasDefault:
    result = "never set"
  elif f.writeCount >= 3:
    result = "contested"

proc mapTouches*(A: var seq[ConfigField], F: seq[FunctionInfo]): int
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## A <- every setting found   F <- every routine in the tree
  ## Returns how many routines touched at least one setting.
  var
    got: tuple[read: bool, write: bool]
    hit: bool = false
    seats: Table[string, HashSet[string]] = initTable[string,
      HashSet[string]]()
    i: int = 0
  result = 0
  for fn in F:
    hit = false
    i = 0
    seats.clear()
    while i < A.len:
      # Worked out once per routine per settings type, not once per
      # field, or a tree with thirty settings is walked thirty times.
      if not seats.hasKey(A[i].typeName):
        seats[A[i].typeName] = receiversIn(fn, A[i].typeName)
      for line in fn.bodyLines:
        # A settings name written inside a comment is somebody
        # explaining the settings, not somebody using them. This file
        # documents itself with an example of exactly what it looks
        # for, and without this guard it reports its own prose.
        if line.strip().startsWith("#"):
          continue
        got = touchesIn(line, A[i].name, seats[A[i].typeName])
        if builtIn(line, A[i].typeName, A[i].name):
          got.write = true
        if got.read:
          A[i].readCount = A[i].readCount + 1
          addName(A[i].readers, fn.name)
          hit = true
        if got.write:
          A[i].writeCount = A[i].writeCount + 1
          addName(A[i].writers, fn.name)
          hit = true
      i = i + 1
    if hit:
      result = result + 1
  i = 0
  while i < A.len:
    A[i].verdict = verdictOf(A[i])
    i = i + 1

proc refusedPairs*(A: seq[ConfigField], F: seq[FunctionInfo],
    root: string): seq[ConfigConflict] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## A <- every setting   F <- every routine   root <- the repository
  ##
  ## Finds the combinations the program itself refuses. A guard that
  ## names two settings and is followed by a refusal is taken at its
  ## word, because the authors wrote the rule down:
  ##
  ##   if cfg.quiet and cfg.verbose:      <- names two settings
  ##     raise newException(...)          <- and refuses
  var
    names: HashSet[string] = initHashSet[string]()
    inLine: seq[string] = @[]
    t: string = ""
    nextLine: string = ""
    rel: string = ""
    seen: HashSet[string] = initHashSet[string]()
    tag: string = ""
    i: int = 0
    j: int = 0
  result = @[]
  for row in A:
    names.incl(row.name)
  for fn in F:
    rel = fn.sourcePath
    if root.len > 0 and rel.startsWith(root):
      rel = rel[root.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    i = 0
    while i < fn.bodyLines.len:
      t = fn.bodyLines[i].strip()
      i = i + 1
      if not (t.startsWith("if ") or t.startsWith("elif ")):
        continue
      if " and " notin t and " or " notin t:
        continue
      inLine = @[]
      j = 0
      while j < t.len:
        if t[j] == '.':
          nextLine = identAt(t, j + 1)
          if nextLine in names:
            addName(inLine, nextLine)
        j = j + 1
      if inLine.len < 2:
        continue
      # The refusal is on the following line, indented under the guard.
      nextLine = ""
      if i < fn.bodyLines.len:
        nextLine = fn.bodyLines[i].strip().toLowerAscii()
      for word in refusalWords:
        if nextLine.startsWith(word) or (word & " ") in nextLine:
          tag = inLine[0] & "|" & inLine[1]
          if tag in seen:
            break
          seen.incl(tag)
          result.add(ConfigConflict(a: inLine[0], b: inLine[1],
            kind: "refused", detail: t, path: rel, line: fn.lineStart + i,
            certainty: 0.95))
          break

proc contestedPairs*(A: seq[ConfigField]): seq[ConfigConflict]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## A <- every setting, already counted.
  ##
  ## Two settings written by the same several routines are reported as
  ## contested: whichever routine runs last decides both, and that is
  ## an order dependency nobody wrote down on purpose.
  var
    shared: int = 0
    i: int = 0
    j: int = 0
  result = @[]
  while i < A.len:
    if A[i].writeCount < 2:
      i = i + 1
      continue
    j = i + 1
    while j < A.len:
      if A[j].writeCount >= 2:
        shared = 0
        for row in A[i].writers:
          if row in A[j].writers:
            shared = shared + 1
        if shared >= 2:
          result.add(ConfigConflict(a: A[i].name, b: A[j].name,
            kind: "contested",
            detail: "both are written by " & $shared &
              " of the same routines, so which value survives depends " &
              "on the order those routines run in",
            path: A[i].path, line: A[i].line,
            certainty: 0.4 + 0.1 * shared.float))
      j = j + 1
    i = i + 1

proc byTouches(a, b: ConfigField): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b <- two settings. Trouble first, then the busiest.
  var
    ra: int = 0
    rb: int = 0
  ra = 1
  rb = 1
  if a.verdict == "fine":
    ra = 0
  if b.verdict == "fine":
    rb = 0
  result = cmp(rb, ra)
  if result == 0:
    result = cmp(b.readCount + b.writeCount, a.readCount + a.writeCount)
  if result == 0:
    result = cmp(a.name, b.name)

proc trimNames*(A: var seq[ConfigField]) {.role: actor,
    metaTags: {tagStats}.} =
  ## A <- every setting. Cuts the lists of routine names down to what
  ## fits on a screen; the counts beside them stay whole.
  var
    i: int = 0
  while i < A.len:
    if A[i].readers.len > touchersShown:
      A[i].readers.setLen(touchersShown)
    if A[i].writers.len > touchersShown:
      A[i].writers.setLen(touchersShown)
    i = i + 1

proc configReportOf*(rootDir: string, files: seq[string],
    F: seq[FunctionInfo]): ConfigReport {.role: metaOrchestrator,
    metaTags: {tagStats}.} =
  ## rootDir <- the repository   files <- every source file
  ## F <- every routine already parsed out of the tree
  var
    found: tuple[types: seq[string], fields: seq[ConfigField]]
    rows: seq[ConfigField] = @[]
  result = ConfigReport(types: @[], fields: @[], conflicts: @[],
    fieldCount: 0, deadCount: 0, unsetCount: 0, contestedCount: 0,
    touchingFunctions: 0)
  found = scanConfigTypes(rootDir, files)
  result.types = found.types
  rows = found.fields
  if rows.len == 0:
    return
  result.touchingFunctions = mapTouches(rows, F)
  result.conflicts = refusedPairs(rows, F, rootDir)
  for row in contestedPairs(rows):
    result.conflicts.add(row)
  rows.sort(byTouches)
  result.fieldCount = rows.len
  for row in rows:
    if row.verdict == "does nothing" or row.verdict == "untouched":
      result.deadCount = result.deadCount + 1
    elif row.verdict == "never set":
      result.unsetCount = result.unsetCount + 1
    elif row.verdict == "contested":
      result.contestedCount = result.contestedCount + 1
  if rows.len > fieldsShown:
    rows.setLen(fieldsShown)
  trimNames(rows)
  result.fields = rows
