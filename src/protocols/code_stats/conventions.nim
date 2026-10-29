## ================================================================
## | conventions.nim  <-  the rules one file can prove on its own   |
## |---------------------------------------------------------------|
## | Everything here is decided by reading one file's text, or by   |
## | looking at which folders a repository has. Nothing here needs  |
## | the call graph.                                                |
## |                                                                |
## |   scanConventions(path, text)  ->  findings for one file       |
## |   scanLayout(dir)              ->  findings for one repository |
## |   conventionRules()            ->  every rule, named           |
## ================================================================
##
## Why these live in Otter and not in the tools that ask
## ----------------------------------------------------
## This module provides the library's file and layout checks. The
## `runStatistics` task and other library callers use these rules.
## `nim-check.sh` separately checks declarations and file placement with
## awk, so a small edit does not need a CLI build. The shell and library
## regression tests both cover strings, comments, and declaration boundaries.
## `otter-gate.sh` asks the parsed graph about structure and roles.
##
## What is deliberately NOT here
## -----------------------------
## Nesting depth and undeclared roles are not text questions. They are
## answered properly from the parsed tree, by `nesting.nim` and by the
## repository graph, and a second line-counting guess at either would
## be exactly the drift this module exists to end.
##
##   text rules      here        one file, no parsing
##   nesting         nesting.nim from the parsed blocks
##   roles           repo_graph  from each routine's own pragma

import std/[os, strutils]
import runePragmas

type
  ConventionSeverity* {.role: other, tag: "check".} = enum
    ## How loudly a finding asks to be dealt with.
    sevOk, sevInfo, sevWarn, sevFail

  ConventionFinding* {.role: preparedData, tag: "check".} = object
    ## One thing wrong, in one place.
    ##
    ##   checkId   which rule spoke, e.g. "letDeclCheck"
    ##   path      the file, or the repository for a layout rule
    ##   line      1-based; 0 when the finding is about the whole tree
    checkId*: string
    path*: string
    line*: int
    severity*: ConventionSeverity
    message*: string

  ConventionRule* {.role: preparedData, tag: "check".} = object
    ## One rule, named once, so no caller has to name it again.
    id*: string
    title*: string
    detail*: string
    hint*: string

  TextState = object
    ## Only multiline strings and block comments carry over to the next line.
    triple: bool
    commentDepth: int

const
  ironDir: string = "." & "iron"
    ## The folder `agents/` replaced. Assembled rather than written out,
    ## because this module is what reports a mention of it, and a rule
    ## that fails its own file teaches every reader to ignore it.
  skipColon: seq[string] = @[
    "of", "else", "elif", "except", "finally", "type", "var", "const",
    "let", "when", "if", "for", "while", "case", "block", "try", "using",
    "asm", "macro", "template", "proc", "func", "method", "defer", "cast",
    "setup", "teardown", "together", "otterInstrument"
  ]
    ## Words that legitimately end a line with a colon, so the colon-call
    ## rule must not mistake them for `name:` call syntax.
  plainNames: seq[string] = @[
    "dir", "args", "S", "S0", "S1", "S2", "t", "i", "j", "k", "l", "m", "n"
  ]
    ## Parameter names the naming rule always accepts.
  pragmaCopyPaths: seq[string] = @[
    "meta/metaPragmas.nim", "meta/runePragmas.nim",
    ironDir & "/meta/metaPragmas.nim", ironDir & "/meta/runePragmas.nim"
  ]
    ## Places a repository used to keep its own pragma copy, before the
    ## shared Rune-Pragmas repository replaced all of them.
  forbiddenNeedle: string = "aud" & "it"
    ## Assembled so the vocabulary check does not report its own definition.
  placeholderWords: seq[string] = @["place" & "holder", "not " & "implemented",
    "un" & "implemented", "for " & "now"]
    ## Marker text is data, not a routine returning a fixed answer.

