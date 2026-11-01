# Otter self-review — 2026-10-29

Otter is easier to read and its checks are more reliable after this review.
It is **not fully convention compliant**. Parameter names, deep nesting, and
large modules still need work. The successful tests below do not clear those
findings.

## Otter on Otter — 2026-11-01

The forced gate found 203 depth-three and 42 depth-four sites. The FFT
butterfly, graph edge collection, universal block reader, guard search,
conditional CSS scan and contested-setting scan now have shallower steps.
The gate then reported 199 depth-three and 33 depth-four sites; its depth
counts can move between buckets when a block is flattened. The FFT and
graph-builder files no longer appear in its oversized-file list; the
universal test now appears there because its remaining routine is long.

Added checks cover a known complex FFT, repeated universal-test blocks,
and graph edge deduplication, local resolution and missing calls.
`nimble runStatistics` still reports 131 parameter naming candidates.
The forced gate also retains 27 layout candidates, 42 embedded-language
strings and other findings. These remain work, not a clean result.

The six secret candidates are examples in tests or the `stack@rsp+0x10`
address in a comment. The example feed intentionally demonstrates a lost
write. `OtterUiConfig.defaultFlags` is read by the catalog, including via
`C.config.defaultFlags`; the state report misses that read. Family and
layout findings are suggestions and need checking against purpose and Nim's
declaration order before moving or merging code.

## Otter on Otter — 2026-10-30, third pass

This pass ran Otter on its own tree, then checked each finding by hand or
with the Nim compiler before deciding anything. Some findings were real
defects. Some were false positives in Otter itself, and those were fixed in
Otter. The rest were kept on purpose, with the reason written below.

### How it was checked

| Check | Command | What it judged |
| --- | --- | --- |
| Gate | `OTTER_REPORT_LOG=off tools/agent_hooks/otter-gate.sh --force .` | secrets, layout, families, nesting, placeholders, state |
| Stats | `$otter stats . --json` | unused routines and imports, coverage, nesting sites |
| Per-file check | `nim-check.sh` over the 118 tracked Nim files | declarations, placeholders, block placement |
| Convention statistics | `nim c -r evaluation/statistics/stat_conventions.nim` | parameter names |
| Compiler | `nim check --warnings:on <file>` for every file | `UnusedImport`, `XDeclaredButNotUsed` |
| Tests | `nimble test` | behaviour, 282 checks at the end |

Two notes for anyone who runs this again:

```
gate needs nqa          no nqa -> "otter: nqa is needed to read the report, see nqa-build.sh", exit 2
gate hides repeats      without OTTER_REPORT_LOG=off, rows printed before are not shown
```

### What the first run said, and what was true

| Reported | Checked | Result |
| --- | --- | --- |
| 279 unused-import candidates | The compiler reports one (`exitprocs`), and it is needed when `-d:otterTrace` is set. The text match was wrong on almost every line. | Check rewritten to read local module exports. Now 0. |
| 6 placeholder routines in tests | All six were fixture code inside `"""` strings, read as Nim. | Parser blanks triple-quoted lines. Now 0. |
| No finding | `## @tags alpha\|beta` produced the tags `s alpha` and `beta`; the `@tags` branch could never run. | Doc directives read by whole word. Regression test added. |
| 1 secret: `f.signature` | Source text of a Nim declaration, not a key. | Declarations kept as text score zero. |
| `isWordChar` unused (new helper) | Used as `c.isWordChar` with no brackets; the call graph only records `.name(`. | Method-style uses counted when they name a repo routine. |
| "not dead" checks passed | `analyzeProject` returns an empty report without a `.git` folder, so six fixtures never analysed anything. | Fixtures get `.git`; each run asserts `s.error` is empty. |
| 2 compiler hints | `owner` (config_touch) and `at` (ui_depth) were never read. | Removed. |
| 20 sites at depth 5 or deeper | Real. Eleven routines. | Each pulled into a named helper. Now 0. |

```
  Otter's own report       what was true
  ────────────────────     ──────────────────────────────────────
  unused imports   279  -> 1 real, config-dependent, kept
  placeholders       6  -> 0 real (fixtures read as code)
  "not dead" checks  6  -> 0 real checks (they never ran)
```

### Changes

