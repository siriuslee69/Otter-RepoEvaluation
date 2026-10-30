## Import scans <- unused candidates and local module dependency depth.
## Reuse the graph parser's bindings so the two reports agree on module names.
##
## Unused candidates read the exports of LOCAL modules only. An import is
## used when its own name, or any name the module exports, appears in the
## file's code. Outside modules (std, submodules) are never reported, because
## their exports are not read here. The compiler is the exact check for them:
##   nim check --warnings:on <file>.nim   -> "imported and not used"

import std/[algorithm, os, sets, strutils, tables]
import runePragmas
import ./types
import ../repo_graph/io_utils
import ../repo_graph/nim_parser
import ../repo_graph/types as graphTypes

type
  ImportWalk = object
    adjacency: Table[string, seq[string]]
    depths: Table[string, int]
    active: HashSet[string]
    path: seq[string]
    cycles: seq[CircularImportInfo]

proc isWordChar(c: char): bool {.inline, role: parser.} =
  ## c: one character. True for the characters an identifier is made of.
  result = c.isAlphaNumeric or c == '_'

proc hasWord(text, word: string): bool {.role: parser.} =
  ## text: source code; word: one identifier. True when the word stands on
  ## its own, not as the middle of a longer name such as `graphTypes`.
  var
    at: int = 0
  result = false
  if word.len == 0:
    return
  at = text.find(word)
  while at >= 0 and not result:
    result = (at == 0 or not text[at - 1].isWordChar) and
      (at + word.len >= text.len or not text[at + word.len].isWordChar)
    at = text.find(word, at + 1)

proc codeWithoutImports(L: seq[string]): string {.role: parser.} =
  ## L: one file's lines. Its code with the top-level import lines left out,
  ## so an import never counts as a use of itself.
  result = ""
  for s in L:
    if not (s.startsWith("import ") or s.startsWith("from ") or
        s.startsWith("include ")):
      result.add(s & "\n")

proc declarationHead(t: string): string {.role: parser.} =
  ## t: one stripped line. Drop the keyword that opens a declaration, so
  ## `proc name*` and `name*` both read as `name*`.
  result = t
  for kw in ["proc ", "func ", "template ", "macro ", "iterator ",
      "converter ", "method ", "type ", "const ", "let ", "var "]:
    if t.startsWith(kw):
      result = t[kw.len .. ^1].strip()
      break

proc exportedNames(L: seq[string]): tuple[names: seq[string], opaque: bool]
    {.role: parser.} =
  ## L: one module's lines. A name is exported when its declaration puts `*`
  ## after it, at the top level or one step in (type and const blocks).
  ## `export` re-exports other modules, so the names cannot be listed: opaque.
  var
    t: string = ""
    head: string = ""
    k: int = 0
    indent: int = 0
  result = (names: @[], opaque: false)
  for s in L:
    t = s.strip()
    indent = s.len - s.strip(leading = true, trailing = false).len
    if t.len == 0 or t.startsWith("#") or indent > 2:
      continue
    if t.startsWith("export "):
      result.opaque = true
      continue
    head = declarationHead(t)
    k = 0
    while k < head.len and head[k].isWordChar:
      k = k + 1
    if k > 0 and k < head.len and head[k] == '*':
      result.names.add(head[0 ..< k])

proc importUsed(dir: string, b: ImportBinding, body: string): bool
    {.role: helper.} =
  ## dir: root; b: one import; body: the file's code without imports.
  ## True when the import is used, or when Otter cannot tell: an outside
  ## module, or one that re-exports. Only a local module with a known export
  ## list and no use of any of its names is reported as unused.
  var
    file: string = dir / (b.modulePath & ".nim")
    E: tuple[names: seq[string], opaque: bool] = (names: @[], opaque: false)
  result = true
  if hasWord(body, b.localName):
    return
  if b.kind == ikSymbol:
    result = false
    return
  if not fileExists(file):
    return
  E = exportedNames(readLinesSafe(file))
  if E.opaque:
    return
  result = false
  for name in E.names:
    if hasWord(body, name):
      result = true
      return

proc unusedLine(R: var seq[UnusedImportInfo], dir, p, m, s, body: string,
    n: int) {.role: actor, inline.} =
  ## R: findings; dir: root; p/m: file and module; s: line n; body: the file's
  ## code without its imports.
  for b in parseImportBindings(@[s], m):
    if b.localName.len > 1 and not importUsed(dir, b, body):
      R.add(UnusedImportInfo(moduleName: b.localName, path: p, line: n))

proc unusedFile(dir, p: string): seq[UnusedImportInfo] {.role: truthBuilder.} =
  ## dir: root; p: file. A candidate is a hint for a reader, not a proof that
  ## the import can be deleted.
  var
    L: seq[string] = @[]
    r: string = normalizeSlashes(relativePath(p, dir))
    m: string = toModulePath(dir, p)
    body: string = ""
    n: int = 0
  result = @[]
  if extensionOf(p) notin ["nim", "nims"]:
    return
  L = readLinesSafe(p)
  body = codeWithoutImports(L)
  for s in L:
    inc n
    unusedLine(result, dir, r, m, s, body, n)

proc scanUnusedImports*(dir: string, P: seq[string]): seq[UnusedImportInfo]
    {.role: truthBuilder.} =
  ## dir: root; P: source files. Report local imports nothing in the file uses.
  result = @[]
  for p in P:
    result.add(unusedFile(dir, p))

proc addImports(S: var ImportWalk, dir, p: string) {.role: actor.} =
  ## S: graph; dir: root; p: file. Retain full paths to distinguish types.nim files.
  var
    m: string = toModulePath(dir, p)
  if extensionOf(p) notin ["nim", "nims"]:
    return
  S.adjacency[m] = @[]
  for b in parseImportBindings(readLinesSafe(p), m):
    if b.modulePath notin S.adjacency[m]:
      S.adjacency[m].add(b.modulePath)
  S.adjacency[m].sort()

proc walkImports(S: var ImportWalk, m: string): int {.role: actor.} =
  ## S: traversal state; m: module. Memoize completed paths, stop at a back edge.
  var
    d: int = 0
    at: int = 0
  if not S.adjacency.hasKey(m):
    return 0 # External libraries are outside this repository's depth.
  if m in S.active:
    at = S.path.find(m)
    S.cycles.add(CircularImportInfo(cycle: S.path[at .. ^1] & @[m]))
    return 0
  if S.depths.hasKey(m):
    return S.depths[m]
  S.active.incl(m)
  S.path.add(m)
  result = 1
  for next in S.adjacency[m]:
    d = walkImports(S, next)
    result = max(result, 1 + d)
  discard S.path.pop()
  S.active.excl(m)
  S.depths[m] = result

proc buildImportGraphAndDepth*(dir: string, P: seq[string]): tuple[
    depth: int, cycles: seq[CircularImportInfo]] {.role: truthBuilder.} =
  ## dir: root; P: source files. Acyclic depth counts local modules on a path.
  ## Cycles are listed separately; depth ignores each discovered back edge.
  var
    scan: ImportWalk = ImportWalk()
    modules: seq[string] = @[]
  for p in P:
    addImports(scan, dir, p)
  for m in scan.adjacency.keys:
    modules.add(m)
  modules.sort()
  result = (0, @[])
  for m in modules:
    result.depth = max(result.depth, walkImports(scan, m))
  result.cycles = scan.cycles
