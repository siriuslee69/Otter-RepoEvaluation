# ============================================================
# | Otter Test UI Jobs                                       |
# | -> Relay, persistent test backend, and isolated workers |
# ============================================================

import std/[json, monotimes, os, osproc, strutils, tables, times]

when not defined(windows):
  import std/posix

import ../../../meta/metaPragmas
import ./[catalog, types]

const
  RelayChannel = "relay"
  BackendChannel = "backend"
  RequestWaitCount = 200
  RequestWaitMs = 25
  WorkerPollMs = 100
  HeartbeatIntervalMs* = 500
  HeartbeatTimeoutMs* = 2000
  NanosecondsPerMillisecond = 1_000_000'i64

type
  ManagedJob {.role: memory, metaTags: {tagExecution, tagTesting, tagUi}.} = object
    id: string
    process: Process

proc channelDirectory(dir, channel: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/channel: runtime root and isolated IPC channel.
  result = joinPath(dir, channel)

proc requestsDirectory(dir, channel: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/channel: runtime root and its request queue.
  result = joinPath(channelDirectory(dir, channel), "requests")

proc responsesDirectory(dir, channel: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/channel: runtime root and its response queue.
  result = joinPath(channelDirectory(dir, channel), "responses")

proc jobsDirectory(dir: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir: runtime root.
  result = joinPath(dir, "jobs")

proc processesDirectory(dir: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir: runtime root containing persistent process identity files.
  result = joinPath(dir, "processes")

proc ensureRuntimeDirectories*(dir: string) {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir: runtime root initialized for file-based IPC.
  createDir(dir)
  createDir(channelDirectory(dir, RelayChannel))
  createDir(requestsDirectory(dir, RelayChannel))
  createDir(responsesDirectory(dir, RelayChannel))
  createDir(channelDirectory(dir, BackendChannel))
  createDir(requestsDirectory(dir, BackendChannel))
  createDir(responsesDirectory(dir, BackendChannel))
  createDir(jobsDirectory(dir))
  createDir(processesDirectory(dir))

proc atomicWrite(path, content: string) {.role: dataWriter,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## path/content: destination and complete replacement payload.
  var
    temporary: string = path & ".tmp-" & $getCurrentProcessId()
  writeFile(temporary, content)
  moveFile(temporary, path)

proc heartbeatPath(dir, name: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/name: runtime root and owner whose liveness lease is stored.
  result = joinPath(processesDirectory(dir), name & ".heartbeat")

proc writeHeartbeat*(dir, name: string) {.role: dataWriter,
    metaTags: {tagExecution, tagTesting, tagUi, tagTiming}.} =
  ## dir/name: runtime root and owner renewing its liveness lease.
  ensureRuntimeDirectories(dir)
  atomicWrite(heartbeatPath(dir, name), $getMonoTime().ticks & "\n")

proc heartbeatExpired*(dir, name: string,
    timeoutMs: int = HeartbeatTimeoutMs): bool {.role: parser,
    metaTags: {tagExecution, tagTesting, tagUi, tagTiming}.} =
  ## dir/name/timeoutMs: lease to reject after the bounded silence interval.
  var
    path: string = heartbeatPath(dir, name)
    heartbeatTicks: int64 = 0
    elapsedTicks: int64 = 0
  if not fileExists(path):
    return true
  try:
    heartbeatTicks = parseBiggestInt(readFile(path).strip()).int64
  except ValueError:
    return true
  elapsedTicks = getMonoTime().ticks - heartbeatTicks
  result = elapsedTicks < 0 or
    elapsedTicks >= timeoutMs.int64 * NanosecondsPerMillisecond

proc requestId(): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  result = $getCurrentProcessId() & "-" & $epochTime().int64 & "-" &
    $getTime().nanosecond

proc ipcRequest(dir, channel, unavailable: string, request: JsonNode): JsonNode
    {.role: dataFetcher, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/channel/unavailable/request: isolated queue and one synchronous command.
  var
    id: string = requestId()
    requestPath: string = joinPath(requestsDirectory(dir, channel), id & ".json")
    responsePath: string = joinPath(responsesDirectory(dir, channel), id & ".json")
    i: int = 0
  atomicWrite(requestPath, $request)
  while i < RequestWaitCount and not fileExists(responsePath):
    sleep(RequestWaitMs)
    i = i + 1
  if not fileExists(responsePath):
    raise newException(IOError, unavailable)
  result = parseJson(readFile(responsePath))
  removeFile(responsePath)

proc orchestratorRequest*(dir: string, request: JsonNode): JsonNode
    {.role: dataFetcher, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/request: browser-side message relayed through the orchestrator backend.
  result = ipcRequest(dir, RelayChannel,
    "Otter relay orchestrator did not answer", request)

proc backendRequest*(dir: string, request: JsonNode): JsonNode
    {.role: dataFetcher, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/request: orchestrator-side message sent to the test backend.
  result = ipcRequest(dir, BackendChannel,
    "Otter test backend did not answer", request)

proc spawnerRequest*(dir: string, request: JsonNode): JsonNode
    {.role: dataFetcher, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## Compatibility alias for callers that use the complete relay path.
  result = orchestratorRequest(dir, request)

proc writeProcessIdentity*(dir, name: string) {.role: dataWriter,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/name: runtime root and persistent process role being announced.
  ensureRuntimeDirectories(dir)
  atomicWrite(joinPath(processesDirectory(dir), name & ".pid"),
    $getCurrentProcessId() & "\n")

proc jobStatePath(dir, id: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/id: runtime root and catalog identity.
  result = joinPath(jobsDirectory(dir), id & ".json")

proc cancelPath(dir, id: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/id: runtime root and catalog identity.
  result = joinPath(jobsDirectory(dir), id & ".cancel")

proc commandPidPath(dir, id: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/id: runtime root and worker command process-group identity.
  result = joinPath(jobsDirectory(dir), id & ".command.pid")

proc entryWithId(C: OtterUiCatalog, id: string): OtterUiTestEntry
    {.role: parser, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## C/id: discovered catalog and allowlisted identity.
  for entry in C.entries:
    if entry.id == id:
      return entry
  raise newException(ValueError, "unknown Otter UI test id: " & id)

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

proc bootstrapState(C: OtterUiCatalog): JsonNode {.role: dataWriter,
    metaTags: {tagTesting, tagUi}.} =
  ## C: discovered test catalog serialized for relay to the WebUI backend.
  var
    entries: JsonNode = newJArray()
  for entry in C.entries:
    entries.add(entryJson(entry))
  result = %*{
    "ok": true,
    "config": configJson(C.config),
    "entries": entries,
    "availableFlags": C.availableFlags,
    "defaultFlags": C.defaultFlags
  }

proc processIdentity(dir, name: string): int {.role: dataFetcher,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/name: runtime root and persistent process role whose PID is read.
  var
    path: string = joinPath(processesDirectory(dir), name & ".pid")
  if not fileExists(path):
    return 0
  try:
    result = parseInt(readFile(path).strip())
  except ValueError:
    result = 0

proc topologyState(runtimeDir: string): JsonNode {.role: dataWriter,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## runtimeDir: process identity root exposed for diagnostics and tests.
  result = %*{
    "ok": true,
    "mainPid": processIdentity(runtimeDir, "main"),
    "orchestratorPid": processIdentity(runtimeDir, "orchestrator"),
    "testBackendPid": processIdentity(runtimeDir, "test-backend")
  }

proc initialState(e: OtterUiTestEntry, flags: openArray[string] = []): JsonNode {.role: truthBuilder,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## e: discovered test represented as a queued job.
  result = %*{
    "id": e.id,
    "testName": e.testName,
    "version": e.version,
    "status": "queued",
    "exitCode": 0,
    "durationMs": 0,
    "compileDurationMs": 0,
    "runDurationMs": 0,
    "flags": flags,
    "logPath": "",
    "failureMessage": "",
    "failurePath": "",
    "failureLine": 0,
    "failureCode": ""
  }

proc locationFromLine(line, repoRoot: string): tuple[path: string, line: int]
    {.role: parser, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## line/repoRoot: compiler or stack line and root used to resolve its Nim file.
  var
    openAt: int = line.find('(')
    commaAt: int = -1
    closeAt: int = -1
    lineText: string = ""
    path: string = ""
  if openAt <= 0:
    return
  commaAt = line.find(',', openAt + 1)
  closeAt = line.find(')', openAt + 1)
  if closeAt < 0:
    return
  if commaAt < 0 or commaAt > closeAt:
    commaAt = closeAt
  lineText = line[openAt + 1 ..< commaAt].strip()
  try:
    result.line = parseInt(lineText)
  except ValueError:
    return
  path = line[0 ..< openAt].strip()
  if not path.endsWith(".nim"):
    result.line = 0
    return
  if not path.isAbsolute():
    path = joinPath(repoRoot, path)
  path = normalizedPath(path)
  if fileExists(path):
    result.path = path

proc failureMessage(L: openArray[string], exitCode: int): string
    {.role: parser, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## L/exitCode: complete log lines and process exit used for one summary.
  var
    i: int = 0
    clean: string = ""
  while i < L.len:
    clean = L[i].strip()
    if clean.contains("Check failed:") or clean.contains("Unhandled exception:"):
      return clean
    i = i + 1
  i = L.len - 1
  while i >= 0:
    clean = L[i].strip()
    if clean.contains(" Error:") or clean.startsWith("Error:"):
      return clean
    i = i - 1
  result = "Test exited with code " & $exitCode

proc failureLocation(L: openArray[string], repoRoot, sourcePath: string,
    defaultLine: int): tuple[path: string, line: int]
    {.role: parser, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## L/repoRoot/sourcePath/defaultLine: log and fallback declaration location.
  var
    i: int = L.len - 1
    candidate: tuple[path: string, line: int]
  while i >= 0:
    candidate = locationFromLine(L[i], repoRoot)
    if candidate.path.len > 0:
      return candidate
    i = i - 1
  result.path = sourcePath
  result.line = defaultLine

proc codeExcerpt(path: string, line: int): string {.role: dataFetcher,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## path/line: source and central one-based line rendered with nearby context.
  var
    L: seq[string] = @[]
    startAt: int = 0
    stopAt: int = 0
    i: int = 0
  if not fileExists(path):
    return
  L = readFile(path).splitLines()
  startAt = max(0, line - 4)
  stopAt = min(L.len - 1, line + 2)
  i = startAt
  while i <= stopAt:
    result.add(align($(i + 1), 5) & (if i + 1 == line: " > " else: " | ") & L[i] & "\n")
    i = i + 1

proc attachFailureDetails(S: var JsonNode, e: OtterUiTestEntry, repoRoot,
    logPath: string, exitCode: int) {.role: truthBuilder,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## S/e/repoRoot/logPath/exitCode: failed state and its persisted process log.
  var
    L: seq[string] = @[]
    location: tuple[path: string, line: int]
  if fileExists(logPath):
    L = readFile(logPath).splitLines()
  location = failureLocation(L, repoRoot, e.sourcePath, e.line)
  S["failureMessage"] = %failureMessage(L, exitCode)
  S["failurePath"] = %location.path.replace('\\', '/')
  S["failureLine"] = %location.line
  S["failureCode"] = %codeExcerpt(location.path, location.line)

proc terminateProcessTree(pid: int) {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## pid: process-group leader whose complete isolated tree is killed.
  if pid <= 0:
    return
  when defined(windows):
    discard execCmd("taskkill /PID " & $pid & " /T /F")
  else:
    discard posix.kill(Pid(-pid), SIGKILL)

proc terminateProcessTree(p: Process) {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## p: running process whose isolated process group is killed.
  if p != nil and p.running():
    terminateProcessTree(processID(p))
    if p.running():
      p.kill()

proc quoteArgs(A: openArray[string]): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## A: process arguments quoted for shell execution and logs.
  var
    i: int = 0
  while i < A.len:
    if i > 0:
      result.add(" ")
    result.add(quoteShell(A[i]))
    i = i + 1

proc appendLogHeader(path, label, command: string, A: openArray[string], append: bool)
    {.role: dataWriter, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## path/label/command/A/append: log destination and launched command.
  var
    content: string = "[" & label & "] $ " & command & " " & quoteArgs(A) & "\n\n"
    prior: string = ""
  if append and fileExists(path):
    prior = readFile(path)
  writeFile(path, prior & content)

proc redirectedCommand(command: string, A: openArray[string], logPath: string): string
    {.role: helper, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## command/A/logPath: child command redirected into an existing log.
  result = quoteShell(command) & " " & quoteArgs(A) & " >> " &
    quoteShell(logPath) & " 2>&1"

proc runCancellable(command: string, A: openArray[string], repoRoot, logPath,
    stopPath, pidPath: string): int {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## command/A/repoRoot/logPath/stopPath/pidPath: cancellable command contract.
  var
    shellCommand: string = redirectedCommand(command, A, logPath)
    process: Process
    options: set[ProcessOption] = {poUsePath}
  when defined(linux):
    process = startProcess("setsid", workingDir = repoRoot,
      args = @["sh", "-c", shellCommand], options = options)
  else:
    options.incl(poEvalCommand)
    when not defined(windows):
      options.incl(poDaemon)
    process = startProcess(shellCommand, workingDir = repoRoot,
      options = options)
  atomicWrite(pidPath, $processID(process) & "\n")
  defer:
    if fileExists(pidPath):
      removeFile(pidPath)
  while process.running():
    if fileExists(stopPath):
      terminateProcessTree(process)
      discard process.waitForExit(3000)
      process.close()
      return 130
    sleep(WorkerPollMs)
  result = process.waitForExit()
  process.close()

proc otterSourceDirectory(): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  result = parentDir(parentDir(parentDir(currentSourcePath())))

proc executablePath(repoRoot: string, e: OtterUiTestEntry): string
    {.role: helper, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## repoRoot/e: output root and test identity.
  var
    filename: string = e.id
  when defined(windows):
    filename.add(".exe")
  result = joinPath(repoRoot, "build", "otter_test_ui", "bin", filename)

proc compileArguments(C: OtterUiCatalog, e: OtterUiTestEntry,
    flags: openArray[string]): seq[string]
    {.role: truthBuilder, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## C/e/flags: catalog test and validated optional compile-time symbols.
  var
    cachePath: string = joinPath(C.config.repoRoot, "build", "otter_test_ui",
      "nimcache", e.id)
    i: int = 0
  result = @["c", "--threads:on", "--path:" & otterSourceDirectory(),
    "--nimcache:" & cachePath, "--out:" & executablePath(C.config.repoRoot, e),
    "-d:OtterUiTarget:" & e.routine]
  while i < flags.len:
    if flags[i] == "gcArc":
      result.add("--mm:arc")
    elif flags[i] == "gcOrc":
      result.add("--mm:orc")
    elif flags[i] == "sse2":
      result.add("-d:sse2")
      result.add("--passC:-msse2")
    elif flags[i] == "avx2":
      result.add("-d:avx2")
      result.add("--passC:-mavx2")
      result.add("--passL:-mavx2")
    elif flags[i] == "aesni":
      result.add("-d:aesni")
      result.add("--passC:-maes")
    elif flags[i] == "neon":
      result.add("-d:neon")
    else:
      result.add("-d:" & flags[i])
    i = i + 1
  result.add(e.sourcePath)

proc finalStatus(exitCode: int): string {.role: parser,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## exitCode: worker result mapped to a stable browser status.
  if exitCode == 0:
    result = "pass"
  elif exitCode == 130:
    result = "stopped"
  else:
    result = "fail"

proc runWorker*(repoRoot, runtimeDir, id: string, resultsPath: string = "",
    flags: seq[string] = @[]) {.role: metaOrchestrator,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## repoRoot/runtimeDir/id/resultsPath/flags: isolated test execution contract.
  var
    C: OtterUiCatalog = discoverOtterUiTests(repoRoot)
    e: OtterUiTestEntry = entryWithId(C, id)
    S: JsonNode = initialState(e, flags)
    startTime: MonoTime = getMonoTime()
    phaseTime: MonoTime
    stamp: string = now().format("yyyyMMdd-HHmmss")
    outputPath: string = resultsPath.strip()
    logPath: string = ""
    statePath: string = jobStatePath(runtimeDir, id)
    stopPath: string = cancelPath(runtimeDir, id)
    pidPath: string = commandPidPath(runtimeDir, id)
    args: seq[string] = @[]
    exitCode: int = 0
  if outputPath.len == 0:
    outputPath = C.config.outputPath
  if not outputPath.isAbsolute():
    outputPath = joinPath(C.config.repoRoot, outputPath)
  outputPath = normalizedPath(outputPath)
  logPath = joinPath(outputPath, stamp & "-" & e.id & ".log")
  createDir(outputPath)
  createDir(parentDir(executablePath(C.config.repoRoot, e)))
  S["status"] = %"running"
  S["logPath"] = %logPath.replace('\\', '/')
  atomicWrite(statePath, $S)
  args = compileArguments(C, e, flags)
  appendLogHeader(logPath, "compile", "nim", args, false)
  phaseTime = getMonoTime()
  exitCode = runCancellable("nim", args, C.config.repoRoot, logPath, stopPath,
    pidPath)
  S["compileDurationMs"] = %inMilliseconds(getMonoTime() - phaseTime)
  atomicWrite(statePath, $S)
  if exitCode == 0:
    args = @[]
    putEnv("OTTER_UI_FLAGS", flags.join(","))
    appendLogHeader(logPath, "run", executablePath(C.config.repoRoot, e), args, true)
    phaseTime = getMonoTime()
    exitCode = runCancellable(executablePath(C.config.repoRoot, e), args,
      C.config.repoRoot, logPath, stopPath, pidPath)
    S["runDurationMs"] = %inMilliseconds(getMonoTime() - phaseTime)
  S["status"] = %finalStatus(exitCode)
  S["exitCode"] = %exitCode
  S["durationMs"] = %inMilliseconds(getMonoTime() - startTime)
  if exitCode != 0 and exitCode != 130:
    attachFailureDetails(S, e, C.config.repoRoot, logPath, exitCode)
  atomicWrite(statePath, $S)

proc workerArguments(repoRoot, runtimeDir, id, resultsPath: string,
    flags: openArray[string]): seq[string]
    {.role: truthBuilder, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## repoRoot/runtimeDir/id/resultsPath/flags: values passed to a worker process.
  result = @["--otter-mode:worker", "--repo-root:" & repoRoot,
    "--runtime-path:" & runtimeDir, "--test-id:" & id,
    "--results-path:" & resultsPath, "--compile-flags:" & flags.join(",")]

proc requestedFlags(request: JsonNode, C: OtterUiCatalog): seq[string]
    {.role: parser, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## request/C: browser symbols validated against repository discovery.
  var
    flag: string = ""
  if request.kind != JObject or not request.hasKey("flags") or
      request["flags"].kind != JArray:
    return C.defaultFlags
  for item in request["flags"]:
    flag = item.getStr("")
    if flag notin C.availableFlags:
      raise newException(ValueError, "unsupported Otter compile flag: " & flag)
    if flag notin result:
      result.add(flag)
  if "gcArc" in result and "gcOrc" in result:
    raise newException(ValueError,
      "gcArc and gcOrc cannot be enabled together")

proc startManagedJob(appPath, repoRoot, runtimeDir, id, resultsPath: string,
    flags: openArray[string], C: OtterUiCatalog): ManagedJob {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## appPath/repoRoot/runtimeDir/id/resultsPath/C: worker launch contract.
  var
    e: OtterUiTestEntry = entryWithId(C, id)
    stopPath: string = cancelPath(runtimeDir, id)
    options: set[ProcessOption] = {poParentStreams}
    launchArgs: seq[string] = @[]
  if fileExists(stopPath):
    removeFile(stopPath)
  atomicWrite(jobStatePath(runtimeDir, id), $initialState(e, flags))
  result.id = id
  when defined(linux):
    launchArgs = @[appPath]
    launchArgs.add(workerArguments(repoRoot, runtimeDir, id, resultsPath, flags))
    options.incl(poUsePath)
    result.process = startProcess("setsid", workingDir = repoRoot,
      args = launchArgs, options = options)
  else:
    when not defined(windows):
      options.incl(poDaemon)
    result.process = startProcess(appPath, workingDir = repoRoot,
      args = workerArguments(repoRoot, runtimeDir, id, resultsPath, flags),
      options = options)

proc collectStates(runtimeDir: string): JsonNode {.role: dataFetcher,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## runtimeDir: IPC root containing worker state files.
  result = newJArray()
  for kind, path in walkDir(jobsDirectory(runtimeDir), relative = false):
    if kind == pcFile and path.endsWith(".json"):
      try:
        result.add(parseJson(readFile(path)))
      except CatchableError:
        discard

proc processRequest(request: JsonNode, jobs: var Table[string, ManagedJob],
    appPath, repoRoot, runtimeDir: string, C: OtterUiCatalog): JsonNode
    {.role: orchestrator, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## request/jobs/appPath/repoRoot/runtimeDir/C: one spawner operation.
  var
    action: string = request{"action"}.getStr("")
    id: string = request{"id"}.getStr("")
    resultsPath: string = request{"resultsPath"}.getStr(C.config.outputPath)
    flags: seq[string] = @[]
    job: ManagedJob
  case action
  of "bootstrap":
    result = bootstrapState(C)
  of "topology":
    result = topologyState(runtimeDir)
  of "start":
    discard entryWithId(C, id)
    flags = requestedFlags(request, C)
    if jobs.hasKey(id) and jobs[id].process.running():
      return %*{"ok": true, "alreadyRunning": true, "id": id}
    job = startManagedJob(appPath, repoRoot, runtimeDir, id, resultsPath, flags, C)
    jobs[id] = job
    result = %*{"ok": true, "id": id, "pid": processID(job.process)}
  of "poll":
    result = %*{"ok": true, "jobs": collectStates(runtimeDir)}
  of "stop":
    discard entryWithId(C, id)
    writeFile(cancelPath(runtimeDir, id), "stop\n")
    result = %*{"ok": true, "id": id}
  of "stopAll", "shutdown":
    for key, managed in jobs.pairs:
      if managed.process.running():
        writeFile(cancelPath(runtimeDir, key), "stop\n")
    result = %*{"ok": true, "shutdown": action == "shutdown"}
  else:
    result = %*{"ok": false, "error": "unsupported test backend action"}

proc cleanupJobs(jobs: var Table[string, ManagedJob], runtimeDir: string) {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## jobs/runtimeDir: process handles and state root repaired after workers finish.
  var
    completed: seq[string] = @[]
    statePath: string = ""
    S: JsonNode
    exitCode: int = 0
  for id, managed in jobs.mpairs:
    if not managed.process.running():
      exitCode = managed.process.waitForExit()
      managed.process.close()
      statePath = jobStatePath(runtimeDir, id)
      if fileExists(statePath):
        try:
          S = parseJson(readFile(statePath))
          if S{"status"}.getStr("") in ["queued", "running"]:
            S["status"] = %"fail"
            S["exitCode"] = %exitCode
            atomicWrite(statePath, $S)
        except CatchableError:
          discard
      completed.add(id)
  for id in completed:
    jobs.del(id)

proc terminateRecordedCommand(runtimeDir, id: string) {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## runtimeDir/id: active compiler or test process group recorded by its worker.
  var
    path: string = commandPidPath(runtimeDir, id)
    pid: int = 0
  if not fileExists(path):
    return
  try:
    pid = parseInt(readFile(path).strip())
  except ValueError:
    discard
  terminateProcessTree(pid)

proc markJobStopped(runtimeDir, id: string) {.role: truthBuilder,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## runtimeDir/id: interrupted job state finalized after owner lease expiry.
  var
    path: string = jobStatePath(runtimeDir, id)
    S: JsonNode
  if not fileExists(path):
    return
  try:
    S = parseJson(readFile(path))
    if S{"status"}.getStr("") in ["queued", "running"]:
      S["status"] = %"stopped"
      S["exitCode"] = %130
      atomicWrite(path, $S)
  except CatchableError:
    discard

proc runTestBackend*(appPath, repoRoot, runtimeDir: string)
    {.role: metaOrchestrator, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## appPath/repoRoot/runtimeDir: persistent backend that owns every test worker.
  var
    C: OtterUiCatalog = discoverOtterUiTests(repoRoot)
    jobs: Table[string, ManagedJob]
    request: JsonNode
    response: JsonNode
    responsePath: string = ""
    requestName: string = ""
    shuttingDown: bool = false
  ensureRuntimeDirectories(runtimeDir)
  writeProcessIdentity(runtimeDir, "test-backend")
  while not shuttingDown and not heartbeatExpired(runtimeDir, "webui") and
      not heartbeatExpired(runtimeDir, "orchestrator"):
    cleanupJobs(jobs, runtimeDir)
    for kind, requestPath in walkDir(requestsDirectory(runtimeDir,
        BackendChannel), relative = false):
      if kind != pcFile or not requestPath.endsWith(".json"):
        continue
      requestName = splitFile(requestPath).name
      try:
        request = parseJson(readFile(requestPath))
        response = processRequest(request, jobs, appPath, repoRoot, runtimeDir, C)
        shuttingDown = response{"shutdown"}.getBool(false)
      except CatchableError as exc:
        response = %*{"ok": false, "error": exc.msg}
      responsePath = joinPath(responsesDirectory(runtimeDir, BackendChannel),
        requestName & ".json")
      atomicWrite(responsePath, $response)
      removeFile(requestPath)
    sleep(25)
  for key, managed in jobs.mpairs:
    terminateRecordedCommand(runtimeDir, key)
    if managed.process.running():
      terminateProcessTree(managed.process)
    discard managed.process.waitForExit(3000)
    managed.process.close()
    markJobStopped(runtimeDir, key)

proc runOrchestrator*(runtimeDir: string) {.role: orchestrator,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## runtimeDir: IPC root whose WebUI requests are relayed without test work.
  var
    request: JsonNode
    response: JsonNode
    responsePath: string = ""
    requestName: string = ""
    shuttingDown: bool = false
  ensureRuntimeDirectories(runtimeDir)
  writeProcessIdentity(runtimeDir, "orchestrator")
  while not shuttingDown and not heartbeatExpired(runtimeDir, "webui"):
    writeHeartbeat(runtimeDir, "orchestrator")
    for kind, requestPath in walkDir(requestsDirectory(runtimeDir,
        RelayChannel), relative = false):
      if kind != pcFile or not requestPath.endsWith(".json"):
        continue
      requestName = splitFile(requestPath).name
      try:
        request = parseJson(readFile(requestPath))
        response = backendRequest(runtimeDir, request)
        shuttingDown = request{"action"}.getStr("") == "shutdown" and
          response{"ok"}.getBool(false)
      except CatchableError as exc:
        response = %*{"ok": false, "error": exc.msg}
      responsePath = joinPath(responsesDirectory(runtimeDir, RelayChannel),
        requestName & ".json")
      atomicWrite(responsePath, $response)
      removeFile(requestPath)
    sleep(10)

proc runSpawner*(appPath, repoRoot, runtimeDir: string)
    {.role: metaOrchestrator, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## Compatibility spelling for callers that launch the test backend directly.
  runTestBackend(appPath, repoRoot, runtimeDir)
