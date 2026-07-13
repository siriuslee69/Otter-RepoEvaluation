# ============================================================
# | Otter Test UI App                                        |
# | -> Supervisor, WebUI host, spawner, and worker modes     |
# ============================================================

import std/[json, os, osproc, strutils]

import webui

import ../../../.iron/metaPragmas
import ../../otter_repo_evaluation

const
  NormalExitFile = "ui-normal-exit"

var
  GRepoRoot: string = ""
  GRuntimeDir: string = ""
  GResultsPath: string = ""

proc argumentValue(A: openArray[string], prefix: string): string {.role: parser,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## A/prefix: command arguments and one recognized key prefix.
  var
    i: int = 0
  while i < A.len:
    if A[i].startsWith(prefix):
      return A[i][prefix.len .. ^1]
    i = i + 1

proc appMode(A: openArray[string]): string {.role: parser,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## A: command arguments containing an optional Otter process mode.
  result = argumentValue(A, "--otter-mode:")

proc configJson(c: OtterUiConfig): JsonNode {.role: dataWriter,
    metaTags: {tagTesting, tagUi}.} =
  ## c: loaded project display and output settings.
  result = %*{
    "repoRoot": c.repoRoot.replace('\\', '/'),
    "title": c.title,
    "banner": c.banner,
    "outputPath": c.outputPath.replace('\\', '/'),
    "customCss": c.customCss
  }

proc entryJson(e: OtterUiTestEntry): JsonNode {.role: dataWriter,
    metaTags: {tagTesting, tagUi}.} =
  ## e: one discovered pragma exposed to the browser.
  result = %*{
    "id": e.id,
    "testName": e.testName,
    "menu": e.menu,
    "filters": e.filters,
    "version": e.version,
    "routine": e.routine,
    "line": e.line,
    "sourcePath": e.relativePath
  }

proc bootstrapPayload(): string {.role: dataWriter,
    metaTags: {tagTesting, tagUi}.} =
  var
    C: OtterUiCatalog = discoverOtterUiTests(GRepoRoot)
    entries: JsonNode = newJArray()
  if GResultsPath.len == 0:
    GResultsPath = C.config.outputPath
  C.config.outputPath = GResultsPath
  for entry in C.entries:
    entries.add(entryJson(entry))
  result = $(%*{
    "ok": true,
    "config": configJson(C.config),
    "entries": entries
  })

proc normalizeResultsPath(path: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## path: typed or picker-selected output directory to validate and create.
  var
    expanded: string = path.strip()
  if expanded == "~":
    expanded = getHomeDir()
  elif expanded.startsWith("~/") or expanded.startsWith("~\\"):
    expanded = joinPath(getHomeDir(), expanded[2 .. ^1])
  if expanded.len == 0:
    expanded = discoverOtterUiTests(GRepoRoot).config.outputPath
  if not expanded.isAbsolute():
    expanded = joinPath(GRepoRoot, expanded)
  expanded = normalizedPath(expanded)
  createDir(expanded)
  if not dirExists(expanded):
    raise newException(IOError, "output directory could not be created: " & expanded)
  result = expanded

proc pickerCommand(initialPath: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## initialPath: directory displayed first by the native folder picker.
  when defined(windows):
    result = "powershell -NoProfile -STA -Command \"Add-Type -AssemblyName System.Windows.Forms; " &
      "$d = New-Object System.Windows.Forms.FolderBrowserDialog; " &
      "$d.SelectedPath = '" & initialPath.replace("'", "''") & "'; " &
      "if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) " &
      "{ [Console]::Write($d.SelectedPath) } else { exit 1 }\""
  elif defined(macosx):
    result = "osascript -e 'POSIX path of (choose folder with prompt \"Select test output folder\")'"
  else:
    if findExe("yad").len > 0:
      result = "yad --file --directory --title=\"Select test output folder\" --filename=" &
        quoteShell(initialPath & DirSep)
    elif findExe("zenity").len > 0:
      result = "zenity --file-selection --directory --title=\"Select test output folder\" --filename=" &
        quoteShell(initialPath & DirSep)
    elif findExe("kdialog").len > 0:
      result = "kdialog --getexistingdirectory " & quoteShell(initialPath) &
        " \"Select test output folder\""

proc chooseResultsPath(): string {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## Opens the OS folder picker and returns its validated selected directory.
  var
    command: string = pickerCommand(GResultsPath)
    probe: tuple[output: string, exitCode: int]
    lines: seq[string] = @[]
    selected: string = ""
  if command.len == 0:
    raise newException(IOError, "no native folder picker is installed; edit the path directly")
  probe = execCmdEx(command, options = {poUsePath, poStdErrToStdOut})
  if probe.exitCode != 0:
    raise newException(IOError, "folder selection was cancelled")
  lines = probe.output.splitLines()
  if lines.len > 0:
    selected = lines[0].strip().strip(chars = {'\'', '"'})
  if selected.len == 0:
    raise newException(IOError, "folder selection returned no path")
  result = normalizeResultsPath(selected)

proc actionPayload(request: JsonNode): string {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  var
    action: string = request{"action"}.getStr("")
    response: JsonNode
  try:
    if action == "setResultsPath":
      GResultsPath = normalizeResultsPath(request{"path"}.getStr(""))
      return $(%*{"ok": true, "path": GResultsPath.replace('\\', '/')})
    if action == "chooseResultsPath":
      GResultsPath = chooseResultsPath()
      return $(%*{"ok": true, "path": GResultsPath.replace('\\', '/')})
    response = spawnerRequest(GRuntimeDir, request)
    result = $response
  except CatchableError as exc:
    result = $(%*{"ok": false, "error": exc.msg})

proc otterUiBootstrap(request: JsonNode): string {.webuiCb, role: dataFetcher,
    metaTags: {tagTesting, tagUi}.} =
  ## request: explicit browser payload used to keep the WebUI call serializable.
  discard request
  try:
    result = bootstrapPayload()
  except CatchableError as exc:
    result = $(%*{"ok": false, "error": exc.msg})

proc otterUiAction(request: JsonNode): string {.webuiCb, role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  result = actionPayload(request)

proc webRoot(): string {.role: helper, metaTags: {tagTesting, tagUi}.} =
  result = joinPath(currentSourcePath().splitFile.dir, "web")

proc runUi() {.role: metaOrchestrator,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  var
    window: Window = newWindow()
    rootOk: bool = false
  window.setSize(1440, 920)
  setTimeout(0)
  rootOk = (window.rootFolder = webRoot())
  if not rootOk:
    raise newException(IOError, "unable to set Otter test UI web root")
  window.bindCb("otterUiBootstrap", otterUiBootstrap)
  window.bindCb("otterUiAction", otterUiAction)
  if not window.show("index.html"):
    raise newException(IOError, "unable to open Otter test UI")
  wait()
  clean()
  writeFile(joinPath(GRuntimeDir, NormalExitFile), "closed\n")

proc terminateChild(process: Process) {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## process: supervisor-owned process and its immediate descendants.
  if process == nil or not process.running():
    return
  when defined(windows):
    discard execCmd("taskkill /PID " & $processID(process) & " /T /F")
  else:
    discard execCmd("pkill -TERM -P " & $processID(process))
    process.terminate()

proc childArguments(mode, repoRoot, runtimeDir: string): seq[string]
    {.role: truthBuilder, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## mode/repoRoot/runtimeDir: child process launch values.
  result = @["--otter-mode:" & mode, "--repo-root:" & repoRoot,
    "--runtime-path:" & runtimeDir]

proc runSupervisor(repoRoot: string) {.role: metaOrchestrator,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  var
    runtimeDir: string = joinPath(getTempDir(), "otter-test-ui-" &
      $getCurrentProcessId())
    normalExitPath: string = joinPath(runtimeDir, NormalExitFile)
    spawner: Process
    ui: Process
    response: JsonNode
    exitCode: int = 0
  ensureRuntimeDirectories(runtimeDir)
  spawner = startProcess(getAppFilename(), workingDir = repoRoot,
    args = childArguments("spawner", repoRoot, runtimeDir),
    options = {poParentStreams})
  try:
    while spawner.running():
      if fileExists(normalExitPath):
        removeFile(normalExitPath)
      ui = startProcess(getAppFilename(), workingDir = repoRoot,
        args = childArguments("ui", repoRoot, runtimeDir),
        options = {poParentStreams})
      exitCode = ui.waitForExit()
      ui.close()
      if fileExists(normalExitPath):
        break
      echo "Otter test UI host exited unexpectedly (", exitCode, "); relaunching."
      sleep(300)
  finally:
    try:
      response = spawnerRequest(runtimeDir, %*{"action": "shutdown"})
      discard response
    except CatchableError:
      discard
    sleep(100)
    terminateChild(spawner)
    if spawner != nil:
      discard spawner.waitForExit(3000)
      spawner.close()

when isMainModule:
  var
    args: seq[string] = commandLineParams()
    mode: string = appMode(args)
  GRepoRoot = argumentValue(args, "--repo-root:")
  GRuntimeDir = argumentValue(args, "--runtime-path:")
  if GRepoRoot.len == 0:
    GRepoRoot = getCurrentDir()
  GRepoRoot = absolutePath(GRepoRoot)
  case mode
  of "spawner":
    runSpawner(getAppFilename(), GRepoRoot, GRuntimeDir)
  of "worker":
    runWorker(GRepoRoot, GRuntimeDir, argumentValue(args, "--test-id:"),
      argumentValue(args, "--results-path:"))
  of "ui":
    runUi()
  else:
    runSupervisor(GRepoRoot)
