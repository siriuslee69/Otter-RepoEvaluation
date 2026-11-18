## ================================================================
## | similar_chunks.nim  <-  cut a source file into routine-sized  |
## |                         pieces, without a real parser         |
## |---------------------------------------------------------------|
## | A parser per language would be a project of its own. This file |
## | does only what the likeness hint needs: find where a routine   |
## | starts, and where it ends.                                     |
## |                                                                |
## |   1. CLEAN   comments gone, every string turned into "s",      |
## |              so a brace inside a string cannot fool the count  |
## |   2. START   a line that begins a function, method, class,     |
## |              struct ... (js ts rs go c java: by keyword shape; |
## |              py: `def` / `class`)                              |
## |   3. END     brace languages: the brace that closes the first  |
## |              one opened. Python: the next line indented less.  |
## |   4. KEEP    classes that hold methods are dropped (their      |
## |              methods are compared instead); a routine inside   |
## |              another routine is dropped (the outer one wins)   |
## |                                                                |
## |   int add(int a, int b) {        <- START                      |
## |       if (a > b) { ... }         <- braces counted: 1, 2, 1    |
## |       return a + b;                                            |
## |   }                              <- END (back to 0)            |
## |                                                                |
## | A wrong cut gives a worse hint, never a crash: every loop has  |
## | a bound and an unclosed brace drops the piece.                 |
## ================================================================

import std/strutils
import runePragmas

type
  Family* = enum
    ## How a language marks the end of a block.
    fmNone, fmBrace, fmIndent

  Decl* = object
    ## One start-and-end found in a file. Line numbers are 0-based.
    first*: int
    last*: int
    name*: string
    isFunc*: bool

  ScanState* = object
    ## Where the scanner stands between two lines, and what the language
    ## allows. mode: 0 code, 1 inside /* */, 2 inside """ or ''',
    ## 3 inside a backtick string. py: `#` comments and triple quotes.
    ## sq: a single quote starts a string (py, js, ts); otherwise it starts
    ## a character like 'x' or is a lifetime like 'a.
    mode*: int
    quote*: string
    py*: bool
    sq*: bool

  Found = tuple[found: bool, name: string, isFunc: bool]

const
  braceExts: array[16, string] = ["js", "ts", "tsx", "jsx", "mjs", "cjs", "rs",
    "go", "c", "h", "cc", "cpp", "hpp", "java", "kt", "cs"]
  sqExts: array[7, string] = ["js", "ts", "tsx", "jsx", "mjs", "cjs", "py"]
  modifierWords: array[22, string] = ["export", "default", "async", "pub", "public",
    "private", "protected", "static", "final", "abstract", "override", "unsafe",
    "extern", "inline", "virtual", "get", "set", "readonly", "declare", "internal",
    "open", "sealed"]
  containerWords: array[6, string] = ["class", "struct", "impl", "trait", "enum",
    "interface"]
  notRoutine: array[24, string] = ["if", "for", "while", "switch", "catch", "return",
    "else", "with", "do", "try", "match", "new", "sizeof", "typeof", "await",
    "throw", "describe", "it", "test", "beforeEach", "afterEach", "beforeAll",
    "afterAll", "useEffect"]
  scanLimit: int = 3000
    ## No block is followed for more than this many lines.

proc familyOf*(ext: string): Family {.role: parser.} =
  ## ext: the file ending without its dot. Which block style it uses.
  result = fmNone
  if ext == "py":
    result = fmIndent
  elif ext in braceExts:
    result = fmBrace

proc newScanState*(ext: string): ScanState {.role: truthBuilder.} =
  ## ext: the file ending. A scanner at the start of a file.
  result = ScanState(mode: 0, quote: "", py: ext == "py", sq: ext in sqExts)

proc isWordChar(c: char): bool {.inline, role: helper.} =
  ## c: one character. Letters, digits, underscore and dollar.
  result = c in {'a'..'z', 'A'..'Z', '0'..'9', '_', '$'}

