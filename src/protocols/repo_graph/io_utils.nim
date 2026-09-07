# ============================================================
# | Otter Repo Graph IO Utils                                |
# | -> File discovery and stable path normalization helpers  |
# ============================================================

import std/[algorithm, os, strutils]

import ../../../meta/metaPragmas

const
  vendoredDirs*: array[9, string] = [
    "/.git/",           # git storage
    "/build/",          # compiler output
    "/builds/",         # compiler output, plural spelling
    "/nimcache/",       # intermediate C files
    "/.nimble_cache/",  # one copy of every dependency source
    "/dist/",           # bundled javascript output
    "/node_modules/",   # javascript dependencies
    "/submodules/",     # other repositories, pinned here
    "/.otter/"          # scratch space belonging to this tool
  ]
    ## Folders whose contents are not the measured repository's own code.
    ##
    ## Measuring them is worse than useless. A pinned copy of OpenSSL
    ## carries tens of thousands of test vectors that read as leaked keys,
    ## and a nimble cache holds several versions of every dependency at
    ## once, so one routine is counted three times. Both drown the findings
    ## that belong to the repository being measured:
    ##
    ##   with vendored code      without
    ##   ------------------      -------
    ##   106323 secrets          the few that are actually the repo's
    ##   8122 routines           the ones someone here wrote
    ##
    ## The list is matched against a path with one slash forced onto each
    ## end, so "/build/" matches a top-level `build` and a nested one, and
    ## never matches a file merely named `build.nim`.

const
  sourceExts*: array[14, string] = [
    "nim", "c", "h", "cpp", "hpp", "js", "ts",
    "html", "css", "json", "toml", "md", "py", "sh"
  ]
    ## Endings of files a person writes by hand. Everything else is
    ## either compiled output or a document that happens to live in the
    ## tree: a PDF read a line at a time yields long jumbled runs of
    ## bytes that score exactly as a key does, and a vendored RFC is
    ## full of published test vectors and author addresses.

proc normalizeSlashes*(s: string): string {.inline.} =
  result = s.replace('\\', '/')

proc extensionOf*(p: string): string {.inline.} =
  ## p: any path. The ending in lower case and without its dot, or ""
  ## when the name carries none.
  var
    at: int = p.rfind('.')
    slash: int = max(p.rfind('/'), p.rfind('\\'))
  result = ""
  if at > slash and at >= 0 and at < p.len - 1:
    result = p[at + 1 .. ^1].toLowerAscii()


proc isIgnoredPath*(relPath: string, bIncludeTests: bool): bool {.role: parser,
    metaTags: {tagGraph}.} =
  ## relPath: one path below the repository root, either slash style.
  ## bIncludeTests: keep `tests/` when true.
  ## True when the path belongs to something this repository did not write.
  var
    t: string = ""
  t = "/" & normalizeSlashes(relPath).toLowerAscii() & "/"
  for d in vendoredDirs:
    if d in t:
      return true
  if not bIncludeTests and "/tests/" in t:
    return true
  result = false

proc isScannablePath*(relPath: string): bool {.role: parser,
    metaTags: {tagGraph}.} =
  ## relPath: one path below the repository root.
  ## True when the file is this repository's own, and of a kind a person
  ## writes by hand. This is the one question both the folder walk and
  ## the history reader ask, so they answer it the same way.
  result = not isIgnoredPath(relPath, bIncludeTests = true) and
    extensionOf(relPath) in sourceExts


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
  for prefix in ["evaluation/tests/", "evaluation/benchmarks/",
                 "evaluation/statistics/", "src/", "tests/", "tools/"]:
    if p.startsWith(prefix):
      p = p[prefix.len .. ^1]
      break
  result = p


proc readLinesSafe*(filePath: string): seq[string] =
  if not fileExists(filePath):
    result = @[]
    return
  result = readFile(filePath).splitLines()


proc isTestPath*(path: string): bool =
  ## path: one source path. Tests live under a tests folder or are
  ## named for what they are.
  ##
  ## Only the file's own name and the folders right above it are read.
  ## A tree that happens to sit in a folder called `my_test_repo` is
  ## not a tree of tests, and looking for the word anywhere in the path
  ## would say that it is.
  ##
  ## This lives here, at the bottom of the stack, because both the
  ## test scanner and the history reader need it and neither may
  ## import the other.
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


proc isSrcPath*(path: string): bool =
  ## path: one source path. Whether it belongs to the source of the
  ## program rather than to its tests. A file under a `tests` folder
  ## is a test even when that folder sits inside `src`, so the two
  ## answers never both claim the same file.
  var
    p: string = normalizeSlashes(path)
  result = (p.startsWith("src/") or "/src/" in p) and not isTestPath(p)