| Commit | What |
| --- | --- |
| `e3f4232` | Unused-import check reads local module exports; outside modules are not reported |
| `aac7aec` | Doc directives read by whole word; triple-quoted text not read as code |
| `fde6bbc` | Depth-5 nesting moved into helpers; two unused variables removed |
| `00fbb17` | Method-style calls counted as uses; fixture repos get `.git`; error asserted |
| `18d6141` | Nim declarations kept as text are not scored as secrets |
| `d6b3a9e` | Dotted-name scan flattened to one loop; two job parameters renamed to one letter |

Each fix has a regression test. Six of the seven new checks fail on the code
from before this pass, so they pin the defect they name. The seventh, whole-word
matching, passes on both versions and guards behaviour rather than a defect.

### Before and after

| Measure | Start | Now | Note |
| --- | --- | --- | --- |
| Unused-import candidates | 279 | 0 | Compiler agrees: 0 real in default build |
| Placeholder routines | 6 | 0 | |
| Nesting, depth 5 or deeper | 20 sites, 11 routines | 0 | |
| Nesting, triple / deeper | 211 / 80 | 203 / 42 | |
| Secret candidates | 8 | 6 | All six are fixtures or history; see below |
| Compiler hints | 2 | 0 | |
| Parameter naming candidates | 131 | 131 | Unchanged; see remaining work |
| Layout candidates | 28 | 27 | |
| Families | 8 | 8 | Kept; see below |
| Embedded language strings | 41 | 42 | One new fixture string |
| Routines counted | 949 | 958 | New helpers from the refactor |
| Routines untested (inferred) | 245 | 282 | Helpers are reached only through callers |
| Tests passing | 275 | 282 | +7 regression checks; 0 failing |

The untested count rose because the refactor added routines that the inferred
test graph reaches only through their callers. It is a lead, not a measured
execution coverage, so it is recorded rather than tuned away.

### Kept on purpose

- `import std/exitprocs` in `src/otter_trace_runtime.nim`: used only when
  `-d:otterTrace` is set. The compiler warns in the default build only. The
  check was run with the define on and the warning went away.
- `examples/families`, `examples/state_writes`, `examples/yields`: these are
  demonstrations. Their family groups and the lost write in `feed.nim` are the
  point of the example.
- `examples/blast/src/pipeline.nim` is a sample tree that `test_blast` reads;
  nothing compiles it. `nim check` on it fails with `invalid pragma: role`,
  because it does not import `runePragmas`. That is expected for a sample.
- Six secret candidates: a synthetic `sk-live` key and `anna`/`me` home paths
  in test fixtures, an email in an old test commit, and a stack-address example
  in history for `machine_code/taint.nim`. None is a real credential. They are
  listed here rather than hidden.
- Three "unused" routines are used by the sibling repo Tyr-Crypto: `runSpawner`,
  `spawnerRequest`, `otterInstrument`. They stay.
- The layout hint for `nim_parser.nim` (`isFunctionStartLine`, `parseImportBindings`,
  `parseFunctionBlock`) cannot be followed as written. `isFunctionStartLine` is
  called at line 227 by a routine above the one that uses it, and Nim needs a
  routine declared before its first use. Only `parseImportBindings` could move.
- Families `lengthOf`, `byLines`, `byInner` are reported as one family. They are a
  measure and two sort comparators over different record types. One generic
  routine would need an accessor argument and read worse.

### Remaining work, in order

1. **Decide on nine exported routines with no caller in the workspace.**
   `timelineLines`, `otterShow`, `getLogPath`, `otterTraceFile`, `visEnter`,
   `visLeave`, `visLoop`, `otterThreadsFromEnv`, `formatRiskTag`. Several look
   like unfinished features. Keep or delete is the owner's call.
2. **Parameter names (131).** Largest: `jobs.nim` (19), `nim_parser.nim` (18),
   `catalog.nim` (15). Rename with their doc comments and named-argument callers.
3. **Nesting (203 triple, 42 at depth 4).** No site is deeper than 4 now. The
   largest groups at depth 4 are `extractCalls` (4 sites), `mapTouches` (4),
   `universalTest` (4), `parseImportBindings` (2), and `detectUserInputSignals` (2).
   The list is `nqa -r '.nest.sites[] | select(.depth==4)' stats.json`.
4. **Seam in `code_stats/state_writes.nim`** at about line 640: 21 routines
   above, 31 below, and only 7 of the upper ones are used below. Split into two
   modules and move those 7 to a shared file.
