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

╭⟢ Asking one question at a time 🌊

The `stats` command measures everything and says a lot. Most of the
time the question is smaller than that, and asking it small is what
keeps the answer readable. Each command below answers one question and
prints nothing else. Every one of them also takes `--json`.

**Def. 1: a *finding*** is one thing a command noticed, in one place,
that somebody may want to do something about.

**Def. 2: a *chain*** is a list of routine names written with arrows -
`seal -> gcmSeal -> init` - meaning the first calls the second, which
calls the third. Chains are read left to right, nearest first.

### Before changing a routine: what can it reach

```sh
./bin/otter-repo-graph blast <dir> <name> [--callers:n] [--feeders:m]
```

Two directions, with their own depths, because they answer different
questions. `n` is how far **up** through callers; `m` is how far
**down** into the arguments handed in.

```
myfunc(t(), x(a(b())))     m = 1  ->  t, x
                           m = 2  ->  t, x, a
                           m = 3  ->  t, x, a, b
```

Going up is worth more, so `n = 2, m = 1` is the default. Two mistakes
this is meant to stop: cleaning a value a caller already cleaned, and
guessing the range of a parameter that only ever receives 0, 1 and 2.

### Before writing a call: how can it end

```sh
./bin/otter-repo-graph yields <dir> <name>
```

A signature names one of the answers. This names the rest.

```
loadWidth  src/config.nim:32
  yields on success: int
  can end with:
    RangeDefect     loadWidth                              [a defect]
    IOError         loadWidth -> readRaw -> readFile       [library]
    ValueError      loadWidth -> parseWidth -> parseInt    [library]
```

The important line is the one that is not an exception at all:

```
    doAssert        seal -> gcmSeal -> check   STOPS THE PROGRAM
```

An exception three levels down can be caught here. A `quit` or a
failed `doAssert` three levels down cannot be caught anywhere, so
those are listed on their own in `stats --json` under `aborts`.

### Before adding a writer: who else changes this

```sh
./bin/otter-repo-graph state <dir> [typeName]
```

```
Feed  (truth_state)  src/feed.nim:15   5 entrie(s)
    entry         replaced by         folded by     read by
    price         ingest, resample                  render     ! overwrite
    volume        ingest              accumulate    render
    lastSeen      ingest, resample                             ! never read
```

**Def. 3: a *blind write*** replaces an entry without reading it
first - `S.price = p`. **Def. 4: a *folding write*** reads it and puts
it back changed - `S.volume = S.volume + 1`, `S.rows.add(row)`. Only
two blind writes can lose information; a folding write carries the
other's work forward.

A loss is proven rather than guessed. Two blind writers are a shape,
not a bug, so a **witness** is looked for - a routine calling one and
then the other with nothing between them that reads the entry:

```
  ! Feed.price - ingest and resample each replace it without reading it first.
    runFeed calls ingest (src/feed.nim:60) then resample (:61) and nothing
    reads price in between, so what ingest stored is gone.
```

If only the newest value matters - a live feed where older readings
are meant to fall on the floor - say so on the entry and it stops
being reported:

```nim
type Feed = object
  ticker*: string   ## otter:latest
```

### Before saying a change is finished: what did it do

```sh
./bin/otter-repo-graph diff <dir> [rev]
```

Measures the tree once and lets the diff decide which part of the
answer is yours.

```
what changed   working tree vs HEAD
  4 file(s), 9 hunk(s), +212 -38 lines

  on lines you changed
    NESTING        parseFrame is 4 blocks deep (if)
                   src/net/client.nim:88   otter-repo-graph stats . --json   (.nest.sites)

  what you may have cut off
    DEAD CODE      you removed the last call to oldParse
                   src/legacy.nim:12   otter-repo-graph blast . oldParse

  what the changed routines reach
    parseFrame            6 caller(s) within 2 hop(s): handshake, session, runLoop

  read these first
    src/net/client.nim                            2 on your lines, 1 nearby
```

`git diff --unified=0` names the lines that moved, so a finding on one
of them is yours, a finding elsewhere in a file you touched is worth a
glance, and the rest is the repository rather than the change. Nothing
is checked out, stashed, reset or unpacked, so this is safe to run on
a folder somebody is in the middle of editing. ʕ•́ᴥ•̀ʔっ♡

Every finding carries **the command that found it**, because a reader
who has to work out how to look again mostly does not look again.

One measurement cannot notice a finding the change caused somewhere
else. The commonest of those is caught anyway, and without a second
tree: the lines a change *removes* name what they called, so any of
those names that nothing calls any more is a routine just orphaned -
usually in a file the author never opened. `--out:FILE` writes the
whole answer as JSON.

### Two more

```sh
./bin/otter-repo-graph ui <dir>       # how many clicks to each control
```

Counts, for every button, input, select and link of a front end, how
many things a person must open first. It reads text, not a running
page, so it can show a priority inversion but cannot promise there is
not one it missed. Controls reachable only by a key are counted apart:
nothing hides them, but somebody who does not know the key cannot
reach them at all.

Routine families and embedded code have no command of their own; both
appear in `stats` and in the gate script. A **family** is a group of
routines that are one routine with a knob on it. **Embedded code** is
a string holding another language - the report names which, because a
comment written on those lines has to be written the way *that*
language writes one.

### Several questions at once

```sh
./bin/otter-repo-graph checks <dir> stats state ui yields:seal [--parallel]
```

