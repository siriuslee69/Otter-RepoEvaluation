## ================================================================
## | continuity_walk.nim  <-  which conditions stand over a line    |
## |---------------------------------------------------------------|
## | Nim marks a block by its indent. To know when a line is        |
## | reached, every `if`, `elif`, `else`, `case`/`of` above it must |
## | be written down, plus the early `return` that skips it:        |
## |                                                                |
## |     proc body(M): Widget =                                     |
## |       if M.picker:                                             |
## |         return pickerView(M)           <- ends the routine     |
## |       case M.view                                              |
## |       of vReport: result = reportView(M)                       |
## |       else:       result = homeColumns(M)                      |
## |                                                                |
## |   statement                    reached when                    |
## |   ───────────────────────────  ─────────────────────────────  |
## |   return pickerView(M)         M.picker                        |
## |   result = reportView(M)       not (M.picker)                  |
## |                                 and M.view in {vReport}        |
## |   result = homeColumns(M)      not (M.picker)                  |
## |                                 and not (M.view in {vReport})  |
## ================================================================
##
## The conditions are kept as text. continuity_guard.nim works out
## what they say once a view is chosen.

import std/[strutils, tables]

import runePragmas
from ./nesting import indentOf
export indentOf

type
  GuardedLine* {.role: preparedData, tag: "stats".} = object
    ## One statement and everything that must hold for it to run.
    line*: int
      ## Index of its line in the routine's body.
    text*: string
      ## The statement. For `of x: stmt` on one line, just `stmt`.
    guards*: seq[string]

  Header = object
    kind: string
    cond: string
    rest: string

  Frame = object
    indent: int
    guard: string
    persistent: bool
      ## True for the condition left behind by an early `return`: it holds
      ## for the rest of the block it was written in.
    returns: bool

  Chain = object
    kind: char
    subject: string
    conds: seq[string]

  Walk = object
    frames: seq[Frame]
    chains: Table[int, Chain]
    lines: seq[GuardedLine]

const
  unknownGuard: string = "?"
    ## What stands for a condition this reader could not make sense of.

proc colonAt(t: string): int {.role: parser, tag: "stats".} =
  ## t: a statement. The index of the first `:` outside brackets and
  ## quotes, or -1.
  var
    depth: int = 0
    quoted: bool = false
  result = -1
  for i in 0 ..< t.len:
    if t[i] == '"':
      quoted = not quoted
    if quoted:
      continue
    if t[i] in {'(', '[', '{'}:
      depth = depth + 1
    if t[i] in {')', ']', '}'}:
      depth = depth - 1
    if t[i] == ':' and depth == 0:
      return i

proc headerOf(t: string): Header {.role: parser, tag: "stats".} =
  ## t: one stripped statement.
  ## Which kind of block it opens (if, elif, else, case, of), its condition,
  ## and whatever stands after the colon on the same line.
  var
    colon: int = colonAt(t)
    word: string = t.split({' ', ':'})[0]
    head: int = 0
  result = Header(kind: "", cond: "", rest: "")
  if word notin ["if", "elif", "else", "case", "of"]:
    return
  result.kind = word
  head = min(t.len, word.len + 1)
  if word == "else" or colon < 0:
    result.cond = (if word == "else": "" else: t[head .. ^1].strip())
  else:
    result.cond = t[head ..< colon].strip()
  if colon >= 0:
    result.rest = t[colon + 1 .. ^1].strip()

proc negations(conds: seq[string]): string {.role: helper, tag: "stats".} =
  ## conds: the conditions of the earlier branches of one chain.
  ## "not (a) and not (b)": none of them held.
  result = ""
  for c in conds:
    result.add((if result.len > 0: " and " else: "") & "not (" & c & ")")

proc guardFor(W: var Walk, indent: int, h: Header): string {.role: actor,
    tag: "stats".} =
  ## W: the walk   indent: the header's indent   h: the header.
  ## The condition its block stands under; the chain it belongs to is noted.
  var
    chain: Chain = W.chains.getOrDefault(indent)
  result = unknownGuard
  case h.kind
  of "if":
    W.chains[indent] = Chain(kind: 'i', subject: "", conds: @[h.cond])
    result = h.cond
  of "elif":
    result = negations(chain.conds) & " and (" & h.cond & ")"
    chain.conds.add(h.cond)
    W.chains[indent] = chain
  of "case":
    W.chains[indent] = Chain(kind: 'c', subject: h.cond, conds: @[])
    result = ""
  of "of":
    result = chain.subject & " in {" & h.cond & "}"
    chain.conds.add(h.cond)
    W.chains[indent] = chain
  else:
    if chain.kind == 'i':
      result = negations(chain.conds)
    if chain.kind == 'c':
      result = "not (" & chain.subject & " in {" & chain.conds.join(", ") &
        "})"

proc closeFrames(W: var Walk, indent: int) {.role: actor, tag: "stats".} =
  ## W: the walk   indent: the indent of the line now read.
  ## Drops the blocks that line is no longer inside. A block that ended with
  ## a `return` leaves its opposite behind for the rest of the routine.
  var
    top: Frame = Frame()
    left: seq[Frame] = @[]
  while W.frames.len > 0:
    top = W.frames[^1]
    if (top.persistent and indent >= top.indent) or
        (not top.persistent and indent > top.indent):
      break
    discard W.frames.pop()
    if top.returns and indent >= top.indent:
      left.add(Frame(indent: top.indent, guard: "not (" & top.guard & ")",
        persistent: true, returns: false))
  W.frames.add(left)

proc addLine(W: var Walk, i: int, text: string) {.role: actor, tag: "stats".} =
  ## W: the walk   i: the line's index   text: the statement.
  ## Records it with every condition that stands over it.
  var
    g: seq[string] = @[]
  for f in W.frames:
    if f.guard.len > 0:
      g.add(f.guard)
  W.lines.add(GuardedLine(line: i, text: text, guards: g))

proc markReturn(W: var Walk) {.role: actor, tag: "stats".} =
  ## W: the walk. A `return` was read: the block it stands in ends the routine.
  for i in countdown(W.frames.high, 0):
    if not W.frames[i].persistent:
      W.frames[i].returns = true
      return

proc readLine(W: var Walk, i: int, raw: string) {.role: actor, tag: "stats".} =
  ## W: the walk   i: the line's index   raw: the line.
  var
    t: string = raw.strip()
    ind: int = indentOf(raw)
    h: Header = Header()
    g: string = ""
  W.closeFrames(ind)
  h = headerOf(t)
  if h.kind == "":
    if t.startsWith("return"):
      W.markReturn()
    W.addLine(i, t)
    return
  g = W.guardFor(ind, h)
  if h.kind == "case":
    return
  W.frames.add(Frame(indent: ind, guard: g, persistent: false,
    returns: false))
  if h.rest.len > 0:
    W.addLine(i, h.rest)
    if h.rest.startsWith("return"):
      W.markReturn()

proc guardedLines*(L: seq[string]): seq[GuardedLine] {.role: parser,
    tag: "stats".} =
  ## L: the body of one routine.
  ## Every statement, with the conditions that must hold for it to run.
  var
    W: Walk = Walk(frames: @[], chains: initTable[int, Chain](), lines: @[])
    t: string = ""
  for i in 0 ..< L.len:
    t = L[i].strip()
    if t.len > 0 and not t.startsWith("#"):
      W.readLine(i, L[i])
  result = W.lines
