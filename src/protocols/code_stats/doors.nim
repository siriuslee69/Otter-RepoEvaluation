## ==============================================================
## | doors.nim  <-  five rules about what a stranger's bytes may do |
## |--------------------------------------------------------------|
## | Nebel's docs/attack_classes.md sorts 108 attacks into eight  |
## | habits. Five of them can be read off the SOURCE, so they are |
## | findings here and cannot rot into a comment:                 |
## |                                                              |
## |   OUTSIDE NUMBER  class 1  a number read from bytes sizes    |
## |                            memory, a loop or a wait with no  |
## |                            limit first                       |
## |   OPEN DOOR       class 2  a table that strangers reach is   |
## |                            changed by a routine that takes no |
## |                            `Admitted`; or `admit` is called  |
## |                            outside a routine tagged `door`   |
## |   RE-READ         class 3  a text is checked, then the       |
## |                            ORIGINAL is used; or read by two  |
## |                            different parsers                 |
## |   SECRET BRANCH   class 4  a secret is compared with ==, or  |
## |                            looped over with an early exit    |
## |   NO DEADLINE     class 6  recv, accept, connect or          |
## |                            waitForExit with no time limit    |
## |                                                              |
## | A site that is right for a reason carries, on its line or    |
## | the line above:   # otter: door <word> <the reason>          |
## | with <word> one of number open reread secret deadline. The   |
## | reason is required; the report counts them.                  |
## |                                                              |
## | Heuristic, line by line, no types: it follows a number from  |
## | the call that read it through plain assignments to the call  |
## | that spends it. What it names is a place to look, with the   |
## | line and the reason in words. Run: otter-repo-graph doors .  |
## ==============================================================

import std/[json, os, sets, strutils, tables]

import ../repo_graph/types as graphTypes
import ../repo_graph/io_utils
import ./doors_text
import ./nesting
import runePragmas

type
  DoorKind* = enum
    dkNumber, dkOpenDoor, dkReread, dkSecret, dkDeadline

  DoorFinding* {.role: truthState.} = object
    ## kind: which rule. path/line: where. routine: in which routine. detail: the
    ## reason, in words a person can check.
    kind*: DoorKind
    path*: string
    line*: int
    routine*: string
    detail*: string

  DoorReport* {.role: truthState.} = object
    ## findings: what to look at. allowed: sites silenced by a written reason.
    ## dooredTypes: the types that carry `tag: "doored"`. routines: how many
    ## were read.
    findings*: seq[DoorFinding]
    allowed*: int
    dooredTypes*: seq[string]
    routines*: int

  View = object
    ## One routine as the checks see it: its code lines (comment and string
    ## contents removed) and the number of its first body line.
    f: FunctionInfo
    path: string
    code: seq[string]
    base: int

const
  doorWords*: array[5, string] = ["number", "open", "reread", "secret",
    "deadline"]
    ## The word that follows `# otter: door` for each kind, in kind order.
  sinkCalls: array[9, string] = ["newSeq", "newSeqOfCap", "newSeqUninit",
    "newString", "setLen", "alloc", "allocShared", "alloc0", "repeat"]
  waitCalls: array[7, string] = ["recv", "recvFrom", "recvLine", "accept",
    "acceptAddr", "connect", "waitForExit"]
  refuseWords: array[5, string] = ["return", "raise", "continue", "break",
    "quit"]
  exactSecrets: array[16, string] = ["secret", "psk", "mac", "token",
    "cookie", "password", "pwd", "seed", "sk", "expectedmac", "expectedtag",
    "sharedsecret", "privatekey", "secretkey", "mackey", "authkey"]
  suffixSecrets: array[6, string] = ["secret", "psk", "password", "authtag",
    "cookie", "mactag"]
  textTypes: array[9, string] = ["string", "cstring", "openArray[byte]",
    "openArray[char]", "seq[byte]", "seq[char]", "ByteSeq", "openArray[uint8]",
    "seq[uint8]"]
  checkPrefixes: array[7, string] = ["is", "valid", "check", "ok", "allowed",
    "safe", "looksLike"]
  quietCalls: array[16, string] = ["len", "high", "low", "echo", "debugEcho",
    "newException", "fmt", "format", "repr", "raise", "error", "fail", "err",
    "refuse", "deny", "log"]

