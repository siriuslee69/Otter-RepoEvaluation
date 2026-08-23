# ============================================================
# | Otter Code Statistics Test Scan                          |
# | -> What each test is for, and what it touches            |
# ============================================================
#
# A test is either a `test "..."` block or a routine carrying a
# testKind pragma. Both are read the same way afterwards: a name, a
# kind, and the routines its body calls.
#
#   test "empty input is refused":        <- kind read from the words
#   proc wideRange() {.testKind: tkEdgeCase.}   <- kind declared
#
# A declared kind always wins. When there is none the wording decides,
# and the window is told how many kinds were declared rather than
# guessed, so nobody mistakes a guess for a promise.

import std/[strutils]

import ./types
import ../repo_graph/io_utils
import ../repo_graph/types as graphTypes
import ../../../.iron/metaPragmas

const
  kindNames*: array[10, string] = ["unit", "edge case", "benchmark",
    "regression", "bugfix", "integration", "fuzz", "smoke", "property",
    "other"]
  edgeWords*: array[8, string] = ["edge", "empty", "boundary", "overflow",
    "zero-length", "out of range", "malformed", "truncated"]
  benchWords*: array[5, string] = ["benchmark", "bench ", "throughput",
    "how fast", "speed of"]
  regressWords*: array[3, string] = ["regression", "must not come back",
    "stays fixed"]
  bugWords*: array[3, string] = ["bugfix", "bug #", "issue #"]

proc isTestPath*(path: string): bool {.role: parser, metaTags: {tagStats}.} =
  ## path: one source path. Tests live under a tests folder or are
  ## named for what they are.
  ##
  ## Only the file's own name and the folders right above it are read.
  ## A tree that happens to sit in a folder called `my_test_repo` is
  ## not a tree of tests, and looking for the word anywhere in the path
  ## would say that it is.
  var
    parts: seq[string] = normalizeSlashes(path).toLowerAscii().split('/')
    i: int = 0
  result = false
  if parts.len == 0:
    return
  if parts[^1].startsWith("test_") or parts[^1].endsWith("_test.nim"):
    result = true
    return
  i = max(0, parts.len - 4)
  while i < parts.len - 1:
    if parts[i] == "tests" or parts[i] == "test":
      result = true
      return
    i = i + 1


proc quotedName*(line: string): string {.role: parser,
    metaTags: {tagStats}.} =
  ## line: a `test "..."` or `suite "..."` line. Empty when the line
  ## carries no quoted name at all.
  var
    a: int = line.find('"')
    b: int = 0
  result = ""
  if a < 0:
    return
  b = line.find('"', a + 1)
  if b <= a:
    return
  result = line[a + 1 ..< b]


proc leadWord(line: string): string {.role: parser, metaTags: {tagStats}.} =
  ## line: one source line, reduced to its first bare word.
  var
    t: string = line.strip()
    i: int = 0
  result = ""
  while i < t.len and (t[i] in {'a' .. 'z'} or t[i] in {'A' .. 'Z'}):
    i = i + 1
  result = t[0 ..< i]


proc indentWidth(line: string): int {.role: parser, metaTags: {tagStats}.} =
  ## line: one source line.
  result = 0
  while result < line.len and (line[result] == ' ' or line[result] == '\t'):
    result = result + 1


proc hasAny(text: string, A: openArray[string]): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## text: lowered wording. A: the words that decide one kind.
  result = false
  for row in A:
    if row in text:
      result = true
      return


proc kindFromWords*(name, suiteName: string): string {.role: parser,
    metaTags: {tagStats}.} =
  ## name: the test's own sentence. suiteName: the group it sits in.
  ## Only used when no testKind pragma said what the test is.
  var
    t: string = (name & " " & suiteName).toLowerAscii()
  result = kindNames[0]
  if hasAny(t, bugWords):
    result = kindNames[4]
  elif hasAny(t, regressWords):
    result = kindNames[3]
  elif hasAny(t, benchWords):
    result = kindNames[2]
  elif hasAny(t, edgeWords):
    result = kindNames[1]
  elif "fuzz" in t or "random" in t:
    result = kindNames[6]
  elif "smoke" in t or "starts at all" in t:
    result = kindNames[7]
  elif "property" in t or "invariant" in t or "for every" in t:
    result = kindNames[8]
  elif "integration" in t or "end to end" in t or "together" in t:
    result = kindNames[5]


proc kindFromPragma*(tag: string): string {.role: parser,
    metaTags: {tagStats}.} =
  ## tag: one pragma tag such as `testkind:tkedgecase`. Empty when the
  ## tag is about something else.
  var
    t: string = tag.toLowerAscii()
    v: string = ""
  result = ""
  if not t.startsWith("testkind:"):
    return
  v = t["testkind:".len .. ^1].strip(chars = {'{', '}', ' ', '.'})
  case v
  of "tkedgecase":
    result = kindNames[1]
  of "tkbenchmark":
    result = kindNames[2]
  of "tkregression":
    result = kindNames[3]
  of "tkbugfix":
    result = kindNames[4]
  of "tkintegration":
    result = kindNames[5]
  of "tkfuzz":
    result = kindNames[6]
  of "tksmoke":
    result = kindNames[7]
  of "tkproperty":
    result = kindNames[8]
  of "tkunit":
    result = kindNames[0]
  else:
    result = kindNames[9]


