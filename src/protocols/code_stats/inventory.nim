## Source inventory <- own files, language totals, ignored files.
## Vendored folders stay outside these counts. Git decides ignore rules,
## including negated patterns; a substring match cannot answer that question.

import std/[algorithm, os, sets, tables]
import runePragmas
import ./types
import ./timeline
import ../repo_graph/io_utils

proc listAllSourceFiles*(dir: string): seq[string] {.role: dataFetcher.} =
  ## dir: repository root. Return hand-written files in stable path order.
  result = @[]
  if not dirExists(dir):
    return
  for p in ownFiles(dir):
    if isScannablePath(normalizeSlashes(relativePath(p, dir))):
      result.add(p)
  result.sort()

proc countLanguage(S: var Table[string, tuple[files, lines: int]], p: string)
    {.role: actor, inline.} =
  ## S: totals by extension; p: one source file.
  var
    e: string = extensionOf(p)
    g: string = "other"
    t: tuple[files, lines: int] = (0, 0)
  if e in ["nim", "c", "js", "ts"]:
    g = e
  t = S.getOrDefault(g)
  inc t.files
  t.lines += readLinesSafe(p).len
  S[g] = t

proc gatherLangStats*(P: seq[string]): seq[LangStat] {.role: truthBuilder.} =
  ## P: source paths. Keep the same language order on every run.
  var
    counts: Table[string, tuple[files, lines: int]] =
      initTable[string, tuple[files, lines: int]]()
  for p in P:
    countLanguage(counts, p)
  result = @[]
  for g in ["nim", "c", "js", "ts", "other"]:
    if counts.hasKey(g):
      result.add(LangStat(ext: g, files: counts[g].files, lines: counts[g].lines))

proc gatherGitignoreStats*(dir: string): GitignoreStat {.role: truthBuilder.} =
  ## dir: root. Count ignored files among the folders ownFiles visits.
  ## Compiled output and vendored folders are excluded before this scan.
  var
    P: seq[string] = @[]
    kept: HashSet[string] = initHashSet[string]()
  result = GitignoreStat()
  if not dirExists(dir):
    return
  P = ownFiles(dir)
  for p in gitKept(dir, P):
    kept.incl(p)
  for p in P:
    if p in kept:
      continue
    inc result.ignoredFiles
    result.ignoredLines += readLinesSafe(p).len