proc skipQuoted(s: string, at: int, q: char): int {.role: parser.} =
  ## s: the line   at: index of the opening quote   q: the quote.
  ## Index just past the closing quote on the same line, or -1.
  var
    i: int = at + 1
  result = -1
  while i < s.len and result < 0:
    if s[i] == '\\':
      i = i + 2
    elif s[i] == q:
      result = i + 1
    else:
      i = i + 1

proc charLiteralEnd(s: string, at: int): int {.role: parser.} =
  ## A single quote in Rust, C, Go or Java may start a character
  ## ('x', '\n', '{') or a lifetime ('a). A character closes within four
  ## letters; a lifetime does not.
  ## s: the line   at: index of the quote. Index past the closing quote, or -1.
  var
    stop: int = min(s.len - 1, at + 4)
    i: int = at + 1
  result = -1
  while i <= stop and result < 0:
    if s[i] == '\\':
      i = i + 2
    elif s[i] == '\'':
      result = i + 1
    else:
      i = i + 1

proc closeInside(s: string, at: int, S0: var ScanState): int {.role: parser.} =
  ## Look for the end of a block comment, a triple-quoted string or a
  ## backtick string that began earlier.
  ## s: the line   at: where to start   S0: the scanner state.
  ## Index past the end, or -1 when it goes on to the next line.
  var
    p: int = -1
    w: int = 1
  case S0.mode
  of 1:
    p = s.find("*/", at)
    w = 2
  of 2:
    p = s.find(S0.quote, at)
    w = S0.quote.len
  else:
    p = s.find('`', at)
  result = -1
  if p >= 0:
    S0.mode = 0
    result = p + w

proc lineCommentAt(s: string, at: int, S0: ScanState): bool {.role: parser.} =
  ## Does a comment that runs to the end of the line start at `at`?
  ## s: the line   at: index   S0: scanner state.
  if S0.py:
    result = s[at] == '#'
  else:
    result = s[at] == '/' and at + 1 < s.len and s[at + 1] == '/'

proc openSpecial(s: string, at: int, S0: var ScanState): int {.role: parser.} =
  ## The scanner is at `at` in plain code. If a comment, string or character
  ## starts there, returns the index after it (s.len when it runs on to the
  ## next line, with S0 set). Returns -1 when `at` is plain code.
  var
    c: char = s[at]
    e: int = -1
  result = -1
  if lineCommentAt(s, at, S0):
    result = s.len
  elif (not S0.py) and c == '/' and at + 1 < s.len and s[at + 1] == '*':
    S0.mode = 1
    e = closeInside(s, at + 2, S0)
    result = (if e < 0: s.len else: e)
  elif S0.py and (s.continuesWith("\"\"\"", at) or s.continuesWith("'''", at)):
    S0.mode = 2
    S0.quote = s[at .. at + 2]
    e = closeInside(s, at + 3, S0)
    result = (if e < 0: s.len else: e)
  elif c == '`':
    S0.mode = 3
    e = closeInside(s, at + 1, S0)
    result = (if e < 0: s.len else: e)
  elif c == '"' or (S0.sq and c == '\''):
    e = skipQuoted(s, at, c)
    result = (if e < 0: s.len else: e)
  elif c == '\'':
    result = charLiteralEnd(s, at)

proc isStringStart(c: char): bool {.inline, role: helper.} =
  ## c: the character a special piece began with.
  result = c in {'"', '\'', '`'}

proc cleanLine*(s: string, S0: var ScanState): string {.role: sanitizer.} =
  ## s: one source line   S0: scanner state kept between lines.
  ## The line with comments removed and every string or character turned
  ## into `"s"`, so only real code is left to count braces and tokens in.
  var
    i: int = 0
    e: int = 0
  result = ""
  if S0.mode != 0:
    e = closeInside(s, 0, S0)
    if e < 0:
      return ""
    i = e
  while i < s.len:
    e = openSpecial(s, i, S0)
    if e < 0:
      result.add(s[i])
      i = i + 1
    else:
      if isStringStart(s[i]):
        result.add("\"s\"")
      i = e

proc cleanLines*(L: seq[string], ext: string): seq[string] {.role: sanitizer.} =
  ## L: the file's lines   ext: the file ending. The cleaned lines, same count.
  var
    S0: ScanState = newScanState(ext)
  result = @[]
  for l in L:
    result.add(cleanLine(l, S0))