proc conventionRules*(): seq[ConventionRule] {.role: truthBuilder,
    input: trusted, risk: rkLow, speed: spFast, tag: "check".} =
  ## Every rule this module can report, with the words a caller shows.
  result = @[
    ConventionRule(id: "letDeclCheck", title: "Let declarations",
      detail: "Flag let unless a branch-init comment marks the rare allowed case.",
      hint: "switch to var or const, or mark a true branch-init let"),
    ConventionRule(id: "blockDeclCheck", title: "Block declarations",
      detail: "Consecutive var/const/type lines must share one block.",
      hint: "join the names under one var/const/type block"),
    ConventionRule(id: "colonCallCheck", title: "Colon calls",
      detail: "Flag foo: call syntax. Use foo(a, b) or a.foo(b).",
      hint: "write name(args) or args.name"),
    ConventionRule(id: "namingCheck", title: "Naming",
      detail: "Parameters use a first letter, dir, args, or S. Arrays use a capital.",
      hint: "rename the parameter to a first letter, dir, args, or S"),
    ConventionRule(id: "fileHeaderCheck", title: "File headers",
      detail: "Every .nim file starts with a ## box that says what the file does.",
      hint: "put a ## box at the top of the file"),
    ConventionRule(id: "forbiddenWordCheck", title: "Forbidden words",
      detail: "Flag the guideline-blocked word that trips internal filters.",
      hint: "use evaluate / benchmark / harden / check / verify instead"),
    ConventionRule(id: "shimDetectCheck", title: "Shim detect",
      detail: "Flag leftover compat/legacy/deprecated shim names.",
      hint: "delete the old shim; breaking the API is fine"),
    ConventionRule(id: "placeholderCheck", title: "Placeholders",
      detail: "A routine that does not do the job yet must be named ph_.",
      hint: "rename it with a ph_ prefix, or finish it"),
    ConventionRule(id: "layoutCheck", title: "Layout check",
      detail: "Need agents/, evaluation/tests/, src/protocols/ next to each other.",
      hint: "create the missing folder from Proto-RepoTemplate"),
    ConventionRule(id: "agentsFolderCheck", title: "Agents folder",
      detail: "Need a live agents/ folder holding PROGRESS.md.",
      hint: "create agents/PROGRESS.md from Proto-RepoTemplate"),
    ConventionRule(id: "pragmaSourceCheck", title: "Pragma source",
      detail: "Pragmas come from the shared Rune-Pragmas repo, never a local copy.",
      hint: "delete the local copy and import runePragmas from Rune-Pragmas")
  ]

proc ruleHint*(id: string): string {.role: parser, input: trusted,
    risk: rkLow, speed: spFast, tag: "check".} =
  ## id: one rule id. The short how-to-fix line, or an empty string.
  var
    R: seq[ConventionRule] = conventionRules()
    i: int = 0
  result = ""
  while i < R.len:
    if R[i].id == id:
      result = R[i].hint
      return
    inc i

proc addFinding(R: var seq[ConventionFinding], id, path: string, line: int,
    sev: ConventionSeverity, msg: string) {.inline, role: helper,
    tag: "check".} =
  ## R: findings collected so far.
  R.add ConventionFinding(checkId: id, path: path, line: line,
    severity: sev, message: msg)

proc indentOf(s: string): int {.inline, role: helper, tag: "check".} =
  ## s: one raw line. How many spaces it starts with.
  var
    i: int = 0
  result = 0
  while i < s.len and s[i] == ' ':
    inc result
    inc i

proc quotedEnd(s: string, i: int): int {.role: parser.} =
  ## s: line; i: opening double quote. Stop after the matching quote.
  ## A name before the quote makes a Nim raw/generalized string literal.
  var
    n: int = i + 1
    raw: bool = i > 0 and s[i - 1] in {'a'..'z', 'A'..'Z', '_'}
  while n < s.len:
    if not raw and s[n] == '\\':
      n += 2
      continue
    if s[n] == '"':
      return n + 1
    inc n
  result = s.len

