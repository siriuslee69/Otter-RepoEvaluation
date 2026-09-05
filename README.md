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
- Measure a whole repository: per-file routine lengths, blocks inside blocks, declared roles, and how much of the tree the tests actually reach.

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

### 3. Measure a repository

```sh
nimble stats                      # the summary, on this repository
nimble statsjson                  # the whole shape, to evaluation/statistics
./bin/otter-repo-graph stats <dir>
./bin/otter-repo-graph stats <dir> --json
```

```
Files: 61   Lines: 10457
Routines: 412   average 18.5 lines
Templates: 15   macros: 5   template calls: 654
Nesting: 326 double, 88 triple, 58 deeper
Nested routines: 165 (165 outside math)
Input handlers: 3   truth states: 27   math: 0
Tests: 43 (4 with a declared kind)
Untested routines: 182 of 412
Edge-case cover: 99   benchmark cover: 8
Never called: 42
```

From code, one call answers everything a window needs to draw:

```nim
import otter_repo_evaluation
var s: ProjectStats = analyzeProject(".")
for line in summaryLines(s):
  echo line
```

| field | what it holds |
|---|---|
| `files` | one `FileStat` per file: length, routine count, average routine length, a health band, a size band, input handlers, templates, nesting, untested routines |
| `nest` | template uses, double / triple / deeper sites, nested routines split by whether they are math, the lines inside each last layer, and the worst sites by name and line |
| `tests` | routines by how many tests reach them (0, 1, 2, 3, 4, 5+), and how many are reached by an edge case, a benchmark, a regression, or a bugfix test |
| `roles` | what each routine declared itself to be, tallied, with `undeclared` counted as its own finding |
| `unused` | routines nothing calls and no test reaches |

A routine counts as tested when a test calls it **or calls something
that calls it**: the walk follows the call graph, so a helper three
calls down is not reported as untested.

Nesting means a block inside another block. `else`, `elif`, `of`,
`except` and `finally` carry on a block that is already open and never
add a level of their own, and a routine written inside another one
starts with a clean stack — so pulling an inline proc out of a loop
removes the nesting instead of hiding it.

### 4. Say what a test is for

Tests carry `testKind`, from the shared pragma file:

```nim
proc wideRange() {.testKind: tkEdgeCase, covers: "parseWidth".} = …
```

`test "…"` is a call to a template, so no pragma can be hung on it.
The kind goes on the line above instead, in the same words:

```nim
# {.testKind: tkEdgeCase.}
test "an empty list is refused":
  check mean(@[]) == 0
```

The kinds are `tkUnit`, `tkEdgeCase`, `tkBenchmark`, `tkRegression`,
`tkBugfix`, `tkIntegration`, `tkFuzz`, `tkSmoke`, `tkProperty`, and
`tkOther`. A declared kind always wins; the wording is only read when
there is none, and `declaredKinds` says how many were declared so a
guess is never mistaken for a promise.

The pragmas themselves come from
`Proto-RepoTemplate/meta/metaPragmas.nim`, which every repository
copies. Otter reads those names out of whatever tree it is pointed at,
so a repository that renames them drops out of every chart.

### 5. Open the interactive UI

```sh
nimble buildwebui
./bin/otter-repo-graph-webui
```

VS Code extension source lives in `src/clients/vscode_extension/`.
Open that folder in VS Code and run the `Otter Repo Graph: Open` command.

### 6. Open the pragma-driven test UI

The runnable annotation example lives at
[`examples/test_ui_catalog.nim`](examples/test_ui_catalog.nim). A parent
repository places the same kind of file below its own `evaluation/tests/` directory.

Minimal parent layout:

```text
my-project/
|-- src/
|-- tests/
|   `-- test_otter_catalog.nim
|-- submodules/
|   `-- Otter-RepoEvaluation/
|-- config.nims
`-- my_project.nimble
```

Add Otter's source directory to `config.nims`:

```nim
import std/os

let
  repoRoot = thisDir()
  otterSrc = joinPath(repoRoot, "submodules", "Otter-RepoEvaluation", "src")

if dirExists(otterSrc):
  switch("path", otterSrc.replace('\\', '/'))
```

Annotate zero-argument routines in `evaluation/tests/test_otter_catalog.nim`:

```nim
import std/unittest
import otter_repo_evaluation

proc vectorV1*() {.otterUiTest: ("Vector check", "Crypto",
    "functional, vectors", "Version 1").} =
  check 2 + 2 == 4

proc vectorV2*() {.otterUiTest: ("Vector check", "Crypto",
    "functional, vectors, wasm", "wasm").} =
  check 3 + 3 == 6

proc parserSmoke*() {.otterUiTest: ("Parser smoke", "Core",
    "functional, parser", "").} =
  check @[1, 2, 3].len == 3
```

The parent Nimble file needs two small tasks. The executable can be built from
Otter's source because it discovers the parent repository at runtime:

```nim
import std/os

