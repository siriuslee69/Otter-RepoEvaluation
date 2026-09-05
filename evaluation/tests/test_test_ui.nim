# ============================================================
# | Otter Test UI Tests                                      |
# | -> Verify discovery, configuration, grouping, and worker |
# ============================================================

import std/[json, monotimes, os, osproc, strutils, times, unittest]

import ../../meta/metaPragmas
import otter_repo_evaluation

proc catalogEntry(C: OtterUiCatalog, routine: string): OtterUiTestEntry
    {.role: parser, metaTags: {tagTesting, tagUi}.} =
  ## C: discovered catalog.
  ## routine: annotated routine name to find.
  for entry in C.entries:
    if entry.routine == routine:
      return entry
  raise newException(ValueError, "missing UI test routine: " & routine)

proc processIsRunning(pid: int): bool {.role: dataFetcher,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## pid: operating-system process identity checked without owning its handle.
  var
    probe: tuple[output: string, exitCode: int]
  when defined(windows):
    probe = execCmdEx("tasklist /FI \"PID eq " & $pid & "\" /NH",
      options = {poEvalCommand, poStdErrToStdOut})
    result = probe.exitCode == 0 and probe.output.contains($pid)
  else:
    probe = execCmdEx("kill -0 " & $pid,
      options = {poEvalCommand, poStdErrToStdOut})
    result = probe.exitCode == 0

suite "Otter test UI":
  test "discovers grouped versions and standalone panels":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
      v1: OtterUiTestEntry = catalogEntry(C, "textPathV1")
      v2: OtterUiTestEntry = catalogEntry(C, "textPathV2")
      standalone: OtterUiTestEntry = catalogEntry(C, "arithmeticPath")
      combinedLeft: OtterUiTestEntry = catalogEntry(C, "combinedLeft")
      combinedRight: OtterUiTestEntry = catalogEntry(C, "combinedRight")
    check v1.testName == "Text paths"
    check v2.testName == v1.testName
    check v1.version == "Version 1"
    check v2.version == "Version 2"
    check v1.menu == "Examples"
    check v1.filters == @["smoke", "text"]
    check standalone.testName == "Arithmetic path"
    check standalone.version == "Default"
    check combinedLeft.testName == "Combined paths"
    check combinedRight.testName == combinedLeft.testName
    check combinedLeft.version.len == 0
    check combinedRight.version.len == 0
    check "otterOptionalTrace" in C.availableFlags
    check "windows" notin C.availableFlags
    check "release" notin C.availableFlags
    check "otterOptionalTrace" in C.defaultFlags
    check "gcArc" notin C.defaultFlags
    check "gcOrc" notin C.defaultFlags

  test "loads project theme and output configuration":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
    check C.config.title == "Otter Test Laboratory"
    check C.config.banner.len > 0
    check C.config.outputPath.endsWith(joinPath("tests", ".otter", "results"))
    check C.config.defaultFlags == @["*", "otterOptionalTrace"]
    check C.defaultFlags == @["otterOptionalTrace"]
    check C.config.customCss.contains("--otter-color-gradient: #738ad7")
    check C.config.customCss.contains("--otter-color-success")
    check C.config.customCss.contains("--otter-color-failure")
    check not C.config.customCss.contains("rgba(")
    check not C.config.customCss.contains("gradient(")

  test "dashboard keeps direct panel references for binary group keys":
    var
      script: string = readFile("src/clients/test_ui/web/js/app.js")
      page: string = readFile("src/clients/test_ui/web/index.html")
      theme: string = readFile("src/clients/test_ui/web/css/app.css")
    check script.contains("group.panel = panel")
    check script.contains("const panel = group.panel")
    check not script.contains("CSS.escape")
    check not script.contains("data-group-key")
    check script.contains("async function bootWhenWebUiReady()")
    check script.contains("attempt < 100")
    check script.contains("setTimeout(resolve, 50)")
    check script.contains("binding(\"otterUiBootstrap\", \"{}\")")
    check page.contains("js/app.js?v=14")
    check page.contains("css/app.css?v=11")
    check page.contains("hero-circuit")
    check theme.contains("radial-gradient(circle at 5% -10%")
    check theme.contains("--otter-color-gradient: #8a969b")
    check theme.contains("--otter-color-success: #73d7a7")
    check theme.contains("--otter-color-failure: #ff718b")
    check theme.contains("color-mix(in srgb, var(--otter-color-primary) 34%")
    check theme.contains(".filters button::before")
    check theme.contains("border-radius: 14px 3px 3px 14px")
    check theme.contains("box-shadow: inset 3px 0 0 var(--otter-color-secondary)")
    check script.contains("async function startSequence(group)")
    check script.contains("await startSequenceEntry(sequence)")
    check script.contains("sequence.index += 1")
    check script.contains("group.entries[sequence.index]")
    check script.contains("function isPendingSequenceState(state)")
    check script.contains("function versionGlyph(state)")
    check script.contains("pass: \"✓\"")
    check script.contains("fail: \"×\"")
    check script.contains("resultsPath, flags: selectedFlags })")
    check script.contains("chooseResultsPath")
    check page.contains("data-pick-output")
    check page.contains("data-output-path")
    check theme.contains(".version-glyph")
    check script.contains("const selectedGroups = new Set()")
    check script.contains("event.ctrlKey || event.metaKey")
    check script.contains("if (event.shiftKey) selectRange")
    check script.contains("const alreadySelected = selectedGroups.size === 1 && selectedGroups.has(group.key)")
    check script.contains("if (!alreadySelected) selectedGroups.add(group.key)")
    check script.contains("event.target.closest(\".versions, [data-panel-run], [data-failure-link], .card-select, .tiny-copy\")")
    check script.contains("window.getSelection()?.removeAllRanges()")
    check script.contains("panel.addEventListener(\"mousedown\", event => { if (event.shiftKey) event.preventDefault(); })")
    check script.contains("$(\".card-select\", panel).addEventListener(\"click\"")
    check not script.contains("checkbox = false")
    check script.contains("Run selected (${selectedCount})")
    check script.contains("function deselectAll()")
    check script.contains("dialog.showModal()")
    check script.contains("dialog.addEventListener(\"cancel\"")
    check script.contains("JSON.stringify(currentFailure, null, 2)")
    check script.contains("plainFailureText(currentFailure)")
    check page.contains("data-failure-dialog")
    check page.contains("data-copy-text")
    check page.contains("data-copy-json")
    check page.contains("data-copy-name")
    check page.contains("data-copy-path")
    check theme.contains(".panel.is-selected")
    check theme.contains("cursor: pointer; user-select: none")
    check theme.contains(".tiny-copy")
    check theme.contains(".failure-dialog::backdrop")
    check theme.contains("overflow-x: auto")
    check theme.contains("flex: 0 0 auto")
    check script.contains("runDurationMs")
    check script.contains("compileDurationMs")
    check script.contains("ms run ·")
    check script.contains("binding(\"otterUiHeartbeat\", \"{}\")")
    check script.contains("window.setInterval(() =>")
    check script.contains("}, 500)")

  test "launcher uses isolated browser fallback and bounded startup failure":
    var
      launcher: string = readFile("src/clients/test_ui/app.nim")
    check launcher.contains("proc showUi(window: Window): bool")
    check launcher.contains("browserExist(Browsers[i])")
    check launcher.contains("WebuiBrowser(13),\n      WebuiBrowser(9),\n      WebuiBrowser(3),\n      WebuiBrowser(8),\n      WebuiBrowser(2)")
    check launcher.contains("window.setProfile(\"OtterTestUi\", profile)")
    check launcher.contains("--disable-background-networking")
    check launcher.contains("if not fileExists(readyPath):")
    check launcher.contains("startupFailed = true")
    check launcher.contains("while waitAsync():")
    check launcher.contains("HeartbeatTimeoutMs.int64")
    check launcher.contains("Otter orchestrator exited; closing the Test UI and active tests.")

  test "heartbeat leases expire after two seconds":
    var
      runtimeDir: string = joinPath(getTempDir(), "otter-ui-heartbeat-unit-" &
        $getCurrentProcessId())
    if dirExists(runtimeDir):
      removeDir(runtimeDir)
    ensureRuntimeDirectories(runtimeDir)
    check HeartbeatIntervalMs == 500
    check HeartbeatTimeoutMs == 2000
    check heartbeatExpired(runtimeDir, "webui")
    writeHeartbeat(runtimeDir, "webui")
    check not heartbeatExpired(runtimeDir, "webui", 30)
    sleep(40)
    check heartbeatExpired(runtimeDir, "webui", 30)
    removeDir(runtimeDir)

  test "first load creates editable configuration without overwriting it":
    var
      root: string = joinPath(getTempDir(), "otter-ui-defaults-" & $getCurrentProcessId())
      testsDir: string = joinPath(root, "tests")
      settingsDir: string = joinPath(testsDir, ".otter")
      configPath: string = joinPath(settingsDir, "config.toml")
      cssPath: string = joinPath(settingsDir, "config.css")
      c: OtterUiConfig
    if dirExists(root):
      removeDir(root)
    createDir(root)
    createDir(testsDir)
    c = loadOtterUiConfig(root)
    check dirExists(settingsDir)
    check fileExists(configPath)
    check fileExists(cssPath)
    check c.title == splitPath(root).tail & " Tests"
    check c.banner == DefaultBanner
    check c.outputPath == joinPath(root, "tests", ".otter", "results")
    check c.customCss == DefaultConfigCss
    check c.defaultFlags == @["*"]
    writeFile(configPath, "title = \"Preserved title\"\n" &
      "banner = \"Preserved banner\"\n" &
      "output_path = \"custom-results\"\n" &
      "default_flags = []\n")
    writeFile(cssPath, ":root { --otter-color-primary: #123456; }\n")
    c = loadOtterUiConfig(root)
    check c.title == "Preserved title"
    check c.banner == "Preserved banner"
    check c.outputPath == joinPath(root, "custom-results")
    check c.customCss == ":root { --otter-color-primary: #123456; }\n"
    removeDir(root)

  test "isolated worker compiles and runs only the selected routine":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
      e: OtterUiTestEntry = catalogEntry(C, "arithmeticPath")
      runtimeDir: string = joinPath(getTempDir(), "otter-ui-worker-" & $getCurrentProcessId())
      outputDir: string = joinPath(runtimeDir, "chosen-results")
      state: JsonNode
      log: string = ""
    if dirExists(runtimeDir):
      removeDir(runtimeDir)
    ensureRuntimeDirectories(runtimeDir)
    runWorker(getCurrentDir(), runtimeDir, e.id, outputDir)
    state = parseJson(readFile(joinPath(runtimeDir, "jobs", e.id & ".json")))
    check state["status"].getStr() == "pass"
    check state["exitCode"].getInt() == 0
    check state["compileDurationMs"].getInt() > 0
    check state["runDurationMs"].getInt() > 0
    check state["durationMs"].getInt() >= state["compileDurationMs"].getInt() +
      state["runDurationMs"].getInt()
    check fileExists(state["logPath"].getStr())
    check parentDir(state["logPath"].getStr()) == outputDir
    log = readFile(state["logPath"].getStr())
    check log.contains("arithmetic path passed")
    check not log.contains("text path version 1 passed")
    removeDir(runtimeDir)

  test "annotated routine executes on its own worker thread":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
      e: OtterUiTestEntry = catalogEntry(C, "threadedPath")
      runtimeDir: string = joinPath(getTempDir(), "otter-ui-thread-" &
        $getCurrentProcessId())
      state: JsonNode
      log: string = ""
    if dirExists(runtimeDir):
      removeDir(runtimeDir)
    ensureRuntimeDirectories(runtimeDir)
    runWorker(getCurrentDir(), runtimeDir, e.id)
    state = parseJson(readFile(joinPath(runtimeDir, "jobs", e.id & ".json")))
    check state["status"].getStr() == "pass"
    log = readFile(state["logPath"].getStr())
    check log.contains("dedicated test thread passed")
    removeDir(runtimeDir)

  test "selected optional flag reaches worker compilation":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
      e: OtterUiTestEntry = catalogEntry(C, "optionalFlagPath")
      runtimeDir: string = joinPath(getTempDir(), "otter-ui-flag-" &
        $getCurrentProcessId())
      state: JsonNode
      log: string = ""
    if dirExists(runtimeDir):
      removeDir(runtimeDir)
    ensureRuntimeDirectories(runtimeDir)
    runWorker(getCurrentDir(), runtimeDir, e.id, flags = @["otterOptionalTrace"])
    state = parseJson(readFile(joinPath(runtimeDir, "jobs", e.id & ".json")))
    check state["status"].getStr() == "pass"
    log = readFile(state["logPath"].getStr())
    check log.contains("-d:otterOptionalTrace")
    check log.contains("optional Otter flag passed")
    removeDir(runtimeDir)

  test "failed worker reports message location and source context":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
      e: OtterUiTestEntry = catalogEntry(C, "intentionalFailure")
      runtimeDir: string = joinPath(getTempDir(), "otter-ui-failure-" & $getCurrentProcessId())
      state: JsonNode
    if dirExists(runtimeDir):
      removeDir(runtimeDir)
    ensureRuntimeDirectories(runtimeDir)
    runWorker(getCurrentDir(), runtimeDir, e.id)
    state = parseJson(readFile(joinPath(runtimeDir, "jobs", e.id & ".json")))
    check state["status"].getStr() == "fail"
    check state["exitCode"].getInt() != 0
    check state["failureMessage"].getStr().contains("Check failed")
    check state["failurePath"].getStr().endsWith("tests/test_ui_failure_example.nim")
    check state["failureLine"].getInt() > 0
    check state["failureCode"].getStr().contains("check 2 + 2 == 5")
    removeDir(runtimeDir)

  test "relay and test backends isolate worker crashes":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
      e: OtterUiTestEntry = catalogEntry(C, "optionalFlagPath")
      crash: OtterUiTestEntry = catalogEntry(C, "intentionalProcessExit")
      runtimeDir: string = joinPath(getTempDir(), "otter-ui-spawner-" & $getCurrentProcessId())
      outputDir: string = joinPath(runtimeDir, "picked-results")
      appPath: string = absolutePath(joinPath("build", "otter-test-ui-contract" & ExeExt))
      command: string = ""
      buildResult: tuple[output: string, exitCode: int]
      orchestrator: Process
      testBackend: Process
      directResponse: JsonNode
      response: JsonNode
      state: JsonNode
      i: int = 0
    if dirExists(runtimeDir):
      removeDir(runtimeDir)
    createDir("build")
    command = "nim c --threads:on --path:src --out:" & quoteShell(appPath) &
      " src/clients/test_ui/app.nim"
    buildResult = execCmdEx(command, options = {poUsePath, poStdErrToStdOut})
    check buildResult.exitCode == 0
    ensureRuntimeDirectories(runtimeDir)
    writeHeartbeat(runtimeDir, "webui")
    writeHeartbeat(runtimeDir, "orchestrator")
    writeFile(joinPath(runtimeDir, "processes", "main.pid"),
      $getCurrentProcessId() & "\n")
    testBackend = startProcess(appPath, workingDir = getCurrentDir(), args = @[
      "--otter-mode:test-backend", "--repo-root:" & getCurrentDir(),
      "--runtime-path:" & runtimeDir], options = {poParentStreams})
    orchestrator = startProcess(appPath, workingDir = getCurrentDir(), args = @[
      "--otter-mode:orchestrator", "--repo-root:" & getCurrentDir(),
      "--runtime-path:" & runtimeDir], options = {poParentStreams})
    try:
      directResponse = backendRequest(runtimeDir, %*{"action": "bootstrap"})
      response = orchestratorRequest(runtimeDir, %*{"action": "bootstrap"})
      check response == directResponse
      response = orchestratorRequest(runtimeDir, %*{"action": "topology"})
      check response["ok"].getBool()
      check response["mainPid"].getInt() == getCurrentProcessId()
      check response["orchestratorPid"].getInt() == processID(orchestrator)
      check response["testBackendPid"].getInt() == processID(testBackend)
      check response["mainPid"].getInt() != response["orchestratorPid"].getInt()
      check response["mainPid"].getInt() != response["testBackendPid"].getInt()
      check response["orchestratorPid"].getInt() != response["testBackendPid"].getInt()
      response = orchestratorRequest(runtimeDir, %*{
        "action": "start", "id": e.id, "resultsPath": outputDir,
        "flags": ["notDiscoveredByOtter"]})
      check not response["ok"].getBool()
      check response["error"].getStr().contains("unsupported Otter compile flag")
      response = orchestratorRequest(runtimeDir, %*{
        "action": "start", "id": crash.id, "resultsPath": outputDir})
      check response["ok"].getBool()
      check response["pid"].getInt() != processID(orchestrator)
      check response["pid"].getInt() != processID(testBackend)
      i = 0
      state = newJNull()
      while i < 300:
        writeHeartbeat(runtimeDir, "webui")
        response = orchestratorRequest(runtimeDir, %*{"action": "poll"})
        for candidate in response["jobs"]:
          if candidate{"id"}.getStr("") == crash.id:
            state = candidate
        if state.kind != JNull and state{"status"}.getStr("") notin ["queued", "running"]:
          break
        sleep(50)
        i = i + 1
      check state{"status"}.getStr("") == "fail"
      check state{"exitCode"}.getInt() == 23
      check state["flags"][0].getStr() == "otterOptionalTrace"
      check testBackend.running()
      check orchestrator.running()
      response = orchestratorRequest(runtimeDir, %*{
        "action": "start", "id": e.id, "resultsPath": outputDir,
        "flags": ["otterOptionalTrace"]})
      check response["ok"].getBool()
      check response["pid"].getInt() != getCurrentProcessId()
      i = 0
      state = newJNull()
      while i < 300:
        writeHeartbeat(runtimeDir, "webui")
        response = orchestratorRequest(runtimeDir, %*{"action": "poll"})
        for candidate in response["jobs"]:
          if candidate{"id"}.getStr("") == e.id:
            state = candidate
        if state.kind != JNull and state{"status"}.getStr("") notin ["queued", "running"]:
          break
        sleep(50)
        i = i + 1
      check state{"status"}.getStr("") == "pass"
      check fileExists(state{"logPath"}.getStr(""))
      check parentDir(state{"logPath"}.getStr("")) == outputDir
      check state["flags"][0].getStr() == "otterOptionalTrace"
      check readFile(state{"logPath"}.getStr("")).contains("-d:otterOptionalTrace")
      response = orchestratorRequest(runtimeDir, %*{"action": "shutdown"})
      check response["ok"].getBool()
    finally:
      if orchestrator != nil and orchestrator.running():
        orchestrator.terminate()
      if orchestrator != nil:
        discard orchestrator.waitForExit(3000)
        orchestrator.close()
      if testBackend != nil and testBackend.running():
        testBackend.terminate()
      if testBackend != nil:
        discard testBackend.waitForExit(3000)
        testBackend.close()
      if dirExists(runtimeDir):
        removeDir(runtimeDir)

  test "missing WebUI pings abort an active test process tree":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
      e: OtterUiTestEntry = catalogEntry(C, "heartbeatLeasePath")
      runtimeDir: string = joinPath(getTempDir(), "otter-ui-lease-process-" &
        $getCurrentProcessId())
      outputDir: string = joinPath(runtimeDir, "results")
      appPath: string = absolutePath(joinPath("build", "otter-test-ui-contract" & ExeExt))
      command: string = ""
      buildResult: tuple[output: string, exitCode: int]
      orchestrator: Process
      testBackend: Process
      response: JsonNode
      state: JsonNode
      logPath: string = ""
      workerPid: int = 0
      commandPid: int = 0
      i: int = 0
      leaseStart: MonoTime
      shutdownMs: int64 = 0
    if dirExists(runtimeDir):
      removeDir(runtimeDir)
    createDir("build")
    command = "nim c --threads:on --path:src --out:" & quoteShell(appPath) &
      " src/clients/test_ui/app.nim"
    buildResult = execCmdEx(command, options = {poUsePath, poStdErrToStdOut})
    check buildResult.exitCode == 0
    ensureRuntimeDirectories(runtimeDir)
    writeHeartbeat(runtimeDir, "webui")
    writeHeartbeat(runtimeDir, "orchestrator")
    testBackend = startProcess(appPath, workingDir = getCurrentDir(), args = @[
      "--otter-mode:test-backend", "--repo-root:" & getCurrentDir(),
      "--runtime-path:" & runtimeDir], options = {poParentStreams})
    orchestrator = startProcess(appPath, workingDir = getCurrentDir(), args = @[
      "--otter-mode:orchestrator", "--repo-root:" & getCurrentDir(),
      "--runtime-path:" & runtimeDir], options = {poParentStreams})
    try:
      response = orchestratorRequest(runtimeDir, %*{
        "action": "start", "id": e.id, "resultsPath": outputDir})
      check response["ok"].getBool()
      workerPid = response["pid"].getInt()
      while i < 600:
        writeHeartbeat(runtimeDir, "webui")
        response = orchestratorRequest(runtimeDir, %*{"action": "poll"})
        for candidate in response["jobs"]:
          if candidate{"id"}.getStr("") == e.id:
            state = candidate
        logPath = state{"logPath"}.getStr("")
        if logPath.len > 0 and fileExists(logPath) and
            readFile(logPath).contains("[run]"):
          break
        sleep(50)
        i = i + 1
      check logPath.len > 0
      check fileExists(logPath)
      check readFile(logPath).contains("[run]")
      commandPid = parseInt(readFile(joinPath(runtimeDir, "jobs",
        e.id & ".command.pid")).strip())
      leaseStart = getMonoTime()
      i = 0
      while i < 120 and (orchestrator.running() or testBackend.running()):
        sleep(50)
        i = i + 1
      shutdownMs = inMilliseconds(getMonoTime() - leaseStart)
      check not orchestrator.running()
      check not testBackend.running()
      check shutdownMs <= 2500
      check not processIsRunning(workerPid)
      check not processIsRunning(commandPid)
      state = parseJson(readFile(joinPath(runtimeDir, "jobs", e.id & ".json")))
      check state{"status"}.getStr("") == "stopped"
      check state{"exitCode"}.getInt() == 130
    finally:
      if orchestrator != nil and orchestrator.running():
        orchestrator.terminate()
      if orchestrator != nil:
        discard orchestrator.waitForExit(3000)
        orchestrator.close()
      if testBackend != nil and testBackend.running():
        testBackend.terminate()
      if testBackend != nil:
        discard testBackend.waitForExit(3000)
        testBackend.close()
      if dirExists(runtimeDir):
        removeDir(runtimeDir)

  test "missing orchestrator pings abort an active test process tree":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
      e: OtterUiTestEntry = catalogEntry(C, "heartbeatLeasePath")
      runtimeDir: string = joinPath(getTempDir(), "otter-ui-orchestrator-lease-" &
        $getCurrentProcessId())
      outputDir: string = joinPath(runtimeDir, "results")
      appPath: string = absolutePath(joinPath("build", "otter-test-ui-contract" & ExeExt))
      command: string = ""
      buildResult: tuple[output: string, exitCode: int]
      testBackend: Process
      response: JsonNode
      state: JsonNode
      logPath: string = ""
      workerPid: int = 0
      commandPid: int = 0
      i: int = 0
      leaseStart: MonoTime
      shutdownMs: int64 = 0
    if dirExists(runtimeDir):
      removeDir(runtimeDir)
    createDir("build")
    command = "nim c --threads:on --path:src --out:" & quoteShell(appPath) &
      " src/clients/test_ui/app.nim"
    buildResult = execCmdEx(command, options = {poUsePath, poStdErrToStdOut})
    check buildResult.exitCode == 0
    ensureRuntimeDirectories(runtimeDir)
    writeHeartbeat(runtimeDir, "webui")
    writeHeartbeat(runtimeDir, "orchestrator")
    testBackend = startProcess(appPath, workingDir = getCurrentDir(), args = @[
      "--otter-mode:test-backend", "--repo-root:" & getCurrentDir(),
      "--runtime-path:" & runtimeDir], options = {poParentStreams})
    try:
      response = backendRequest(runtimeDir, %*{
        "action": "start", "id": e.id, "resultsPath": outputDir})
      check response["ok"].getBool()
      workerPid = response["pid"].getInt()
      while i < 600:
        writeHeartbeat(runtimeDir, "webui")
        writeHeartbeat(runtimeDir, "orchestrator")
        response = backendRequest(runtimeDir, %*{"action": "poll"})
        for candidate in response["jobs"]:
          if candidate{"id"}.getStr("") == e.id:
            state = candidate
        logPath = state{"logPath"}.getStr("")
        if logPath.len > 0 and fileExists(logPath) and
            readFile(logPath).contains("[run]"):
          break
        sleep(50)
        i = i + 1
      check logPath.len > 0
      check fileExists(logPath)
      check readFile(logPath).contains("[run]")
      commandPid = parseInt(readFile(joinPath(runtimeDir, "jobs",
        e.id & ".command.pid")).strip())
      leaseStart = getMonoTime()
      i = 0
      while i < 120 and testBackend.running():
        writeHeartbeat(runtimeDir, "webui")
        sleep(50)
        i = i + 1
      shutdownMs = inMilliseconds(getMonoTime() - leaseStart)
      check not testBackend.running()
      check shutdownMs <= 2500
      check not processIsRunning(workerPid)
      check not processIsRunning(commandPid)
      state = parseJson(readFile(joinPath(runtimeDir, "jobs", e.id & ".json")))
      check state{"status"}.getStr("") == "stopped"
      check state{"exitCode"}.getInt() == 130
    finally:
      if testBackend != nil and testBackend.running():
        testBackend.terminate()
      if testBackend != nil:
        discard testBackend.waitForExit(3000)
        testBackend.close()
      if dirExists(runtimeDir):
        removeDir(runtimeDir)
