## ==================================================================
## | tracing.nim  <-  every call, with its arguments and its result    |
## |----------------------------------------------------------------|
## | Built for `otter trace` (and for small models debugging through  |
## | Draupnir): when a test fails, run it once with every routine of  |
## | the project wrapped, and read where the values go wrong.         |
## |                                                                  |
## |   [trace] > polyvecBaseMulAccMontgomeryCached  p=(k: 3, ...)      |
## |   [trace]   > baseMulCachedTermsChunk8  ...                       |
## |   [trace]   < baseMulCachedTermsChunk8                           |
## |   [trace] < polyvecBaseMulAccMontgomeryCached  r=(coeffs: [1737, ..|
## |   [trace] ! decodeRle raised: rle run length must be > 0          |
## |                                                                  |
## | Rules the wrapping follows, each for a reason:                   |
## |  - only built with -d:otterTrace; otherwise the macro returns the  |
## |    code unchanged                                                |
## |  - the trace calls sit in a cast(noSideEffect) + cast(gcsafe)     |
## |    block, so func / noSideEffect / thread code still compiles    |
## |  - try/finally, never except: a {.raises: [].} routine may not    |
## |    re-raise, but finally adds no raise effect                    |
## |  - a value that cannot be printed shows its type name            |
## |  - the first `perRoutine` calls of each routine are shown; after  |
## |    that they are only counted (a per-coefficient helper would     |
## |    otherwise print 256 lines per call)                           |
## |  - routines run at compile time (const tables) are not traced:   |
## |    `when nimvm` skips the trace calls there                      |
## |  - templates, macros, iterators and routines without a body are   |
## |    left alone                                                    |
## ==================================================================

import std/[algorithm, macros, sequtils, strutils, tables]
import runePragmas

const
  OtterTraceEnabled* {.role: helper.} = defined(otterTrace)
  perRoutine: int = 8      ## calls shown per routine before only counting
  maxEvents: int = 4000    ## lines in all, so a hot loop cannot flood the log
  maxValue: int = 120      ## characters per shown value

var
  traceDepth: int = 0
  traceEvents: int = 0
  traceCalls: Table[string, int] = initTable[string, int]()

proc otterShow*[T](x: T): string {.role: helper, tag: "tracing", raises: [].} =
  ## x: any value; a short one-line text, or its type name.
  ## Never raises: tracing must not add a way for the traced code to fail.
  result = "<" & $typeof(x) & ">"
  when compiles($x):
    try:
      result = ($x).replace("\n", "\\n")
    except CatchableError:
      discard
  if result.len > maxValue:
    result = result[0 ..< maxValue] & "..."

proc traceLine(mark, name, rest: string) {.role: dataWriter, tag: "tracing",
    raises: [].} =
  ## mark: ">" enter, "<" exit, "!" raised.
  if traceEvents >= maxEvents:
    return
  inc traceEvents
  try:
    stderr.writeLine("[trace] " & spaces(2 * max(0, traceDepth)) & mark & " " &
    name & (if rest.len > 0: "  " & rest else: ""))
  except CatchableError:
    discard

proc otterTraceEnter*(name, loc: string, A: openArray[(string, string)]): bool
    {.role: actor, tag: "tracing", raises: [].} =
  ## Returns whether this call is shown (the exit must match it).
  var
    parts: seq[string] = @[]
  traceCalls.mgetOrPut(name, 0) += 1
  result = traceCalls.getOrDefault(name, 0) <= perRoutine
  if result:
    for (k, v) in A:
      parts.add(k & "=" & v)
    traceLine(">", name, parts.join(" ") & "  @" & loc)
  inc traceDepth

proc otterTraceExit*(name: string, shown: bool, res: string, failed: string,
    V: openArray[(string, string)]) {.role: actor, tag: "tracing", raises: [].} =
  ## res: the result shown ("" when none); failed: exception message or "".
  ## V: var parameters as they are when the routine leaves (its outputs).
  var
    parts: seq[string] = @[]
  dec traceDepth
  if failed.len > 0:
    traceLine("!", name, "raised: " & failed)
    return
  if not shown:
    return
  for (k, v) in V:
    parts.add(k & "=" & v)
  traceLine("<", name, (if res.len > 0: res & "  " else: "") & parts.join(" "))

proc otterTraceSummary*() {.role: dataWriter, tag: "tracing".} =
  ## How often each routine was called, most first; call at program end.
  var
    L: seq[(int, string)] = @[]
  for k, v in traceCalls:
    L.add((v, k))
  L.sort(proc(a, b: (int, string)): int = cmp(b[0], a[0]))
  stderr.writeLine("[trace] calls: " & L[0 ..< min(L.len, 25)].mapIt(
    it[1] & " x" & $it[0]).join(", "))

# ------------------------------------------------------------ the wrapping

