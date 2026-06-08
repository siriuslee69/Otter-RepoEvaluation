# Otter-RepoEvaluation

Compile-time timing instrumentation, debug tracing, and interactive Nim repo graph analysis.

## Purpose
- Let a parent repo enable function timing with `-d:otterTiming`.
- Auto-wrap plain Nim files with `otter-nim` for crash tracing and timing without hand edits.
- Parse Nim repos into function graphs with roles, comments, sockets, and helper-grouped orchestrators.
- Run best-effort sample calls against selected functions to inspect output.
- Expose the graph through a Nim WebUI shell and a VS Code webview that can hand queued notes to the Codex extension.

## Main Workflows

### 1. Instrument a repo or file
1. Import `otter_repo_evaluation`.
2. Wrap routines with `otterInstrument:` or attach `.otterTimed.`, `.otterInstrument.`, or `.otterBench.`.
3. Run with `-d:otterTiming`.
4. Read `build/otter_timings.log`.

For a plain Nim file:

```sh
nimble buildcli
./bin/otter-nim c -r my_file.nim
```

### 2. Analyze a repo graph

```sh
nimble buildgraphcli
./bin/otter-repo-graph snapshot .
./bin/otter-repo-graph artifacts .
./bin/otter-repo-graph run . 'src/protocols/foo::bar:42'
```

### 3. Open the interactive UI

```sh
nimble buildwebui
./bin/otter-repo-graph-webui
```

VS Code extension source lives in `src/clients/vscode_extension/`.
Open that folder in VS Code and run the `Otter Repo Graph: Open` command.

## Instrumentation Example

```nim
import otter_repo_evaluation

otterInstrument:
  proc parseInput*(s: string): int =
    var
      t: int = 0
    t = s.len
    result = t

  proc runCase*(s: string): int =
    var
      t: int = 0
    t = parseInput(s)
    result = t + 1
```

Direct pragma form:

```nim
import otter_repo_evaluation

proc parseInput*(s: string): int {.otterBench.} =
  var
    t: int = 0
  t = s.len
  result = t
```

## Repo Graph Surface

The merged graph layer ports the Ratatoskr parser into Otter and extends it with:
- function sockets from parameter and return types,
- hoverable doc/comment payloads,
- orchestrator helper grouping,
- graph JSON export,
- sample-function execution,
- shared WebUI/VS Code frontend assets.

Main graph modules:
- `src/protocols/repo_graph/`
  - parser, graph builder, role inference, grouping, exporters, sample runner.
- `src/clients/cli/otter_repo_graph.nim`
  - repo graph CLI.
- `src/clients/webui/`
- Nim WebUI host plus shared HTML/CSS/JS graph client.
- `src/clients/vscode_extension/`
- source-only VS Code extension wrapper around the same frontend.

The shared WebUI now uses qlacier-style floating menu shells: repo root search on the left, centered file/view/selection menus, collapsible action rails on the left edge, and node/workspace utilities on the right.

## Main State
- `OtterTimingTuple`
  - one timing span plus source location.
- `OtterTimingMemory`
  - process-local timing store and flush metadata.
- `FunctionInfo`
  - one parsed Nim function plus sockets, comments, tags, and role data.
- `RepoGraph`
  - full function/call/group graph for one analyzed repo.
- `RunSampleResult`
  - best-effort sample execution result for one selected function.

## Commands
- `nimble test`
  - run instrumentation smoke tests plus repo-graph tests.
- `nimble build`
  - compile the smoke test in release mode.
- `nimble buildcli`
  - build `bin/otter-nim`.
- `nimble buildgraphcli`
  - build `bin/otter-repo-graph`.
- `nimble buildwebui`
  - build `bin/otter-repo-graph-webui`.
- `nimble runwebui`
  - compile and run the WebUI shell.
- `nimble buildvscode`
  - verify the VS Code extension source files exist.
- `nimble find`
  - switch submodule URLs to local sibling clones when available.

## Issue Playbook
- Non-exported function sample runs can fail:
  - exported functions use import mode;
  - private functions fall back to include mode only when the source file has no `when isMainModule`.
- Very large repos create dense root graphs:
  - use orchestrator expansion or enter a group with `Tab` in the UI.
- VS Code packaging is not built in this shell:
  - the extension is source-only to avoid a local Node toolchain requirement here.

## License
Released under [The Unlicense](LICENSE.txt).

## Development Conventions (Short)
- Keep timing capture monotonic, process-local, and source-location aware.
- Keep graph parsing deterministic and comment-preserving.
- Prefer one shared graph model for CLI, WebUI, and VS Code instead of parallel feature copies.
- Update `.iron/PROGRESS.md` and this README when public behavior changes.
- Follow the full workspace rules in `.iron/CONVENTIONS.md`.
