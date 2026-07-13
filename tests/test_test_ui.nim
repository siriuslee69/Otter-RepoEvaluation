# ============================================================
# | Otter Test UI Tests                                      |
# | -> Verify discovery, configuration, grouping, and worker |
# ============================================================

import std/[json, os, osproc, strutils, unittest]

import ../.iron/metaPragmas
import otter_repo_evaluation

proc catalogEntry(C: OtterUiCatalog, routine: string): OtterUiTestEntry
    {.role: parser, metaTags: {tagTesting, tagUi}.} =
  ## C: discovered catalog.
  ## routine: annotated routine name to find.
  for entry in C.entries:
    if entry.routine == routine:
      return entry
  raise newException(ValueError, "missing UI test routine: " & routine)

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

  test "loads project theme and output configuration":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
    check C.config.title == "Otter Test Laboratory"
    check C.config.banner.len > 0
    check C.config.outputPath.endsWith(joinPath("tests", ".otter", "results"))
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
    check page.contains("js/app.js?v=10")
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
    check script.contains("resultsPath })")
    check script.contains("chooseResultsPath")
    check page.contains("data-pick-output")
    check page.contains("data-output-path")
    check theme.contains(".version-glyph")
    check script.contains("const selectedGroups = new Set()")
    check script.contains("event.ctrlKey || event.metaKey")
    check script.contains("if (event.shiftKey) selectRange")
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

  test "missing configuration uses repository defaults":
    var
      root: string = joinPath(getTempDir(), "otter-ui-defaults-" & $getCurrentProcessId())
      testsDir: string = joinPath(root, "tests")
      c: OtterUiConfig
    if dirExists(root):
      removeDir(root)
    createDir(root)
    createDir(testsDir)
    c = loadOtterUiConfig(root)
    check c.title == splitPath(root).tail
    check c.banner == DefaultBanner
    check c.outputPath == joinPath(root, "tests", ".otter", "results")
    check c.customCss.len == 0
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
    check fileExists(state["logPath"].getStr())
    check parentDir(state["logPath"].getStr()) == outputDir
    log = readFile(state["logPath"].getStr())
    check log.contains("arithmetic path passed")
    check not log.contains("text path version 1 passed")
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

  test "spawner launches and reports a separate worker process":
    var
      C: OtterUiCatalog = discoverOtterUiTests(getCurrentDir())
      e: OtterUiTestEntry = catalogEntry(C, "textPathV1")
      runtimeDir: string = joinPath(getTempDir(), "otter-ui-spawner-" & $getCurrentProcessId())
      outputDir: string = joinPath(runtimeDir, "picked-results")
      appPath: string = absolutePath(joinPath("build", "otter-test-ui-contract" & ExeExt))
      command: string = ""
      buildResult: tuple[output: string, exitCode: int]
      spawner: Process
      response: JsonNode
      state: JsonNode
      i: int = 0
    if dirExists(runtimeDir):
      removeDir(runtimeDir)
    createDir("build")
    command = "nim c --path:src --out:" & quoteShell(appPath) &
      " src/clients/test_ui/app.nim"
    buildResult = execCmdEx(command, options = {poUsePath, poStdErrToStdOut})
    check buildResult.exitCode == 0
    ensureRuntimeDirectories(runtimeDir)
    spawner = startProcess(appPath, workingDir = getCurrentDir(), args = @[
      "--otter-mode:spawner", "--repo-root:" & getCurrentDir(),
      "--runtime-path:" & runtimeDir], options = {poParentStreams})
    try:
      response = spawnerRequest(runtimeDir, %*{
        "action": "start", "id": e.id, "resultsPath": outputDir})
      check response["ok"].getBool()
      check response["pid"].getInt() != getCurrentProcessId()
      while i < 300:
        response = spawnerRequest(runtimeDir, %*{"action": "poll"})
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
      response = spawnerRequest(runtimeDir, %*{"action": "shutdown"})
      check response["ok"].getBool()
    finally:
      if spawner != nil and spawner.running():
        spawner.terminate()
      if spawner != nil:
        discard spawner.waitForExit(3000)
        spawner.close()
      if dirExists(runtimeDir):
        removeDir(runtimeDir)
