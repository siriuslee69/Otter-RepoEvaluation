## ================================================================
## | continuity_guard.nim  <-  is this `if` true when view = vX?    |
## |---------------------------------------------------------------|
## | A menu decides what to draw with conditions:                   |
## |                                                                |
## |     var bare = M.view in {vReport}                             |
## |     ...                                                        |
## |     if not bare:                                               |
## |       insert(headerBar(M))                                     |
## |                                                                |
## | To know whether pressing "Report" (which sets view = vReport)  |
## | hides the header bar, the condition is worked out with the     |
## | view set to vReport. Three answers, never a guess:             |
## |                                                                |
## |   true     it holds for sure       (`not bare`  -> false)      |
## |   false    it cannot hold                                      |
## |   unknown  it depends on something else (a search text, a      |
## |            flag): the check says nothing about it              |
## ================================================================
##
## What it understands
## -------------------
##   M.view in {vA, vB}        M.view notin {vA}       M.view == vA    M.view != vA
##   not x    x and y    x or y    (x)    true    false
##   a local name:             var bare = M.view in {vReport}  ->  `bare`
##   a helper over a view:     proc isForm(v: View): bool = result = v in {...}
##                             ->  `M.view.isForm()` and `isForm(M.view)`
##
## Anything else (a number, a string, a call it does not know) is
## `unknown`. `unknown and false` is false and `unknown or true` is
## true, the way a person would read them; every other mix stays
## unknown, so a condition that merely MIGHT hold is never reported
## as one that does not.

import std/[sets, strutils, tables]

import runePragmas

type
  Tri* {.role: other, tag: "stats".} = enum
    tFalse, tTrue, tUnknown

  ValueKind = enum
    vkBool, vkField, vkMember, vkOther

  Value = object
    kind: ValueKind
    tri: Tri
    name: string

  HelperFn* {.role: preparedData, tag: "stats".} = object
    ## A routine over one view whose answer is a single expression.
    param*: string
    expr*: string

  GuardEnv* {.role: preparedData, tag: "stats".} = object
    members*: HashSet[string]
      ## Every member of every view enum.
    fields*: HashSet[string]
      ## The names of the state fields that hold a view.
    assigned*: Table[string, string]
      ## Which view each field is set to, for this question.
    locals*: Table[string, string]
      ## `bare` -> `M.view in {vReport}`, from the routine that wrote the `if`.
    funcs*: Table[string, HelperFn]

  Cur = object
    S: string
    i: int

const
  wordStops: set[char] = {' ', '\t', '(', ')', '{', '}', '=', '!', ',', ':'}
  expandRounds: int = 4
  expandCap: int = 4000

proc triNot*(t: Tri): Tri {.role: math, tag: "stats".} =
  ## t: an answer. The opposite; unknown stays unknown.
  case t
  of tTrue:
    result = tFalse
  of tFalse:
    result = tTrue
  of tUnknown:
    result = tUnknown

proc triAnd*(a, b: Tri): Tri {.role: math, tag: "stats".} =
  ## a, b: two answers. Both must hold; one false settles it.
  if a == tFalse or b == tFalse:
    result = tFalse
  elif a == tTrue and b == tTrue:
    result = tTrue
  else:
    result = tUnknown

proc triOr*(a, b: Tri): Tri {.role: math, tag: "stats".} =
  ## a, b: two answers. Either may hold; one true settles it.
  ## Written through `triAnd` (not a second copy of its logic): a or b is
  ## not (not a and not b).
  result = triNot(triAnd(triNot(a), triNot(b)))

# --- text expansion: names and helpers become plain conditions ------------------

proc isWordChar(c: char): bool {.role: helper, inline, tag: "stats".} =
  ## c: one character. True inside a name.
  result = c.isAlphaNumeric() or c == '_'

proc replaceWord(S, word, by: string): string {.role: helper, tag: "stats".} =
  ## S: a condition   word: a name   by: text to put in its place.
  ## Every whole-word `word` that does not follow a dot is replaced.
  var
    i: int = 0
    at: int = 0
    before: bool = false
    after: bool = false
  result = ""
  while i < S.len:
    at = S.find(word, i)
    if at < 0:
      break
    before = at > 0 and (isWordChar(S[at - 1]) or S[at - 1] == '.')
    after = at + word.len < S.len and isWordChar(S[at + word.len])
    result.add(S[i ..< at])
    result.add(if before or after: word else: by)
    i = at + word.len
  result.add(S[min(i, S.len) .. ^1])