proc otterRoot(): string =
  result = joinPath(getCurrentDir(), "submodules", "Otter-RepoEvaluation")

proc testUiPath(): string =
  result = joinPath(getCurrentDir(), "build", "otter-test-ui")

task buildTestUi, "Build the Otter Test UI":
  mkDir("build")
  exec "nim c --path:" & quoteShell(joinPath(otterRoot(), "src")) &
    " --out:" & quoteShell(testUiPath()) & " " &
    quoteShell(joinPath(otterRoot(), "src", "clients", "test_ui", "app.nim"))

task testUi, "Open the Otter Test UI":
  exec "nimble buildTestUi -y"
  exec quoteShell(testUiPath()) & " --repo-root:" & quoteShell(getCurrentDir())
```

Run it from the parent repository:

```sh
nimble testUi
```

Otter tries renderers in this order: WebView, Vivaldi, Firefox, Brave, then
Chrome. It uses a private profile below the temporary Test UI runtime directory.

Before the catalog becomes runnable, Otter scans project `.nim`, `.nims`, and
`.nimble` files for project-controlled `defined(name)` conditions and opens an
optional flag dropdown. Selected names become validated `-d:name` compiler
arguments for every launched test. Compiler/target facts such as `windows`,
`linux`, `release`, `threads`, and `wasm32` are excluded. The Flags button in
the output bar can reopen the selector during the session.

The four metadata values are:

```text
(test panel name, menu point, comma-separated filters, version tab)
```

Tests with the same menu point and test panel name share one panel. Two or more
versions become tabs. A single version remains a plain panel without a tab.
Leave the version string empty on grouped routines to keep one tab-free panel;
running that panel launches all of its routines as separate isolated jobs.

The grouping rules are exact:

```text
same menu + same panel name + named versions -> one card with version tabs
same menu + same panel name + empty versions -> one card running all routines
different menu or panel name                -> different card
```

The conventional target labels `Native`/`native` and `WASM`/`wasm` are
normalized to lowercase `native` and `wasm`. Otter does not invent a WASM
compiler command from the label. The annotated WASM routine must call the
parent project's Emscripten helper, as Tyr does, or directly perform its WASM
compile and run steps.

Every click starts a separate worker process. That worker compiles the selected
source with `OtterUiTarget` set to the selected routine, starts one dedicated
thread for that routine, joins it, and writes its output to a log. No two tests
share one process or one thread.

The persistent runtime has three independent backend processes beside the
actual WebUI window:

```text
main supervisor
  |-> WebUI host -> relay orchestrator -> test backend -> worker process
  |        ^              ^                    ^             `-> test thread
  |        |              |                    |
  `--------+--------------+--------------------+  monitor/restart
```

The WebUI callback sends test messages only to the relay orchestrator. The
orchestrator forwards each message unchanged to the test backend. Only the test
backend discovers tests, launches workers, polls state, or stops jobs. The main
supervisor monitors and restarts both backends. Compiler errors, assertions,
explicit exits, and native crashes stay inside the disposable worker and do not
occupy or terminate the WebUI, main supervisor, relay, or test backend.

When one panel has named version tabs, its Run button executes every version in
tab order. Each version starts only after the prior version finishes. Tabs are
for inspecting individual source, result, and log details; their glyph shows
idle, running, passed, failed, or stopped state. The output bar accepts a typed
directory and provides a native folder picker. Its selected directory is passed
through the relay and test backend into every worker.

Version tabs form a horizontal scrollable flex list. They keep a fixed usable
width rather than shrinking into unreadable labels when a card has many
versions.

Each result card shows actual test run time first and compiler time second:

```text
18 ms run · 742 ms compile
```

The aggregate `durationMs` remains in job JSON for diagnostics, while
`runDurationMs` and `compileDurationMs` provide the separate phases.

### First-run configuration

On first discovery, Otter creates these paths when they are absent:

```text
evaluation/tests/.otter/
|-- config.toml
`-- config.css
```

Creation is file-by-file and non-destructive. If the directory exists, Otter
uses it. If one file exists, Otter preserves it and creates only the missing
file. Existing contents are never replaced. This also means a repository can
commit either file and let Otter generate the other one locally.

Optional project settings live beside the test files:

```text
tests/
|-- .otter/
|   |-- config.toml
|   `-- config.css
`-- test_example.nim
```

`evaluation/tests/.otter/config.toml` supports:

```toml
title = "My Project Tests"
banner = "Choose a test and inspect its isolated result."
output_path = "evaluation/tests/.otter/results"
default_flags = ["*"]
```

`default_flags` contains desired startup selections. `"*"` asks Otter to enable
every discovered safe compiler capability supported by the current host. This
currently includes `sse2`, `avx2`, `aesni`, and `neon` where available. It
intentionally excludes third-party `has...` integrations, compiler-internal
conditions such as `sizeof_Int128`,
`gcArc`/`gcOrc`, target/test modes, debug or unsafe switches, and experimental
algorithm alternatives. Explicit names can be added beside `"*"` when a
repository deliberately wants one of those choices.

