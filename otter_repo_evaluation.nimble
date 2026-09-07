import std/[os, strutils]

version       = "0.1.0"
author        = "siriuslee69"
description   = "Compile-time timing instrumentation for parent Nim repos."
license       = "Unlicense"
srcDir        = "src"
requires "nim >= 2.0.0", "webui >= 2.5.0"

proc shellPath(p: string): string =
  result = quoteShell(p.replace('\\', '/'))

proc shellCommand(command: string; args: openArray[string]): string =
  var
    parts: seq[string] = @[shellPath(command)]
  for arg in args:
    parts.add(shellPath(arg))
  result = parts.join(" ")

proc runCommand(command: string; args: openArray[string]) =
  exec shellCommand(command, args)

proc probeCommand(command: string; args: openArray[string]): tuple[output: string, exitCode: int] =
  result = gorgeEx(shellCommand(command, args))

proc captureCommand(command: string; args: openArray[string]): string =
  var
    probe: tuple[output: string, exitCode: int] = probeCommand(command, args)
  result = probe.output
  if probe.exitCode != 0:
    if result.len > 0:
      echo result
    quit(probe.exitCode)

proc progressCommitMessage(): string =
  const
    candidatePaths: array[2, string] = [
      "agents/PROGRESS.md",
      "agents/progress.md"
    ]
  var
    path: string = ""
    content: string = ""
    i: int = 0
  while i < candidatePaths.len:
    if fileExists(candidatePaths[i]):
      path = candidatePaths[i]
      break
    inc i
  if path.len > 0:
    content = readFile(path)
    for line in content.splitLines:
      if line.startsWith("Commit Message:"):
        result = line["Commit Message:".len .. ^1].strip()
        break
  if result.len == 0:
    result = "No specific commit message given."

