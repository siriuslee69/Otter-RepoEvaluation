## Otter-specific builds and the test list that excludes deliberate crashes.
import std/[os, strutils]

when fileExists(thisDir() & "/../Nimble-Tasks/src/preset.nims"):
  include "../Nimble-Tasks/src/preset.nims"
elif fileExists(thisDir() & "/submodules/Nimble-Tasks/src/preset.nims"):
  include "submodules/Nimble-Tasks/src/preset.nims"
else:
  {.error: "Nimble-Tasks/src/preset.nims not found: update the submodule".}

version       = projectValue("version")
author        = projectValue("author")
description   = projectValue("description")
license       = projectValue("license")
srcDir        = "src"
requires "nim >= 2.0.0", "webui >= 2.5.0"

## Otter keeps these under the shared names: its test list leaves out the
## deliberate crash examples, and the builds land in bin/ where the README
## points. runCli, runWebui, autopush, switch, applyNightly, find, … come
## from Nimble-Tasks, included at the end of this file.
const
  ownTasks: array[4, string] = ["test", "runTests", "buildCli", "buildWebui"]
  cliEntry: string = "src/clients/cli/otter_repo_graph.nim"

const
  testPrograms: array[21, string] = [
    "test_evaluation",
    "test_smoke",
    "test_repo_graph",
    "test_code_stats",
    "test_test_ui",
    "test_insights",
    "test_embedded",
    "test_families",
    "test_layout",
    "test_blast",
    "test_ui_depth",
    "test_ui_continuity",
    "test_state_writes",
    "test_yields",
    "test_diff_review",
    "test_checks",
    "test_conventions",
    "test_visibility",
    "test_machine_code",
    "test_source_scans",
    "test_tracing"]

task test, "Run the complete test list, excluding deliberate failure examples":
  for name in testPrograms:
    exec "nim c --path:src -r " & quoteShell("evaluation/tests/" & name & ".nim")
  when defined(posix):
    exec "bash evaluation/tests/test_agent_hooks.sh"
    exec "bash evaluation/tests/test_repo_checks.sh"

task runTests, "Run the same selected tests as nimble test":
  exec "nimble test"

task buildtests, "Build the complete test list in release mode":
  for name in testPrograms:
    exec "nim c --path:src -d:release " & quoteShell("evaluation/tests/" & name & ".nim")

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

task buildNimCli, "Build the otter-nim CLI wrapper into bin/":
  mkDir("bin")
  exec "nim c -d:release --path:src -o:" & quoteShell("bin/otter-nim" & ExeExt) &
    " src/clients/cli/otter_nim.nim"

task installNimCli, "Install the otter-nim CLI into ~/.local/bin":
  var dir: string = getHomeDir() / ".local" / "bin"
  mkDir(dir)
  exec "nim c -d:release --path:src -o:" & quoteShell(dir / ("otter-nim" & ExeExt)) &
    " src/clients/cli/otter_nim.nim"

task buildCli, "Build the repo graph CLI into bin/otter-repo-graph":
  mkDir("bin")
  exec "nim c -d:release --path:src -o:" & quoteShell("bin/otter-repo-graph" & ExeExt) &
    " src/clients/cli/otter_repo_graph.nim"

task stats, "Measure this repository and print the code statistics":
  mkDir("build")
  exec "nim c -r --path:src -o:build/otter-repo-graph-stats src/clients/cli/otter_repo_graph.nim stats ."

task statsjson, "Write the code statistics of this repository as JSON":
  mkDir("build")
  mkDir("evaluation/statistics")
  exec "nim c -r --path:src -o:build/otter-repo-graph-stats src/clients/cli/otter_repo_graph.nim stats . --json > evaluation/statistics/code_stats.json"

task buildWebui, "Build the Nim WebUI frontend into bin/otter-repo-graph-webui":
  mkDir("bin")
  exec "nim c --path:src -o:" & quoteShell("bin/otter-repo-graph-webui" & ExeExt) &
    " src/clients/webui/app.nim"

task buildvscode, "Build the VS Code extension":
  assert fileExists("src/clients/vscode_extension/package.json")
  assert fileExists("src/clients/vscode_extension/src/extension.js")

task packagevscode, "Package the VS Code extension":
  echo "The VS Code extension is source-only. Open src/clients/vscode_extension in VS Code or package it with your local VSIX tooling."


## Shared tasks: the sibling clone wins, the submodule is the fallback.
## `nimble sharedTasks` lists them.
when fileExists(thisDir() & "/../Nimble-Tasks/src/nimbleTasks.nims"):
  include "../Nimble-Tasks/src/nimbleTasks.nims"
elif fileExists(thisDir() & "/submodules/Nimble-Tasks/src/nimbleTasks.nims"):
  include "submodules/Nimble-Tasks/src/nimbleTasks.nims"
else:
  {.error: "Nimble-Tasks not found: git submodule update --init submodules/Nimble-Tasks".}
