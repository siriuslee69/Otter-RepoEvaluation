# ============================================================
# | Otter Repo Graph WebUI App                               |
# | -> Nim WebUI host for the interactive repo graph         |
# ============================================================

import std/[json, os, osproc, strutils]

import webui
import runePragmas
import ../../otter_repo_evaluation

const
  AppName {.role: helper, tag: "ui|graph".} = "Otter Repo Graph"

proc resolveWebRoot(): string {.role: helper, tag: "ui|graph".} =
  result = joinPath(currentSourcePath().splitFile.dir, "web")


proc pickerCommandAvailable(): bool {.role: helper, tag: "ui|graph".} =
  when defined(windows):
    result = findExe("powershell.exe").len > 0 or findExe("powershell").len > 0
  elif defined(macosx):
    result = findExe("osascript").len > 0
  else:
    result = findExe("yad").len > 0 or findExe("zenity").len > 0 or findExe("kdialog").len > 0


proc folderPickerCommand(): string {.role: helper, tag: "ui|graph".} =
  when defined(windows):
    result = "powershell -NoProfile -STA -Command \"Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = 'Select Repo'; if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::Write($d.SelectedPath) } else { exit 1 }\""
  elif defined(macosx):
    if findExe("osascript").len > 0:
      result = "osascript -e 'POSIX path of (choose folder with prompt \"Select Repo\")'"
  else:
    if findExe("yad").len > 0:
      result = "yad --file --directory --title=\"Select Repo\""
    elif findExe("zenity").len > 0:
      result = "zenity --file-selection --directory --title=\"Select Repo\""
    elif findExe("kdialog").len > 0:
      result = "kdialog --getexistingdirectory . \"Select Repo\""


proc firstPickerLine(output: string): string {.role: helper, tag: "ui|graph".} =
  var
    lines: seq[string] = @[]
    selected: string = ""
  lines = output.splitLines()
  if lines.len > 0:
    selected = lines[0].strip()
  if selected.len >= 2:
    if (selected[0] == '"' and selected[^1] == '"') or
        (selected[0].ord == 39 and selected[^1].ord == 39):
      selected = selected[1 .. ^2]
  result = selected


proc bootstrapPayload(): string {.role: helper, tag: "ui|graph".} =
  result = pretty(%*{
    "host": "webui",
    "appName": AppName,
    "defaultRepoRoot": getCurrentDir().replace('\\', '/'),
    "supportsFolderPicker": pickerCommandAvailable(),
    "supportsCodexSend": false
  })


proc analyzePayload(rootDir: string, includeTests: bool): string {.role: actor, tag: "ui|graph".} =
  var
    g: RepoGraph
  g = analyzeRepo(rootDir, includeTests)
  result = pretty(%*{
    "ok": true,
    "summary": graphSummaryLines(g),
    "graph": parseJson(toGraphJson(g))
  })


proc annotationPayload(rootDir: string, annotations: JsonNode): string {.role: actor, tag: "ui|graph".} =
  var
    lines: seq[string] = @[]
    i: int = 0
    item: JsonNode
    outPath: string = ""
  lines.add("# Otter Notes For Codex")
  lines.add("")
  lines.add("Repo: `" & rootDir.replace('\\', '/') & "`")
  lines.add("")
  while i < annotations.len:
    item = annotations[i]
    lines.add("## " & item{"name"}.getStr(item{"functionId"}.getStr("function")))
    lines.add("- functionId: `" & item{"functionId"}.getStr("") & "`")
    lines.add("- source: `" & item{"sourcePath"}.getStr("") & ":" & $item{"lineStart"}.getInt(0) & "`")
    lines.add("- note: " & item{"note"}.getStr(""))
    lines.add("")
    i = i + 1
  createDir("build")
  outPath = joinPath("build", "otter_annotations_for_codex.md")
  writeFile(outPath, lines.join("\n") & "\n")
  result = pretty(%*{
    "ok": true,
    "message": "annotations exported for Codex",
    "path": outPath.replace('\\', '/'),
    "markdown": lines.join("\n")
  })


proc viewSettingsPath(rootDir: string): string {.role: helper, tag: "ui|graph".} =
  result = joinPath(rootDir, ".otter", "repo_graph_view_settings.json")


proc loadViewSettingsPayload(rootDir: string): string {.role: helper, tag: "ui|graph".} =
  var
    path: string = ""
    settings: JsonNode
  path = viewSettingsPath(rootDir)
  if fileExists(path):
    settings = parseJson(readFile(path))
  else:
    settings = newJNull()
  result = pretty(%*{
    "ok": true,
    "path": path.replace('\\', '/'),
    "settings": settings
  })


proc saveViewSettingsPayload(rootDir: string, settings: JsonNode): string {.role: actor, tag: "ui|graph".} =
  var
    path: string = ""
  path = viewSettingsPath(rootDir)
  createDir(path.splitFile.dir)
  writeFile(path, pretty(settings) & "\n")
  result = pretty(%*{
    "ok": true,
    "path": path.replace('\\', '/')
  })


