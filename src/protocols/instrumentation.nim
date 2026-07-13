# ============================================================
# | Otter Instrumentation                                   |
# | -> Compile-time wrapping for parent-repo routines       |
# ============================================================

import std/macros

import ../../.iron/metaPragmas
import ./state
import ./evaluation/benchmarks

const
  OtterUiTarget* {.strdefine.} = ""
  OtterRoutineKinds = {
    nnkProcDef,
    nnkFuncDef,
    nnkMethodDef,
    nnkConverterDef
  }


template otterSpan*(n: string, p: string, l: int, c: int,
    body: untyped): untyped {.role: helper, metaTags: {tagInstrumentation, tagTiming}.} =
  ## n: function name.
  ## p: source path.
  ## l: source line.
  ## c: source column.
  bind OtterTimingEnabled
  bind OtterDebugEnabled
  bind emitOtterDebug
  bind ensureOtterHook
  bind monotonicTick
  bind recordTiming
  when OtterTimingEnabled or OtterDebugEnabled:
    var
      otterEnd: int64 = 0
      otterStart: int64 = 0
    if OtterTimingEnabled:
      ensureOtterHook()
      otterStart = monotonicTick()
    when OtterDebugEnabled:
      emitOtterDebug("enter", n, p, l, c)
      try:
        body
      except:
        emitOtterDebug("exception", n, p, l, c)
        raise
      finally:
        otterEnd = monotonicTick()
        recordTiming(n, p, l, c, otterStart, otterEnd)
        emitOtterDebug("exit", n, p, l, c, otterStart, otterEnd)
    else:
      try:
        body
      finally:
        otterEnd = monotonicTick()
        recordTiming(n, p, l, c, otterStart, otterEnd)
  else:
    body


proc otterRoutineName(n: NimNode): string {.compileTime, role: helper, metaTags: {tagInstrumentation}.} =
  var
    t: NimNode
    s: string = ""
  t = n[0]
  if t.kind == nnkPostfix and t.len > 1:
    t = t[1]
  s = $t
  result = s


proc otterInstrumentNode(n: NimNode, sourcePath: string = "", lineOffset: int = 0): NimNode {.compileTime, role: helper, metaTags: {tagInstrumentation}.}


proc otterInstrumentRoutine(n: NimNode, sourcePath: string = "", lineOffset: int = 0): NimNode {.compileTime, role: helper, metaTags: {tagInstrumentation}.} =
  var
    info: LineInfo
    r: NimNode
    b: NimNode
    c: NimNode
    i: int = 0
    p: NimNode
    s: NimNode
    l: NimNode
  r = copyNimTree(n)
  info = lineInfoObj(n)
  if sourcePath.len > 0:
    info.filename = sourcePath
    info.line = info.line - lineOffset
    if info.line < 1:
      info.line = 1
  i = r.len - 1
  b = otterInstrumentNode(r[i], sourcePath, lineOffset)
  c = newLit(info.column)
  p = newLit(info.filename)
  s = newLit(otterRoutineName(n))
  l = newLit(info.line)
  r[i] = quote do:
    otterSpan(`s`, `p`, `l`, `c`):
      `b`
  r[i].setLineInfo(info)
  result = r


proc otterInstrumentNode(n: NimNode, sourcePath: string = "",
    lineOffset: int = 0): NimNode {.compileTime, role: helper, metaTags: {tagInstrumentation}.} =
  var
    t: NimNode
  if n.kind in OtterRoutineKinds:
    result = otterInstrumentRoutine(n, sourcePath, lineOffset)
    return
  t = copyNimNode(n)
  for c in n:
    t.add(otterInstrumentNode(c, sourcePath, lineOffset))
  result = t


macro otterTimed*(body: untyped): untyped {.role: helper, metaTags: {tagInstrumentation, tagParentIntegration}.} =
  ## body: statement list or single routine definition.
  result = otterInstrumentNode(body)


macro otterInstrument*(body: untyped): untyped {.role: helper, metaTags: {tagInstrumentation, tagParentIntegration}.} =
  ## body: statement list or single routine definition.
  result = otterInstrumentNode(body)


macro otterBench*(body: untyped): untyped {.role: helper, metaTags: {tagInstrumentation, tagParentIntegration}.} =
  ## body: statement list or single routine definition.
  ## Supports both block-macro use and direct routine pragmas.
  result = otterInstrumentNode(body)


proc otterUiRoutineName(n: NimNode): NimNode {.compileTime, role: helper,
    metaTags: {tagInstrumentation, tagUi}.} =
  ## n: annotated routine whose callable symbol is returned.
  var
    t: NimNode
  t = n[0]
  if t.kind == nnkPostfix and t.len > 1:
    t = t[1]
  result = t


proc validateOtterUiMetadata(n: NimNode) {.compileTime, role: parser,
    metaTags: {tagInstrumentation, tagUi}.} =
  ## n: literal four-string tuple or array attached to an UI test.
  if n.kind notin {nnkTupleConstr, nnkBracket}:
    error("otterUiTest expects (test name, menu, filters, version)", n)
  if n.len != 4:
    error("otterUiTest metadata must contain exactly four strings", n)
  for item in n:
    if item.kind notin {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
      error("otterUiTest metadata values must be string literals", item)


macro otterUiTest*(metadata: untyped, body: untyped): untyped
    {.role: helper, metaTags: {tagInstrumentation, tagParentIntegration, tagUi}.} =
  ## metadata: test name, menu point, comma-separated filters, and version label.
  ## body: zero-argument routine compiled and called by the isolated UI worker.
  var
    routineName: NimNode
    params: NimNode
  validateOtterUiMetadata(metadata)
  if body.kind notin OtterRoutineKinds:
    error("otterUiTest can only annotate a proc, func, method, or converter", body)
  params = body[3]
  if params.len != 1:
    error("otterUiTest routines must not accept parameters", params)
  routineName = otterUiRoutineName(body)
  result = quote do:
    `body`
    when isMainModule and OtterUiTarget == astToStr(`routineName`):
      `routineName`()
      quit(programResult)


macro otterWrapFile*(p: static[string], lineOffset: static[int],
    body: untyped): untyped {.role: helper, metaTags: {tagInstrumentation, tagParentIntegration}.} =
  ## p: original source path for debug output.
  ## lineOffset: wrapper header line count added before the original file.
  ## body: original source body to instrument.
  result = otterInstrumentNode(body, p, lineOffset)