proc firstWords(t: string): seq[string] {.role: parser.} =
  ## t: a trimmed line. Its words with the modifiers (export, pub, async ...)
  ## taken off the front.
  var
    W: seq[string] = t.splitWhitespace()
    i: int = 0
  while i < W.len and (W[i] in modifierWords or W[i].startsWith("pub(")):
    i = i + 1
  result = W[i .. ^1]

proc nameAfter(t: string): string {.role: parser.} =
  ## t: text that starts with a name, maybe followed by `<`, `(` or `:`.
  var
    i: int = 0
  result = ""
  while i < t.len and (t[i] in {' ', '*', '&'}):
    i = i + 1
  while i < t.len and isWordChar(t[i]):
    result.add(t[i])
    i = i + 1

proc wordEnd(t, w: string): string {.role: parser.} =
  ## t: a line   w: a word in it. The text after the first `w`.
  var
    at: int = t.find(w)
  result = ""
  if at >= 0:
    result = t[at + w.len .. ^1]

proc routineBeforeParen(t: string): string {.role: parser.} =
  ## t: a trimmed line like `int add(int a) {` or `render(x) {`.
  ## The name before the first `(`, or "" when this is not a routine start.
  var
    at: int = t.find('(')
    j: int = 0
    w: string = ""
  result = ""
  if at > 0 and not (t.endsWith(";") or t.endsWith(",")):
    j = at
    while j > 0 and isWordChar(t[j - 1]):
      j = j - 1
    w = t[j ..< at]
    if w.len > 0 and w notin notRoutine and not t.startsWith("}"):
      result = w

proc braceDecl(t, nextLine: string): Found {.role: parser.} =
  ## t: a trimmed cleaned line   nextLine: the one after it.
  ## Does a routine or a type start here (js ts rs go c java)?
  var
    W: seq[string] = firstWords(t)
    n: string = ""
    rest: string = ""
  result = (found: false, name: "", isFunc: false)
  if W.len == 0:
    return
  rest = wordEnd(t, W[0])
  if W[0] in ["function", "fn", "func"]:
    n = nameAfter(rest)
    if n.len == 0 and rest.find(')') > 0:
      n = nameAfter(rest[rest.find(')') + 1 .. ^1])
    result = (found: true, name: n, isFunc: true)
  elif W[0] in containerWords or (W[0] == "type" and '{' in t):
    result = (found: true, name: nameAfter(rest), isFunc: false)
  elif W[0] in ["const", "let", "var"] and W.len > 2 and ("=>" in t or "function" in t):
    result = (found: true, name: nameAfter(rest), isFunc: true)
  else:
    n = routineBeforeParen(t)
    if n.len > 0 and (t.endsWith("{") or nextLine.strip() == "{"):
      result = (found: true, name: n, isFunc: true)

proc indentDecl(t: string): Found {.role: parser.} =
  ## t: a trimmed cleaned line. Does a Python def or class start here?
  var
    W: seq[string] = t.splitWhitespace()
    i: int = 0
  result = (found: false, name: "", isFunc: false)
  if W.len > 1 and W[0] == "async":
    i = 1
  if W.len > i + 1 and W[i] == "def":
    result = (found: true, name: nameAfter(W[i + 1]), isFunc: true)
  elif W.len > i + 1 and W[i] == "class":
    result = (found: true, name: nameAfter(W[i + 1]), isFunc: false)

proc braceDelta(l: string): tuple[delta: int, opens: bool] {.role: math.} =
  ## l: one cleaned line. Opening braces minus closing ones, and whether
  ## it holds an opening brace at all.
  result = (delta: 0, opens: false)
  for c in l:
    if c == '{':
      result.delta = result.delta + 1
      result.opens = true
    elif c == '}':
      result.delta = result.delta - 1