proc lineParts(S: var TextState, s: string): tuple[code, comment: string]
    {.role: parser.} =
  ## S: multiline state; s: one line. Mask literals before judging its code.
  ## Example programs in strings must not become findings about this module.
  var
    i: int = 0
  result = ("", "")
  while i < s.len:
    if S.commentDepth > 0:
      if s.continuesWith("#[", i): inc S.commentDepth
      if s.continuesWith("]#", i): dec S.commentDepth
      i += (if s.continuesWith("#[", i) or s.continuesWith("]#", i): 2 else: 1)
      continue
    if s.continuesWith("\"\"\"", i):
      S.triple = not S.triple
      result.code.add("\"\"")
      i += 3
      continue
    if S.triple:
      inc i
      continue
    if s.continuesWith("#[", i):
      S.commentDepth = 1
      i += 2
      continue
    if s[i] == '#':
      result.comment = s[i .. ^1]
      return
    if s[i] == '"':
      result.code.add("\"\"")
      i = quotedEnd(s, i)
      continue
    if s[i] == '\'' and i + 2 < s.len and s[i + 2] == '\'':
      result.code.add("''")
      i += 3
      continue
    result.code.add(s[i])
    inc i

proc isFnLine(s: string): bool {.inline, role: helper, tag: "check".} =
  ## s: stripped code. Whether the line opens a routine.
  result = s.startsWith("proc ") or s.startsWith("func ") or
    s.startsWith("method ")

proc routineName(s: string): string {.inline, role: parser, tag: "check".} =
  ## s: stripped code opening a routine. Its name without pragmas.
  var
    rest: string = ""
    cut: int = 0
  result = ""
  cut = s.find(' ')
  if cut < 0:
    return
  rest = s[cut + 1 .. ^1].strip()
  cut = 0
  while cut < rest.len and rest[cut] notin {'(', '*', ':', ' ', '['}:
    inc cut
  result = rest[0 ..< cut]

proc checkHeader(R: var seq[ConventionFinding], path, text: string)
    {.inline, role: actor, tag: "check".} =
  ## The first line that is not blank must open a `##` description box.
  var
    line: string = ""
    n: int = 0
  for raw in text.splitLines:
    inc n
    line = raw.strip()
    if line.len == 0:
      continue
    if not line.startsWith("##"):
      addFinding(R, "fileHeaderCheck", path, n, sevWarn,
        "file should start with a ## description box")
    return

proc checkForbidden(R: var seq[ConventionFinding], path, text: string)
    {.inline, role: actor, tag: "check".} =
  ## The one word the guidelines avoid, anywhere in the file.
  var
    n: int = 0
  for raw in text.splitLines:
    inc n
    if forbiddenNeedle in raw.toLowerAscii():
      addFinding(R, "forbiddenWordCheck", path, n, sevFail,
        "guideline-blocked word is present")

proc checkLet(R: var seq[ConventionFinding], path: string, n: int,
    stripped, raw: string) {.inline, role: actor, tag: "check".} =
  ## `let` is only for a routine whose branches would each have to
  ## initialise the same name. The escape is written as a comment, so it
  ## is looked for in the raw line rather than in the stripped code.
  if not stripped.startsWith("let ") and stripped != "let":
    return
  if "branch-init" in raw:
    return
  addFinding(R, "letDeclCheck", path, n, sevWarn,
    "let is reserved for heavy branch init; use var or const")

proc checkShim(R: var seq[ConventionFinding], path: string, n: int,
    stripped: string) {.inline, role: actor, tag: "check".} =
  ## A name that only exists to keep an old call working.
  if ("legacy" & "Shim") in stripped or ("back" & "Compat") in stripped or
      ("compat" & "Shim") in stripped:
    addFinding(R, "shimDetectCheck", path, n, sevWarn,
      "leftover compatibility shim name")

proc checkColon(R: var seq[ConventionFinding], path: string, n: int,
    stripped: string) {.inline, role: actor, tag: "check".} =
  ## `name:` on its own line is the call form the conventions refuse.
  var
    name: string = ""
    cut: int = 0
  if not stripped.endsWith(":") or stripped.endsWith("::"):
    return
  if stripped.endsWith("=:"):
    return
  if "{." in stripped:
    return
  cut = stripped.find(':')
  if cut <= 0 or cut != stripped.high:
    return
  name = stripped[0 ..< cut].strip()
  if " " in name or name in skipColon:
    return
  if name.len == 0:
    return
  if not name.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_', '.'}):
    return # A continued condition or parameter list is not a bare name: call.
  addFinding(R, "colonCallCheck", path, n, sevInfo,
    "avoid colon call syntax; use name(args)")

