# Otter-RepoEvaluation

Compile-time timing instrumentation, debug tracing, and interactive Nim repo graph analysis.

## Purpose
- Let a parent repo enable function timing with `-d:otterTiming`.
- Auto-wrap plain Nim files with `otter-nim` for crash tracing and timing without hand edits.
- Parse Nim repos into function graphs with roles, comments, sockets, and helper-grouped orchestrators.
- Run best-effort sample calls against selected functions to inspect output.
- Compare algorithm runtimes and evaluate binary streams with the built-in statistical suite.
- Expose the graph through a Nim WebUI shell and a VS Code webview that can hand queued notes to the Codex extension.
- Discover `.otterUiTest` routines and run each selected test in an isolated compiler/worker process from a test WebUI.

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

### 4. Open the pragma-driven test UI

Annotate zero-argument test routines inside `tests/`:

```nim
import std/unittest
import otter_repo_evaluation

proc vectorV1*() {.otterUiTest: ("Vector check", "Crypto",
    "functional, vectors", "Version 1").} =
  check 2 + 2 == 4

proc vectorV2*() {.otterUiTest: ("Vector check", "Crypto",
    "functional, vectors", "Version 2").} =
  check 3 + 3 == 6
```

Run from the parent repository:

```sh
nimble testUi
```

The four metadata values are:

```text
(test panel name, menu point, comma-separated filters, version tab)
```

Tests with the same menu point and test panel name share one panel. Two or more
versions become tabs. A single version remains a plain panel without a tab.
Leave the version string empty on grouped routines to keep one tab-free panel;
running that panel launches all of its routines as separate isolated jobs.
Every click starts a separate worker process. That worker compiles the selected
source with `OtterUiTarget` set to the selected routine, runs only that routine,
and writes its output to a log. Compiler errors, assertions, and crashes do not
take down the WebUI host or the spawner.

When one panel has named version tabs, its Run button executes every version in
tab order. Each version starts only after the prior version finishes. Tabs are
for inspecting individual source, result, and log details; their glyph shows
idle, running, passed, failed, or stopped state. The output bar accepts a typed
directory and provides a native folder picker. Its selected directory is passed
through the spawner into every worker.

Optional project settings live beside the test files:

```text
tests/
|-- .otter/
|   |-- config.toml
|   `-- config.css
`-- test_example.nim
```

`tests/.otter/config.toml` supports:

```toml
title = "My Project Tests"
banner = "Choose a test and inspect its isolated result."
output_path = "tests/.otter/results"
```

`config.css` is appended after Otter's built-in stylesheet. Its public theme is
an intentionally small set of solid colors. Otter builds gradients, transparent
surfaces, shadows, glows, hover colors, and state backgrounds from these values:

```css
:root {
  --otter-color-background: #101a21;
  --otter-color-gradient: #738ad7;
  --otter-color-surface: #0b151c;
  --otter-color-border: #8abdc9;
  --otter-color-text: #dce8ed;
  --otter-color-muted: #8ca4ae;
  --otter-color-primary: #738ad7;
  --otter-color-secondary: #cf7ba9;
  --otter-color-success: #73d7a7;
  --otter-color-failure: #ff718b;
  --otter-color-running: #e4bd72;
}
```

The colors are grouped by role:

```text
background  <- page base, dark shadows, inactive control fills
gradient    <- far end of the page gradient, alternate glass tint
surface     <- menus, cards, hero, output bar
border      <- panel borders and background grid
text        <- main text and automatically mixed light tones
muted       <- secondary text, source paths, idle tabs
primary     <- menus, run controls, links, first background glow
secondary   <- filters, stopped state, circuit accents, second glow
success     <- passed cards, tabs, badges, and result text
failure     <- failed cards, stop controls, tabs, badges, and result text
running     <- queued/running cards, tabs, badges, and result text
```

Users only choose regular colors. They do not need to write `rgba(...)`,
transparency values, shadows, or gradient expressions. If either configuration
file is absent, Otter uses the repository folder name as the title, a built-in
banner and palette, and `tests/.otter/results` for logs.

### Selecting and sharing failures

Each test panel has a checkbox and the entire card is clickable except for its
version tabs, Run button, and failure link. A plain click selects one card,
`Ctrl`/`Cmd` toggles cards, and `Shift` selects a visible range. When any cards
are selected, `Run visible` becomes `Run selected` and a Deselect button appears.
The checkbox and card use the same selection state and modifier rules. Shift
selection suppresses native text highlighting. Small highlighted copy controls
beside the test name and source path copy those values without changing selection.

Failed tests display their available failure message directly in the card.
Opening it shows a non-fullscreen dialog with the message, source path, line,
and nearby Nim code. The dialog closes with its close button, backdrop click,
or `Escape`. Plain text and JSON buttons copy a shareable report containing the
test name, menu, version, routine, message, source location, exit code, log path,
and code excerpt.

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

### 2. Compare algorithms

```nim
import otter_repo_evaluation

var
  algorithms: array[1, BenchAlgo]
  results: seq[BenchResult] = @[]

algorithms[0] = BenchAlgo(name: "work", run: proc() = discard)
results = compareAlgorithms(algorithms, loops = 1000, warmup = 10)
echo formatBenchResults(results)
```

The benchmark and NIST-style statistical evaluation protocols live inside
Otter. They have no Sigma package or submodule dependency.

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
- `BenchAlgo` / `BenchResult`
  - one callable benchmark case and its monotonic timing result.
- `NistParams` / `NistResult`
  - settings and outcomes for binary-stream statistical evaluation.
- `FunctionInfo`
  - one parsed Nim function plus sockets, comments, tags, and role data.
- `RepoGraph`
  - full function/call/group graph for one analyzed repo.
- `RunSampleResult`
  - best-effort sample execution result for one selected function.

## Commands
- `nimble test`
  - run instrumentation smoke tests plus repo-graph tests.
- `nimble buildtests`
  - compile the smoke and repo-graph tests in release mode.
- `nimble testUi`
  - discover `.otterUiTest` routines, build the host, and open the isolated test dashboard.
- `nimble buildTestUi`
  - build `bin/otter-test-ui` without opening a browser.
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
- Statistical results need adequate input sizes:
  - use the NIST parameter ranges appropriate for the supplied byte stream;
  - short streams intentionally produce failed or empty test outcomes.
- VS Code packaging is not built in this shell:
  - the extension is source-only to avoid a local Node toolchain requirement here.
- Test UI routines must take no parameters:
  - put setup values inside the routine or call a helper from it so the worker has one unambiguous entry point.
- Test discovery reads literal pragma strings:
  - use four direct string literals rather than constants or computed expressions.

## License
Released under [The Unlicense](LICENSE.txt).

## Development Conventions (Short)
- Keep timing capture monotonic, process-local, and source-location aware.
- Keep graph parsing deterministic and comment-preserving.
- Prefer one shared graph model for CLI, WebUI, and VS Code instead of parallel feature copies.
- Update `.iron/PROGRESS.md` and this README when public behavior changes.
- Follow the full workspace rules in `.iron/CONVENTIONS.md`.