proc kindHeading*(k: DoorKind): string {.role: helper.} =
  ## k: a kind. Its heading in the report.
  case k
  of dkNumber: result = "OUTSIDE NUMBER"
  of dkOpenDoor: result = "OPEN DOOR"
  of dkReread: result = "RE-READ"
  of dkSecret: result = "SECRET BRANCH"
  of dkDeadline: result = "NO DEADLINE"

proc kindRule*(k: DoorKind): string {.role: helper.} =
  ## k: a kind. The rule it enforces, one sentence.
  case k
  of dkNumber:
    result = "  Rule (class 1): a number read from outside sizes nothing until it has passed `bounded` or a refusing comparison against a NAMED limit."
  of dkOpenDoor:
    result = "  Rule (class 2): a table or session a stranger can reach changes only through a routine that takes an `Admitted`; `admit` is called only by a routine tagged `door`."
  of dkReread:
    result = "  Rule (class 3): parse a text ONCE into a typed value; check and use that value, never the original text a second time."
  of dkSecret:
    result = "  Rule (class 4): a secret is compared with constantTimeEqual and never decides an early exit."
  of dkDeadline:
    result = "  Rule (class 6): every wait has a deadline; every receive, accept, connect and wait for a program names a timeout."

proc viewOf(f: FunctionInfo, dir: string): View {.role: parser.} =
  ## f: a routine. dir: the repository root.
  var
    i: int = 0
  result.f = f
  result.path = normalizeSlashes(relativePath(f.sourcePath, dir))
  result.base = f.lineEnd - f.bodyLines.len + 1
  result.code = @[]
  while i < f.bodyLines.len:
    result.code.add(lineCode(f.bodyLines[i]))
    i = i + 1

proc allowedAt(v: View, i: int, k: DoorKind): bool {.role: parser.} =
  ## v/i/k: body line i of a routine, and a kind. True when that line or the
  ## one above says `# otter: door <word> <reason>` with a reason.
  var
    j: int = i
    marker: string = ""
    at: int = 0
    rest: string = ""
  result = false
  while j >= 0 and j >= i - 1:
    marker = "otter: door " & doorWords[ord(k)]
    at = v.f.bodyLines[j].find(marker)
    if at >= 0:
      rest = v.f.bodyLines[j][at + marker.len .. ^1].strip()
      if rest.len >= 3:
        return true
    j = j - 1

proc note(R: var DoorReport, v: View, k: DoorKind, i: int, detail: string)
    {.role: actor.} =
  ## R: the report. v/i: the routine and body line. k/detail: what was found.
  ## A site with a written reason counts as allowed and is not listed.
  if allowedAt(v, i, k):
    R.allowed = R.allowed + 1
    return
  R.findings.add(DoorFinding(kind: k, path: v.path, line: v.base + i,
    routine: v.f.name, detail: detail))

# --- assignments and taint (OUTSIDE NUMBER) --------------------------------

type
  Assign = tuple[ok: bool, lhs, rhs: string]

proc splitAssign(code: string): Assign {.role: parser.} =
  ## code: one line. The name on the left and the text on the right of the
  ## first plain `=`, when the left is one simple name.
  var
    i: int = 0
    depth: int = 0
    prev: char = ' '
    next: char = ' '
    lhs: string = ""
    colon: int = 0
  result = (false, "", "")
  while i < code.len:
    if code[i] in {'(', '[', '{'}:
      depth = depth + 1
    elif code[i] in {')', ']', '}'}:
      depth = depth - 1
    elif code[i] == '=' and depth == 0:
      prev = if i > 0: code[i - 1] else: ' '
      next = if i + 1 < code.len: code[i + 1] else: ' '
      if next == '=' or next == '>':
        i = i + 2
        continue
      if prev in {'<', '>', '!', '+', '-', '*', '/', '&', '|', '^', '%', '~',
          '.', '@', '$', '?', '='}:
        i = i + 1
        continue
      lhs = code[0 ..< i].strip()
      for w in ["var ", "let ", "const "]:
        if lhs.startsWith(w):
          lhs = lhs[w.len .. ^1].strip()
      colon = lhs.find(':')
      if colon > 0:
        lhs = lhs[0 ..< colon].strip()
      if lhs.len == 0 or not isIdentStart(lhs[0]):
        return
      for c in lhs:
        if not isIdentChar(c) and c != '*':
          return
      result = (true, lhs.strip(chars = {'*'}), code[i + 1 .. ^1].strip())
      return
    i = i + 1