proc chooseFolderPayload(): string {.role: actor, tag: "ui|graph".} =
  var
    cmd: string = ""
    r: tuple[output: string, exitCode: int]
    selected: string = ""
  cmd = folderPickerCommand()
  if cmd.len == 0:
    result = pretty(%*{
      "ok": false,
      "error": "no folder picker available"
    })
    return
  r = execCmdEx(cmd, options = {poUsePath, poStdErrToStdOut})
  if r.exitCode != 0:
    result = pretty(%*{
      "ok": false,
      "error": "no folder selected"
    })
    return
  selected = firstPickerLine(r.output)
  if selected.len == 0:
    result = pretty(%*{
      "ok": false,
      "error": "no folder selected"
    })
    return
  if not dirExists(selected):
    result = pretty(%*{
      "ok": false,
      "error": "selected folder does not exist: " & selected
    })
    return
  result = pretty(%*{
    "ok": true,
    "repoRoot": selected.replace('\\', '/')
  })


proc parseIncludeTests(req: JsonNode): bool {.role: helper, tag: "ui|graph".} =
  if req.hasKey("includeTests"):
    result = req["includeTests"].getBool(false)


proc parseRootDir(req: JsonNode): string {.role: helper, tag: "ui|graph".} =
  if req.hasKey("repoRoot"):
    result = req["repoRoot"].getStr("").strip()
  if result.len == 0:
    result = getCurrentDir()


proc parseFunctionId(req: JsonNode): string {.role: helper, tag: "ui|graph".} =
  if req.hasKey("functionId"):
    result = req["functionId"].getStr("").strip()


proc otterBootstrap(): string {.webuiCb, role: helper, tag: "ui|graph".} =
  result = bootstrapPayload()


proc otterAnalyze(req: JsonNode): string {.webuiCb, role: actor, tag: "ui|graph".} =
  var
    rootDir: string = ""
    includeTests: bool = false
  rootDir = parseRootDir(req)
  includeTests = parseIncludeTests(req)
  try:
    result = analyzePayload(rootDir, includeTests)
  except CatchableError as e:
    result = pretty(%*{
      "ok": false,
      "error": e.msg
    })


proc otterRunFunction(req: JsonNode): string {.webuiCb, role: actor, tag: "ui|graph|execution".} =
  var
    rootDir: string = ""
    functionId: string = ""
    includeTests: bool = true
    r: RunSampleResult
  rootDir = parseRootDir(req)
  functionId = parseFunctionId(req)
  includeTests = if req.hasKey("includeTests"): req["includeTests"].getBool(true) else: true
  r = runFunctionSample(rootDir, functionId, includeTests)
  result = toRunSampleJson(r)


proc otterSendAnnotations(req: JsonNode): string {.webuiCb, role: actor, tag: "ui|graph".} =
  var
    rootDir: string = ""
    annotations: JsonNode
  rootDir = parseRootDir(req)
  if req.hasKey("annotations"):
    annotations = req["annotations"]
  else:
    annotations = newJArray()
  result = annotationPayload(rootDir, annotations)


proc otterLoadViewSettings(req: JsonNode): string {.webuiCb, role: helper, tag: "ui|graph".} =
  var
    rootDir: string = ""
  rootDir = parseRootDir(req)
  try:
    result = loadViewSettingsPayload(rootDir)
  except CatchableError as e:
    result = pretty(%*{
      "ok": false,
      "error": e.msg
    })


proc otterSaveViewSettings(req: JsonNode): string {.webuiCb, role: actor, tag: "ui|graph".} =
  var
    rootDir: string = ""
    settings: JsonNode
  rootDir = parseRootDir(req)
  if req.hasKey("settings"):
    settings = req["settings"]
  else:
    settings = newJObject()
  try:
    result = saveViewSettingsPayload(rootDir, settings)
  except CatchableError as e:
    result = pretty(%*{
      "ok": false,
      "error": e.msg
    })


proc otterChooseFolder(req: JsonNode): string {.webuiCb, role: actor, tag: "ui|graph".} =
  discard req
  try:
    result = chooseFolderPayload()
  except CatchableError as e:
    result = pretty(%*{
      "ok": false,
      "error": e.msg
    })


when isMainModule:
  var
    w: Window
    rootOk: bool = false
  w = newWindow()
  w.setSize(1480, 920)
  setTimeout(3)
  rootOk = (w.rootFolder = resolveWebRoot())
  if not rootOk:
    raise newException(IOError, "unable to set web root")
  w.bindCb("otterBootstrap", otterBootstrap)
  w.bindCb("otterAnalyze", otterAnalyze)
  w.bindCb("otterRunFunction", otterRunFunction)
  w.bindCb("otterSendAnnotations", otterSendAnnotations)
  w.bindCb("otterChooseFolder", otterChooseFolder)
  w.bindCb("otterLoadViewSettings", otterLoadViewSettings)
  w.bindCb("otterSaveViewSettings", otterSaveViewSettings)
  discard w.show("index.html")
  wait()
  clean()