proc closeAt(S: string, open: int): int {.role: parser, tag: "stats".} =
  ## S: text   open: index of a `(`. Index of its `)`, or -1.
  var
    depth: int = 0
  result = -1
  for i in open ..< S.len:
    if S[i] == '(':
      depth = depth + 1
    if S[i] == ')':
      depth = depth - 1
    if depth == 0:
      return i

proc chainBefore(S: string, at: int): int {.role: parser, tag: "stats".} =
  ## S: text   at: index of a `.`. Where the dotted name before it starts.
  var
    i: int = at - 1
  while i >= 0 and (isWordChar(S[i]) or S[i] == '.'):
    i = i - 1
  result = i + 1

proc withParam(fn: HelperFn, arg: string): string {.role: helper,
    tag: "stats".} =
  ## fn: a helper over one view   arg: what it is called with.
  result = "(" & replaceWord(fn.expr, fn.param, "(" & arg & ")") & ")"

proc expandMethod(S, name: string, fn: HelperFn): string {.role: helper,
    tag: "stats".} =
  ## S: a condition   name, fn: a helper.
  ## `M.view.name()` becomes the helper's expression with `M.view` put in.
  var
    key: string = "." & name & "()"
    at: int = S.find(key)
    from0: int = 0
    rounds: int = 0
  result = S
  while at >= 0 and rounds < 20:
    rounds = rounds + 1
    from0 = chainBefore(result, at)
    result = result[0 ..< from0] & withParam(fn, result[from0 ..< at]) &
      result[at + key.len .. ^1]
    at = result.find(key)

proc expandCall(S, name: string, fn: HelperFn): string {.role: helper,
    tag: "stats".} =
  ## S: a condition   name, fn: a helper.
  ## `name(M.view)` becomes the helper's expression with `M.view` put in.
  var
    key: string = name & "("
    at: int = S.find(key)
    close: int = 0
    rounds: int = 0
  result = S
  while at >= 0 and rounds < 20:
    rounds = rounds + 1
    close = closeAt(result, at + name.len)
    if close < 0 or (at > 0 and (isWordChar(result[at - 1]) or
        result[at - 1] == '.')):
      break
    result = result[0 ..< at] & withParam(fn, result[at + key.len ..< close]) &
      result[close + 1 .. ^1]
    at = result.find(key)

proc expandGuard*(text: string, locals: Table[string, string],
    funcs: Table[string, HelperFn]): string {.role: sanitizer,
    tag: "stats".} =
  ## text: a condition as written   locals: names the routine made
  ## funcs: helpers over one view.
  ## The same condition with every local name and every helper call
  ## replaced by what it stands for, a few rounds deep.
  result = text
  for _ in 0 ..< expandRounds:
    for name, fn in funcs:
      result = expandCall(expandMethod(result, name, fn), name, fn)
    for name, expr in locals:
      result = replaceWord(result, name, "(" & expr & ")")
    if result.len > expandCap:
      return text

# --- the evaluator ------------------------------------------------------------------

proc skipSpace(P: var Cur) {.role: helper, inline, tag: "stats".} =
  ## P: the reader. Moves past spaces.
  while P.i < P.S.len and P.S[P.i] in {' ', '\t'}:
    P.i = P.i + 1

proc readWord(P: var Cur): string {.role: parser, tag: "stats".} =
  ## P: the reader. The next name, dotted chain or call, as written.
  var
    start: int = P.i
    close: int = 0
  while P.i < P.S.len and P.S[P.i] notin wordStops:
    P.i = P.i + 1
  if P.i < P.S.len and P.S[P.i] == '(' and P.i > start:
    close = closeAt(P.S, P.i)
    P.i = (if close < 0: P.S.len else: close + 1)
  result = P.S[start ..< P.i]

proc peekWord(P: var Cur): string {.role: parser, tag: "stats".} =
  ## P: the reader. The next word, without moving.
  var
    at: int = P.i
  skipSpace(P)
  result = readWord(P)
  P.i = at

proc boolValue(t: Tri): Value {.role: helper, inline, tag: "stats".} =
  ## t: an answer, as a value.
  result = Value(kind: vkBool, tri: t, name: "")

proc atomValue(w: string, env: GuardEnv): Value {.role: parser,
    tag: "stats".} =
  ## w: one word   env: what is known. The value it stands for.
  var
    last: string = w.split('.')[^1]
  result = Value(kind: vkOther, tri: tUnknown, name: w)
  if w == "true":
    result = boolValue(tTrue)
  elif w == "false":
    result = boolValue(tFalse)
  elif '(' in w:
    result = Value(kind: vkOther, tri: tUnknown, name: w)
  elif last in env.members:
    result = Value(kind: vkMember, tri: tUnknown, name: last)
  elif last in env.fields:
    result = Value(kind: vkField, tri: tUnknown, name: last)

