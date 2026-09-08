# ============================================================
# | Otter Repo Graph Nim Parser                              |
# | -> Lightweight Nim parser for graph and socket data      |
# ============================================================

import std/[sets, strutils]

import ./io_utils
import ./sample_values
import ./types
import otterPragmas

const
  NimFunctionKinds = [
    "proc",
    "func",
    "method",
    "iterator",
    "template",
    "macro",
    "converter"
  ]
  NimCallStopWords = [
    "if", "elif", "else", "for", "while", "case", "of", "when", "block",
    "let", "var", "const", "type", "proc", "func", "template", "macro",
    "method", "iterator", "converter", "return", "discard", "echo", "defer",
    "do", "try", "except", "finally", "raise", "result", "not", "and", "or"
  ]
  NimUserInputCallHints = [
    "readline",
    "readchar",
    "readpasswordfromstdin",
    "getch",
    "getkey",
    "getkeywithtimeout",
    "commandlineparams",
    "paramstr",
    "recv",
    "recvfrom",
    "recvline",
    "receive",
    "readall"
  ]
  NimUserInputBodyHints = [
    "stdin.read",
    "stdin.readline(",
    "stdin.readchar(",
    "readline(stdin",
    "readlinefromstdin(",
    "readpasswordfromstdin(",
    "commandlineparams(",
    "paramstr(",
    "recv(",
    "recvfrom(",
    "recvline(",
    "receive(",
    "getch(",
    "getkey("
  ]

