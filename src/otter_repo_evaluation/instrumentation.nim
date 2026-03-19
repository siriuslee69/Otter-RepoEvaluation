# ============================================================
# | Otter Instrumentation                                   |
# | -> Compile-time wrapping for parent-repo routines       |
# ============================================================

import std/macros

import ../../.iron/metaPragmas
import ./state
import ./sigma_bridge

const
  OtterRoutineKinds = {
    nnkProcDef,
    nnkFuncDef,
    nnkMethodDef,
    nnkConverterDef
  }


template otterSpan*(n: string, body: untyped): untyped {.role: helper, metaTags: {tagInstrumentation, tagTiming}.} =
  ## n: function name.
  when OtterTimingEnabled:
    var
      otterStart: int64 = 0
    ensureOtterHook()
    otterStart = otterTick()
    try:
      body
    finally:
      recordTiming(n, otterStart, otterTick())
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


proc otterInstrumentNode(n: NimNode): NimNode {.compileTime, role: helper, metaTags: {tagInstrumentation}.}


proc otterInstrumentRoutine(n: NimNode): NimNode {.compileTime, role: helper, metaTags: {tagInstrumentation}.} =
  var
    r: NimNode
    b: NimNode
    i: int = 0
    s: NimNode
  r = copyNimTree(n)
  i = r.len - 1
  b = otterInstrumentNode(r[i])
  s = newLit(otterRoutineName(n))
  r[i] = quote do:
    otterSpan(`s`):
      `b`
  result = r


proc otterInstrumentNode(n: NimNode): NimNode {.compileTime, role: helper, metaTags: {tagInstrumentation}.} =
  var
    t: NimNode
  if n.kind in OtterRoutineKinds:
    result = otterInstrumentRoutine(n)
    return
  t = copyNimNode(n)
  for c in n:
    t.add(otterInstrumentNode(c))
  result = t


macro otterTimed*(body: untyped): untyped {.role: helper, metaTags: {tagInstrumentation, tagParentIntegration}.} =
  ## body: statement list or single routine definition.
  result = otterInstrumentNode(body)


macro otterInstrument*(body: untyped): untyped {.role: helper, metaTags: {tagInstrumentation, tagParentIntegration}.} =
  ## body: statement list or single routine definition.
  result = otterInstrumentNode(body)
