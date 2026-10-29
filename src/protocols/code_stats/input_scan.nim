## Input scans <- declared input handlers and unsafe-operation candidates.
## Each pass turns one file or one parsed routine into report rows.
## Input reach here means a direct handler; it does not follow the call graph.

import std/[os, sets, strutils]
import runePragmas
import ./types
import ./pipeline
import ../repo_graph/io_utils
import ../repo_graph/types as graphTypes

type
  InputScan = tuple[inputs: seq[InputFuncInfo], inputCount, sanitizerCount: int]

proc addInput(S: var InputScan, p, n, e: string, l: int, bInput, bSan: bool)
    {.role: actor, inline.} =
  ## S: report; p: path; n: name; e: language; l: line; booleans: roles found.
  if not bInput and not bSan:
    return
  if bInput: inc S.inputCount
  if bSan: inc S.sanitizerCount
  S.inputs.add(InputFuncInfo(name: n, path: p, line: l, lang: e,
    role: if bSan: "sanitizer" else: "input",
    inputSource: if bSan: "sanitizer" else: "user/network",
    sanitizerName: if bSan: n else: ""))

proc scanNimInput(S: var InputScan, dir: string, f: FunctionInfo)
    {.role: actor, inline.} =
  ## S: report; dir: root; f: parsed Nim routine with its own pragmas.
  var
    r: string = declaredRoleOf(f)
    p: string = normalizeSlashes(relativePath(f.sourcePath, dir))
  addInput(S, p, f.name, "nim", f.lineStart,
    f.handlesUserInput or r == "data fetcher" or r == "input", r == "sanitizer")

proc foreignName(s: string): string {.role: parser.} =
  ## s: declaration after a comment pragma. Best-effort name for C/JS/TS.
  result = "anonymous"
  for p in s.strip().split({' ', '(', '{', ':'}):
    if p.len > 0 and p notin ["function", "async", "void", "int", "char",
        "const", "static", "proc", "fn"]:
      return p

proc scanForeignInput(S: var InputScan, p, e: string, L: seq[string], i: int)
    {.role: actor, inline.} =
  ## S: report; p/e: path and language; L: lines; i: comment pragma index.
  var
    s: string = L[i]
    n: string = "anonymous"
  if "{.role:" notin s and "{.input:" notin s:
    return
  s = s.toLowerAscii()
  if i + 1 < L.len:
    n = foreignName(L[i + 1])
  addInput(S, p, n, e, i + 1,
    "datafetcher" in s or "input" in s or "user" in s, "sanitizer" in s)

proc scanForeignFile(S: var InputScan, dir, p: string) {.role: actor.} =
  ## S: report; dir: root; p: one C, JS, or TS file.
  var
    e: string = extensionOf(p)
    r: string = normalizeSlashes(relativePath(p, dir))
    L: seq[string] = @[]
    i: int = 0
  if e notin ["c", "js", "ts"]:
    return
  L = readLinesSafe(p)
  while i < L.len:
    scanForeignInput(S, r, e, L, i)
    inc i

proc scanInputDetailsAndSanitizers*(dir: string, P: seq[string],
    F: seq[FunctionInfo]): InputScan {.role: truthBuilder.} =
  ## dir: root; P: source files; F: parsed Nim routines.
  result = (@[], 0, 0)
  for f in F:
    scanNimInput(result, dir, f)
  for p in P:
    scanForeignFile(result, dir, p)

proc unsafeKind(s, e: string): string {.role: parser, inline.} =
  ## s: source line; e: extension. A candidate operation, or an empty string.
  result = ""
  case e
  of "nim", "nims":
    if "cast[" in s: return "cast"
    if "addr(" in s or "unsafeAddr(" in s: return "addr"
    if "UncheckedArray[" in s or "uncheckedArray" in s: return "uncheckedArray"
    if "alloc(" in s or "dealloc(" in s: return "alloc"
    if "copyMem(" in s: return "copyMem"
  of "c", "cpp", "h":
    if "malloc(" in s or "free(" in s: return "malloc"
    if "memcpy(" in s or "strcpy(" in s: return "memcpy"
    if "(void*)" in s or "cast" in s: return "pointerCast"
  else: discard

proc ownerName(F: seq[FunctionInfo], p: string, n: int): string {.role: parser.} =
  ## F: routines; p: full path; n: source line. Fall back to the file name.
  result = extractFilename(p)
  for f in F:
    if f.sourcePath == p and n >= f.lineStart and n <= f.lineEnd:
      return f.name

proc unsafeFile(dir, p: string, F: seq[FunctionInfo], I: HashSet[string]):
    seq[UnsafeFuncInfo] {.role: truthBuilder.} =
  ## dir/p: root and file; F: routines; I: direct input handlers by path/name.
  var
    r: string = normalizeSlashes(relativePath(p, dir))
    e: string = extensionOf(p)
    k: string = ""
    n: int = 0
    f: string = ""
    bInput: bool = false
  result = @[]
  for s in readLinesSafe(p):
    inc n
    k = unsafeKind(s, e)
    if k.len == 0:
      continue
    f = ownerName(F, p, n)
    bInput = r & "::" & f.toLowerAscii() in I
    result.add(UnsafeFuncInfo(name: f, path: r, line: n, lang: e, kind: k,
      touchesExternalData: bInput,
      externalDataTrace: (if bInput: "Direct input handler: " else: "Internal function: ") & f))

proc scanUnsafeDetails*(dir: string, P: seq[string], F: seq[FunctionInfo],
    I: seq[InputFuncInfo]): seq[UnsafeFuncInfo] {.role: truthBuilder.} =
  ## dir: root; P: files; F: routines; I: input findings from the earlier pass.
  var
    names: HashSet[string] = initHashSet[string]()
  for i in I:
    names.incl(i.path & "::" & i.name.toLowerAscii())
  result = @[]
  for p in P:
    result.add(unsafeFile(dir, p, F, names))
