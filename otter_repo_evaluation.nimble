import std/[os, strutils]

version       = "0.1.0"
author        = "siriuslee69"
description   = "Compile-time timing instrumentation for parent Nim repos."
license       = "Unlicense"
srcDir        = "src"
requires "nim >= 2.0.0"

task test, "Run smoke tests":
  exec "nim c --path:src -r tests/test_smoke.nim"

task build, "Build smoke tests in release mode":
  exec "nim c --path:src -d:release tests/test_smoke.nim"

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
