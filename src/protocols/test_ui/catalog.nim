# ============================================================
# | Otter Test UI Catalog                                    |
# | -> Discover annotated zero-argument routines in tests    |
# ============================================================

import std/[algorithm, os, sets, strutils]

import ../../../.iron/metaPragmas
import ./[config, types]

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
    entry.version = values[3]
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
  result.config = loadOtterUiConfig(repoRoot)
  if not dirExists(result.config.testsRoot):
    raise newException(IOError, "tests directory does not exist: " & result.config.testsRoot)
  for sourcePath in walkDirRec(result.config.testsRoot):
    if sourcePath.endsWith(".nim") and not sourcePath.contains(DirSep & ".otter" & DirSep) and
        not sourcePath.contains(DirSep & "build" & DirSep):
      appendSourceEntries(result.entries, sourcePath, result.config.testsRoot)
  result.entries.sort(compareEntries)
  validateEntries(result.entries)
