import std/[os, strutils]

version       = "0.1.0"
author        = "siriuslee69"
description   = "Compile-time timing instrumentation for parent Nim repos."
license       = "Unlicense"
srcDir        = "src"
requires "nim >= 2.0.0", "webui >= 2.5.0"

## Otter keeps these under the shared names: its test list leaves out the
## deliberate crash examples, and the builds land in bin/ where the README
## points. runCli, runWebui, autopush, switch, applyNightly, find, … come
## from Nimble-Tasks, included at the end of this file.
const
  ownTasks: array[3, string] = ["test", "buildCli", "buildWebui"]
  cliEntry: string = "src/clients/cli/otter_repo_graph.nim"

task test, "Run smoke tests":
  exec "nim c --path:src -r evaluation/tests/test_evaluation.nim"
  exec "nim c --path:src -r evaluation/tests/test_smoke.nim"
  exec "nim c --path:src -r evaluation/tests/test_repo_graph.nim"
  exec "nim c --path:src -r evaluation/tests/test_code_stats.nim"
  exec "nim c --path:src -r evaluation/tests/test_test_ui.nim"
  exec "nim c --path:src -r evaluation/tests/test_insights.nim"
  exec "nim c --path:src -r evaluation/tests/test_embedded.nim"
  exec "nim c --path:src -r evaluation/tests/test_families.nim"
  exec "nim c --path:src -r evaluation/tests/test_layout.nim"
  exec "nim c --path:src -r evaluation/tests/test_blast.nim"
  exec "nim c --path:src -r evaluation/tests/test_ui_depth.nim"
  exec "nim c --path:src -r evaluation/tests/test_state_writes.nim"
  exec "nim c --path:src -r evaluation/tests/test_yields.nim"
  exec "nim c --path:src -r evaluation/tests/test_diff_review.nim"
  exec "nim c --path:src -r evaluation/tests/test_checks.nim"
  exec "nim c --path:src -r evaluation/tests/test_conventions.nim"
  exec "nim c --path:src -r evaluation/tests/test_visibility.nim"

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

task buildNimCli, "Build the otter-nim CLI wrapper into bin/":
  exec "mkdir -p bin && nim c -d:release --path:src -o:bin/otter-nim src/clients/cli/otter_nim.nim"

task installNimCli, "Install the otter-nim CLI into ~/.local/bin":
  exec "mkdir -p bin && mkdir -p ~/.local/bin && nim c -d:release --path:src -o:~/.local/bin/otter-nim src/clients/cli/otter_nim.nim"

task buildCli, "Build the repo graph CLI into bin/otter-repo-graph":
  exec "mkdir -p bin && nim c -d:release --path:src -o:bin/otter-repo-graph src/clients/cli/otter_repo_graph.nim"

task stats, "Measure this repository and print the code statistics":
  exec "mkdir -p build && nim c -r --path:src -o:build/otter-repo-graph-stats src/clients/cli/otter_repo_graph.nim stats ."

task statsjson, "Write the code statistics of this repository as JSON":
  exec "mkdir -p evaluation/statistics && nim c -r --path:src -o:build/otter-repo-graph-stats src/clients/cli/otter_repo_graph.nim stats . --json > evaluation/statistics/code_stats.json"

task buildWebui, "Build the Nim WebUI frontend into bin/otter-repo-graph-webui":
  exec "mkdir -p bin && nim c --path:src -o:bin/otter-repo-graph-webui src/clients/webui/app.nim"

task buildvscode, "Build the VS Code extension":
  exec "test -f src/clients/vscode_extension/package.json && test -f src/clients/vscode_extension/src/extension.js"

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