proc isNumberReader(name: string): bool {.role: parser.} =
  ## name: a routine name. True when it reads a number out of bytes or text.
  var
    n: string = name.toLowerAscii()
  result = false
  if n in ["parseint", "parseuint", "parsebiggestint", "parsebiggestuint",
      "parsehexint"]:
    return true
  for p in ["read", "decode", "parse", "extract", "load"]:
    if n.startsWith(p):
      for w in ["u8", "u16", "u32", "u64", "int", "varint", "len", "count",
          "size", "length"]:
        if w in n:
          return true
  for w in ["le16", "le32", "le64", "be16", "be32", "be64", "fromle",
      "fromb"]:
    if w in n:
      return true

proc readerIn(rhs: string): string {.role: parser.} =
  ## rhs: the right side of an assignment. The number reader it calls, or "".
  result = ""
  for c in callsOf(rhs):
    if isNumberReader(c.name):
      return c.name

proc isCleanRhs(rhs: string): bool {.role: parser.} =
  ## rhs: the right side of an assignment. True when it passes the number
  ## through a check: `bounded`, `toInt` of a Bounded, `min`, `clamp`.
  result = false
  for w in ["bounded", "toInt", "min", "clamp"]:
    if hasIdent(rhs, w):
      return true

proc firstTainted(s: string, T: Table[string, string],
    G: HashSet[string]): string {.role: parser.} =
  ## s: text. T: numbers from outside, with where they came from. G: those that
  ## were checked. The first unchecked outside number named in `s`, or "".
  result = ""
  for w in identsOf(s):
    if w in T and w notin G:
      return w

proc anyTainted(s: string, T: Table[string, string]): string {.role: parser.} =
  ## s/T: as above; checked or not. The first outside number named, or "".
  result = ""
  for w in identsOf(s):
    if w in T:
      return w

proc refusesBelow(v: View, i: int): bool {.role: parser.} =
  ## v/i: an `if` on body line i. True when it refuses (return, raise, ...) on
  ## the same line or within the next three lines that sit deeper.
  var
    ind: int = indentOf(v.code[i])
    j: int = i
    colon: int = v.code[i].rfind(':')
  result = false
  if colon >= 0:
    for w in refuseWords:
      if hasIdent(v.code[i][colon .. ^1], w):
        return true
  while j + 1 < v.code.len and j < i + 3:
    j = j + 1
    if v.code[j].strip().len == 0:
      continue
    if indentOf(v.code[j]) <= ind:
      return
    for w in refuseWords:
      if hasIdent(v.code[j], w):
        return true

proc noteGuard(v: View, i: int, T: Table[string, string],
    G: var HashSet[string]) {.role: actor.} =
  ## v/i/T/G: an `if` that compares an outside number and then refuses or
  ## resets it makes that number checked from here on.
  var
    c: string = v.code[i].strip()
  if not (c.startsWith("if ") or c.startsWith("elif ")):
    return
  if '<' notin c and '>' notin c:
    return
  if not refusesBelow(v, i) and " = " notin c:
    return
  for w in identsOf(c):
    if w in T:
      G.incl(w)

proc noteAssign(v: View, i: int, T: var Table[string, string],
    G: var HashSet[string]) {.role: actor.} =
  ## v/i/T/G: follow an outside number along an assignment.
  var
    a: Assign = splitAssign(v.code[i])
    src: string = ""
    via: string = ""
  if not a.ok:
    return
  if isCleanRhs(a.rhs):
    T.del(a.lhs)
    G.excl(a.lhs)
    return
  src = readerIn(a.rhs)
  if src.len > 0:
    T[a.lhs] = src & " at line " & $(v.base + i)
    G.excl(a.lhs)
    return
  via = anyTainted(a.rhs, T)
  if via.len == 0:
    T.del(a.lhs)
    return
  T[a.lhs] = T[via]
  if via in G:
    G.incl(a.lhs)
  else:
    G.excl(a.lhs)