The host-sensitive SIMD names are preselected only when supported by the
current CPU. `gcArc` and `gcOrc` map to Nim's `--mm:arc` and `--mm:orc`; neither
is selected by `"*"`, and they cannot be selected together. This leaves Nim's
configured memory-manager default unchanged unless the user explicitly changes
it.

`config.css` is appended after Otter's built-in stylesheet. Its public theme is
an intentionally small set of solid colors. Otter builds gradients, transparent
surfaces, shadows, glows, hover colors, and state backgrounds from these values:

```css
:root {
  --otter-color-background: #101a21;
  --otter-color-gradient: #8a969b;
  --otter-color-surface: #0b151c;
  --otter-color-border: #8abdc9;
  --otter-color-text: #dce8ed;
  --otter-color-muted: #8ca4ae;
  --otter-color-primary: #73d7d0;
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
file was absent on first run, Otter writes the editable defaults shown above.

### Compile flag discovery

Otter scans project `.nim`, `.nims`, and `.nimble` files while excluding build,
result, Git, and submodule trees. It reads symbols from `when defined(name)` and
`elif defined(name)` conditions. The resulting names form an allowlist:

```text
source conditions -> discovered allowlist -> startup dropdown
                  -> validated selection -> worker compiler arguments
```

Unknown names sent to the backend are rejected. Built-in target/compiler facts
such as `windows`, `linux`, `release`, `threads`, and `wasm32` are not offered.
Selected ordinary names become `-d:name`. `gcArc` and `gcOrc` become
`--mm:arc` and `--mm:orc`, and the UI prevents selecting both. If neither is
selected, Otter does not add a memory-manager option and Nim keeps its normal
configured default.

For native targets, the known SIMD selections also receive required compiler
switches:

```text
sse2  -> -d:sse2  --passC:-msse2
avx2  -> -d:avx2  --passC:-mavx2 --passL:-mavx2
aesni -> -d:aesni --passC:-maes
neon  -> -d:neon
```

Configured SIMD defaults are checked against the current CPU. x86 uses CPUID
and XCR0, including operating-system AVX state support. ARM64 enables NEON by
architecture. Unsupported configured defaults remain visible but unchecked.

### Emscripten and SIMD

Emscripten can use WebAssembly SIMD. The important distinction is that
WebAssembly exposes portable 128-bit `simd128` operations. It does not expose
the host's SSE2, AVX2, AES-NI, or NEON instruction sets as interchangeable
backends:

```text
x86 native      -> SSE2 / AVX2 / AES-NI intrinsics
ARM native      -> NEON intrinsics
WebAssembly     -> WASM SIMD128 operations (`-msimd128`)
```

Enabling `-d:avx2` during an Emscripten build would select Tyr's x86 AVX2 code,
not translate that code into WASM SIMD. It can therefore fail compilation or
choose an invalid target path. Otter passes host SIMD defaults to native nested
compilers but filters `sse2`, `avx2`, `aesni`, and `neon` from Tyr's Emscripten
compiler arguments.

To use SIMD in a WASM test, the parent library needs a separate WASM SIMD128
implementation or a portability layer that emits WASM vectors, plus
`-msimd128` in the Emscripten compile/link flags. Tyr and SIMD-Nexus do not yet
provide that backend, so Tyr's WASM tabs currently use scalar WASM code rather
than pretending desktop SIMD flags are portable.

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

For repeated timing samples, per-operation medians, and throughput:

```nim
algorithms[0].bytesPerOp = 64
var stable = compareAlgorithmsStable(algorithms, loops = 1000,
  warmup = 100, samples = 9)
echo formatStableBenchResults(stable)
```

For a practical parameter preset and the lower-cost core statistical diagnostics:

```nim
var params = nistParamsForBits(bytes.len * 8)
var diagnostics = nistCoreSuiteFromBytes(bytes, params)
```

The core suite runs frequency, block frequency, runs, longest-run, matrix-rank,
spectral, approximate-entropy, serial, and both cumulative-sums diagnostics.
It is useful for deterministic engineering checks. It is not the official
multi-sequence SP 800-22 process and must not be treated as a security proof.

For fixed-versus-random timing leakage measurements:

```nim
var timing = welchTimingLeakage("encrypt", fixedSamples, randomSamples,
  threshold = 4.5)
```

The result contains first- and second-order Welch t-statistics. For repeated
statistical windows, `evaluateFailureProportion` compares the observed failure
rate with an alpha-centered normal bound. Packed `gf2Rank` and `gf2Nullity`
support linear-invariant certificates over bit matrices.

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
- Update `agents/PROGRESS.md` and this README when public behavior changes.
- Follow the full workspace rules in the Agent-Conventions repo.
