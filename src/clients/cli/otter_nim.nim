# ============================================================
# | Otter Nim CLI                                           |
# | -> Auto-wrap a target Nim file with Otter spans         |
# ============================================================

import std/[os, osproc, strutils]

import runePragmas

const
  OtterCliSourcePath* {.role: helper, tag: "parentIntegration".} = currentSourcePath()
  OtterCliDir* {.role: helper, tag: "parentIntegration".} = parentDir(OtterCliSourcePath)
  OtterClientsDir* {.role: helper, tag: "parentIntegration".} = parentDir(OtterCliDir)
  OtterSrcDir* {.role: helper, tag: "parentIntegration".} = parentDir(OtterClientsDir)
  OtterRepoDir* {.role: helper, tag: "parentIntegration".} = parentDir(OtterSrcDir)


proc escapeNimString(s: string): string {.role: helper, tag: "parentIntegration".} =
  ## s: runtime string that will be embedded as a Nim string literal.
  var
    t: string = "\""
  for ch in s:
    case ch
    of '\\':
      t.add("\\\\")
    of '\"':
      t.add("\\\"")
    of '\n':
      t.add("\\n")
    of '\r':
      t.add("\\r")
    of '\t':
      t.add("\\t")
    else:
      t.add(ch)
  t.add("\"")
  result = t


proc indentBlock(s: string, n: int): string {.role: helper, tag: "parentIntegration".} =
  ## s: source block to indent.
  ## n: indentation width in spaces.
  var
    lines: seq[string] = @[]
    prefix: string = ""
    t: string = ""
    line: string = ""
    i: int = 0
  prefix = repeat(' ', n)
  lines = s.splitLines()
  if lines.len == 0:
    result = prefix & "discard"
    return
  while i < lines.len:
    line = lines[i]
    if line.len == 0:
      t.add("\n")
    else:
      t.add(prefix & line & "\n")
    inc(i)
  if t.len > 0 and t[^1] == '\n':
    t.setLen(t.len - 1)
  result = t


proc normalizeWrappedSource(s: string): string {.role: helper, tag: "parentIntegration".} =
  ## s: original source file contents.
  var
    lines: seq[string] = @[]
    t: string = ""
  lines = s.splitLines()
  if lines.len > 0 and lines[0].startsWith("#!"):
    lines[0] = "#" & lines[0][1 .. ^1]
  t = lines.join("\n")
  result = t


proc otterDependencyPaths*(): seq[string] {.role: helper, tag: "parentIntegration".} =
  var
    A: seq[string] = @[]
    p: string = ""
  A.add(OtterSrcDir)
  p = joinPath(OtterRepoDir, "submodules", "Fylgia-Utils", "src")
  if dirExists(p):
    A.add(p)
  result = A


proc hasArgWithPrefix(args: openArray[string], prefix: string): bool {.role: helper, tag: "parentIntegration".} =
  ## args: argument list.
  ## prefix: option prefix to search for.
  for a in args:
    if a.startsWith(prefix):
      result = true
      return


proc normalizeCliPath(p: string): string {.role: helper, tag: "parentIntegration".} =
  ## p: raw path from a CLI `--path:` option.
  var
    t: string = ""
  t = p
  if not isAbsolute(t):
    t = absolutePath(t)
  result = normalizedPath(t)


proc existingPathArgs(args: openArray[string]): seq[string] {.role: helper, tag: "parentIntegration".} =
  ## args: raw CLI args to scan for `--path:` switches.
  var
    t: string = ""
  for a in args:
    if a.startsWith("--path:"):
      t = a["--path:".len .. ^1]
      result.add(normalizeCliPath(t))
    elif a.startsWith("-p:"):
      t = a["-p:".len .. ^1]
      result.add(normalizeCliPath(t))


proc containsPath(paths: openArray[string], p: string): bool {.role: helper, tag: "parentIntegration".} =
  ## paths: normalized absolute paths.
  ## p: candidate path.
  var
    normalizedCandidate: string = ""
  normalizedCandidate = normalizeCliPath(p)
  for existingPath in paths:
    if existingPath == normalizedCandidate:
      result = true
      return


proc isCompileCommand(s: string): bool {.role: helper, tag: "parentIntegration".} =
  ## s: nim command token.
  if s == "c" or s == "compile" or s == "r" or s == "cpp":
    result = true
    return


proc findProjectIndex(args: openArray[string]): int {.role: helper, tag: "parentIntegration".} =
  ## args: otter-nim arguments without argv[0].
  var
    a: string = ""
    i: int = 0
  while i < args.len:
    a = args[i]
    if i == 0 and isCompileCommand(a):
      inc(i)
      continue
    if a == "--":
      break
    if a.endsWith(".nim") or a.endsWith(".nims"):
      result = i
      return
    inc(i)
  result = -1


proc wrapperPathFor(targetPath: string): string {.role: helper, tag: "parentIntegration".} =
  ## targetPath: absolute project path.
  var
    f: tuple[dir, name, ext: string]
    t: string = ""
  f = splitFile(targetPath)
  t = f.name & "_otter_wrapped" & f.ext
  result = joinPath(f.dir, t)