proc sinkNamed(code: string): seq[Call] {.role: parser.} =
  ## code: one line. The calls on it that spend a number: they size memory or
  ## set a wait; plus the head of a loop, whose text is the bound.
  var
    w: string = firstWord(code)
  result = @[]
  for c in callsOf(code):
    if c.name in sinkCalls or c.name in ["sleep", "sleepAsync"]:
      result.add(c)
  if w == "while":
    result.add(Call(name: "while", args: code.strip()))
  elif w == "for" and " in " in code:
    result.add(Call(name: "for", args: code[code.find(" in ") + 4 .. ^1]))

proc checkNumbers(v: View, R: var DoorReport) {.role: actor.} =
  ## v/R: follow every number a reader returned to the call that spends it.
  var
    T: Table[string, string] = initTable[string, string]()
    G: HashSet[string] = initHashSet[string]()
    i: int = 0
    hit: string = ""
  while i < v.code.len:
    for c in sinkNamed(v.code[i]):
      hit = firstTainted(c.args, T, G)
      if hit.len > 0:
        note(R, v, dkNumber, i, "`" & hit & "` (read by " & T[hit] &
          ") reaches " & c.name & " with no limit before it")
        G.incl(hit)
    noteGuard(v, i, T, G)
    noteAssign(v, i, T, G)
    i = i + 1

# --- doors (OPEN DOOR) -----------------------------------------------------

proc typeHead(t: string): string {.role: parser.} =
  ## t: a type as written. Its name without generics: `Table[a, b]` -> Table.
  var
    i: int = 0
  while i < t.len and isIdentChar(t[i]):
    i = i + 1
  result = t[0 ..< i]

proc checkOpenDoor(v: View, doored, admitFiles: HashSet[string],
    R: var DoorReport) {.role: actor.} =
  ## v/doored/R: a `var` parameter of a doored type needs an `Admitted`
  ## beside it. admitFiles: the files that import the intake `admit`; only
  ## there is a call of `admit` the one that is meant, and only a routine tagged
  ## `door` may make it.
  var
    isDoor: bool = "door" in v.f.pragmaTags or v.path notin admitFiles
    hasAdmitted: bool = false
    i: int = 0
  for s in v.f.sockets:
    if typeHead(s.typeName) == "Admitted":
      hasAdmitted = true
  if "door" notin v.f.pragmaTags and not hasAdmitted:
    for s in v.f.sockets:
      if s.direction == sdVarInput and typeHead(s.typeName) in doored:
        note(R, v, dkOpenDoor, 0, "takes `var " & s.typeName &
          "` (a doored type) and no `Admitted`: a stranger can reach it before any proof")
  while not isDoor and i < v.code.len:
    for c in callsOf(v.code[i]):
      if c.name == "admit":
        note(R, v, dkOpenDoor, i, "calls admit() but is not tagged `door`: only the routine that checks the proof may say it passed")
    i = i + 1

# --- re-read (RE-READ) -----------------------------------------------------

proc argList(args: string): seq[string] {.role: parser.} =
  ## args: the text between a call's parentheses. The arguments, split at the
  ## commas that are not inside brackets.
  var
    depth: int = 0
    cur: string = ""
  result = @[]
  for c in args:
    if c in {'(', '[', '{'}:
      depth = depth + 1
    elif c in {')', ']', '}'}:
      depth = depth - 1
    if c == ',' and depth == 0:
      result.add(cur.strip())
      cur = ""
    else:
      cur.add(c)
  if cur.strip().len > 0:
    result.add(cur.strip())

proc isIntLiteral(s: string): bool {.role: parser.} =
  ## s: one argument. True for a whole number written out: 500, 2_000.
  result = s.len > 0
  for c in s:
    if c notin {'0' .. '9', '_'}:
      return false

proc isCheckName(n: string): bool {.role: parser.} =
  ## n: a routine name. True when it asks a yes-or-no question about a text.
  result = false
  for p in checkPrefixes:
    if n.startsWith(p) and n.len > p.len and n[p.len].isUpperAscii():
      return true