proc equalTo(a, b: Value, env: GuardEnv): Tri {.role: math, tag: "stats".} =
  ## a, b: a state field and a view member, either way round.
  ## Whether they are equal for the question being asked.
  var
    f: Value = (if a.kind == vkField: a else: b)
    m: Value = (if a.kind == vkMember: a else: b)
  result = tUnknown
  if f.kind == vkField and m.kind == vkMember and f.name in env.assigned:
    result = (if env.assigned[f.name] == m.name: tTrue else: tFalse)

proc inSet(a: Value, items: seq[string], env: GuardEnv): Tri {.role: math,
    tag: "stats".} =
  ## a: a state field   items: the members written in `{ ... }`.
  ## Whether the field's view is among them.
  result = tUnknown
  if a.kind != vkField or a.name notin env.assigned:
    return
  for it in items:
    if it notin env.members:
      return
  result = (if env.assigned[a.name] in items: tTrue else: tFalse)

proc readSet(P: var Cur): seq[string] {.role: parser, tag: "stats".} =
  ## P: the reader, standing on a `{`. The words written inside it.
  var
    stop: int = P.S.find('}', P.i)
  result = @[]
  if stop < 0:
    P.i = P.S.len
    return
  for part in P.S[P.i + 1 ..< stop].split(','):
    result.add(part.strip().split('.')[^1])
  P.i = stop + 1

proc comparison(P: var Cur, left: Value, env: GuardEnv): Value {.role: parser,
    tag: "stats".} =
  ## P: the reader   left: the value before a comparison   env: what is known.
  ## The value after `== x`, `!= x`, `in {..}` or `notin {..}`; `left` itself
  ## when none follows.
  var
    op: string = ""
    right: Value = left
    t: Tri = tUnknown
  result = left
  skipSpace(P)
  if P.S.continuesWith("==", P.i) or P.S.continuesWith("!=", P.i):
    op = P.S[P.i ..< P.i + 2]
    P.i = P.i + 2
    skipSpace(P)
    right = atomValue(readWord(P), env)
    t = equalTo(left, right, env)
    result = boolValue(if op == "!=": triNot(t) else: t)
    return
  op = peekWord(P)
  if op in ["in", "notin"]:
    skipSpace(P)
    discard readWord(P)
    skipSpace(P)
    if P.i < P.S.len and P.S[P.i] == '{':
      t = inSet(left, readSet(P), env)
    result = boolValue(if op == "notin": triNot(t) else: t)

proc evalAt(P: var Cur, env: GuardEnv, minPrec: int): Value {.role: parser,
    tag: "stats".} =
  ## P: the reader   env: what is known
  ## minPrec: 0 reads everything, 2 only what binds tighter than `or`,
  ## 3 only what binds tighter than `and`.
  ## The value of the condition from here on.
  var
    left: Value = boolValue(tUnknown)
    w: string = ""
    op: string = ""
    right: Value = boolValue(tUnknown)
  skipSpace(P)
  if P.i < P.S.len and P.S[P.i] == '(':
    P.i = P.i + 1
    left = evalAt(P, env, 0)
    skipSpace(P)
    if P.i < P.S.len and P.S[P.i] == ')':
      P.i = P.i + 1
    left = comparison(P, left, env)
  else:
    w = readWord(P)
    if w == "not":
      right = evalAt(P, env, 3)
      left = boolValue(triNot(if right.kind == vkBool: right.tri
        else: tUnknown))
    else:
      left = comparison(P, atomValue(w, env), env)
  while true:
    op = peekWord(P)
    if op == "and" and minPrec <= 2:
      skipSpace(P)
      discard readWord(P)
      right = evalAt(P, env, 3)
      left = boolValue(triAnd(left.tri, right.tri))
    elif op == "or" and minPrec <= 1:
      skipSpace(P)
      discard readWord(P)
      right = evalAt(P, env, 2)
      left = boolValue(triOr(left.tri, right.tri))
    else:
      break
  result = left

proc evalGuard*(text: string, env: GuardEnv): Tri {.role: parser,
    tag: "stats".} =
  ## text: one condition as written in the routine   env: what is known.
  ## Whether it holds, for the view the question assumes.
  var
    P: Cur = Cur(S: expandGuard(text, env.locals, env.funcs), i: 0)
    v: Value = Value(kind: vkOther, tri: tUnknown, name: "")
  v = evalAt(P, env, 0)
  result = (if v.kind == vkBool: v.tri else: tUnknown)