proc camelParam(s: string): bool {.inline, role: helper, tag: "check".} =
  ## s: a parameter name. Whether it carries an inner capital.
  var
    i: int = 1
  result = false
  while i < s.len:
    if s[i] in {'A'..'Z'}:
      result = true
      return
    inc i

proc checkNaming(R: var seq[ConventionFinding], path: string, n: int,
    stripped: string) {.inline, role: actor, tag: "check".} =
  ## Parameters are a first letter, one of the reserved plain names, or
  ## a capital for a list. A camelCase word is none of those.
  var
    inside: string = ""
    a: int = 0
    b: int = 0
    parts: seq[string] = @[]
    pname: string = ""
  if not isFnLine(stripped):
    return
  a = stripped.find('(')
  b = stripped.find(')')
  if a < 0 or b <= a:
    return
  inside = stripped[a + 1 ..< b]
  parts = inside.split(',')
  for item in parts:
    pname = item.strip()
    if pname.len == 0:
      continue
    pname = pname.split(':')[0].strip()
    if pname in plainNames:
      continue
    if pname.len == 1:
      continue
    if pname[0] in {'A'..'Z'}:
      continue
    if camelParam(pname):
      addFinding(R, "namingCheck", path, n, sevInfo,
        "parameter '" & pname & "' should use a first letter, dir, args, or S")

proc checkBlockDecl(R: var seq[ConventionFinding], path: string, n: int,
    prevKind, kind: string, sameIndent: bool)
    {.inline, role: actor, tag: "check".} =
  ## Two `var` lines at one indent are one `var` block written twice.
  if not sameIndent:
    return
  if kind.len == 0 or prevKind != kind:
    return
  if kind notin ["var", "const", "type"]:
    return
  addFinding(R, "blockDeclCheck", path, n, sevWarn,
    "repeat of `" & kind & "` at the same indent; use one block")

proc checkPlaceholder(R: var seq[ConventionFinding], path, fn: string,
    n: int, comment: string, done: var string) {.inline, role: actor,
    tag: "check".} =
  ## A body that says it is not finished, in a routine whose name does
  ## not admit it.
  ##
  ## The admission is nearly always written as a trailing comment on the
  ## line returning the fixed value, so only the comment is searched. A
  ## routine merely NAMED after this rule is then not caught by it, which
  ## the older copies of this rule got wrong. `done` carries the last
  ## routine already reported, so a routine saying it three times is
  ## still one finding.
  var
    low: string = comment.toLowerAscii()
    i: int = 0
  if fn.len == 0 or fn.startsWith("ph_") or fn == done or low.len == 0:
    return
  while i < placeholderWords.len:
    if placeholderWords[i] in low:
      addFinding(R, "placeholderCheck", path, n, sevWarn,
        "placeholder body in `" & fn & "` - rename to `ph_" & fn &
        "` or finish it")
      done = fn
      return
    inc i

proc declKindOf(s: string): string {.inline, role: parser, tag: "check".} =
  ## s: stripped code. Which declaration block the line opens, if any.
  result = ""
  if s == "var" or s.startsWith("var "):
    result = "var"
  elif s == "const" or s.startsWith("const "):
    result = "const"
  elif s == "type" or s.startsWith("type "):
    result = "type"