proc touches(c: Call, name: string): bool {.role: parser.} =
  ## c/name: the call is given the WHOLE text `name`: as an argument of its own
  ## or as the receiver. A single character (`name[i]`) or a length is not the
  ## text, and a routine that asks "is this character a letter?" has not
  ## checked the string.
  result = c.recv == name
  for a in argList(c.args):
    if a == name:
      return true

proc textParams(v: View): seq[string] {.role: parser.} =
  ## v: a routine. The names of its parameters that hold a text or bytes.
  result = @[]
  for s in v.f.sockets:
    if s.typeName in textTypes:
      result.add(s.name)

proc firstCheck(v: View, name: string): int {.role: parser.} =
  ## v/name: the first body line where a yes-or-no routine is asked about
  ## `name`, or -1.
  var
    i: int = 0
  result = -1
  while i < v.code.len:
    for c in callsOf(v.code[i]):
      if isCheckName(c.name) and touches(c, name):
        return i
    i = i + 1

proc useAfter(v: View, name: string, at: int): tuple[line: int, call: string]
    {.role: parser.} =
  ## v/name/at: the first call after body line `at` that takes the checked text
  ## itself, other than another question, a length or a message.
  var
    i: int = at + 1
  result = (-1, "")
  while i < v.code.len:
    for c in callsOf(v.code[i]):
      if touches(c, name) and not isCheckName(c.name) and
          c.name notin quietCalls:
        return (i, c.name)
    i = i + 1

proc checkReread(v: View, R: var DoorReport) {.role: actor.} =
  ## v/R: a text that is asked about (a yes-or-no routine) and then used as it
  ## was. Two readers of different FIELDS of one buffer are not this: they are
  ## how a decoder works, and flagging them drowned the real ones.
  var
    at: int = -1
    use: tuple[line: int, call: string] = (-1, "")
  for name in textParams(v):
    at = firstCheck(v, name)
    if at < 0:
      continue
    use = useAfter(v, name, at)
    if use.line >= 0:
      note(R, v, dkReread, use.line, "`" & name &
        "` is checked at line " & $(v.base + at) & " and then given to " &
        use.call & " as the ORIGINAL text; parse it once and use the result")

# --- secrets (SECRET BRANCH) -----------------------------------------------

proc isSecretName(w: string): bool {.role: parser.} =
  ## w: a name. True when it reads like a secret: key, mac, tag, token ...
  var
    n: string = w.toLowerAscii()
  result = n in exactSecrets
  if result:
    return
  for s in suffixSecrets:
    if n.endsWith(s):
      return true

proc operandAt(s: string, i: int, leftward: bool): string {.role: parser.} =
  ## s/i: a line and the place just beside an operator. The name or dotted name
  ## that stands there, with its brackets.
  var
    j: int = i
  result = ""
  if leftward:
    while j >= 0 and s[j] == ' ':
      j = j - 1
    while j >= 0 and (isIdentChar(s[j]) or s[j] in {'.', ']', '[', ')', '('}):
      result = $s[j] & result
      j = j - 1
  else:
    while j < s.len and s[j] == ' ':
      j = j + 1
    while j < s.len and (isIdentChar(s[j]) or s[j] in {'.', ']', '[', ')', '('}):
      result.add(s[j])
      j = j + 1

proc rootName(operand: string): string {.role: parser.} =
  ## operand: `a.b[3]`. The word it starts with: a.
  var
    i: int = 0
  while i < operand.len and not isIdentStart(operand[i]):
    i = i + 1
  result = ""
  while i < operand.len and isIdentChar(operand[i]):
    result.add(operand[i])
    i = i + 1

proc isPlainOperand(o: string): bool {.role: parser.} =
  ## o: one side of a comparison. True for a literal, a length or nothing: those
  ## say nothing about a secret's bytes.
  result = o.len == 0 or not isIdentStart(o[0]) or ".len" in o or
    ".high" in o or ".low" in o or o in ["nil", "true", "false"]

