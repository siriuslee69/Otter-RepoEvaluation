# ============================================================
# | Otter Repo Graph Sample Values                           |
# | -> Best-effort sample expressions for function sockets   |
# ============================================================

import std/[strutils]

import runePragmas

proc cleanTypeName*(s: string): string {.role: helper, tag: "graph|execution".} =
  var
    t: string = ""
  t = s.strip()
  while t.startsWith("var "):
    t = t[4 .. ^1].strip()
  while t.startsWith("sink "):
    t = t[5 .. ^1].strip()
  while t.startsWith("lent "):
    t = t[5 .. ^1].strip()
  result = t


proc genericInnerType(s: string): string {.role: helper, tag: "graph|execution".} =
  var
    a: int = -1
    b: int = -1
  a = s.find('[')
  b = s.rfind(']')
  if a < 0 or b <= a:
    result = ""
    return
  result = s[a + 1 ..< b].strip()


proc guessSampleExpr*(typeName: string): string {.role: helper, tag: "graph|execution".} =
  var
    raw: string = ""
    t: string = ""
    inner: string = ""
  raw = cleanTypeName(typeName)
  t = raw.toLowerAscii().replace(" ", "")
  if t.len == 0:
    result = ""
    return
  if t in ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16",
      "uint32", "uint64", "byte", "cint", "cuint", "clong", "culong", "csize_t"]:
    result = "42"
    return
  if t in ["float", "float32", "float64", "cfloat", "cdouble"]:
    result = "3.14"
    return
  if t == "bool":
    result = "true"
    return
  if t == "string" or t == "cstring":
    result = "\"sample\""
    return
  if t == "char":
    result = "'x'"
    return
  if t == "jsonnode":
    result = "%*{\"sample\": true}"
    return
  if t.startsWith("seq[") or t.startsWith("openarray["):
    inner = genericInnerType(raw)
    if inner.len == 0:
      result = "@[]"
      return
    result = "@[" & guessSampleExpr(inner) & "]"
    return
  if t.startsWith("array["):
    result = "default(" & raw & ")"
    return
  if t.startsWith("set["):
    result = "{}"
    return
  if t.startsWith("option["):
    inner = genericInnerType(raw)
    if inner.len == 0:
      result = "none(int)"
      return
    result = "some(" & guessSampleExpr(inner) & ")"
    return
  if t.startsWith("table[") or t.startsWith("orderedtable["):
    result = "initTable[" & genericInnerType(raw) & "]()"
    return
  if t.startsWith("ref ") or t.startsWith("ptr "):
    result = "nil"
    return
  result = "default(" & raw & ")"
