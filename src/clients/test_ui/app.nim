# ============================================================
# | Otter Test UI App                                        |
# | -> Main supervisor, WebUI, relay, test backend, workers  |
# ============================================================

import std/[atomics, json, monotimes, os, osproc, strutils]

import webui
from webui/bindings import set_custom_parameters

when not defined(windows):
  import std/posix

import ../../../.iron/metaPragmas
import ../../otter_repo_evaluation

const
  NormalExitFile = "ui-normal-exit"
  ReadyFile = "ui-ready"

var
  GRepoRoot: string = ""
  GRuntimeDir: string = ""
  GResultsPath: string = ""
  GLastBrowserHeartbeat: Atomic[int64]

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

proc argumentList(A: openArray[string], prefix: string): seq[string]
    {.role: parser, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## A/prefix: command arguments and comma-separated value prefix.
  var
    value: string = argumentValue(A, prefix)
    item: string = ""
  for candidate in value.split(','):
    item = candidate.strip()
    if item.len > 0:
      result.add(item)

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
    response = orchestratorRequest(GRuntimeDir, request)
    result = $response
  except CatchableError as exc:
    result = $(%*{"ok": false, "error": exc.msg})

proc otterUiBootstrap(request: JsonNode): string {.webuiCb, role: dataFetcher,
    metaTags: {tagTesting, tagUi}.} =
  ## request: explicit browser payload used to keep the WebUI call serializable.
  discard request
  try:
    result = $orchestratorRequest(GRuntimeDir, %*{"action": "bootstrap"})
    if GResultsPath.len == 0:
      GResultsPath = parseJson(result){"config"}{"outputPath"}.getStr("")
  except CatchableError as exc:
    result = $(%*{"ok": false, "error": exc.msg})

proc otterUiAction(request: JsonNode): string {.webuiCb, role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  result = actionPayload(request)

proc otterUiHeartbeat(request: JsonNode): string {.webuiCb, role: dataFetcher,
    metaTags: {tagExecution, tagTesting, tagUi, tagTiming}.} =
  ## request: explicit browser ping proving the WebUI client is still alive.
  discard request
  GLastBrowserHeartbeat.store(getMonoTime().ticks)
  writeHeartbeat(GRuntimeDir, "webui")
  result = $(%*{"ok": true})

proc webRoot(): string {.role: helper, metaTags: {tagTesting, tagUi}.} =
  result = joinPath(currentSourcePath().splitFile.dir, "web")

proc browserProfile(): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## Returns the private browser profile used by this Otter UI process.
  result = joinPath(GRuntimeDir, "browser-profile")

proc showUi(window: Window): bool {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## window: prepared WebUI window opened with the first available renderer.
  var
    Browsers: array[5, WebuiBrowser] = [
      WebuiBrowser(13),
      WebuiBrowser(9),
      WebuiBrowser(3),
      WebuiBrowser(8),
      WebuiBrowser(2)
    ]
    i: int = 0
  while i < Browsers.len:
    if Browsers[i] == WebuiBrowser(13) or browserExist(Browsers[i]):
      if window.show("index.html", Browsers[i]):
        return true
    i = i + 1

proc runUi() {.role: metaOrchestrator,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  var
    window: Window = newWindow()
    profile: string = browserProfile()
    rootOk: bool = false
    shown: bool = false
  createDir(profile)
  window.setSize(1440, 920)
  window.setProfile("OtterTestUi", profile)
  set_custom_parameters(csize_t(int(window)),
    "--disable-background-networking --disable-component-update " &
    "--disable-sync --disable-default-apps --disable-extensions")
  setTimeout(0)
  rootOk = (window.rootFolder = webRoot())
  if not rootOk:
    raise newException(IOError, "unable to set Otter test UI web root")
  window.bindCb("otterUiBootstrap", otterUiBootstrap)
  window.bindCb("otterUiAction", otterUiAction)
  window.bindCb("otterUiHeartbeat", otterUiHeartbeat)
  shown = showUi(window)
  if not shown:
    raise newException(IOError,
      "unable to open Otter test UI in WebView, Vivaldi, Firefox, Brave, or Chrome")
  GLastBrowserHeartbeat.store(getMonoTime().ticks)
  writeHeartbeat(GRuntimeDir, "webui")
  writeFile(joinPath(GRuntimeDir, ReadyFile), "ready\n")
  while waitAsync():
    if getMonoTime().ticks - GLastBrowserHeartbeat.load() >=
        HeartbeatTimeoutMs.int64 * 1_000_000'i64:
      window.close()
      break
    sleep(25)
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
    discard posix.kill(Pid(-processID(process)), SIGKILL)
    if process.running():
      process.kill()

proc childArguments(mode, repoRoot, runtimeDir: string): seq[string]
    {.role: truthBuilder, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## mode/repoRoot/runtimeDir: child process launch values.
  result = @["--otter-mode:" & mode, "--repo-root:" & repoRoot,
    "--runtime-path:" & runtimeDir]

proc startBackend(mode, repoRoot, runtimeDir: string): Process {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## mode/repoRoot/runtimeDir: persistent backend role and launch context.
  var
    options: set[ProcessOption] = {poParentStreams}
    launchArgs: seq[string] = @[]
  when defined(linux):
    launchArgs = @[getAppFilename()]
    launchArgs.add(childArguments(mode, repoRoot, runtimeDir))
    options.incl(poUsePath)
    result = startProcess("setsid", workingDir = repoRoot, args = launchArgs,
      options = options)
  else:
    when not defined(windows):
      options.incl(poDaemon)
    result = startProcess(getAppFilename(), workingDir = repoRoot,
      args = childArguments(mode, repoRoot, runtimeDir),
      options = options)

proc restartBackend(process: var Process, mode, repoRoot, runtimeDir: string)
    {.role: actor, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## process/mode/repoRoot/runtimeDir: monitored backend and restart context.
  if process != nil and process.running():
    return
  if process != nil:
    discard process.waitForExit(100)
    process.close()
  echo "Otter ", mode, " exited unexpectedly; restarting."
  process = startBackend(mode, repoRoot, runtimeDir)

proc stopBackend(process: var Process) {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## process: persistent backend handle stopped during supervisor shutdown.
  terminateChild(process)
  if process != nil:
    discard process.waitForExit(3000)
    process.close()
    process = nil

proc runSupervisor(repoRoot: string) {.role: metaOrchestrator,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  var
    runtimeDir: string = joinPath(getTempDir(), "otter-test-ui-" &
      $getCurrentProcessId())
    normalExitPath: string = joinPath(runtimeDir, NormalExitFile)
    readyPath: string = joinPath(runtimeDir, ReadyFile)
    orchestrator: Process
    testBackend: Process
    ui: Process
    response: JsonNode
    exitCode: int = 0
    startupFailed: bool = false
    serviceFailed: bool = false
  ensureRuntimeDirectories(runtimeDir)
  writeProcessIdentity(runtimeDir, "main")
  testBackend = startBackend("test-backend", repoRoot, runtimeDir)
  orchestrator = startBackend("orchestrator", repoRoot, runtimeDir)
  writeHeartbeat(runtimeDir, "webui")
  writeHeartbeat(runtimeDir, "orchestrator")
  try:
    while true:
      if fileExists(normalExitPath):
        removeFile(normalExitPath)
      if fileExists(readyPath):
        removeFile(readyPath)
      ui = startBackend("ui", repoRoot, runtimeDir)
      while ui.running():
        if not fileExists(readyPath):
          writeHeartbeat(runtimeDir, "webui")
        restartBackend(testBackend, "test-backend", repoRoot, runtimeDir)
        if orchestrator == nil or not orchestrator.running():
          echo "Otter orchestrator exited; closing the Test UI and active tests."
          serviceFailed = true
          terminateChild(ui)
          break
        sleep(100)
      exitCode = ui.waitForExit()
      ui.close()
      ui = nil
      if serviceFailed:
        break
      if not fileExists(readyPath):
        startupFailed = true
        break
      if fileExists(normalExitPath):
        break
      echo "Otter test UI host exited unexpectedly (", exitCode,
        "); relaunching."
      sleep(300)
  finally:
    try:
      response = orchestratorRequest(runtimeDir, %*{"action": "shutdown"})
      discard response
    except CatchableError:
      discard
    sleep(100)
    stopBackend(orchestrator)
    stopBackend(testBackend)
    stopBackend(ui)
  if startupFailed:
    raise newException(IOError,
      "Otter test UI renderer failed during startup; see the preceding WebUI error")

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
  of "spawner", "test-backend":
    runTestBackend(getAppFilename(), GRepoRoot, GRuntimeDir)
  of "orchestrator":
    runOrchestrator(GRuntimeDir)
  of "worker":
    runWorker(GRepoRoot, GRuntimeDir, argumentValue(args, "--test-id:"),
      argumentValue(args, "--results-path:"),
      argumentList(args, "--compile-flags:"))
  of "ui":
    runUi()
  else:
    runSupervisor(GRepoRoot)