proc countIndent(s: string): int {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    i: int = 0
  while i < s.len and s[i] == ' ':
    i = i + 1
  result = i


proc trimQuotes(s: string): string {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = s.strip()
  if t.len >= 2 and ((t[0] == '"' and t[^1] == '"') or (t[0] == '\'' and t[^1] == '\'')):
    t = t[1 .. ^2]
  result = t.strip()


proc stripComment(s: string): string {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    i: int = -1
  i = s.find('#')
  if i < 0:
    result = s
    return
  result = s[0 ..< i]


proc commentPayload(s: string): string {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    i: int = -1
  i = s.find('#')
  if i < 0:
    result = ""
    return
  result = s[i + 1 .. ^1].strip()
  while result.startsWith("#"):
    result = result[1 .. ^1].strip()


proc isFunctionStartLine(s: string): bool {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = s.strip()
  if t.len == 0:
    result = false
    return
  if t[0] == '#':
    result = false
    return
  for k in NimFunctionKinds:
    if t.startsWith(k & " ") or t.startsWith(k & "`"):
      result = true
      return


proc detectFunctionKind(s: string): string {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = s.strip()
  for k in NimFunctionKinds:
    if t.startsWith(k & " ") or t.startsWith(k & "`"):
      result = k
      return


proc extractFunctionNameData(line: string): tuple[name: string, isExported: bool] {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
    i: int = 0
    k: string = ""
    j: int = -1
    start: int = 0
  t = line.strip()
  for c in NimFunctionKinds:
    if t.startsWith(c & " ") or t.startsWith(c & "`"):
      k = c
      break
  if k.len == 0:
    return
  i = k.len
  while i < t.len and t[i].isSpaceAscii():
    i = i + 1
  if i >= t.len:
    return
  if t[i] == '`':
    i = i + 1
    j = t.find('`', i)
    if j > i:
      result.name = t[i ..< j]
      if result.name.endsWith("*"):
        result.isExported = true
        result.name = result.name[0 .. ^2]
      return
    return
  start = i
  while i < t.len and (t[i].isAlphaNumeric() or t[i] == '_' or t[i] == '*'):
    i = i + 1
  if i <= start:
    return
  result.name = t[start ..< i]
  if result.name.endsWith("*"):
    result.isExported = true
    result.name = result.name[0 .. ^2]


proc parseHeader(ls: seq[string], iStart: int): tuple[sHeader: string, iEnd: int] {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    i: int = iStart
    baseIndent: int = countIndent(ls[iStart])
    parts: seq[string] = @[]
    raw: string = ""
    t: string = ""
  while i < ls.len:
    raw = ls[i]
    t = stripComment(raw).strip()
    if t.len > 0:
      parts.add(t)
    if t.endsWith("="):
      break
    if i > iStart and t.len == 0:
      break
    if i + 1 >= ls.len:
      break
    if ls[i + 1].strip().len > 0 and countIndent(ls[i + 1]) <= baseIndent and isFunctionStartLine(ls[i + 1]):
      break
    i = i + 1
  result = (parts.join(" "), i)


proc splitTopLevel(s: string, sep: char): seq[string] {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    depthParen: int = 0
    depthBracket: int = 0
    depthBrace: int = 0
    inSingle: bool = false
    inDouble: bool = false
    start: int = 0
    i: int = 0
    part: string = ""
  result = @[]
  while i < s.len:
    if s[i] == '\'' and not inDouble:
      inSingle = not inSingle
    elif s[i] == '"' and not inSingle:
      inDouble = not inDouble
    elif not inSingle and not inDouble:
      case s[i]
      of '(':
        depthParen = depthParen + 1
      of ')':
        depthParen = depthParen - 1
      of '[':
        depthBracket = depthBracket + 1
      of ']':
        depthBracket = depthBracket - 1
      of '{':
        depthBrace = depthBrace + 1
      of '}':
        depthBrace = depthBrace - 1
      else:
        discard
      if s[i] == sep and depthParen == 0 and depthBracket == 0 and depthBrace == 0:
        part = s[start ..< i].strip()
        if part.len > 0:
          result.add(part)
        start = i + 1
    i = i + 1
  part = s[start .. ^1].strip()
  if part.len > 0:
    result.add(part)


proc findTopLevelChar(s: string, target: char): int {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    depthParen: int = 0
    depthBracket: int = 0
    depthBrace: int = 0
    inSingle: bool = false
    inDouble: bool = false
    i: int = 0
  while i < s.len:
    if s[i] == '\'' and not inDouble:
      inSingle = not inSingle
    elif s[i] == '"' and not inSingle:
      inDouble = not inDouble
    elif not inSingle and not inDouble:
      case s[i]
      of '(':
        depthParen = depthParen + 1
      of ')':
        depthParen = depthParen - 1
      of '[':
        depthBracket = depthBracket + 1
      of ']':
        depthBracket = depthBracket - 1
      of '{':
        depthBrace = depthBrace + 1
      of '}':
        depthBrace = depthBrace - 1
      else:
        discard
      if s[i] == target and depthParen == 0 and depthBracket == 0 and depthBrace == 0:
        result = i
        return
    i = i + 1
  result = -1


proc stripPragmaBlocks(s: string): string {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    i: int = 0
    a: int = -1
    b: int = -1
  result = ""
  while i < s.len:
    a = s.find("{.", i)
    if a < 0:
      result.add(s[i .. ^1])
      break
    result.add(s[i ..< a])
    b = s.find(".}", a + 2)
    if b < 0:
      break
    i = b + 2


proc parseReturnType(sHeader, funcName: string): string {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    header: string = ""
    start: int = -1
    i: int = 0
    endIdx: int = -1
  header = stripPragmaBlocks(sHeader)
  if header.endsWith("="):
    header = header[0 .. ^2].strip()
  start = findTopLevelChar(header, ')')
  if start >= 0:
    i = start + 1
  else:
    start = header.find(funcName)
    if start < 0:
      result = ""
      return
    i = start + funcName.len
  while i < header.len and header[i].isSpaceAscii():
    i = i + 1
  if i >= header.len or header[i] != ':':
    result = ""
    return
  i = i + 1
  while i < header.len and header[i].isSpaceAscii():
    i = i + 1
  endIdx = findTopLevelChar(header[i .. ^1], '=')
  if endIdx >= 0:
    result = header[i ..< i + endIdx].strip()
  else:
    result = header[i .. ^1].strip()


proc parseParamSockets(sHeader: string): tuple[params: seq[string], sockets: seq[FunctionSocket]] {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    i0: int = -1
    i1: int = -1
    depth: int = 0
    i: int = 0
    inner: string = ""
    segments: seq[string] = @[]
    pendingNames: seq[string] = @[]
    segment: string = ""
    splitIdx: int = -1
    left: string = ""
    right: string = ""
    names: seq[string] = @[]
    cleanName: string = ""
    cleanType: string = ""
    dir: SocketDirection = sdInput
    eqIdx: int = -1
    socket: FunctionSocket

  proc splitParamSegments(s: string): seq[string] =
    result = @[]
    for part in splitTopLevel(s, ';'):
      for item in splitTopLevel(part, ','):
        if item.strip().len > 0:
          result.add(item.strip())

  i0 = sHeader.find('(')
  result.params = @[]
  result.sockets = @[]
  if i0 < 0:
    return
  i = i0
  while i < sHeader.len:
    if sHeader[i] == '(':
      depth = depth + 1
    elif sHeader[i] == ')':
      depth = depth - 1
      if depth == 0:
        i1 = i
        break
    i = i + 1
  if i1 <= i0 + 1:
    return
  inner = sHeader[i0 + 1 ..< i1]
  segments = splitParamSegments(inner)
  for item in segments:
    segment = item.strip()
    if segment.len == 0:
      continue
    splitIdx = findTopLevelChar(segment, ':')
    if splitIdx < 0:
      pendingNames.add(segment)
      continue
    left = segment[0 ..< splitIdx].strip()
    right = segment[splitIdx + 1 .. ^1].strip()
    names = @[]
    for p in pendingNames:
      if p.strip().len > 0:
        names.add(p.strip())
    pendingNames = @[]
    for p in splitTopLevel(left, ','):
      if p.strip().len > 0:
        names.add(p.strip())
    eqIdx = findTopLevelChar(right, '=')
    if eqIdx >= 0:
      right = right[0 ..< eqIdx].strip()
    cleanType = right
    dir = sdInput
    if cleanType.startsWith("var "):
      dir = sdVarInput
      cleanType = cleanType[4 .. ^1].strip()
    elif cleanType.startsWith("sink "):
      cleanType = cleanType[5 .. ^1].strip()
    elif cleanType.startsWith("lent "):
      cleanType = cleanType[5 .. ^1].strip()
    for rawName in names:
      cleanName = rawName.strip()
      if cleanName.startsWith("var "):
        cleanName = cleanName[4 .. ^1].strip()
      elif cleanName.startsWith("let "):
        cleanName = cleanName[4 .. ^1].strip()
      elif cleanName.startsWith("const "):
        cleanName = cleanName[6 .. ^1].strip()
      if cleanName.endsWith("*"):
        cleanName = cleanName[0 .. ^2]
      if cleanName.len == 0:
        continue
      result.params.add(cleanName)
      socket = default(FunctionSocket)
      socket.name = cleanName
      socket.typeName = cleanType
      socket.direction = dir
      socket.sampleExpr = guessSampleExpr(cleanType)
      result.sockets.add(socket)

proc addRiskTag(f: var FunctionInfo, k, v: string) {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    rk: RiskTag
  rk.key = k.strip()
  rk.value = v.strip()
  if rk.key.len == 0:
    return
  f.riskTags.add(rk)


proc addIssueRef(f: var FunctionInfo, v: string) {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = v.strip()
  if t.len == 0:
    return
  if t notin f.issueRefs:
    f.issueRefs.add(t)


proc addPragmaTag(f: var FunctionInfo, v: string) {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = v.strip().toLowerAscii()
  if t.len == 0:
    return
  if t notin f.pragmaTags:
    f.pragmaTags.add(t)


proc addUserInputSignal(f: var FunctionInfo, v: string) {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = v.strip()
  if t.len == 0:
    return
  if t notin f.userInputSignals:
    f.userInputSignals.add(t)


proc markUserInputDeclared(f: var FunctionInfo, reason: string) {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  f.userInputDeclared = true
  f.handlesUserInput = true
  if reason.len > 0:
    if f.userInputReason.len == 0:
      f.userInputReason = reason
    elif f.userInputReason != reason and reason notin f.userInputReason:
      f.userInputReason = f.userInputReason & "; " & reason


proc parseBoolLike(s: string, bDefault: bool = true): bool {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = s.strip().toLowerAscii()
  if t.len == 0:
    result = bDefault
    return
  if t in ["1", "true", "yes", "on", "y"]:
    result = true
    return
  if t in ["0", "false", "no", "off", "n"]:
    result = false
    return
  result = bDefault


proc parsePragmaToken(tok: string, f: var FunctionInfo) {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
    key: string = ""
    rawValue: string = ""
    kv: seq[string] = @[]
    r: FunctionRole = frUnknown
  t = tok.strip()
  if t.len == 0:
    return
  if ":" notin t:
    key = trimQuotes(t).strip().toLowerAscii()
    if key.len == 0:
      return
    r = parseRole(key)
    if r != frUnknown:
      f.declaredRole = r
      f.role = r
      f.roleConfidence = 1.0
      f.roleReason = "pragma role"
      addPragmaTag(f, "role:" & roleToString(r))
      return
    if key == "user_input" or key == "userinput" or key == "input_handler":
      markUserInputDeclared(f, "pragma user_input")
      addPragmaTag(f, "user_input")
      return
    addPragmaTag(f, key)
    return
  kv = t.split(":", maxsplit = 1)
  if kv.len != 2:
    return
  key = kv[0].strip().toLowerAscii()
  rawValue = trimQuotes(kv[1])
  if key == "role":
    r = parseRole(rawValue)
    if r != frUnknown:
      f.declaredRole = r
      f.role = r
      f.roleConfidence = 1.0
      f.roleReason = "pragma role"
      addPragmaTag(f, "role:" & roleToString(r))
    else:
      addPragmaTag(f, "role:" & rawValue.strip())
  elif key == "risk":
    for item in rawValue.split('|'):
      if item.strip().len > 0:
        addRiskTag(f, item.strip(), "")
        addPragmaTag(f, "risk:" & item.strip().toLowerAscii())
  elif key == "issue" or key == "issueref":
    addIssueRef(f, rawValue)
    addPragmaTag(f, "issue:" & rawValue.toLowerAscii())
  elif key == "tag" or key == "tags":
    addPragmaTag(f, key)
    for item in rawValue.split({'|', ',', ';'}):
      if item.strip().len > 0:
        addPragmaTag(f, item.strip())
  elif key == "user_input" or key == "userinput" or key == "input_handler":
    if parseBoolLike(rawValue, true):
      markUserInputDeclared(f, "pragma user_input")
      addPragmaTag(f, "user_input")
    else:
      addPragmaTag(f, "user_input:false")
  elif key.startsWith("risk_"):
    addRiskTag(f, key, rawValue)
    addPragmaTag(f, key.toLowerAscii() & ":" & rawValue.toLowerAscii())
  elif key.startsWith("tag_"):
    key = key["tag_".len .. ^1]
    if rawValue.len > 0:
      addPragmaTag(f, key & ":" & rawValue)
    else:
      addPragmaTag(f, key)
  else:
    if rawValue.len > 0:
      addPragmaTag(f, key & ":" & rawValue)
    else:
      addPragmaTag(f, key)


proc parsePragmas(sHeader: string, f: var FunctionInfo) {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    i: int = 0
    a: int = -1
    b: int = -1
    body: string = ""
  while true:
    a = sHeader.find("{.", i)
    if a < 0:
      break
    b = sHeader.find(".}", a + 2)
    if b < 0:
      break
    body = sHeader[a + 2 ..< b]
    for token in splitTopLevel(body, ','):
      parsePragmaToken(token, f)
    i = b + 2


proc parseDocTags(ls: seq[string], iStart: int, f: var FunctionInfo) {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    i: int = iStart - 1
    t: string = ""
    v: string = ""
    r: FunctionRole = frUnknown
  while i >= 0:
    t = ls[i].strip()
    if t.len == 0:
      i = i - 1
      continue
    if t.startsWith("## @role"):
      v = t["## @role".len .. ^1].strip()
      r = parseRole(v)
      if r != frUnknown and f.declaredRole == frUnknown:
        f.declaredRole = r
        f.role = r
        f.roleConfidence = 1.0
        f.roleReason = "doc role"
        addPragmaTag(f, "role:" & roleToString(r))
    elif t.startsWith("## @risk"):
      v = t["## @risk".len .. ^1].strip()
      if v.len > 0:
        for s in v.split({'|', ','}):
          if s.strip().len > 0:
            addRiskTag(f, s.strip(), "")
            addPragmaTag(f, "risk:" & s.strip().toLowerAscii())
    elif t.startsWith("## @issue"):
      v = t["## @issue".len .. ^1].strip()
      addIssueRef(f, v)
      addPragmaTag(f, "issue:" & v.toLowerAscii())
    elif t.startsWith("## @tag"):
      v = t["## @tag".len .. ^1].strip()
      if v.len > 0:
        for s in v.split({'|', ',', ';'}):
          if s.strip().len > 0:
            addPragmaTag(f, s.strip())
    elif t.startsWith("## @tags"):
      v = t["## @tags".len .. ^1].strip()
      if v.len > 0:
        for s in v.split({'|', ',', ';'}):
          if s.strip().len > 0:
            addPragmaTag(f, s.strip())
    elif t.startsWith("## @user_input") or t.startsWith("## @input_handler"):
      v = t[t.find('@') + 1 .. ^1]
      v = if " " in v: v.split(' ', maxsplit = 1)[1].strip() else: ""
      if parseBoolLike(v, true):
        markUserInputDeclared(f, "doc user_input")
        addPragmaTag(f, "user_input")
      else:
        addPragmaTag(f, "user_input:false")
    elif t.startsWith("#"):
      discard
    else:
      break
    i = i - 1


proc collectLeadingComments(ls: seq[string], iStart: int): tuple[docLines: seq[string], commentLines: seq[string]] {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    i: int = iStart - 1
    docLines: seq[string] = @[]
    commentLines: seq[string] = @[]
    t: string = ""
    payload: string = ""
  while i >= 0:
    t = ls[i].strip()
    if t.len == 0:
      i = i - 1
      continue
    if not t.startsWith("#"):
      break
    payload = commentPayload(ls[i])
    if ls[i].strip().startsWith("##"):
      docLines.insert(payload, 0)
    else:
      commentLines.insert(payload, 0)
    i = i - 1
  result = (docLines, commentLines)


proc collectInnerComments(bodyLines: seq[string]): seq[string] {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    payload: string = ""
  result = @[]
  for line in bodyLines:
    payload = commentPayload(line)
    if payload.len > 0:
      result.add(payload)


proc buildTooltipText(f: FunctionInfo): string {.role: helper, metaTags: {tagGraph}.} =
  var
    lines: seq[string] = @[]
  lines.add(f.signature)
  if f.docCommentLines.len > 0:
    lines.add("")
    lines.add("Docs:")
    for line in f.docCommentLines:
      lines.add("  " & line)
  if f.leadingCommentLines.len > 0:
    lines.add("")
    lines.add("Comments:")
    for line in f.leadingCommentLines:
      lines.add("  " & line)
  if f.innerCommentLines.len > 0:
    lines.add("")
    lines.add("Inner Notes:")
    for line in f.innerCommentLines:
      lines.add("  " & line)
  result = lines.join("\n")


proc moduleDir(modulePath: string): string {.role: helper, metaTags: {tagGraph, tagImportContext}.} =
  var
    i: int = -1
  i = modulePath.rfind('/')
  if i < 0:
    result = ""
    return
  result = modulePath[0 ..< i]


proc moduleTail(modulePath: string): string {.role: helper, metaTags: {tagGraph, tagImportContext}.} =
  var
    i: int = -1
  i = modulePath.rfind('/')
  if i < 0:
    result = modulePath
    return
  result = modulePath[i + 1 .. ^1]


proc normalizeImportModule(currentModulePath, raw: string): string {.role: helper, metaTags: {tagGraph, tagImportContext}.} =
  var
    t: string = ""
    base: seq[string] = @[]
    token: string = ""
    dir: string = ""
  t = raw.strip()
  if t.len == 0:
    result = ""
    return
  if t.contains("/") or t.contains("\\"):
    t = t.replace('\\', '/')
  else:
    t = t.replace('.', '/')
  if t.endsWith(".nim"):
    t = t[0 .. ^5]
  if t.startsWith("src/") or t.startsWith("tests/") or t.startsWith("tools/") or
      t.startsWith("evaluation/"):
    base = @[]
  else:
    dir = moduleDir(currentModulePath)
    if dir.len > 0:
      base = dir.split('/')
    else:
      base = @[]
  for part in t.split('/'):
    token = part.strip()
    case token
    of "", ".":
      discard
    of "..":
      if base.len > 0:
        base.setLen(base.len - 1)
    else:
      base.add(token)
  result = base.join("/")


proc addImportBinding(bs: var seq[ImportBinding], b: ImportBinding) {.role: helper, metaTags: {tagGraph, tagImportContext}.} =
  for existing in bs:
    if existing.kind == b.kind and
        existing.modulePath == b.modulePath and
        existing.localName == b.localName and
        existing.remoteName == b.remoteName:
      return
  bs.add(b)


proc parseAliasSpec(raw: string): tuple[name: string, alias: string] {.role: parser, metaTags: {tagGraph, tagImportContext}.} =
  var
    parts: seq[string] = @[]
  parts = raw.strip().split(" as ", maxsplit = 1)
  result.name = parts[0].strip()
  if parts.len == 2:
    result.alias = parts[1].strip()


proc parseImportBindings(ls: seq[string], currentModulePath: string): seq[ImportBinding] {.role: parser, metaTags: {tagGraph, tagImportContext}.} =
  var
    line: string = ""
    body: string = ""
    moduleSpec: tuple[name: string, alias: string]
    modulePath: string = ""
    item: string = ""
    symbolSpec: tuple[name: string, alias: string]
    splitIdx: int = -1
  result = @[]
  for raw in ls:
    line = stripComment(raw).strip()
    if line.len == 0:
      continue
    if line.startsWith("import "):
      body = line["import ".len .. ^1].strip()
      if '[' in body or ']' in body:
        continue
      for rawItem in splitTopLevel(body, ','):
        moduleSpec = parseAliasSpec(rawItem)
        modulePath = normalizeImportModule(currentModulePath, moduleSpec.name)
        if modulePath.len == 0:
          continue
        item = if moduleSpec.alias.len > 0: moduleSpec.alias else: moduleTail(modulePath)
        addImportBinding(result, ImportBinding(
          kind: ikModule,
          modulePath: modulePath,
          localName: item,
          remoteName: ""
        ))
    elif line.startsWith("from "):
      body = line["from ".len .. ^1].strip()
      splitIdx = body.find(" import ")
      if splitIdx < 0:
        continue
      modulePath = normalizeImportModule(currentModulePath, body[0 ..< splitIdx].strip())
      if modulePath.len == 0:
        continue
      body = body[splitIdx + " import ".len .. ^1].strip()
      if '[' in body or ']' in body:
        continue
      for rawItem in splitTopLevel(body, ','):
        symbolSpec = parseAliasSpec(rawItem)
        if symbolSpec.name.len == 0:
          continue
        item = if symbolSpec.alias.len > 0: symbolSpec.alias else: symbolSpec.name
        addImportBinding(result, ImportBinding(
          kind: ikSymbol,
          modulePath: modulePath,
          localName: item,
          remoteName: symbolSpec.name
        ))


proc addCall(cs: var seq[string], hs: var HashSet[string], name: string) {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = name.strip()
  if t.len == 0:
    return
  if t.toLowerAscii() in NimCallStopWords:
    return
  if t notin hs:
    hs.incl(t)
    cs.add(t)


proc extractCalls*(bodyLines: seq[string]): seq[string] {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  ## bodyLines: any lines of Nim. Every name written with a bracket
  ## after it. Exported because the diff review reads the lines a
  ## change removed, which belong to no routine at all.
  var
    seen: HashSet[string]
    line: string = ""
    i: int = 0
    i0: int = 0
    j: int = 0
    k: int = 0
    name: string = ""
  result = @[]
  seen = initHashSet[string]()
  for raw in bodyLines:
    line = stripComment(raw)
    i = 0
    while i < line.len:
      if line[i].isAlphaAscii() or line[i] == '_':
        i0 = i
        i = i + 1
        while i < line.len and (line[i].isAlphaNumeric() or line[i] == '_'):
          i = i + 1
        name = line[i0 ..< i]
        j = i
        while j < line.len and line[j].isSpaceAscii():
          j = j + 1
        if j < line.len and line[j] == '(':
          addCall(result, seen, name)
      elif line[i] == '.':
        j = i + 1
        while j < line.len and line[j].isSpaceAscii():
          j = j + 1
        if j < line.len and (line[j].isAlphaAscii() or line[j] == '_'):
          i0 = j
          j = j + 1
          while j < line.len and (line[j].isAlphaNumeric() or line[j] == '_'):
            j = j + 1
          name = line[i0 ..< j]
          k = j
          while k < line.len and line[k].isSpaceAscii():
            k = k + 1
          if k < line.len and line[k] == '(':
            addCall(result, seen, name)
          i = j
        else:
          i = i + 1
      else:
        i = i + 1


proc detectUserInputSignals(calls: seq[string], bodyLines: seq[string]): seq[string] {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    seen: HashSet[string]
    t: string = ""
    lc: string = ""
  result = @[]
  seen = initHashSet[string]()
  for c in calls:
    lc = c.strip().toLowerAscii()
    if lc.len == 0:
      continue
    for hint in NimUserInputCallHints:
      if lc == hint:
        if c notin seen:
          seen.incl(c)
          result.add(c)
        break
  for raw in bodyLines:
    t = stripComment(raw).toLowerAscii().replace(" ", "")
    if t.len == 0:
      continue
    for hint in NimUserInputBodyHints:
      if hint in t:
        if hint notin seen:
          seen.incl(hint)
          result.add(hint)
        break


proc parseFunctionBlock(ls: seq[string], modulePath, sourcePath: string,
    fileBindings: seq[ImportBinding], iStart: int): tuple[ok: bool, f: FunctionInfo,
    iNext: int] {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    f: FunctionInfo
    i: int = 0
    baseIndent: int = 0
    header: tuple[sHeader: string, iEnd: int]
    nameData: tuple[name: string, isExported: bool]
    leading: tuple[docLines: seq[string], commentLines: seq[string]]
    parsedParams: tuple[params: seq[string], sockets: seq[FunctionSocket]]
  if not isFunctionStartLine(ls[iStart]):
    result = (false, f, iStart + 1)
    return
  f = default(FunctionInfo)
  f.modulePath = modulePath
  f.importModulePath = toImportModulePath(modulePath)
  f.sourcePath = normalizeSlashes(sourcePath)
  f.declKind = detectFunctionKind(ls[iStart])
  nameData = extractFunctionNameData(ls[iStart])
  f.name = nameData.name
  f.isExported = nameData.isExported
  if f.name.len == 0:
    result = (false, f, iStart + 1)
    return
  f.lineStart = iStart + 1
  f.declaredRole = frUnknown
  f.role = frUnknown
  f.roleConfidence = 0.0
  f.roleReason = ""
  f.pragmaTags = @[]
  f.riskTags = @[]
  f.issueRefs = @[]
  f.importBindings = fileBindings
  f.userInputDeclared = false
  f.handlesUserInput = false
  f.userInputSignals = @[]
  f.userInputReason = ""
  header = parseHeader(ls, iStart)
  f.signature = header.sHeader
  parsedParams = parseParamSockets(header.sHeader)
  f.params = parsedParams.params
  f.sockets = parsedParams.sockets
  f.returnType = parseReturnType(header.sHeader, f.name)
  if f.returnType.len > 0:
    var
      resultSocket: FunctionSocket
    resultSocket.name = "result"
    resultSocket.typeName = f.returnType
    resultSocket.direction = sdOutput
    resultSocket.sampleExpr = ""
    f.sockets.add(resultSocket)
  leading = collectLeadingComments(ls, iStart)
  f.docCommentLines = leading.docLines
  f.leadingCommentLines = leading.commentLines
  parseDocTags(ls, iStart, f)
  parsePragmas(header.sHeader, f)
  baseIndent = countIndent(ls[iStart])
  i = header.iEnd + 1
  f.bodyLines = @[]
  # A routine's body is what is indented under it. Anything at the
  # routine's own indentation, or further left, has ended it - not
  # only the next routine:
  #
  #   proc stream(n: int): seq[byte] =    <- indent 0, the body opens
  #     result = @[]                      <- indent 2, body
  #                                       <- blank, still body
  #   when isMainModule:                  <- indent 0. NOT this body.
  #     doAssert stream(1).len == 1
  #
  # Reading only the next routine as the end handed every trailing
  # `when isMainModule` block, and every `type` or `const` section
  # written after the last routine of a file, to whoever came last.
  # That routine then appeared to raise, to assert, to nest, and to
  # be far longer than it is, and every count drawn from a body was
  # wrong by however much sat below it.
  while i < ls.len:
    if ls[i].strip().len > 0 and countIndent(ls[i]) <= baseIndent:
      break
    f.bodyLines.add(ls[i])
    i = i + 1
  # Blank lines between the body and whatever follows belong to
  # neither, and counting them would put `lineEnd` past the routine.
  while f.bodyLines.len > 0 and f.bodyLines[^1].strip().len == 0:
    f.bodyLines.setLen(f.bodyLines.len - 1)
    i = i - 1
  f.lineEnd = i
  f.id = f.modulePath & "::" & f.name & ":" & $f.lineStart
  f.calls = extractCalls(f.bodyLines)
  f.innerCommentLines = collectInnerComments(f.bodyLines)
  for signal in detectUserInputSignals(f.calls, f.bodyLines):
    addUserInputSignal(f, signal)
  if f.userInputDeclared:
    f.handlesUserInput = true
    if f.userInputSignals.len > 0:
      f.userInputReason = "declared + io detection: " & f.userInputSignals.join(", ")
    elif f.userInputReason.len == 0:
      f.userInputReason = "declared user_input"
  elif f.userInputSignals.len > 0:
    f.handlesUserInput = true
    f.userInputReason = "io detection: " & f.userInputSignals.join(", ")
  if f.role == frUnknown and f.declaredRole != frUnknown:
    f.role = f.declaredRole
    f.roleConfidence = 1.0
    f.roleReason = "declared role"
  f.tooltipText = buildTooltipText(f)
  result = (true, f, i)


proc parseNimFile*(rootDir, filePath: string): seq[FunctionInfo] {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    lines: seq[string] = @[]
    i: int = 0
    parsed: tuple[ok: bool, f: FunctionInfo, iNext: int]
    modulePath: string = ""
    fileBindings: seq[ImportBinding] = @[]
  result = @[]
  lines = readLinesSafe(filePath)
  if lines.len == 0:
    return
  modulePath = toModulePath(rootDir, filePath)
  fileBindings = parseImportBindings(lines, modulePath)
  while i < lines.len:
    if isFunctionStartLine(lines[i]):
      parsed = parseFunctionBlock(lines, modulePath, filePath, fileBindings, i)
      if parsed.ok:
        result.add(parsed.f)
        if parsed.iNext <= i:
          i = i + 1
        else:
          i = parsed.iNext
        continue
    i = i + 1

proc pragmaNamesIn*(lines: seq[string]): seq[string] {.role: parser,
    metaTags: {tagGraph, tagParsing}.} =
  ## lines: one file.
  ##
  ## Every name written in a pragma anywhere in it. A macro used as a
  ## pragma is applied by name and never called, so without this it
  ## reads as a routine nothing uses:
  ##
  ##   proc withdraw(a, b: int): int {.needs: b <= a.} =
  ##                                   ^^^^^ used here, called nowhere
  ##
  ## Only the leading name of each entry is taken. `{.needs: b <= a.}`
  ## yields `needs`, not `b` - what follows the colon is the argument
  ## and is read as ordinary code elsewhere.
  ##
  ## The whole file is read as one piece rather than a line at a time,
  ## because a pragma is often written across two:
  ##
  ##   proc withdraw(a, b: int): int {.needs: b <= a,
  ##       gives: result >= 0.} =
  ##
  ## Line by line, the opening brace never meets its closing one and
  ## both names are missed - which is how the very macros this was
  ## written for went on reading as dead.
  var
    stripped: seq[string] = @[]
    text: string = ""
    at: int = 0
    close: int = 0
    inside: string = ""
    name: string = ""
    k: int = 0
  result = @[]
  for raw in lines:
    stripped.add(stripComment(raw))
  text = stripped.join("\n")
  block:
    at = 0
    while at < text.len:
      at = text.find("{.", at)
      if at < 0:
        break
      close = text.find(".}", at + 2)
      if close < 0:
        break
      inside = text[at + 2 ..< close]
      at = close + 2
      for piece in inside.split(','):
        name = piece.strip()
        k = 0
        while k < name.len and (name[k].isAlphaNumeric() or name[k] == '_'):
          k = k + 1
        name = name[0 ..< k]
        if name.len > 0 and name notin result:
          result.add(name)

proc topLevelCalls*(lines: seq[string], A: seq[FunctionInfo]): seq[string]
    {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  ## lines: one file   A: the routines declared in it.
  ##
  ## What is called from the parts of the file that belong to no
  ## routine - a `when isMainModule` block, a module-level `var`
  ## initialised by a call, a `static:` section at the foot. A call is
  ## a call whoever makes it, and leaving these out made every routine
  ## only ever called from such a place look like dead weight.
  var
    covered: HashSet[int] = initHashSet[int]()
    rest: seq[string] = @[]
    i: int = 0
  result = @[]
  for f in A:
    i = f.lineStart - 1
    while i < f.lineEnd and i < lines.len:
      covered.incl(i)
      i = i + 1
  i = 0
  while i < lines.len:
    if i notin covered:
      rest.add(lines[i])
    i = i + 1
  result = extractCalls(rest)
