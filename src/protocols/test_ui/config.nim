# ============================================================
# | Otter Test UI Configuration                              |
# | -> Read tests/.otter theme, title, banner, and log path  |
# ============================================================

import std/[os, strutils]

import ../../../.iron/metaPragmas
import ./types

const
  DefaultBanner* = "Select a test, run it in isolation, and keep the result for review."

proc unquoteValue(s: string): string {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## s: configuration value with optional single or double quotes.
  var
    t: string = s.strip()
  if t.len >= 2 and ((t[0] == '"' and t[^1] == '"') or
      (t[0] == '\'' and t[^1] == '\'')):
    t = t[1 .. ^2]
  result = t

proc assignConfigValue(S: var OtterUiConfig, key, value: string)
    {.role: truthBuilder, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## S: settings receiving one parsed value.
  ## key/value: normalized TOML key and text value.
  case key
  of "title":
    S.title = unquoteValue(value)
  of "banner", "description":
    S.banner = unquoteValue(value)
  of "outputpath", "output_path", "defaultoutputpath", "default_output_path":
    S.outputPath = unquoteValue(value)
  else:
    discard

proc parseConfigFile(S: var OtterUiConfig, path: string)
    {.role: parser, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## S: settings receiving supported top-level TOML values.
  ## path: tests/.otter/config.toml file.
  var
    line: string = ""
    clean: string = ""
    splitAt: int = 0
    key: string = ""
    value: string = ""
  for sourceLine in readFile(path).splitLines():
    line = sourceLine
    clean = line.strip()
    if clean.len == 0 or clean.startsWith("#") or clean.startsWith("["):
      continue
    splitAt = clean.find('=')
    if splitAt <= 0:
      continue
    key = clean[0 ..< splitAt].strip().toLowerAscii()
    value = clean[splitAt + 1 .. ^1]
    assignConfigValue(S, key, value)

proc resolveOutputPath(repoRoot, configured: string): string
    {.role: helper, metaTags: {tagTesting, tagUi}.} =
  ## repoRoot/configured: repository and optional configured output location.
  var
    path: string = configured.strip()
  if path.len == 0:
    path = joinPath("tests", ".otter", "results")
  if not path.isAbsolute():
    path = joinPath(repoRoot, path)
  result = normalizedPath(path)

proc loadOtterUiConfig*(repoRoot: string): OtterUiConfig
    {.role: truthBuilder, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## repoRoot: parent repository containing the tests directory.
  var
    settingsDir: string = ""
    configPath: string = ""
    cssPath: string = ""
    repoName: string = ""
  result.repoRoot = absolutePath(repoRoot)
  result.testsRoot = joinPath(result.repoRoot, "tests")
  repoName = splitPath(result.repoRoot).tail
  result.title = repoName
  result.banner = DefaultBanner
  settingsDir = joinPath(result.testsRoot, ".otter")
  configPath = joinPath(settingsDir, "config.toml")
  cssPath = joinPath(settingsDir, "config.css")
  if fileExists(configPath):
    parseConfigFile(result, configPath)
  result.outputPath = resolveOutputPath(result.repoRoot, result.outputPath)
  if fileExists(cssPath):
    result.customCss = readFile(cssPath)