5. **Oversized files:** `diff_review.nim` (372 code lines), `blast.nim` (322),
   `role_inference.nim` (173), `linear_complexity.nim` (114), `fft.nim` (101).
   The list changes as routines shrink, so it is not a clean measure yet.
6. **Embedded HTML** in `src/clients/webui/web/app.js` and `app_layers.js`
   (about 50 lines). Move each template into its own `.html` file.
7. **Otter follow-ups found here:**
   - the layout check should respect declaration order before suggesting a move;
   - the family check groups routines by shape even when they share no job;
   - nested field reads such as `C.config.defaultFlags` are still missed;
   - an exact unused-import mode through `nim check` costs about one second per
     file, so it is not on by default.

### Limits of this pass

- The compiler check ran in the default configuration. A warning that depends on
  a define is seen only when that define is set.
- Only Linux, x86-64, Nim 2.4.0 was used.
- The sibling-repo search covered eleven named repositories, not every folder
  in the workspace.

## Follow-up — 2026-10-30

A second pass fixed the three statistical nesting hotspots and the path-helper
naming findings. These are source changes; no rule thresholds were relaxed.

| Measurement | Before | After |
| --- | --- | --- |
| Naming candidates | 141 | 131 |
| Triple nesting sites | 224 | 211 |
| Deeper nesting sites | 97 | 80 |
| `templates.nim` maximum depth / average code lines per routine | 6 / 39.6 | 2 / 12.7 |
| `excursions.nim` maximum depth / average code lines per routine | 5 / 42.7 | 2 / 10.7 |
| `rank.nim` maximum depth / average code lines per routine | 5 / 34.0 | 2 / 10.6 |

Template matching now separates window reading, match counting, category counts,
and scoring. Excursion counting shares one cycle-finalization step, resets its
outputs explicitly, and scores each state separately. Matrix blocks are packed
and reduced by the existing GF(2) implementation instead of a second elimination
implementation. Four statistics modules share one checked chi-square calculation.
The original pattern enumeration and probability models are retained.

The pass also fixes undefined or non-finite results at input boundaries:

- Non-overlapping pattern widths must fit their positive integer representation:
  1 through `sizeof(int)*8-2` (62 on a 64-bit build). Invalid dimensions yield an
  empty result. Computing moments uses floating-point powers, so a doubled-width
  integer shift no longer wraps for otherwise valid wide patterns.
- Overlapping tests return a finite failing result when their category model
  underflows or produces a zero-probability category.
- Matrix bounds are checked with division before dimensions are multiplied.
  Invalid or incomplete direct rank ranges return zero. Large rank-probability
  exponents use a factored logarithm instead of an overflowing exponential.
- Runtime contracts check block bounds and the shared score's category dimensions
  and positive, finite probabilities.

Path helpers in `repo_graph/io_utils.nim` now use documented `dir`, `p`, and `b`
parameters; every in-repository named call was updated. External callers using
named arguments must use the new names, for example `listNimFiles(dir = root,
b = true)` instead of `rootDir` / `bIncludeTests`. Positional argument order and
path behavior are unchanged.

Validation adds eleven cases, including all 64 two-row, three-column matrices,
a packed-word boundary, cycle-tail and saturation counts, invalid dimensions,
and large exponents. A fixed 257-bit xorshift stream matches the 32 saved results
captured from commit `0087ec1` before refactoring, within numerical tolerance.
The fixture is `evaluation/tests/fixtures/statistics/evaluation_reference.json`;
its seed and bit-generation steps are explicit in the regression test.

`nimble test` passes all 20 programs / 275 unittest cases plus shell regressions.
The expanded statistical suite also passes in release mode. This follow-up used
Nim 2.4.0 on Linux/x86-64.

A separate machine-code regression fixes a brittle test expectation exposed by
Nim 2.4.0: optimized line information can place a real secret comparison on a
branch-free source line. The known constant-time sample must still stay clean.
A fixed instruction/source fixture verifies that an added secret branch is
reported as SECRET and is never hidden to satisfy that expectation. Production
machine-code checks are unchanged. Changed-file checks pass.

A real tracing defect exposed by the same compiler update is also fixed:
implicit results were returned correctly but printed as zero by an early
`finally` exit hook. Value bodies now assign their result before that hook runs.
Statement bodies keep their explicit assignments and returns. The integration
fixture checks the traced values, evaluation exactly once, early returns,
generic/inferred types, exception flow, and compile-time calls. It passes in
debug and release modes.