proc currentUpstreamBranch(): string =
  var
    probe: tuple[output: string, exitCode: int] =
      probeCommand("git", @["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
  if probe.exitCode == 0:
    result = probe.output.strip()

proc branchDivergenceCounts(): tuple[ahead: int, behind: int] =
  var
    probe: tuple[output: string, exitCode: int] =
      probeCommand("git", @["rev-list", "--left-right", "--count", "HEAD...@{u}"])
    parts: seq[string] = @[]
  if probe.exitCode != 0:
    return
  parts = probe.output.strip().splitWhitespace()
  if parts.len >= 2:
    try:
      result.ahead = parseInt(parts[0])
      result.behind = parseInt(parts[1])
    except ValueError:
      discard

task test, "Run smoke tests":
  exec "nim c --path:src -r evaluation/tests/test_evaluation.nim"
  exec "nim c --path:src -r evaluation/tests/test_smoke.nim"
  exec "nim c --path:src -r evaluation/tests/test_repo_graph.nim"
  exec "nim c --path:src -r evaluation/tests/test_code_stats.nim"
  exec "nim c --path:src -r evaluation/tests/test_test_ui.nim"
  exec "nim c --path:src -r evaluation/tests/test_insights.nim"
  exec "nim c --path:src -r evaluation/tests/test_embedded.nim"
  exec "nim c --path:src -r evaluation/tests/test_families.nim"
  exec "nim c --path:src -r evaluation/tests/test_blast.nim"
  exec "nim c --path:src -r evaluation/tests/test_ui_depth.nim"

task buildtests, "Build smoke tests in release mode":
  exec "nim c --path:src -d:release evaluation/tests/test_evaluation.nim"
  exec "nim c --path:src -d:release evaluation/tests/test_smoke.nim"
  exec "nim c --path:src -d:release evaluation/tests/test_repo_graph.nim"
  exec "nim c --path:src -d:release evaluation/tests/test_code_stats.nim"
  exec "nim c --path:src -d:release evaluation/tests/test_test_ui.nim"
  exec "nim c --path:src -d:release evaluation/tests/test_insights.nim"

task testevaluation, "Run statistical evaluation and stable benchmark tests":
  exec "nim c --path:src -r evaluation/tests/test_evaluation.nim"

task buildTestUi, "Build the pragma-driven test WebUI":
  mkDir("bin")
  exec "nim c --path:src -o:" & quoteShell(joinPath("bin", "otter-test-ui" & ExeExt)) &
    " src/clients/test_ui/app.nim"

task testUi, "Discover pragma tests and open the isolated test WebUI":
  var
    appPath: string = joinPath("build", "otter-test-ui" & ExeExt)
  mkDir("build")
  exec "nim c --path:src -o:" & quoteShell(appPath) & " src/clients/test_ui/app.nim"
  exec quoteShell(appPath) & " --repo-root:."

task buildcli, "Build the otter-nim CLI wrapper":
  exec "mkdir -p bin && nim c -d:release --path:src -o:bin/otter-nim src/clients/cli/otter_nim.nim"

task installcli, "Install the otter-nim CLI into ~/.local/bin":
  exec "mkdir -p bin && mkdir -p ~/.local/bin && nim c -d:release --path:src -o:~/.local/bin/otter-nim src/clients/cli/otter_nim.nim"

task stats, "Measure this repository and print the code statistics":
  exec "mkdir -p build && nim c -r --path:src -o:build/otter-repo-graph-stats src/clients/cli/otter_repo_graph.nim stats ."

task statsjson, "Write the code statistics of this repository as JSON":
  exec "mkdir -p evaluation/statistics && nim c -r --path:src -o:build/otter-repo-graph-stats src/clients/cli/otter_repo_graph.nim stats . --json > evaluation/statistics/code_stats.json"

task buildgraphcli, "Build the repo graph CLI":
  exec "mkdir -p bin && nim c -d:release --path:src -o:bin/otter-repo-graph src/clients/cli/otter_repo_graph.nim"

task rungraphcli, "Run the repo graph CLI help":
  exec "mkdir -p build && nim c -r --path:src -o:build/otter-repo-graph-run src/clients/cli/otter_repo_graph.nim"

task buildwebui, "Build the Nim WebUI frontend":
  exec "mkdir -p bin && nim c --path:src -o:bin/otter-repo-graph-webui src/clients/webui/app.nim"

task runwebui, "Run the Nim WebUI frontend":
  exec "mkdir -p build && nim c -r --path:src -o:build/otter-repo-graph-webui src/clients/webui/app.nim"

task buildvscode, "Build the VS Code extension":
  exec "test -f src/clients/vscode_extension/package.json && test -f src/clients/vscode_extension/src/extension.js"

task packagevscode, "Package the VS Code extension":
  echo "The VS Code extension is source-only. Open src/clients/vscode_extension in VS Code or package it with your local VSIX tooling."

task autopush, "Add, commit, and push the current branch with message from agents/PROGRESS.md":
  var
    msg: string = progressCommitMessage()
    staged: string = ""
    branch: string = ""
    upstream: string = ""
    diverged: tuple[ahead: int, behind: int]
  runCommand("git", @["add", "-A", "."])
  staged = captureCommand("git", @["diff", "--cached", "--name-only"]).strip()
  if staged.len == 0:
    echo "No staged changes. Skipping commit."
  else:
    runCommand("git", @["commit", "-m", msg])
  branch = captureCommand("git", @["branch", "--show-current"]).strip()
  if branch.len == 0:
    quit "Refusing autopush from detached HEAD."
  upstream = currentUpstreamBranch()
  if upstream.len == 0:
    runCommand("git", @["push", "--set-upstream", "origin", branch])
    return
  diverged = branchDivergenceCounts()
  if diverged.behind > 0:
    runCommand("git", @["pull", "--rebase", "--autostash"])
  runCommand("git", @["push", "origin", branch])

task switch, "Toggle the working branch between nightly and main":
  var
    branch: string = captureCommand("git", @["branch", "--show-current"]).strip()
    target: string = ""
  if branch == "nightly":
    target = "main"
  else:
    target = "nightly"
  echo "Switching from '" & (if branch.len > 0: branch else: "(detached HEAD)") &
    "' to '" & target & "'."
  runCommand("git", @["checkout", target])

task applynightly, "Promote the current nightly state onto main (fast-forward) and push, keeping nightly":
  var
    branch: string = captureCommand("git", @["branch", "--show-current"]).strip()
  if branch == "main":
    quit "On 'main'. Run `nimble switch` to move to nightly before applying."
  runCommand("git", @["fetch", ".", "nightly:main"])
  runCommand("git", @["push", "origin", "nightly:main"])
  echo "main is now at the nightly state; nightly branch left intact."

task find, "Use local sibling clones for submodules when available":
  var
    modulesPath: string = ".gitmodules"
    root: string = ""
    current: string = ""
    content: string = ""
    parts: seq[string] = @[]
    subPath: string = ""
    tail: string = ""
    localDir: string = ""
    localUrl: string = ""
  if not fileExists(modulesPath):
    echo "No .gitmodules found."
  else:
    root = parentDir(getCurrentDir())
    content = readFile(modulesPath)
    for line in content.splitLines():
      var
        s: string = line.strip()
        startIdx: int = 0
        stopIdx: int = 0
      if s.startsWith("[submodule"):
        startIdx = s.find('"')
        stopIdx = s.rfind('"')
        if startIdx >= 0 and stopIdx > startIdx:
          current = s[startIdx + 1 .. stopIdx - 1]
      elif current.len > 0 and s.startsWith("path"):
        parts = s.split("=", maxsplit = 1)
        if parts.len == 2:
          subPath = parts[1].strip()
          tail = splitPath(subPath).tail
          localDir = joinPath(root, tail)
          if dirExists(localDir):
            localUrl = localDir.replace('\\', '/')
            exec "git config -f .gitmodules submodule." & current & ".url " & localUrl
            exec "git config submodule." & current & ".url " & localUrl
    exec "git submodule sync --recursive"
    exec "git submodule update --init --recursive"
