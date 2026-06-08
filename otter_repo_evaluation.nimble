import std/[os, strutils]

version       = "0.1.0"
author        = "siriuslee69"
description   = "Compile-time timing instrumentation for parent Nim repos."
license       = "Unlicense"
srcDir        = "src"
requires "nim >= 2.0.0", "webui >= 2.5.0"

task test, "Run smoke tests":
  exec "nim c --path:src -r tests/test_smoke.nim"
  exec "nim c --path:src -r tests/test_repo_graph.nim"

task build, "Build smoke tests in release mode":
  exec "nim c --path:src -d:release tests/test_smoke.nim"

task buildcli, "Build the otter-nim CLI wrapper":
  exec "mkdir -p bin && nim c -d:release --path:src -o:bin/otter-nim src/clients/cli/otter_nim.nim"

task installcli, "Install the otter-nim CLI into ~/.local/bin":
  exec "mkdir -p bin && mkdir -p ~/.local/bin && nim c -d:release --path:src -o:~/.local/bin/otter-nim src/clients/cli/otter_nim.nim"

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

task autopush, "Add, commit, and push with message from .iron/PROGRESS.md":
  var
    path: string = ".iron/PROGRESS.md"
    msg: string = ""
    content: string = ""
    lines: seq[string] = @[]
  if fileExists(path):
    content = readFile(path)
    lines = content.splitLines()
    for line in lines:
      if line.startsWith("Commit Message:"):
        msg = line["Commit Message:".len .. ^1].strip()
        break
  if msg.len == 0:
    msg = "No specific commit message given."
  exec "git add -A ."
  exec "git commit -m \"" & msg & "\""
  exec "git push"

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
