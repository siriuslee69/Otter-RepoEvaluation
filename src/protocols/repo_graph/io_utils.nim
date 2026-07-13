# ============================================================
# | Otter Repo Graph IO Utils                                |
# | -> File discovery and stable path normalization helpers  |
# ============================================================

import std/[algorithm, os, strutils]

proc normalizeSlashes*(s: string): string {.inline.} =
  result = s.replace('\\', '/')


proc isIgnoredPath(relPath: string, bIncludeTests: bool): bool =
  var
    t: string = ""
  t = "/" & normalizeSlashes(relPath).toLowerAscii() & "/"
  if "/.git/" in t:
    result = true
    return
  if "/build/" in t or "/builds/" in t:
    result = true
    return
  if "/nimcache/" in t:
    result = true
    return
  if "/dist/" in t or "/node_modules/" in t:
    result = true
    return
  if "/submodules/" in t:
    result = true
    return
  if "/.otter/" in t:
    result = true
    return
  if not bIncludeTests and "/tests/" in t:
    result = true
    return


proc listNimFiles*(rootDir: string, bIncludeTests: bool = false): seq[string] =
  var
    rootNormalized: string = ""
    pNormalized: string = ""
    rel: string = ""
    s: string = ""
  result = @[]
  if not dirExists(rootDir):
    return
  rootNormalized = normalizeSlashes(normalizedPath(rootDir)).toLowerAscii()
  for p in walkDirRec(rootDir):
    s = normalizeSlashes(p)
    if not s.endsWith(".nim"):
      continue
    pNormalized = normalizeSlashes(normalizedPath(p)).toLowerAscii()
    rel = pNormalized
    if pNormalized.startsWith(rootNormalized):
      rel = pNormalized[rootNormalized.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    if isIgnoredPath(rel, bIncludeTests):
      continue
    result.add(p)
  result.sort(system.cmp[string])


proc toModulePath*(rootDir, filePath: string): string =
  var
    rootNormalized: string = ""
    fileNormalized: string = ""
    p: string = ""
  rootNormalized = normalizeSlashes(normalizedPath(rootDir))
  fileNormalized = normalizeSlashes(normalizedPath(filePath))
  p = fileNormalized
  if fileNormalized.startsWith(rootNormalized):
    p = fileNormalized[rootNormalized.len .. ^1]
  if p.startsWith("/"):
    p = p[1 .. ^1]
  if p.endsWith(".nim"):
    p = p[0 .. ^5]
  result = p


proc toImportModulePath*(modulePath: string): string =
  var
    p: string = ""
  p = normalizeSlashes(modulePath)
  for prefix in ["src/", "tests/", "tools/"]:
    if p.startsWith(prefix):
      p = p[prefix.len .. ^1]
      break
  result = p


proc readLinesSafe*(filePath: string): seq[string] =
  if not fileExists(filePath):
    result = @[]
    return
  result = readFile(filePath).splitLines()