proc braceEnd(C: seq[string], s: int): int {.role: parser.} =
  ## C: cleaned lines   s: the start line. The line where the first block
  ## opened at or after `s` closes again, or -1.
  var
    depth: int = 0
    opened: bool = false
    done: bool = false
    i: int = s
    stop: int = min(C.len - 1, s + scanLimit)
    d: tuple[delta: int, opens: bool] = (delta: 0, opens: false)
  result = -1
  while i <= stop and not done:
    d = braceDelta(C[i])
    depth = depth + d.delta
    opened = opened or d.opens
    if opened and depth <= 0:
      result = i
      done = true
    if (not opened) and i >= s + 2:
      done = true
    i = i + 1

proc indentOf(l: string): int {.inline, role: parser.} =
  ## l: a line. Leading blanks counted, a tab as four.
  var
    i: int = 0
  result = 0
  while i < l.len and l[i] in {' ', '\t'}:
    result = result + (if l[i] == '\t': 4 else: 1)
    i = i + 1

proc indentEnd(C: seq[string], s: int): int {.role: parser.} =
  ## C: cleaned lines   s: the line of `def` or `class`.
  ## The last line before the first later line that is indented no more.
  var
    base: int = indentOf(C[s])
    i: int = s + 1
    last: int = s
    blank: bool = false
    stop: bool = false
  while i < C.len and i <= s + scanLimit and not stop:
    blank = C[i].strip().len == 0
    stop = (not blank) and indentOf(C[i]) <= base
    if (not blank) and not stop:
      last = i
    i = i + 1
  result = last

proc lineCount(C: seq[string], a, b: int): int {.role: math.} =
  ## C: cleaned lines   a, b: first and last (0-based). How many hold code.
  result = 0
  for i in a .. b:
    if C[i].strip().len > 0:
      result = result + 1

proc declsOf*(C: seq[string], ext: string): seq[Decl] {.role: truthBuilder.} =
  ## C: cleaned lines of one file   ext: its ending.
  ## Every start-and-end found, containers and nested ones included.
  var
    fam: Family = familyOf(ext)
    t: string = ""
    d: Found = (found: false, name: "", isFunc: false)
    e: int = -1
    i: int = 0
  result = @[]
  while i < C.len:
    t = C[i].strip()
    d = (found: false, name: "", isFunc: false)
    e = -1
    if t.len > 0 and fam == fmBrace:
      d = braceDecl(t, (if i + 1 < C.len: C[i + 1] else: ""))
    elif t.len > 0 and fam == fmIndent:
      d = indentDecl(t)
    if d.found:
      e = (if fam == fmBrace: braceEnd(C, i) else: indentEnd(C, i))
    if d.found and e >= i:
      result.add(Decl(first: i, last: e, name: d.name, isFunc: d.isFunc))
    i = i + 1

proc holdsRoutine(D: seq[Decl], c: Decl): bool {.role: helper.} =
  ## D: all found pieces   c: one container.
  ## True when a routine sits inside it.
  result = false
  for f in D:
    if f.isFunc and f.first > c.first and f.last <= c.last:
      return true

proc keepOutermost*(D: seq[Decl]): seq[Decl] {.role: truthBuilder.} =
  ## D: all pieces found in one file, in order of start.
  ## Containers that hold routines are dropped (the routines are compared
  ## instead); a piece that lies inside a kept one is dropped (the outer one
  ## wins).
  var
    K: seq[Decl] = @[]
    reach: int = -1
  result = @[]
  for d in D:
    if d.isFunc or not holdsRoutine(D, d):
      K.add(d)
  for d in K:
    if d.first > reach:
      result.add(d)
      reach = d.last

proc chunkRanges*(L: seq[string], ext: string, minLines, maxLines: int):
    tuple[ranges: seq[Decl], clean: seq[string]] {.role: truthBuilder.} =
  ## L: the file's lines   ext: its ending   minLines, maxLines: size bounds.
  ## The pieces worth comparing, and the cleaned lines they index into.
  var
    C: seq[string] = cleanLines(L, ext)
    n: int = 0
  result = (ranges: @[], clean: C)
  for d in keepOutermost(declsOf(C, ext)):
    n = lineCount(C, d.first, d.last)
    if n >= minLines and n <= maxLines:
      result.ranges.add(d)
