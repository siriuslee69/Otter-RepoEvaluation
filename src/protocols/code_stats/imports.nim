## Import scans <- unused candidates and local module dependency depth.
## Reuse the graph parser's bindings so the two reports agree on module names.
## An unused candidate is only a text hint: unqualified exports need the compiler.

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

proc unusedLine(R: var seq[UnusedImportInfo], p, m, s, text: string, n: int)
    {.role: actor, inline.} =
  ## R: findings; p/m: file and module; s: line n; text: whole file.
  for b in parseImportBindings(@[s], m):
    if b.localName.len > 1 and text.count(b.localName) <= 1:
      R.add(UnusedImportInfo(moduleName: b.localName, path: p, line: n))

proc unusedFile(dir, p: string): seq[UnusedImportInfo] {.role: truthBuilder.} =
  ## dir: root; p: file. Candidate names are not proof an import can be deleted.
  var
    L: seq[string] = @[]
    r: string = normalizeSlashes(relativePath(p, dir))
    m: string = toModulePath(dir, p)
    text: string = ""
    n: int = 0
  result = @[]
  if extensionOf(p) notin ["nim", "nims"]:
    return
  L = readLinesSafe(p)
  text = L.join("\n")
  for s in L:
    inc n
    unusedLine(result, r, m, s, text, n)

proc scanUnusedImports*(dir: string, P: seq[string]): seq[UnusedImportInfo]
    {.role: truthBuilder.} =
  ## dir: root; P: source files. Report text candidates in source order.
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
