# ============================================================
# | Otter Test UI Jobs                                       |
# | -> IPC spawner and isolated compile/run workers          |
# ============================================================

import std/[json, monotimes, os, osproc, strutils, tables, times]

import ../../../.iron/metaPragmas
import ./[catalog, types]

const
  RequestWaitCount = 200
  RequestWaitMs = 25
  WorkerPollMs = 100

type
  ManagedJob {.role: memory, metaTags: {tagExecution, tagTesting, tagUi}.} = object
    id: string
    process: Process

proc requestsDirectory(dir: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir: runtime root.
  result = joinPath(dir, "requests")

proc responsesDirectory(dir: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir: runtime root.
  result = joinPath(dir, "responses")

proc jobsDirectory(dir: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir: runtime root.
  result = joinPath(dir, "jobs")

proc ensureRuntimeDirectories*(dir: string) {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir: runtime root initialized for file-based IPC.
  createDir(dir)
  createDir(requestsDirectory(dir))
  createDir(responsesDirectory(dir))
  createDir(jobsDirectory(dir))

proc atomicWrite(path, content: string) {.role: dataWriter,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## path/content: destination and complete replacement payload.
  var
    temporary: string = path & ".tmp-" & $getCurrentProcessId()
  writeFile(temporary, content)
  moveFile(temporary, path)

proc requestId(): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  result = $getCurrentProcessId() & "-" & $epochTime().int64 & "-" &
    $getTime().nanosecond

proc spawnerRequest*(dir: string, request: JsonNode): JsonNode
    {.role: dataFetcher, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/request: runtime root and one short spawner command.
  var
    id: string = requestId()
    requestPath: string = joinPath(requestsDirectory(dir), id & ".json")
    responsePath: string = joinPath(responsesDirectory(dir), id & ".json")
    i: int = 0
  atomicWrite(requestPath, $request)
  while i < RequestWaitCount and not fileExists(responsePath):
    sleep(RequestWaitMs)
    i = i + 1
  if not fileExists(responsePath):
    raise newException(IOError, "Otter test spawner did not answer")
  result = parseJson(readFile(responsePath))
  removeFile(responsePath)

proc jobStatePath(dir, id: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/id: runtime root and catalog identity.
  result = joinPath(jobsDirectory(dir), id & ".json")

proc cancelPath(dir, id: string): string {.role: helper,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## dir/id: runtime root and catalog identity.
  result = joinPath(jobsDirectory(dir), id & ".cancel")

proc entryWithId(C: OtterUiCatalog, id: string): OtterUiTestEntry
    {.role: parser, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## C/id: discovered catalog and allowlisted identity.
  for entry in C.entries:
    if entry.id == id:
      return entry
  raise newException(ValueError, "unknown Otter UI test id: " & id)

proc initialState(e: OtterUiTestEntry): JsonNode {.role: truthBuilder,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## e: discovered test represented as a queued job.
  result = %*{
    "id": e.id,
    "testName": e.testName,
    "version": e.version,
    "status": "queued",
    "exitCode": 0,
    "durationMs": 0,
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

proc terminateProcessTree(p: Process) {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## p: compiler or test process and its descendants.
  if p == nil or not p.running():
    return
  when defined(windows):
    discard execCmd("taskkill /PID " & $processID(p) & " /T /F")
  else:
    discard execCmd("pkill -TERM -P " & $processID(p))
    p.terminate()

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
    stopPath: string): int {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## command/A/repoRoot/logPath/stopPath: isolated cancellable command contract.
  var
    shellCommand: string = redirectedCommand(command, A, logPath)
    process: Process = startProcess(shellCommand, workingDir = repoRoot,
      options = {poEvalCommand, poUsePath})
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

proc compileArguments(C: OtterUiCatalog, e: OtterUiTestEntry): seq[string]
    {.role: truthBuilder, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## C/e: catalog settings and test used to construct fixed compiler flags.
  var
    cachePath: string = joinPath(C.config.repoRoot, "build", "otter_test_ui",
      "nimcache", e.id)
  result = @["c", "--path:" & otterSourceDirectory(),
    "--nimcache:" & cachePath, "--out:" & executablePath(C.config.repoRoot, e),
    "-d:OtterUiTarget:" & e.routine, e.sourcePath]

proc finalStatus(exitCode: int): string {.role: parser,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## exitCode: worker result mapped to a stable browser status.
  if exitCode == 0:
    result = "pass"
  elif exitCode == 130:
    result = "stopped"
  else:
    result = "fail"

proc runWorker*(repoRoot, runtimeDir, id: string, resultsPath: string = "") {.role: metaOrchestrator,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## repoRoot/runtimeDir/id/resultsPath: repository, IPC root, test, and log root.
  var
    C: OtterUiCatalog = discoverOtterUiTests(repoRoot)
    e: OtterUiTestEntry = entryWithId(C, id)
    S: JsonNode = initialState(e)
    startTime: MonoTime = getMonoTime()
    stamp: string = now().format("yyyyMMdd-HHmmss")
    outputPath: string = resultsPath.strip()
    logPath: string = ""
    statePath: string = jobStatePath(runtimeDir, id)
    stopPath: string = cancelPath(runtimeDir, id)
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
  args = compileArguments(C, e)
  appendLogHeader(logPath, "compile", "nim", args, false)
  exitCode = runCancellable("nim", args, C.config.repoRoot, logPath, stopPath)
  if exitCode == 0:
    args = @[]
    appendLogHeader(logPath, "run", executablePath(C.config.repoRoot, e), args, true)
    exitCode = runCancellable(executablePath(C.config.repoRoot, e), args,
      C.config.repoRoot, logPath, stopPath)
  S["status"] = %finalStatus(exitCode)
  S["exitCode"] = %exitCode
  S["durationMs"] = %inMilliseconds(getMonoTime() - startTime)
  if exitCode != 0 and exitCode != 130:
    attachFailureDetails(S, e, C.config.repoRoot, logPath, exitCode)
  atomicWrite(statePath, $S)

proc workerArguments(repoRoot, runtimeDir, id, resultsPath: string): seq[string]
    {.role: truthBuilder, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## repoRoot/runtimeDir/id/resultsPath: values passed to a new worker process.
  result = @["--otter-mode:worker", "--repo-root:" & repoRoot,
    "--runtime-path:" & runtimeDir, "--test-id:" & id,
    "--results-path:" & resultsPath]

proc startManagedJob(appPath, repoRoot, runtimeDir, id, resultsPath: string,
    C: OtterUiCatalog): ManagedJob {.role: actor,
    metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## appPath/repoRoot/runtimeDir/id/resultsPath/C: worker launch contract.
  var
    e: OtterUiTestEntry = entryWithId(C, id)
    stopPath: string = cancelPath(runtimeDir, id)
  if fileExists(stopPath):
    removeFile(stopPath)
  atomicWrite(jobStatePath(runtimeDir, id), $initialState(e))
  result.id = id
  result.process = startProcess(appPath, workingDir = repoRoot,
    args = workerArguments(repoRoot, runtimeDir, id, resultsPath),
    options = {poParentStreams})

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
    job: ManagedJob
  case action
  of "start":
    discard entryWithId(C, id)
    if jobs.hasKey(id) and jobs[id].process.running():
      return %*{"ok": true, "alreadyRunning": true, "id": id}
    job = startManagedJob(appPath, repoRoot, runtimeDir, id, resultsPath, C)
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
    result = %*{"ok": false, "error": "unsupported spawner action"}

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

proc runSpawner*(appPath, repoRoot, runtimeDir: string)
    {.role: metaOrchestrator, metaTags: {tagExecution, tagTesting, tagUi}.} =
  ## appPath/repoRoot/runtimeDir: worker executable, target repo, and IPC root.
  var
    C: OtterUiCatalog = discoverOtterUiTests(repoRoot)
    jobs: Table[string, ManagedJob]
    request: JsonNode
    response: JsonNode
    responsePath: string = ""
    requestName: string = ""
    shuttingDown: bool = false
  ensureRuntimeDirectories(runtimeDir)
  while not shuttingDown:
    cleanupJobs(jobs, runtimeDir)
    for kind, requestPath in walkDir(requestsDirectory(runtimeDir), relative = false):
      if kind != pcFile or not requestPath.endsWith(".json"):
        continue
      requestName = splitFile(requestPath).name
      try:
        request = parseJson(readFile(requestPath))
        response = processRequest(request, jobs, appPath, repoRoot, runtimeDir, C)
        shuttingDown = response{"shutdown"}.getBool(false)
      except CatchableError as exc:
        response = %*{"ok": false, "error": exc.msg}
      responsePath = joinPath(responsesDirectory(runtimeDir), requestName & ".json")
      atomicWrite(responsePath, $response)
      removeFile(requestPath)
    sleep(25)
  for key, managed in jobs.mpairs:
    if managed.process.running():
      terminateProcessTree(managed.process)
    discard managed.process.waitForExit(3000)
    managed.process.close()