Otter still reports 131 naming candidates and 291 sites at depth 3 or more;
the older state-write, coupling, configuration, and UI-depth hotspots remain.
There are no missing roles. The earlier measurements below are retained as history.

## Scope and method

The shared Agent-Conventions Markdown files were read before the review.
Otter was rebuilt from source, then used on its own tree. Vendored submodules
were excluded from source statistics. Tests and intentional example programs
were kept so the findings could be checked against what those files demonstrate.

The checks had distinct jobs:

| Check | What it supplied |
| --- | --- |
| `otter-gate.sh --force .` | roles, nesting, layout, families, coverage, state, secret candidates |
| `nim-check.sh` with every own `.nim` and `.nims` path | declaration and placement findings |
| `nimble runStatistics` | Otter's library file/layout rules, with every finding saved as JSON |
| `otter-repo-graph diff . HEAD --json` before committing | findings in changed code and nearby code |
| `otter-repo-graph checks . stats state --parallel` | combined reports and their local execution timings |
| Source inspection | deciding whether a candidate was a real problem, a fixture, or a limitation |

The first measurement showed 127 missing roles, 243 triple nesting sites and
125 deeper sites. Those are the original tool's observations. Later figures
also reflect a correction to source/test classification, so they should not be
read as a strict before/after coverage comparison.

## Problems fixed

1. **A failed build could silently return an old CLI.** The build hook now hashes
   source, configuration, and dependency contents, including files with old
   timestamps. It builds into a temporary output and replaces the cached program
   only after success. A failed rebuild returns 2 and keeps the previous file
   intact. Gate/checker failures now remain failures and report their cause.
2. **The file checks could mistake examples for live code.** The shell check
   masks strings and ignores doc explanations when looking for unfinished bodies.
   It handles CRLF files and multiline constructors. The library scanner also
   handles multiline strings, escaped quotes, character literals, nested block
   comments, and continued expressions. It no longer compares declaration blocks
   from separate routines. Incorrect `metaTags` and copied-pragma advice was removed.
3. **The statistics pipeline mixed several jobs.** Its file scanning half was
   split into `inventory.nim`, `input_scan.nim`, `imports.nim`, and
   `source_metrics.nim`. Their deepest nesting is now 2. The old input scanner
   reached depth 7. Callers import the appropriate module; the public umbrella
   still exports the actual routines.
4. **Input labels could cross between unrelated files.** An unsafe operation is
   matched to a direct input handler by path and routine name, rather than name
   alone. This report still describes direct handlers, not indirect input flow.
5. **Import depth depended on traversal order and collapsed equal file names.**
   It now uses full module paths, the graph parser's import bindings, stable
   traversal, and completed-path depths. External libraries are outside the local
   depth. Cycles are listed separately.
6. **Ignore and scope totals could be wrong.** Ignore counts use Git's rules,
   including negations. A test below `src/` belongs only to the test scope.
   Deep fixtures remain tests; production files such as `test_scan.nim` remain
   source code. Scope accumulation now uses one shared routine.
7. **The longest-run calculation repeated three versions of one algorithm.**
   Probability tables now choose the categories, and shared helpers count runs
   and calculate the result. Zero, negative, and unsupported block sizes return
   a failing result before division. A runtime contract checks each block's bounds.
   Regression cases check the reference tail probabilities for all three sizes.
8. **Repeated parsed-string insertion helpers differed only in destination and
   case conversion.** One helper now handles pragma tags, issue references, and
   input signals, preserving their different case rules.
9. **Metadata and builds depended on the workspace.** Metadata/build defaults now
   live in `configs/default.toml` and use the shared preset reader. Rune-Pragmas
   is directly pinned, and Nimble-Tasks is pinned to a version containing that
   reader. Directory creation and executable suffixes in build tasks use Nim's
   platform helpers. Test and release-build tasks share the same selected list;
   `runTests` also excludes deliberate crash examples.
10. **Descriptions and declarations were inconsistent.** Existing Nim file
    descriptions are now doc comments, production/example routines declare roles,
    and reported live variables have explicit defaults. Real test blocks now
    declare their purpose. Installation, configuration, and module ownership are
    explained in the README and contributing guide.

## Findings from 2026-10-29

The initial structural measurement covers 935 routines and 28,008 Nim source lines.