proc keepWrapperFileEnabled*(): bool {.role: helper, tag: "parentIntegration".} =
  var
    t: string = ""
  t = getEnv("OTTER_KEEP_WRAPPER")
  if t == "1" or t == "true" or t == "yes":
    result = true
    return


proc showForwardedCommandEnabled*(): bool {.role: helper, tag: "parentIntegration".} =
  var
    t: string = ""
  t = getEnv("OTTER_SHOW_CMD")
  if t == "1" or t == "true" or t == "yes":
    result = true
    return


proc shellEscapeArg(s: string): string {.role: helper, tag: "parentIntegration".} =
  ## s: one CLI argument that will be displayed for debugging.
  var
    t: string = "'"
  for ch in s:
    if ch == '\'':
      t.add("'\\''")
    else:
      t.add(ch)
  t.add("'")
  result = t


proc formatForwardedCommand(args: openArray[string]): string {.role: helper, tag: "parentIntegration".} =
  ## args: full argument vector passed to Nim.
  var
    A: seq[string] = @["nim"]
  for a in args:
    A.add(shellEscapeArg(a))
  result = A.join(" ")


proc buildWrapperSource(targetPath: string, sourceText: string): string {.role: helper, tag: "parentIntegration".} =
  ## targetPath: absolute project path.
  ## sourceText: original project source.
  var
    A: seq[string] = @[]
    headerLines: int = 0
    t: string = ""
  A.add("# This file is generated by otter-nim.")
  A.add("import otter_repo_evaluation")
  headerLines = A.len + 2
  A.add("otterWrapFile(" & escapeNimString(targetPath) & ", " & $headerLines & "):")
  t = normalizeWrappedSource(sourceText)
  t = "import otter_repo_evaluation\n" & t & "\n\nwhen isMainModule:\n  flushTimingLog()"
  A.add(indentBlock(t, 2))
  result = A.join("\n") & "\n"


proc forwardArgs(args: seq[string], projectIdx: int, wrapperPath: string): seq[string] {.role: helper, tag: "parentIntegration".} =
  ## args: original CLI args.
  ## projectIdx: project argument index inside args.
  ## wrapperPath: generated wrapper path.
  var
    A: seq[string] = @[]
    knownPaths: seq[string] = @[]
    i: int = 0
  if args.len == 0:
    result = @[]
    return
  if isCompileCommand(args[0]):
    A.add(args[0])
    i = 1
  if not hasArgWithPrefix(args, "-d:otterTiming") and not hasArgWithPrefix(args, "--define:otterTiming"):
    A.add("-d:otterTiming")
  if not hasArgWithPrefix(args, "-d:otterDebug") and not hasArgWithPrefix(args, "--define:otterDebug"):
    A.add("-d:otterDebug")
  if not hasArgWithPrefix(args, "--stackTrace:"):
    A.add("--stackTrace:on")
  if not hasArgWithPrefix(args, "--lineTrace:"):
    A.add("--lineTrace:on")
  if not hasArgWithPrefix(args, "--hint:DuplicateModuleImport:"):
    A.add("--hint:DuplicateModuleImport:off")
  knownPaths = existingPathArgs(args)
  for depPath in otterDependencyPaths():
    if containsPath(knownPaths, depPath):
      continue
    A.add("--path:" & depPath)
    knownPaths.add(normalizeCliPath(depPath))
  while i < args.len:
    if i == projectIdx:
      A.add(wrapperPath)
    else:
      A.add(args[i])
    inc(i)
  result = A


proc normalizeCliArgs(args: seq[string]): seq[string] {.role: helper, tag: "parentIntegration".} =
  ## args: raw `commandLineParams()` output.
  var
    i: int = 0
  if args.len > 0 and args[0] == "--":
    i = 1
  while i < args.len:
    result.add(args[i])
    inc(i)


proc runForwardedCompile(args: seq[string]): int {.role: orchestrator, tag: "parentIntegration".} =
  ## args: raw otter-nim arguments.
  var
    cliArgs: seq[string] = @[]
    cmd: string = ""
    exitCode: int = 0
    projectIdx: int = -1
    sourceText: string = ""
    targetPath: string = ""
    targetWrapperPath: string = ""
    forwarded: seq[string] = @[]
  cliArgs = normalizeCliArgs(args)
  if cliArgs.len == 0:
    stderr.writeLine("usage: otter-nim c -r file.nim [program args]")
    result = 1
    return
  projectIdx = findProjectIndex(cliArgs)
  if projectIdx < 0:
    cmd = formatForwardedCommand(cliArgs)
    exitCode = execCmd(cmd)
    result = exitCode
    return
  targetPath = absolutePath(cliArgs[projectIdx])
  sourceText = readFile(targetPath)
  targetWrapperPath = wrapperPathFor(targetPath)
  writeFile(targetWrapperPath, buildWrapperSource(targetPath, sourceText))
  forwarded = forwardArgs(cliArgs, projectIdx, targetWrapperPath)
  cmd = formatForwardedCommand(forwarded)
  if showForwardedCommandEnabled():
    stderr.writeLine("[otter-cmd] " & cmd)
  try:
    exitCode = execCmd(cmd)
  finally:
    if fileExists(targetWrapperPath) and not keepWrapperFileEnabled():
      removeFile(targetWrapperPath)
  result = exitCode


when isMainModule:
  quit(runForwardedCompile(commandLineParams()))
