# ============================================================
# | Otter Test UI Configuration                              |
# | -> Read tests/.otter theme, title, banner, and log path  |
# ============================================================

import std/[os, strutils]

import ../../../.iron/metaPragmas
import ./types

const
  DefaultBanner* = "Select a test, run it in isolation, and keep the result for review."
  DefaultConfigCss* = """:root {
  --otter-color-background: #101a21;
  --otter-color-gradient: #8a969b;
  --otter-color-surface: #0b151c;
  --otter-color-border: #8abdc9;
  --otter-color-text: #dce8ed;
  --otter-color-muted: #8ca4ae;
  --otter-color-primary: #73d7d0;
  --otter-color-secondary: #cf7ba9;
  --otter-color-success: #73d7a7;
  --otter-color-failure: #ff718b;
  --otter-color-running: #e4bd72;
}
"""

proc unquoteValue(s: string): string {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## s: configuration value with optional single or double quotes.
  var
    t: string = s.strip()
  if t.len >= 2 and ((t[0] == '"' and t[^1] == '"') or
      (t[0] == '\'' and t[^1] == '\'')):
    t = t[1 .. ^2]
  result = t

proc stringArray(s: string): seq[string] {.role: parser,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## s: one-line TOML string array such as ["sse2", "avx2"].
  var
    quote: char = '\0'
    value: string = ""
    escaped: bool = false
  for c in s:
    if quote == '\0' and c in {'"', '\''}:
      quote = c
      value = ""
      escaped = false
    elif quote != '\0' and escaped:
      value.add(c)
      escaped = false
    elif quote != '\0' and c == '\\':
      escaped = true
    elif quote != '\0' and c == quote:
      if value.len > 0 and value notin result:
        result.add(value)
      quote = '\0'
    elif quote != '\0':
      value.add(c)

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
  of "defaultflags", "default_flags":
    S.defaultFlags = stringArray(value)
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

proc tomlString(s: string): string {.role: helper,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## s: text encoded as one basic TOML string.
  result = "\"" & s.replace("\\", "\\\\").replace("\"", "\\\"").replace(
    "\n", "\\n").replace("\r", "\\r") & "\""

proc defaultConfigToml(repoName: string): string {.role: dataWriter,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## repoName: repository label used in a new editable configuration file.
  result = "title = " & tomlString(repoName & " Tests") & "\n" &
    "banner = " & tomlString(DefaultBanner) & "\n" &
    "output_path = \"tests/.otter/results\"\n" &
    "default_flags = [\"*\"]\n"

proc ensureOtterConfigFiles(testsRoot, repoName: string): tuple[configPath,
    cssPath: string] {.role: dataWriter,
    metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## testsRoot/repoName: parent tests directory and generated project label.
  var
    settingsDir: string = joinPath(testsRoot, ".otter")
  createDir(settingsDir)
  result.configPath = joinPath(settingsDir, "config.toml")
  result.cssPath = joinPath(settingsDir, "config.css")
  if not fileExists(result.configPath):
    writeFile(result.configPath, defaultConfigToml(repoName))
  if not fileExists(result.cssPath):
    writeFile(result.cssPath, DefaultConfigCss)

proc loadOtterUiConfig*(repoRoot: string): OtterUiConfig
    {.role: truthBuilder, metaTags: {tagParsing, tagTesting, tagUi}.} =
  ## repoRoot: parent repository containing the tests directory.
  var
    configPath: string = ""
    cssPath: string = ""
    repoName: string = ""
    generated: tuple[configPath, cssPath: string]
  result.repoRoot = absolutePath(repoRoot)
  result.testsRoot = joinPath(result.repoRoot, "tests")
  repoName = splitPath(result.repoRoot).tail
  result.title = repoName
  result.banner = DefaultBanner
  generated = ensureOtterConfigFiles(result.testsRoot, repoName)
  configPath = generated.configPath
  cssPath = generated.cssPath
  parseConfigFile(result, configPath)
  result.outputPath = resolveOutputPath(result.repoRoot, result.outputPath)
  result.customCss = readFile(cssPath)