proc scanConventions*(path, text: string): seq[ConventionFinding]
    {.role: actor, input: thirdParty, risk: rkLow,
    speed: spDataDependent, tag: "check".} =
  ## path: what to call the file in a finding   text: the whole file.
  ##
  ## One pass down the lines. Every rule sees the same stripped line,
  ## so the file is read once however many rules are switched on.
  var
    raw: string = ""
    stripped: string = ""
    ind: int = 0
    prevKind: string = ""
    prevInd: int = -1
    kind: string = ""
    lines: seq[string] = text.splitLines
    fn: string = ""
    phDone: string = ""
    n: int = 0
    textState: TextState = TextState()
    parts: tuple[code, comment: string] = ("", "")
  result = @[]
  checkHeader(result, path, text)
  checkForbidden(result, path, text)
  while n < lines.len:
    raw = lines[n]
    parts = lineParts(textState, raw)
    stripped = parts.code.strip()
    ind = indentOf(raw)
    inc n
    if stripped.len == 0:
      continue
    if isFnLine(stripped):
      fn = routineName(stripped)
    kind = declKindOf(stripped)
    checkBlockDecl(result, path, n, prevKind, kind, ind == prevInd)
    checkLet(result, path, n, stripped, raw)
    checkShim(result, path, n, stripped)
    checkColon(result, path, n, stripped)
    checkNaming(result, path, n, stripped)
    checkPlaceholder(result, path, fn, n, parts.comment, phDone)
    prevKind = kind
    prevInd = ind

proc hasTests(dir: string): bool {.inline, role: parser, tag: "check".} =
  ## dir: repository root.
  ## Either the current `evaluation/tests` or a plain `tests/` counts, so
  ## a repository part-way through the move is not told off twice.
  result = dirExists(dir / "evaluation" / "tests") or dirExists(dir / "tests")

proc localPragmaCopy(dir: string): string {.inline, role: parser,
    tag: "check".} =
  ## dir: repository root.
  ## The first per-repository pragma copy found, or an empty string. Such
  ## a copy is what the shared Rune-Pragmas repository exists to remove:
  ## two copies land on the Nim path together, the last one read wins,
  ## and the losing repository fails on the first tag of its own.
  var
    i: int = 0
  result = ""
  while i < pragmaCopyPaths.len:
    if fileExists(dir / pragmaCopyPaths[i]):
      result = pragmaCopyPaths[i]
      return
    inc i

proc sharedPragmaPath(dir: string): bool {.inline, role: parser,
    tag: "check".} =
  ## dir: repository root.
  ## Whether `config.nims` puts the shared pragma module on the Nim path.
  var
    p: string = dir / "config.nims"
  result = false
  if not fileExists(p):
    return
  result = "Rune-Pragmas" in readFile(p)

proc scanLayout*(dir: string): seq[ConventionFinding] {.role: actor,
    input: trusted, risk: rkLow, speed: spFast, tag: "check".} =
  ## dir: repository root.
  ##
  ## The layout a repository is expected to have:
  ##
  ##   agents/PROGRESS.md      handoff state, and the commit message line
  ##   src/protocols/          the library, ordered by dependency level
  ##   evaluation/tests/       tests, benchmarks, statistics
  ##   (no meta/ of its own)   pragmas come from the shared Rune-Pragmas
  ##
  ## The folder `agents/` replaced is gone; a leftover copy is reported.
  var
    copyAt: string = ""
  result = @[]
  if not dirExists(dir / "src" / "protocols"):
    addFinding(result, "layoutCheck", dir, 0, sevFail,
      "missing src/protocols")
  if not hasTests(dir):
    addFinding(result, "layoutCheck", dir, 0, sevFail,
      "missing evaluation/tests")
  if not dirExists(dir / "agents"):
    addFinding(result, "agentsFolderCheck", dir, 0, sevFail, "missing agents/")
    addFinding(result, "layoutCheck", dir, 0, sevFail, "missing agents/")
  if not fileExists(dir / "agents" / "PROGRESS.md"):
    addFinding(result, "agentsFolderCheck", dir / "agents", 0, sevWarn,
      "missing agents/PROGRESS.md")
  if dirExists(dir / ironDir):
    addFinding(result, "agentsFolderCheck", dir / ironDir, 0, sevWarn,
      ironDir & "/ was removed - move its progress line into agents/PROGRESS.md")
  copyAt = localPragmaCopy(dir)
  if copyAt.len > 0:
    addFinding(result, "pragmaSourceCheck", dir / copyAt, 0, sevWarn,
      "per-repository pragma copy - import runePragmas from Rune-Pragmas")
  if not sharedPragmaPath(dir):
    addFinding(result, "pragmaSourceCheck", dir / "config.nims", 0, sevWarn,
      "config.nims does not put Rune-Pragmas/meta on the Nim path")
