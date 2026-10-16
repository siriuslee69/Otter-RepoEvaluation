## ==================================================================
## | trace_run.nim  <-  `otter trace`: run one test with every routine |
## |                    of the project traced                         |
## |----------------------------------------------------------------|
## |  <parent>/<repo>/                  the project (never changed)    |
## |  <parent>/<repo>__otter_trace/     the traced copy:               |
## |     src/  evaluation/  tests/      copied, every src module wrapped|
## |     every top-level file, configs/ copied (a linked test file     |
## |                                    would import the ORIGINAL src) |
## |     everything else                linked to the original (read)  |
## |     .otter-trace-copy              marker: the only kind of folder |
## |                                    trace ever deletes             |
## |                                                                  |
## |  A wrapped module:                                               |
## |     import otter_trace_runtime                                    |
## |     otterTraceFile("src/x.nim", 2):                              |
## |       <the original module, indented>                            |
## |                                                                  |
## |  The copy sits BESIDE the project so "../Sibling" paths in its    |
## |  config still resolve. The test is built with -d:otterTrace and   |
## |  Otter's src on the path; its output (test lines and [trace]      |
## |  lines, in order) is what `otter trace` prints.                   |
## ==================================================================

import std/[os, osproc, strutils]
import ./fylgia_threads
import runePragmas

const
  marker: string = ".otter-trace-copy"
  suffix: string = "__otter_trace"
  copied: array[5, string] = ["src", "evaluation", "tests", "configs", "tools"]
  headerLines: int = 2

proc traceCopyPath*(repo: string): string {.role: helper, tag: "tracing".} =
  ## repo <- project folder; its traced copy beside it.
  var
    r: string = normalizedPath(absolutePath(repo))
  result = r.parentDir / (r.lastPathPart & suffix)

proc removeTraceCopy*(dir: string) {.role: actor, risk: rkHigh, tag: "tracing".} =
  ## Deletes dir only when it is a trace copy: named *__otter_trace AND
  ## holding the marker file. Links inside are removed, never followed.
  if not dir.lastPathPart.endsWith(suffix) or not fileExists(dir / marker):
    if dirExists(dir):
      raise newException(IOError, "refusing to delete " & dir & ": not a trace copy")
    return
  removeDir(dir)

proc wrapModule(path, rel: string) {.role: dataWriter, tag: "tracing".} =
  ## path <- a copied .nim file   rel <- its path in the project (for marks)
  var
    s: string = readFile(path)
  writeFile(path, "import otter_trace_runtime\notterTraceFile(\"" & rel & "\", " &
    $headerLines & "):\n" & s.indent(2))

proc wrapTree(copy: string) {.role: orchestrator, tag: "tracing".} =
  ## Every .nim under copy/src gets wrapped.
  for f in walkDirRec(copy / "src", yieldFilter = {pcFile}):
    if f.endsWith(".nim"):
      wrapModule(f, f.relativePath(copy))

proc linkOrCopy(repo, copy: string, k: PathComponent, name: string)
    {.role: actor, tag: "tracing".} =
  ## One top-level entry: small editable parts copied, the rest linked.
  ## Files are always copied: a LINKED test file makes Nim resolve its
  ## imports from the original folder, so the untraced code gets built.
  var
    small: bool = name in copied or k in {pcFile, pcLinkToFile}
  if name == ".git" or name.endsWith(suffix):
    return
  if small and k == pcDir:
    copyDir(repo / name, copy / name)
  elif small:
    copyFile(repo / name, copy / name)
  else:
    createSymlink(repo / name, copy / name)

proc makeTraceCopy*(repo: string): string {.role: orchestrator, risk: rkMedium,
    tag: "tracing".} =
  ## repo <- project folder; builds (or rebuilds) its traced copy.
  var
    r: string = normalizedPath(absolutePath(repo))
  result = traceCopyPath(r)
  removeTraceCopy(result)
  createDir(result)
  writeFile(result / marker, "made by otter trace; safe to delete\n")
  for k, p in walkDir(r, relative = true):
    linkOrCopy(r, result, k, p)
  if dirExists(result / "src"):
    wrapTree(result)

proc runTrace*(repo, test, otterSrc: string, timeoutSec = 600, keep = false):
    (string, int) {.role: metaOrchestrator, risk: rkMedium, speed: spLong,
    tag: "tracing".} =
  ## repo <- project   test <- test file, relative to the project
  ## otterSrc <- Otter's src folder (holds otter_trace_runtime.nim)
  ## Returns the test's output with the trace lines, and its exit code.
  var
    copy: string = makeTraceCopy(repo)
    cmd: string = "timeout -k 5 " & $timeoutSec & " nim c -r --hints:off -d:otterTrace" &
      " --path:" & quoteShell(otterSrc) & " --nimcache:" &
      quoteShell(copy / "build" / "otter_trace_cache") & " -o:" &
      quoteShell(copy / "build" / "otter_trace_test") & " " & quoteShell(copy / test)
  result = execCmdShared(cmd, workingDir = copy)
  if not keep:
    removeTraceCopy(copy)