proc coveredNames*(tag: string): seq[string] {.role: parser,
    metaTags: {tagStats}.} =
  ## tag: one pragma tag such as `covers:@["parse", "check"]`.
  var
    t: string = ""
  result = @[]
  if not tag.toLowerAscii().startsWith("covers:"):
    return
  t = tag["covers:".len .. ^1].strip(chars = {'@', '[', ']', ' '})
  for row in t.split(','):
    if row.strip(chars = {'"', '\'', ' '}).len > 0:
      result.add(row.strip(chars = {'"', '\'', ' '}))


proc identAt(line: string, i: int): int {.role: parser,
    metaTags: {tagStats}.} =
  ## line: one source line. i: where an identifier may start.
  ## Answers the index just past it, or i when there is none.
  result = i
  while result < line.len and (line[result] in {'a' .. 'z'} or
      line[result] in {'A' .. 'Z'} or line[result] in {'0' .. '9'} or
      line[result] == '_'):
    result = result + 1


proc callNames*(A: seq[string]): seq[string] {.role: parser,
    metaTags: {tagStats}.} =
  ## A: the lines of one test body. Every name written with a bracket
  ## after it, which is what a call looks like whether it was reached
  ## as `f(x)` or as `x.f(y)`.
  var
    i: int = 0
    j: int = 0
    name: string = ""
  result = @[]
  for raw in A:
    if raw.strip().startsWith("#"):
      continue
    i = 0
    while i < raw.len:
      j = identAt(raw, i)
      if j == i:
        i = i + 1
        continue
      name = raw[i ..< j]
      if j < raw.len and raw[j] == '(' and name notin result:
        result.add(name)
      i = j


proc blockBody*(A: seq[string], start, indent: int): seq[string]
    {.role: parser, metaTags: {tagStats}.} =
  ## A: every line of the file. start: the line after the test's own.
  ## indent: the test line's indent, so the body is what sits deeper.
  var
    i: int = start
  result = @[]
  while i < A.len:
    if A[i].strip().len == 0:
      result.add(A[i])
      i = i + 1
      continue
    if indentWidth(A[i]) <= indent:
      return
    result.add(A[i])
    i = i + 1


proc markedKind*(A: seq[string], at: int): string {.role: parser,
    metaTags: {tagStats}.} =
  ## A: every line of the file. at: the `test "..."` line's index.
  ##
  ## A `test` block is a call to a template, so no pragma can be hung
  ## on it. The kind is written on the line above instead, in the same
  ## words a pragma would use:
  ##
  ##     # {.testKind: tkEdgeCase.}
  ##     test "an empty list is refused":
  ##
  ## Empty when nothing declared a kind, and the wording decides.
  var
    i: int = at - 1
    t: string = ""
  result = ""
  while i >= 0 and at - i <= 3:
    t = A[i].strip()
    if t.len == 0:
      i = i - 1
      continue
    if not t.startsWith("#"):
      return
    t = t.strip(chars = {'#', ' ', '{', '}', '.'})
    if t.toLowerAscii().startsWith("testkind:"):
      result = kindFromPragma(t)
      return
    i = i - 1


proc scanTestFile*(path: string): seq[TestInfo] {.role: parser,
    metaTags: {tagStats, tagTesting}.} =
  ## path: one test file. Reads its `suite` and `test` blocks; routines
  ## carrying a testKind pragma are added by the caller, which already
  ## has them parsed.
  var
    lines: seq[string] = @[]
    suiteName: string = ""
    name: string = ""
    kind: string = ""
    body: seq[string] = @[]
    i: int = 0
  result = @[]
  lines = readLinesSafe(path)
  while i < lines.len:
    case leadWord(lines[i])
    of "suite":
      suiteName = quotedName(lines[i])
    of "test":
      name = quotedName(lines[i])
      kind = markedKind(lines, i)
      if name.len > 0:
        body = blockBody(lines, i + 1, indentWidth(lines[i]))
        result.add(TestInfo(id: path & ":" & $(i + 1), name: name,
          path: normalizeSlashes(path), suite: suiteName, line: i + 1,
          kind: (if kind.len > 0: kind else: kindFromWords(name, suiteName)),
          declared: kind.len > 0, calls: callNames(body), reaches: 0))
    else:
      discard
    i = i + 1


proc pragmaTest*(f: FunctionInfo): TestInfo {.role: truthBuilder,
    metaTags: {tagStats, tagTesting}.} =
  ## f: one routine. An empty `kind` means it carries no testKind
  ## pragma and so is not a test at all.
  var
    kind: string = ""
    covers: seq[string] = @[]
  result = TestInfo(id: "", name: f.name, path: f.sourcePath, suite: "",
    line: f.lineStart, kind: "", declared: true, calls: @[], reaches: 0)
  for tagRow in f.pragmaTags:
    if kindFromPragma(tagRow).len > 0:
      kind = kindFromPragma(tagRow)
    for row in coveredNames(tagRow):
      covers.add(row)
  if kind.len == 0:
    return
  result.id = f.sourcePath & ":" & $f.lineStart
  result.kind = kind
  result.calls = callNames(f.bodyLines)
  for row in covers:
    if row notin result.calls:
      result.calls.add(row)