proc showPair(n: NimNode): NimNode {.compileTime, role: parser, tag: "tracing".} =
  ## ("name", otterShow(name)); an empty node for "_", which cannot be read.
  var
    s: string = (if n.kind == nnkPragmaExpr: n[0].strVal else: n.strVal)
  if s == "_":
    return newEmptyNode()
  result = nnkTupleConstr.newTree(newLit(s), newCall(bindSym"otterShow", ident(s)))

proc dropEmpty(B: NimNode): NimNode {.compileTime, role: parser, tag: "tracing".} =
  ## B without the empty entries; an empty list when nothing is left.
  result = nnkBracket.newTree()
  for x in B:
    if x.kind != nnkEmpty:
      result.add(x)
  if result.len == 0:
    result = parseExpr("newSeq[(string, string)]()")

proc paramPairs(params: NimNode): NimNode {.compileTime, role: parser,
    tag: "tracing".} =
  ## [("a", otterShow(a)), ...] for every named parameter.
  var
    k: int = 1
  result = nnkBracket.newTree()
  while k < params.len:
    for n in params[k][0 ..< params[k].len - 2]:
      result.add(showPair(n))
    inc k
  result = dropEmpty(result)

proc varPairs(params: NimNode): NimNode {.compileTime, role: parser,
    tag: "tracing".} =
  ## [("r", otterShow(r)), ...] for the var parameters only: their values on
  ## the way out are what the routine produced.
  var
    k: int = 1
  result = nnkBracket.newTree()
  while k < params.len:
    if params[k][^2].kind == nnkVarTy:
      for n in params[k][0 ..< params[k].len - 2]:
        result.add(showPair(n))
    inc k
  result = dropEmpty(result)

proc hasBody(n: NimNode): bool {.compileTime, role: parser, tag: "tracing".} =
  result = n.body.kind != nnkEmpty

proc returnsValue(n: NimNode): bool {.compileTime, role: parser, tag: "tracing".} =
  ## A plain return type (not void, var or lent) whose `result` can be shown.
  var
    r: NimNode = n.params[0]
  result = r.kind != nnkEmpty and not (r.kind == nnkIdent and r.strVal == "void") and
    r.kind notin {nnkVarTy} and not (r.kind == nnkCommand and r[0].eqIdent("lent"))

proc skipPragma(n: NimNode): bool {.compileTime, role: parser, tag: "tracing".} =
  ## compileTime, importc and the like cannot or need not be traced.
  result = false
  for p in n.pragma:
    if p.kind in {nnkIdent, nnkSym} and p.strVal in ["compileTime", "importc",
        "importcpp", "exportc", "noreturn", "asmNoStackFrame", "error"]:
      return true

proc traceRoutine(n: NimNode, loc: string): NimNode {.compileTime, role: truthBuilder,
    tag: "tracing".} =
  ## n: one proc/func/method/converter; its body wrapped with enter/exit.
  var
    name: NimNode = newLit(n.name.repr)
    body: NimNode = n.body
    shown: NimNode = genSym(nskVar, "otterShown")
    res: NimNode = if returnsValue(n): newCall(bindSym"otterShow", ident"result") else: newLit("")
    args: NimNode = paramPairs(n.params)
    outs: NimNode = varPairs(n.params)
    L: NimNode = newLit(loc)
  result = copyNimTree(n)
  result.body = quote do:
    var `shown` = block:
      when nimvm:
        false                      # at compile time (const tables): not traced
      else:
        {.cast(noSideEffect), cast(gcsafe).}:
          otterTraceEnter(`name`, `L`, `args`)
    var otterFailed: string = ""
    try:
      `body`
    finally:
      when nimvm:
        discard
      else:
        {.cast(noSideEffect), cast(gcsafe).}:
          if getCurrentException() != nil:
            otterFailed = getCurrentExceptionMsg()
          otterTraceExit(`name`, `shown`, (if otterFailed.len == 0: `res` else: ""),
            otterFailed, `outs`)

proc traceNode(n: NimNode, file: string, lineOffset: int): NimNode {.compileTime,
    role: orchestrator, tag: "tracing".} =
  ## Walks a module body; routines with a body get wrapped.
  var
    loc: string = ""
  if n.kind in {nnkProcDef, nnkFuncDef, nnkMethodDef, nnkConverterDef} and
      hasBody(n) and not skipPragma(n):
    loc = file & ":" & $(max(1, n.lineInfoObj.line - lineOffset))
    return traceRoutine(n, loc)
  result = copyNimNode(n)
  for c in n:
    result.add(traceNode(c, file, lineOffset))

macro otterTraceFile*(file: static[string], lineOffset: static[int],
    body: untyped): untyped {.role: helper, tag: "tracing|parentIntegration".} =
  ## file: the original path, for the "@src/x.nim:12" marks.
  ## lineOffset: lines the wrapper added above the original source.
  ## body: the whole original module.
  when OtterTraceEnabled:
    result = traceNode(body, file, lineOffset)
  else:
    result = body
