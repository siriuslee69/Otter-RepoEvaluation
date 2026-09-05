# ============================================================
# | Otter Test UI Catalog                                    |
# | -> Discover annotated zero-argument routines in tests    |
# ============================================================

import std/[algorithm, os, sets, strutils]

import ../../../meta/metaPragmas
import ./[config, types]

const
  ImplicitFlags = [
    "aarch64", "amd64", "android", "arm", "arm64", "debug", "danger",
    "dragonfly", "emscripten", "freebsd", "haiku", "i386", "ios", "js",
    "linux", "macosx", "netbsd", "nimvm", "openbsd", "posix", "release",
    "solaris", "threads", "unix", "wasm", "wasm32", "windows"
  ]

when defined(amd64) or defined(i386):
  proc cpuid(eaxInput, ecxInput: int32): array[4, int32] {.role: dataFetcher,
      metaTags: {tagParsing, tagTesting, tagUi}.} =
    ## eaxInput/ecxInput: CPUID leaf and subleaf queried on the host CPU.
    when defined(vcc):
      proc cpuidEx(cpuInfo: ptr int32, functionId, subFunctionId: int32)
          {.cdecl, importc: "__cpuidex", header: "intrin.h".}
      cpuidEx(cast[ptr int32](result.addr), eaxInput, ecxInput)
    else:
      var
        eaxResult, ebxResult, ecxResult, edxResult: int32 = 0
      asm """
        cpuid
        :"=a"(`eaxResult`), "=b"(`ebxResult`), "=c"(`ecxResult`), "=d"(`edxResult`)
        :"a"(`eaxInput`), "c"(`ecxInput`)"""
      result = [eaxResult, ebxResult, ecxResult, edxResult]

  proc xgetbv(): uint64 {.role: dataFetcher,
      metaTags: {tagParsing, tagTesting, tagUi}.} =
    ## Returns XCR0 so AVX defaults are enabled only when the OS saves YMM state.
    when defined(vcc):
      proc readXcr(register: uint32): uint64
          {.cdecl, importc: "_xgetbv", header: "immintrin.h".}
      result = readXcr(0)
    else:
      var
        eaxResult, edxResult: uint32 = 0
      asm """
        xgetbv
        :"=a"(`eaxResult`), "=d"(`edxResult`)
        :"c"(0)"""
      result = (uint64(edxResult) shl 32) or uint64(eaxResult)

  proc x86Feature(flag: string): bool {.role: parser,
      metaTags: {tagParsing, tagTesting, tagUi}.} =
    ## flag: x86 SIMD/AES feature checked directly through CPUID.
    var
      leaf0, leaf1, leaf7: array[4, int32]
      avxState: bool = false
    leaf0 = cpuid(0, 0)
    leaf1 = cpuid(1, 0)
    if flag == "sse2":
      return (leaf1[3] and (1'i32 shl 26)) != 0
    if flag == "aesni":
      return (leaf1[2] and (1'i32 shl 25)) != 0
    if flag != "avx2" or leaf0[0] < 7:
      return false
    avxState = (leaf1[2] and (1'i32 shl 27)) != 0 and
      (leaf1[2] and (1'i32 shl 28)) != 0
    if not avxState or (xgetbv() and 0x6'u64) != 0x6'u64:
      return false
    leaf7 = cpuid(7, 0)
    result = (leaf7[1] and (1'i32 shl 5)) != 0

proc isIdentifierChar(c: char): bool {.inline, role: helper,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## c: character checked for a Nim identifier position.
  result = c.isAlphaNumeric() or c == '_'

proc quotedValues(s: string, startAt: int): seq[string]
    {.role: parser, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## s/startAt: source and pragma position from which four strings are read.
  var
    i: int = startAt
    quote: char = '\0'
    value: string = ""
    escaped: bool = false
  while i < s.len and result.len < 4:
    if quote == '\0' and s[i] in {'"', '\''}:
      quote = s[i]
      value = ""
      escaped = false
    elif quote != '\0' and escaped:
      value.add(s[i])
      escaped = false
    elif quote != '\0' and s[i] == '\\':
      escaped = true
    elif quote != '\0' and s[i] == quote:
      result.add(value)
      quote = '\0'
    elif quote != '\0':
      value.add(s[i])
    elif s[i] == '}':
      break
    i = i + 1

proc previousRoutineName(s: string, pragmaAt: int): string
    {.role: parser, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## s/pragmaAt: source and pragma offset whose owner routine is located.
  const
    Keywords = ["proc", "func", "method", "converter"]
  var
    best: int = -1
    position: int = -1
    startAt: int = 0
    stopAt: int = 0
  for keyword in Keywords:
    position = s.rfind(keyword, 0, pragmaAt)
    if position > best:
      best = position
      startAt = position + keyword.len
  if best < 0:
    return
  while startAt < pragmaAt and s[startAt].isSpaceAscii():
    startAt = startAt + 1
  if startAt < pragmaAt and s[startAt] == '`':
    startAt = startAt + 1
  stopAt = startAt
  while stopAt < pragmaAt and isIdentifierChar(s[stopAt]):
    stopAt = stopAt + 1
  if stopAt > startAt:
    result = s[startAt ..< stopAt]

proc normalizedFilters(s: string): seq[string]
    {.role: parser, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## s: comma-separated filter labels from pragma metadata.
  var
    value: string = ""
  for item in s.split(','):
    value = item.strip()
    if value.len > 0 and value notin result:
      result.add(value)

proc normalizedVersion(s: string): string {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## s: version label normalized for standard native and wasm target tabs.
  if s.toLowerAscii() in ["native", "wasm"]:
    result = s.toLowerAscii()
  else:
    result = s

proc implicitFlag(name: string): bool {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## name: defined symbol checked against compiler and target built-ins.
  var
    normalized: string = name.toLowerAscii()
    i: int = 0
  while i < ImplicitFlags.len:
    if normalized == ImplicitFlags[i]:
      return true
    i = i + 1

proc appendDefinedFlags(F: var HashSet[string], line: string)
    {.role: parser, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## F/line: discovered optional symbols and one compile-time condition line.
  var
    searchAt: int = 0
    markerAt: int = 0
    startAt: int = 0
    stopAt: int = 0
    name: string = ""
  while searchAt < line.len:
    markerAt = line.find("defined", searchAt)
    if markerAt < 0:
      break
    startAt = markerAt + "defined".len
    while startAt < line.len and line[startAt].isSpaceAscii():
      startAt = startAt + 1
    if startAt < line.len and line[startAt] == '(':
      startAt = startAt + 1
    while startAt < line.len and line[startAt].isSpaceAscii():
      startAt = startAt + 1
    stopAt = startAt
    while stopAt < line.len and isIdentifierChar(line[stopAt]):
      stopAt = stopAt + 1
    if stopAt > startAt:
      name = line[startAt ..< stopAt]
      if not implicitFlag(name):
        F.incl(name)
    searchAt = max(stopAt, markerAt + "defined".len)

proc appendSourceFlags(F: var HashSet[string], sourcePath: string)
    {.role: parser, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## F/sourcePath: optional symbols collected from Nim when/elif conditions.
  var
    clean: string = ""
    conditionOpen: bool = false
  for line in readFile(sourcePath).splitLines():
    clean = line.strip()
    if clean.startsWith("when ") or clean.startsWith("elif "):
      conditionOpen = true
    if conditionOpen:
      appendDefinedFlags(F, clean)
    if conditionOpen and clean.endsWith(":"):
      conditionOpen = false

proc ignoredFlagSource(repoRoot, sourcePath: string): bool {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## repoRoot/sourcePath: project file checked against generated/dependency trees.
  var
    relative: string = relativePath(sourcePath, repoRoot).replace('\\', '/')
  result = relative.startsWith(".git/") or relative.startsWith("build/") or
    relative.startsWith("builds/") or relative.startsWith("dist/") or
    relative.startsWith("submodules/") or relative.startsWith("testResults/") or
    relative.contains("/.otter/results/") or relative.contains("/nimcache/")

proc nimFlagSource(path: string): bool {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## path: source-like Nim file whose compile conditions can expose flags.
  result = path.endsWith(".nim") or path.endsWith(".nims") or
    path.endsWith(".nimble")

proc hostSupportsFlag(flag: string): bool {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## flag: configured default filtered against current host CPU capabilities.
  case flag.toLowerAscii()
  of "sse2", "avx2", "aesni":
    when defined(amd64) or defined(i386):
      result = x86Feature(flag.toLowerAscii())
  of "neon":
    when defined(arm64) or defined(aarch64):
      result = true
  else:
    result = true

proc automaticDefaultFlag(flag: string): bool {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## flag: discovered symbol safe to enable automatically when host-supported.
  result = flag in ["sse2", "avx2", "aesni", "neon"]

proc resolveDefaultFlags(C: var OtterUiCatalog) {.role: truthBuilder,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## C: discovered allowlist receiving supported configured default flags.
  var
    flag: string = ""
  for configured in C.config.defaultFlags:
    flag = configured.strip()
    if flag == "*":
      for available in C.availableFlags:
        if automaticDefaultFlag(available) and hostSupportsFlag(available) and
            available notin C.defaultFlags:
          C.defaultFlags.add(available)
      continue
    if flag notin C.availableFlags:
      raise newException(ValueError,
        "configured default Otter flag was not discovered: " & flag)
    if hostSupportsFlag(flag):
      C.defaultFlags.add(flag)

proc stableId(relativePath, routine: string): string
    {.role: helper, metaTags: {tagTesting, tagUi}.} =
  ## relativePath/routine: source identity converted to a filesystem-safe ID.
  var
    source: string = relativePath & "-" & routine
  for c in source:
    if isIdentifierChar(c):
      result.add(c.toLowerAscii())
    elif result.len > 0 and result[^1] != '-':
      result.add('-')
  result = result.strip(chars = {'-'})

proc isPragmaMarker(s: string, markerAt: int): bool {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## s/markerAt: source and candidate marker checked for an open pragma block.
  var
    openAt: int = s.rfind("{.", 0, markerAt)
    closedAt: int = s.rfind(".}", 0, markerAt)
  result = openAt >= 0 and closedAt < openAt

proc appendSourceEntries(E: var seq[OtterUiTestEntry], sourcePath, testsRoot: string)
    {.role: truthBuilder, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## E: catalog receiving every valid pragma from one source.
  ## sourcePath/testsRoot: source file and path used for relative labels.
  const
    Marker = "otterUiTest"
  var
    source: string = readFile(sourcePath)
    relativePath: string = relativePath(sourcePath, parentDir(testsRoot)).replace('\\', '/')
    searchAt: int = 0
    pragmaAt: int = 0
    values: seq[string] = @[]
    routine: string = ""
    entry: OtterUiTestEntry
  while searchAt < source.len:
    pragmaAt = source.find(Marker, searchAt)
    if pragmaAt < 0:
      break
    searchAt = pragmaAt + Marker.len
    if not isPragmaMarker(source, pragmaAt):
      continue
    values = quotedValues(source, searchAt)
    routine = previousRoutineName(source, pragmaAt)
    if values.len != 4 or routine.len == 0:
      continue
    entry.id = stableId(relativePath, routine)
    entry.testName = values[0]
    entry.menu = values[1]
    entry.filters = normalizedFilters(values[2])
    entry.version = normalizedVersion(values[3])
    entry.routine = routine
    entry.line = source[0 ..< pragmaAt].count('\n') + 1
    entry.sourcePath = sourcePath
    entry.relativePath = relativePath
    E.add(entry)

proc compareEntries(a, b: OtterUiTestEntry): int
    {.role: helper, metaTags: {tagTesting, tagUi}.} =
  ## a/b: entries sorted by menu, panel name, version, and source.
  result = cmp(a.menu, b.menu)
  if result == 0:
    result = cmp(a.testName, b.testName)
  if result == 0:
    result = cmp(a.version, b.version)
  if result == 0:
    result = cmp(a.relativePath, b.relativePath)

proc validateEntries(E: openArray[OtterUiTestEntry])
    {.role: parser, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## E: complete catalog checked for ambiguous worker identities and tabs.
  var
    ids: HashSet[string]
    tabs: HashSet[string]
    i: int = 0
    tabKey: string = ""
  while i < E.len:
    if E[i].id in ids:
      raise newException(ValueError, "duplicate Otter UI test routine: " & E[i].id)
    ids.incl(E[i].id)
    if E[i].version.len > 0:
      tabKey = E[i].menu & "\x1f" & E[i].testName & "\x1f" & E[i].version
      if tabKey in tabs:
        raise newException(ValueError, "duplicate Otter UI test tab: " & E[i].testName & " / " & E[i].version)
      tabs.incl(tabKey)
    i = i + 1

proc discoverOtterUiTests*(repoRoot: string): OtterUiCatalog
    {.role: metaOrchestrator, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## repoRoot: repository whose tests tree is scanned for otterUiTest pragmas.
  var
    flags: HashSet[string]
  result.config = loadOtterUiConfig(repoRoot)
  if not dirExists(result.config.testsRoot):
    raise newException(IOError, "tests directory does not exist: " & result.config.testsRoot)
  for sourcePath in walkDirRec(result.config.testsRoot):
    if sourcePath.endsWith(".nim") and not sourcePath.contains(DirSep & ".otter" & DirSep) and
        not sourcePath.contains(DirSep & "build" & DirSep):
      appendSourceEntries(result.entries, sourcePath, result.config.testsRoot)
  for sourcePath in walkDirRec(result.config.repoRoot):
    if nimFlagSource(sourcePath) and not ignoredFlagSource(
        result.config.repoRoot, sourcePath):
      appendSourceFlags(flags, sourcePath)
  for flag in flags:
    result.availableFlags.add(flag)
  result.availableFlags.sort(system.cmp[string])
  resolveDefaultFlags(result)
  result.entries.sort(compareEntries)
  validateEntries(result.entries)
