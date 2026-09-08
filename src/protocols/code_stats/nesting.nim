# ============================================================
# | Otter Code Statistics Nesting                            |
# | -> Blocks inside blocks, and how much lives in the last  |
# ============================================================
#
# One routine's body is read line by line while a stack of open blocks
# is kept. A line that opens a block is a site; its depth is how many
# counting blocks are already open.
#
#     proc f =
#       for row in A:          depth 1
#         if row.ok:           depth 2   <- a site
#           while n > 0:       depth 3   <- a site, and a leaf
#             dec n            1 line inside the last layer
#
# `else`, `elif`, `of`, `except` and `finally` continue a block that is
# already open, so they never add a level of their own. A routine
# declared inside another routine starts with a clean stack, which is
# why pulling an inline proc out of a loop removes the nesting instead
# of hiding it.

import std/[strutils]

import ./types
import ../repo_graph/types as graphTypes
import otterPragmas

const
  openerWords*: array[7, string] = ["if", "for", "while", "case", "when",
    "try", "block"]
  continueWords*: array[5, string] = ["elif", "else", "of", "except",
    "finally"]
  routineWords*: array[7, string] = ["proc", "func", "method", "iterator",
    "template", "macro", "converter"]

type
  BlockFrame = object
    indent: int
    counts: bool

proc indentOf*(line: string): int {.role: parser, metaTags: {tagStats}.} =
  ## line: one source line. Tabs count as one, which is enough because
  ## a tree that mixes tabs and spaces has a bigger problem than this.
  result = 0
  while result < line.len and (line[result] == ' ' or line[result] == '\t'):
    result = result + 1


proc skippable*(line: string): bool {.role: parser, metaTags: {tagStats}.} =
  ## line: one source line. Blank lines and comments carry no block.
  var
    t: string = line.strip()
  result = t.len == 0 or t.startsWith("#")


proc firstWord*(line: string): string {.role: parser, metaTags: {tagStats}.} =
  ## line: one source line, stripped down to its leading keyword.
  var
    t: string = line.strip()
    i: int = 0
  result = ""
  while i < t.len and (t[i] in {'a' .. 'z'} or t[i] in {'A' .. 'Z'}):
    i = i + 1
  if i == 0:
    return
  result = t[0 ..< i]


proc wordIn(A: openArray[string], w: string): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## A: the keyword list. w: the word read off the line.
  result = false
  for row in A:
    if row == w:
      result = true
      return


proc opensBlock*(line: string): bool {.role: parser, metaTags: {tagStats}.} =
  ## line: one source line. A block opener also has to end in a colon
  ## or carry one, so `if a: b` and `result = if x: 1 else: 2` are told
  ## apart from a bare word.
  var
    w: string = firstWord(line)
  result = false
  if not wordIn(openerWords, w):
    return
  result = ':' in line


proc continuesBlock*(line: string): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## line: one source line that carries on a block already open.
  var
    w: string = firstWord(line)
  result = wordIn(continueWords, w) and ':' in line


proc startsRoutine*(line: string): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## line: one source line declaring a routine inside another one.
  result = wordIn(routineWords, firstWord(line))


proc unwind(S: var seq[BlockFrame], indent: int): bool {.role: actor,
    metaTags: {tagStats}.} =
  ## S: the open blocks. indent: the indent of the line being read.
  ## Answers whether the last block closed here was a counting one, so
  ## an `else` can inherit what its `if` was.
  result = false
  while S.len > 0 and indent <= S[^1].indent:
    result = S[^1].counts
    discard S.pop()


proc bodyStartLine*(f: FunctionInfo): int {.role: parser,
    metaTags: {tagStats}.} =
  ## f: one parsed routine. The first body line's own line number, one
  ## based, worked back from where the routine ends.
  result = f.lineEnd - f.bodyLines.len + 1


proc innerLinesAt*(A: seq[string], start, indent: int): int {.role: parser,
    metaTags: {tagStats}.} =
  ## A: the routine's body. start: index just after the opener.
  ## indent: the opener's own indent. Counts code lines that sit inside
  ## the block, which is every line indented further than the opener.
  var
    i: int = start
  result = 0
  while i < A.len:
    if skippable(A[i]):
      i = i + 1
      continue
    if indentOf(A[i]) <= indent:
      return
    result = result + 1
    i = i + 1


proc markLeaves*(S: var seq[NestSite]) {.role: actor, metaTags: {tagStats}.} =
  ## S: sites of one routine, in the order they were read. A site is a
  ## leaf when the site right after it is not deeper than itself.
  var
    i: int = 0
  while i < S.len:
    S[i].leaf = i + 1 >= S.len or S[i + 1].depth <= S[i].depth
    i = i + 1


proc nestSites*(f: FunctionInfo): seq[NestSite] {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## f: one parsed routine. Every block that sits inside another block,
  ## with the lines that live in it.
  var
    frames: seq[BlockFrame] = @[]
    base: int = bodyStartLine(f)
    i: int = 0
    ind: int = 0
    depth: int = 0
    closed: bool = false
  result = @[]
  while i < f.bodyLines.len:
    if skippable(f.bodyLines[i]):
      i = i + 1
      continue
    ind = indentOf(f.bodyLines[i])
    closed = unwind(frames, ind)
    if startsRoutine(f.bodyLines[i]):
      frames = @[]
      i = i + 1
      continue
    if continuesBlock(f.bodyLines[i]):
      frames.add(BlockFrame(indent: ind, counts: closed))
      i = i + 1
      continue
    if not opensBlock(f.bodyLines[i]):
      i = i + 1
      continue
    depth = frames.len + 1
    if depth >= 2:
      result.add(NestSite(path: f.sourcePath, fn: f.name,
        keyword: firstWord(f.bodyLines[i]), line: base + i, depth: depth,
        innerLines: innerLinesAt(f.bodyLines, i + 1, ind), leaf: false))
    frames.add(BlockFrame(indent: ind, counts: true))
    i = i + 1
  markLeaves(result)


proc deepestOf*(A: seq[NestSite]): int {.role: parser,
    metaTags: {tagStats}.} =
  ## A: sites of one routine or file. One means nothing was nested.
  result = 1
  for row in A:
    if row.depth > result:
      result = row.depth
