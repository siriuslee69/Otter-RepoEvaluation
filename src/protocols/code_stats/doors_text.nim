## ==============================================================
## | doors_text.nim  <-  reading one line of Nim well enough for  |
## |                     the five door findings                   |
## |--------------------------------------------------------------|
## | Not a parser. It adds to what Otter already has (codeOf and  |
## | withoutStrings in state_writes.nim, indentOf and firstWord   |
## | in nesting.nim) the things the door checks need:             |
## |                                                              |
## |   lineCode    the line without its comment, with the inside  |
## |               of every string blanked (so a word in an error |
## |               message is never mistaken for a variable)      |
## |   callsOf     every `name(args)` and `x.name(args)` on it    |
## |   hasIdent    does this NAME appear, as a whole word?        |
## |                                                              |
## |   lineCode("n = readU16(A, 2)  # length")                    |
## |       ->  "n = readU16(A, 2)"                                |
## |   callsOf("newSeq[byte](n * 4)")                             |
## |       ->  [name "newSeq", args "n * 4", recv ""]             |
## |   callsOf("s.recv(512)")                                     |
## |       ->  [name "recv", args "512", recv "s"]                |
## ==============================================================

import std/[strutils]

import runePragmas
import ./state_writes

type
  Call* {.role: preparedData.} = object
    ## name: the routine called. args: the text between its parentheses.
    ## recv: the first word of what it was called on (`s` in `s.recv(1)`).
    name*: string
    args*: string
    recv*: string

proc lineCode*(line: string): string {.role: sanitizer.} =
  ## line: one source line. The comment cut off, the inside of every string
  ## blanked: only code is left to read.
  result = withoutStrings(codeOf(line))

proc isIdentChar*(c: char): bool {.role: parser, inline.} =
  ## c: a letter, a digit or an underscore.
  result = c in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}

proc isIdentStart*(c: char): bool {.role: parser, inline.} =
  ## c: a letter or an underscore.
  result = c in {'a' .. 'z', 'A' .. 'Z', '_'}

proc hasIdent*(s, w: string): bool {.role: parser.} =
  ## s: text. w: a name. True when `w` stands in `s` as a whole word.
  var
    i: int = 0
    before: bool = true
    after: bool = true
  result = false
  if w.len == 0:
    return
  i = s.find(w)
  while i >= 0:
    before = i == 0 or not isIdentChar(s[i - 1])
    after = i + w.len >= s.len or not isIdentChar(s[i + w.len])
    if before and after:
      return true
    i = s.find(w, i + 1)

proc identsOf*(s: string): seq[string] {.role: parser.} =
  ## s: text. Every word that could be a name, in order.
  var
    i: int = 0
    j: int = 0
  result = @[]
  while i < s.len:
    if isIdentStart(s[i]):
      j = i
      while j < s.len and isIdentChar(s[j]):
        j = j + 1
      result.add(s[i ..< j])
      i = j
    else:
      i = i + 1

proc balancedEnd*(s: string, open: int): int {.role: parser.} =
  ## s: text. open: the place of ( [ or {. The place of its partner, or -1.
  var
    depth: int = 0
    i: int = open
  result = -1
  while i < s.len:
    if s[i] in {'(', '[', '{'}:
      depth = depth + 1
    elif s[i] in {')', ']', '}'}:
      depth = depth - 1
      if depth == 0:
        return i
    i = i + 1

proc receiverOf(s: string, at: int): string {.role: parser.} =
  ## s: the line. at: where a called name starts. The first word of what it was
  ## called on, or "" for a plain call.
  var
    i: int = at - 1
  result = ""
  if i < 0 or s[i] != '.':
    return
  while i >= 0 and (isIdentChar(s[i]) or s[i] in {'.', ']', '[', ')', '('}):
    i = i - 1
  i = i + 1
  while i < at and not isIdentStart(s[i]):
    i = i + 1
  while i < at and isIdentChar(s[i]):
    result.add(s[i])
    i = i + 1

proc callsOf*(s: string): seq[Call] {.role: parser.} =
  ## s: one line of code (use `codeOf` first). Every call on it, outer ones
  ## before the ones inside their arguments.
  var
    i: int = 0
    j: int = 0
    k: int = 0
    e: int = 0
    one: Call = default(Call)
  result = @[]
  while i < s.len:
    if not isIdentStart(s[i]) or (i > 0 and isIdentChar(s[i - 1])):
      i = i + 1
      continue
    j = i
    while j < s.len and isIdentChar(s[j]):
      j = j + 1
    k = j
    if k < s.len and s[k] == '[':
      e = balancedEnd(s, k)
      if e > 0:
        k = e + 1
    e = if k < s.len and s[k] == '(': balancedEnd(s, k) else: -1
    if k < s.len and s[k] == '(':
      ## A call whose closing bracket is on a later line keeps what this line
      ## has of its arguments.
      one.name = s[i ..< j]
      one.args = if e > 0: s[k + 1 ..< e] else: s[k + 1 .. ^1]
      one.recv = receiverOf(s, i)
      result.add(one)
    i = j