| Finding | Observed result | Interpretation |
| --- | --- | --- |
| Missing roles | 0 | Every measured source routine declares a role. |
| Shell file checks | 0 findings | All own Nim/NimScript paths were checked. |
| Library file checks | 141 naming candidates; other rules 0 | Older camelCase parameters remain. This is not an exhaustive count of all naming issues. |
| Nesting | 224 triple, 97 deeper sites | Real readability debt remains; the gate still returns 1. |
| Layout | 28 candidates, including one proposed file split | Inspect dependency boundaries before moving code. |
| Related routine families | 8 candidates | Some are deliberate examples or different jobs with similar shapes. |
| Test reach | 246 of 935 routines not reached by the inferred test graph | A coverage lead, not compiler-measured execution coverage. |
| Discovered tests | 291, of which 288 have declared kinds | Three undeclared rows are program text inside scanner fixtures. |

Work should start with these areas:

- `code_stats/state_writes.nim`: separate field/source parsing from write/read
  analysis. Otter suggests a boundary around the start of its analysis helpers.
- Completed in the follow-up: `evaluation/templates.nim`, `evaluation/excursions.nim`,
  and `evaluation/rank.nim` now separate block calculations and reject invalid
  dimensions before division or indexing.
- `code_stats/config_touch.nim`, `coupling.nim`, and `ui_depth.nim`: give the
  deepest search steps named helpers with explicit inputs and results.
- Parameter naming: the largest reported groups are `repo_graph/nim_parser.nim`
  (18), `test_ui/jobs.nim` (17), and `test_ui/catalog.nim` (15). Rename parameters
  together with named arguments and their doc comments.

No blanket suppression was added to produce a clean gate.

## Candidates that are not production defects

The eight secret candidates were inspected. They are synthetic detector values,
example home paths, source-signature text, a test Git identity in history, and a
machine-code stack-address example in history. No real credential was identified.
History line numbers refer to their original commits, not necessarily today's file.

The lost `Feed.price` write and unread `Feed.lastSeen` belong to the intentional
`examples/state_writes` demonstration. `OtterUiConfig.defaultFlags` is read through
`C.config.defaultFlags` in `test_ui/catalog.nim`; the unread-field report misses
that nested access. The six unfinished-body candidates are source programs stored
inside tests. They are test data rather than unfinished Otter implementations.

The family examples deliberately contain related routines. String slicers such
as `stripComment`, `moduleDir`, and `moduleTail` have different jobs even though
Otter sees similar shapes. A runtime enum selecting between them would make their
call sites harder to understand. Unused public helpers and instrumentation
entry points also need caller inspection before deletion.

HTML strings in the browser clients are a remaining separation task. Embedded
language fixtures and documentation examples should stay recognizable as data.

## Validation and limits

- `nimble test`: 20 programs, 263 passing unittest cases, plus shell-hook
  regressions. Intentional worker failures are exercised by the isolation tests.
- `nimble buildtests`: the same 20 programs compiled in release mode.
- CLI, tracing CLI, graph WebUI, and test WebUI builds checked.
- An isolated source copy built the CLI, ran the statistical/benchmark tests, and
  ran the convention statistics task using only its pinned direct submodules.
  Installed Nimble packages were still supplied by this machine.
- Local combined reading: 818 ms to read the tree and 115 ms for the two checks
  on top. This is one observed run, not a controlled performance comparison.
- Validation used Linux/x86-64 and Nim 2.2.12. Windows task portability was reviewed;
  Windows execution and interactive browser behavior were not tested.

Known measurement limits remain: bracket-group imports are skipped, unqualified
exports can make unused-import candidates wrong, overload resolution is approximate,
three tests inside multiline fixtures are counted, and some nested field reads
are missed. Treat the reports as leads backed by source inspection.

## Reproduce

Enter the README's Nix development shell when the checking tools are not on PATH.

```sh
nimble test
nimble buildtests
nimble runStatistics
nimble statsjson
OTTER_REPORT_LOG=off tools/agent_hooks/nim-check.sh $(git ls-files '*.nim' '*.nims')
OTTER_REPORT_LOG=off tools/agent_hooks/otter-gate.sh --force .
```

`evaluation/statistics/conventions.json` and `code_stats.json` are generated and
ignored by Git. Exit 1 from the forced gate means it reported findings; exit 2
means the check failed to run. Use `otter-build.sh` to obtain the current CLI for
further graph, state, or timing queries.