Reading the tree is most of the work; the checks on top of it are
quick. So the reading happens once and every check is handed the same
result, and only what is asked for is built — `checks . ui` never
parses a routine.

`--parallel` runs the checks at the same time, and the two readings at
the same time as well. Without it they run one after another, which is
the right choice on a small board, on a machine already busy, or where
heat matters more than minutes. **Neither form changes a single line
of any answer.** ʕ•́ᴥ•̀ʔっ♡

```
── state  (2316 ms)
── ui     (1602 ms)
── reading the tree, once: 32007 ms
── 3 check(s), together, 3918 ms of work on top
```

The reading is timed apart from the checks on purpose. Folded into the
first check it would make that one look slow and the rest look free,
which is the opposite of what is true.

╭⟢ Promises a routine has to keep 🐦‍🔥

`src/protocols/invariants.nim` is not a measurement. It is a small
library a repository imports so that a sentence a signature cannot say
gets checked instead of rotting in a comment.

```nim
import otter_repo_evaluation/protocols/invariants

proc withdraw(balance, amount: int): int {.
  needs: amount <= balance,
  gives: result >= 0
.} =
  balance - amount
```

| written | checked while building | checked while running |
|---|---|---|
| `needs` / `gives` / `keeps` | yes | no |
| `needsRun` / `givesRun` / `keepsRun` | yes | yes |

| word | checked | what it says |
|---|---|---|
| `needs` | on the way in | "I refuse bad input." |
| `gives` | on the way out | "I promise good output." |
| `keeps` | at both ends | "I do not break this." |

`keeps` is `needs` and `gives` in one word, with the same sentence at
both ends - and that is what makes it an invariant rather than a
precondition: it was true when we arrived, and this routine has not
broken it. `result` names what comes back.

The first three cost **nothing**. Not almost nothing: the check sits
inside `when nimvm:`, a branch the compiler keeps for its own
interpreter and never writes into the program. Two programs, one with
the promises and one without, build to the same number of bytes, and
`nimble test` compiles both and compares them.

A build-time check runs wherever the compiler runs the routine - in a
`const`, in a `static:` block, inside a macro:

```nim
static:
  discard withdraw(100, 40)     # checked, and passes
  discard withdraw(40, 100)     # the build stops here, and says why
```

```
needs failed in `withdraw`: amount <= balance [ContractDefect]
```

The `Run` three add the check to the program too, raising a
`ContractDefect`. They are on in an ordinary build, off with
`-d:danger` or `-d:noOtterContracts`, and on again with
`-d:otterContracts`.

Saying something about many values at once, or about the way in:

```nim
gives: forall(i in 1 ..< A.len, A[i - 1] <= A[i])   # A comes back sorted
needs: exists(c in s, c == '=')                     # s has an equals sign
givesRun: S.len == old(S).len + 1                   # exactly one was added
```

**Why the names are not `requires` and `ensures`.** ୨୧ Those two are
pragmas the Nim compiler already knows: they belong to DrNim, a
separate build of the compiler that proves them with a solver. The
ordinary compiler reads them, checks that what is written makes sense,
and then does nothing with it. Written that way a broken promise
builds cleanly and nobody is told, which is worse than having no
promise at all. So these are called something else.

╭⟢ Making a program say where it is 🍣

`src/protocols/visibility.nim` puts the debugging echoes in for you,
and takes them back out.

```nim
import otter_repo_evaluation/protocols/visibility

proc parseFrame(b: seq[byte]): Frame {.visGroup: 3.} =
  ...
```

```sh
nim c -d:otterVis:3 app.nim
```

```
[vis 3]      0.000 ms  -> parseFrame            src/net.nim:88
[vis 3]      0.031 ms    | loop 1 begins        src/net.nim:94
[vis 3]   4102.884 ms    | loop 1 ended after 65536 turn(s)
[vis 3]   4102.901 ms  <- parseFrame  (4102.9 ms)
```

**Def. 5: a *group*** is a plain number written on a routine. A whole
path through a program can carry one number, so lighting that path up
means adding one switch and touching nothing else.

| switch | what it does |
|---|---|
| `-d:otterVis:3` | group 3 talks |
| `-d:otterVis:1,3,7` | three groups talk |
| `-d:otterVis:all` | every group that carries the pragma |
| *nothing* | nothing at all |
| `-d:otterVisEvery:1000` | a word every 1000 turns of a loop |

The time is milliseconds since the first message, so **the gaps are
the thing to read**. A routine that never prints its `<-` line is the
one that stalled. A loop that prints `begins` and never `ended` is the
loop it stalled in. Depth is printed as indentation, so the shape of
the calls reads down the left-hand edge, and a loop inside a loop is
numbered after it and printed one step further in.

Nothing asked for means nothing at all. ୨୧ The decision is made while
the program is being built, so with the group off the routine is
handed back exactly as it was written — no branch, no timer, no
string. The runtime itself sits behind the same switch, so importing
the module costs the same as not importing it. Two programs, one with
the pragma and one without, build to the same number of bytes, and
`nimble test` compiles both and compares them.

The `<-` line is put in with `defer`, so it prints on an early
`return` and on the way out of an exception too — a routine that threw
is a routine somebody wants to see leave. A loop written inside a
routine written inside the body is left alone: it belongs to that
routine, which can carry its own pragma.

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
