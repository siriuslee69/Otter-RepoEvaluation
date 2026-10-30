## ============================================================
## | Otter Repo Graph IO Utils                                |
## | -> File discovery and stable path normalization helpers  |
## ============================================================

import std/[algorithm, os, strutils]

import runePragmas

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

proc normalizeSlashes*(s: string): string {.inline, role: helper.} =
  ## s: path text. Replace Windows separators with forward slashes.
  result = s.replace('\\', '/')

proc extensionOf*(p: string): string {.inline, role: parser.} =
  ## p: any path. The ending in lower case and without its dot, or ""
  ## when the name carries none.
  var
    at: int = p.rfind('.')
    slash: int = max(p.rfind('/'), p.rfind('\\'))
  result = ""
  if at > slash and at >= 0 and at < p.len - 1:
    result = p[at + 1 .. ^1].toLowerAscii()


proc isIgnoredPath*(p: string, b: bool): bool {.role: parser,
    tag: "graph".} =
  ## p: one path below the repository root, either slash style.
  ## b: keep `tests/` when true.
  ## True when the path belongs to something this repository did not write.
  var
    t: string = ""
  t = "/" & normalizeSlashes(p).toLowerAscii() & "/"
  for d in vendoredDirs:
    if d in t:
      return true
  if not b and "/tests/" in t:
    return true
  result = false

proc folderStep(dir, d: string, S0: var seq[string],
    S1: var seq[string]) {.role: dataFetcher, tag: "graph".} =
  ## dir: the tree; d: relative folder, "" for the top.
  ## S0: pending folders; S1: collected file paths. Add only non-vendored
  ## sub-folders to S0; `vendoredDirs` are never stepped into.
  for k, p in walkDir(dir / d, relative = true):
    if k == pcDir and not isIgnoredPath(d / p, b = true):
      S0.add(d / p)
    if k == pcFile:
      S1.add(dir / (d / p))

proc ownFiles*(dir: string): seq[string] {.role: dataFetcher,
    tag: "graph".} =
  ## dir: the tree. Every file `walkDirRec(dir)` yields, in the
  ## same order, minus everything inside a vendored folder - which every
  ## caller dropped anyway, one file at a time:
  ##
  ##   Tyr-Crypto   113 000 files under submodules/ and build/
  ##                walkDirRec  looks at all of them, keeps ~1 200
  ##                ownFiles    never opens those two folders
  ##
  ## A folder linked in by a symlink is not followed, as in walkDirRec.
  var
    stack: seq[string] = @[""]
  result = @[]
  while stack.len > 0:
    folderStep(dir, stack.pop(), stack, result)

proc isScannablePath*(p: string): bool {.role: parser,
    tag: "graph".} =
  ## p: one path below the repository root.
  ## True when the file is this repository's own, and of a kind a person
  ## writes by hand. This is the one question both the folder walk and
  ## the history reader ask, so they answer it the same way.
  result = not isIgnoredPath(p, b = true) and
    extensionOf(p) in sourceExts


proc listNimFiles*(dir: string, b: bool = false): seq[string] {.role: dataFetcher.} =
  ## dir: repository root; b: include test folders when true. Paths are sorted.
  var
    rootNormalized: string = ""
    pNormalized: string = ""
    rel: string = ""
    s: string = ""
  result = @[]
  if not dirExists(dir):
    return
  rootNormalized = normalizeSlashes(normalizedPath(dir)).toLowerAscii()
  for p in ownFiles(dir):
    s = normalizeSlashes(p)
    if not s.endsWith(".nim"):
      continue
    pNormalized = normalizeSlashes(normalizedPath(p)).toLowerAscii()
    rel = pNormalized
    if pNormalized.startsWith(rootNormalized):
      rel = pNormalized[rootNormalized.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    if isIgnoredPath(rel, b):
      continue
    result.add(p)
  result.sort(system.cmp[string])


proc toModulePath*(dir, p: string): string {.role: helper.} =
  ## dir: root; p: source path. Return the relative module name without .nim.
  var
    rootNormalized: string = ""
    fileNormalized: string = ""
    t: string = ""
  rootNormalized = normalizeSlashes(normalizedPath(dir))
  fileNormalized = normalizeSlashes(normalizedPath(p))
  t = fileNormalized
  if fileNormalized.startsWith(rootNormalized):
    t = fileNormalized[rootNormalized.len .. ^1]
  if t.startsWith("/"):
    t = t[1 .. ^1]
  if t.endsWith(".nim"):
    t = t[0 .. ^5]
  result = t


proc toImportModulePath*(p: string): string {.role: helper.} =
  ## p: module name. Remove the standard source/evaluation prefix for imports.
  var
    t: string = ""
  t = normalizeSlashes(p)
  for prefix in ["evaluation/tests/", "evaluation/benchmarks/",
                 "evaluation/statistics/", "src/", "tests/", "tools/"]:
    if t.startsWith(prefix):
      t = t[prefix.len .. ^1]
      break
  result = t


proc readLinesSafe*(p: string): seq[string] {.role: dataFetcher.} =
  ## p: file to read. A missing file yields an empty list.
  if not fileExists(p):
    result = @[]
    return
  result = readFile(p).splitLines()


proc isTestPath*(p: string): bool {.role: parser.} =
  ## p: one source path. Tests live under a tests folder or are
  ## named for what they are.
  ##
  ## Match whole folder names, at any fixture depth. A test_ prefix under
  ## src/ alone is not enough: test_scan.nim is part of Otter's library.
  ## A tree that happens to sit in a folder called `my_test_repo` is
  ## not a tree of tests, and looking for the word anywhere in the path
  ## would say that it is.
  ##
  ## This lives here, at the bottom of the stack, because both the
  ## test scanner and the history reader need it and neither may
  ## import the other.
  var
    parts: seq[string] = normalizeSlashes(p).toLowerAscii().split('/')
    i: int = 0
    inSource: bool = false
  result = false
  if parts.len == 0:
    return
  while i < parts.len - 1:
    if parts[i] == "tests" or parts[i] == "test":
      result = true
      return
    if parts[i] == "src":
      inSource = true
    i = i + 1
  result = not inSource and
    (parts[^1].startsWith("test_") or parts[^1].endsWith("_test.nim"))


proc isSrcPath*(p: string): bool {.role: parser.} =
  ## p: one source path. Whether it belongs to the source of the
  ## program rather than to its tests. A file under a `tests` folder
  ## is a test even when that folder sits inside `src`, so the two
  ## answers never both claim the same file.
  var
    t: string = normalizeSlashes(p)
  result = (t.startsWith("src/") or "/src/" in t) and not isTestPath(t)

proc padTo*(s: string, n: int): string {.inline, role: helper.} =
  ## s: any text   n: the width of the column it sits in.
  ## The same text with spaces after it, so that what follows lines
  ## up. Here rather than in each report because three reports wanted
  ## it and three copies of four lines is how a tree starts to rot.
  result = s
  while result.len < n:
    result = result & " "