proc secretEquals(code: string): string {.role: parser.} =
  ## code: one line. The secret compared with == or !=, or "".
  var
    i: int = code.find("==")
    l: string = ""
    r: string = ""
  result = ""
  while i >= 0:
    l = operandAt(code, i - 1, true)
    r = operandAt(code, i + 2, false)
    if not isPlainOperand(l) and not isPlainOperand(r):
      if isSecretName(rootName(l)):
        return rootName(l)
      if isSecretName(rootName(r)):
        return rootName(r)
    i = code.find("==", i + 2)
  i = code.find("!=")
  while i >= 0:
    l = operandAt(code, i - 1, true)
    r = operandAt(code, i + 2, false)
    if not isPlainOperand(l) and not isPlainOperand(r):
      if isSecretName(rootName(l)):
        return rootName(l)
      if isSecretName(rootName(r)):
        return rootName(r)
    i = code.find("!=", i + 2)

proc secretIn(s: string): string {.role: parser.} =
  ## s: text. The first secret-looking name in it, or "".
  result = ""
  for w in identsOf(s):
    if isSecretName(w):
      return w

proc loopExitsEarly(v: View, i: int): bool {.role: parser.} =
  ## v/i: a loop head on body line i. True when its body holds break, return,
  ## raise or continue.
  var
    ind: int = indentOf(v.code[i])
    j: int = i + 1
  result = false
  while j < v.code.len and (v.code[j].strip().len == 0 or
      indentOf(v.code[j]) > ind):
    for w in refuseWords:
      if hasIdent(v.code[j], w):
        return true
    j = j + 1

proc isConstantTime(v: View): bool {.role: parser.} =
  ## v: a routine. True when it IS the constant-time one, so a loop with a
  ## fixed length is its job.
  var
    n: string = v.f.name.toLowerAscii()
  result = "constanttime" in n or "cteq" in n or "consttime" in n or
    "ct" in v.f.pragmaTags

proc checkSecret(v: View, R: var DoorReport) {.role: actor.} =
  ## v/R: a secret compared with ==, indexed in a condition, or looped over
  ## with an early exit.
  var
    i: int = 0
    w: string = ""
    s: string = ""
    c: string = ""
  if isConstantTime(v):
    return
  while i < v.code.len:
    c = v.code[i].strip()
    w = firstWord(c)
    s = secretEquals(c)
    if s.len > 0:
      note(R, v, dkSecret, i, "`" & s & "` is compared with ==/!=: the time shows where it differs; use constantTimeEqual")
    elif w in ["if", "elif", "while", "case"] and secretIn(c).len > 0 and
        (secretIn(c) & "[") in c:
      note(R, v, dkSecret, i, "a branch on a byte of `" & secretIn(c) & "`: the time shows its value")
    elif w == "for" and " in " in c and
        secretIn(c[c.find(" in ") + 4 .. ^1]).len > 0 and
        loopExitsEarly(v, i):
      note(R, v, dkSecret, i, "a loop over `" &
        secretIn(c[c.find(" in ") + 4 .. ^1]) &
        "` can stop early: the time shows how far it got")
    i = i + 1

# --- deadlines (NO DEADLINE) -----------------------------------------------

proc hasTimeout(args: string): bool {.role: parser.} =
  ## args: the text of a call's arguments. True when one word names a time:
  ## timeout, deadline, or one ending in Ms.
  result = false
  for w in identsOf(args):
    if "timeout" in w.toLowerAscii() or "deadline" in w.toLowerAscii() or
        w.endsWith("Ms") or w.endsWith("MS") or w.endsWith("Millis"):
      return true

proc hasDeadline(c: Call): bool {.role: parser.} =
  ## c: a call to a routine that waits. True when it names a time: a word like
  ## timeoutMs, a third argument to `connect`, a last number to `s.recv(n, 500)`,
  ## or any argument to `waitForExit`.
  var
    A: seq[string] = argList(c.args)
  result = hasTimeout(c.args)
  if c.name == "waitForExit":
    result = A.len > 0
  elif c.name == "connect":
    result = result or A.len >= 3
  elif c.name in ["recv", "recvLine"] and c.recv.len > 0:
    result = result or (A.len >= 2 and isIntLiteral(A[^1]))

proc checkDeadline(v: View, R: var DoorReport) {.role: actor.} =
  ## v/R: every wait that has no time limit named in its arguments.
  var
    i: int = 0
    w: string = ""
  while i < v.code.len:
    w = firstWord(v.code[i])
    if w in ["proc", "func", "template", "method", "iterator"]:
      i = i + 1
      continue
    for c in callsOf(v.code[i]):
      if c.name in waitCalls and not hasDeadline(c):
        note(R, v, dkDeadline, i, c.name &
          "(" & c.args.strip() & ") has no time limit: a silent peer holds it forever")
    i = i + 1

# --- the whole report ------------------------------------------------------

proc dooredTypesIn(files: seq[string]): HashSet[string]
    {.role: dataFetcher.} =
  ## files: the sources. The names of types declared with `doored` in their
  ## pragma: `Slots* {.role: truthState, tag: "doored".} = object`.
  var
    t: string = ""
    n: string = ""
  result = initHashSet[string]()
  for p in files:
    if not fileExists(p):
      continue
    for line in readFile(p).splitLines():
      t = line.strip()
      if "{." in t and "doored" in t and (" = object" in t or
          " = ref object" in t):
        n = typeHead(t)
        if n.len > 0 and n != "type":
          result.incl(n)

proc filesImporting(dir: string, files: seq[string]): HashSet[string]
    {.role: dataFetcher.} =
  ## dir/files: the root and the sources. The (relative) paths of the files
  ## that import the intake module with `admit`.
  var
    text: string = ""
  result = initHashSet[string]()
  for p in files:
    if fileExists(p):
      text = readFile(p)
      if "intake/admitted" in text or "fylgia_utils" in text:
        result.incl(normalizeSlashes(relativePath(p, dir)))

proc isShipped(path: string): bool {.role: parser.} =
  ## path: a source file, relative to the root. False for tests, examples and
  ## dev tools: they are not what a stranger's bytes reach.
  result = true
  for d in ["evaluation/", "examples/", "tools/", "benchmarks/", "docs/"]:
    if path.startsWith(d):
      return false

proc doorReport*(g: RepoGraph, dir: string): DoorReport {.role: orchestrator.} =
  ## g: the analysed repository. dir: its root. Every finding of the five
  ## rules, sorted by kind and place.
  var
    files: seq[string] = listNimFiles(dir)
    doored: HashSet[string] = dooredTypesIn(files)
    admitFiles: HashSet[string] = filesImporting(dir, files)
    v: View = default(View)
  result = DoorReport(findings: @[], allowed: 0, dooredTypes: @[],
    routines: g.functions.len)
  for n in doored:
    result.dooredTypes.add(n)
  for f in g.functions:
    if f.bodyLines.len == 0:
      continue
    v = viewOf(f, dir)
    if not isShipped(v.path):
      continue
    checkNumbers(v, result)
    checkOpenDoor(v, doored, admitFiles, result)
    checkReread(v, result)
    checkSecret(v, result)
    checkDeadline(v, result)

proc doorLines*(R: DoorReport): seq[string] {.role: dataWriter.} =
  ## R: the report. Lines for a person, one heading per kind that has findings.
  var
    k: DoorKind = dkNumber
    n: int = 0
  result = @[]
  for kind in DoorKind:
    k = kind
    n = 0
    for f in R.findings:
      if f.kind == k:
        n = n + 1
    if n == 0:
      continue
    result.add(kindHeading(k) & " — " & $n & " place(s).")
    result.add(kindRule(k))
    for f in R.findings:
      if f.kind == k:
        result.add("  " & f.path & ":" & $f.line & "  " & f.routine & "  " &
          f.detail)
  if R.allowed > 0:
    result.add("(" & $R.allowed & " site(s) are allowed with a written reason: `# otter: door <word> <reason>`)")

proc doorJson*(R: DoorReport): string {.role: dataWriter.} =
  ## R: the report as JSON: counts per kind, every finding, the doored types.
  var
    j: JsonNode = newJObject()
    a: JsonNode = newJArray()
    counts: JsonNode = newJObject()
    n: int = 0
  for kind in DoorKind:
    n = 0
    for f in R.findings:
      if f.kind == kind:
        n = n + 1
    counts[kindHeading(kind)] = %n
  for f in R.findings:
    a.add(%*{"kind": kindHeading(f.kind), "path": f.path, "line": f.line,
      "routine": f.routine, "detail": f.detail})
  j["counts"] = counts
  j["findings"] = a
  j["allowed"] = %R.allowed
  j["dooredTypes"] = %R.dooredTypes
  j["routines"] = %R.routines
  result = pretty(j)
