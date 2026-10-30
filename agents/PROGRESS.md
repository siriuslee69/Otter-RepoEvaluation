# Progress

Commit Message: simplify statistical checks and fix traced return values

Features (Planned):
- Compile-time instrumentation blocks for parent repos.
- Monotonic function timing capture with start and end ticks.
- End-of-run timing log flush for test runs.
- Built-in benchmark and binary-stream evaluation helpers for parent repos.
- Shared repo graph UI and extension polish beyond the first merged pass.
- Parent-repo adoption of the pragma-driven test UI after Otter example validation.

Features (Done):
- Tracing captures implicit results before the finally hook, fixing zero-valued
  exit logs on Nim 2.4.0. Fixtures cover one evaluation, early/explicit returns,
  generic/inferred result types, func/no-raise routines, and compile-time use.
- 2026-10-30 follow-up: templates, excursions, and matrix rank modules reduced
  to maximum nesting depth 2, with separate counting and scoring steps. Matrix
  blocks use the existing GF(2) reducer; four modules share chi-square scoring.
- Guarded template widths and matrix ranges before shifts, division, or indexing;
  factored rank logarithms avoid overflowing exponentials. Contracts check block
  ranges and scoring inputs. Invalid statistical dimensions fail finitely.
- Ten path-helper naming findings fixed with documented short parameter names;
  internal named calls updated. External named callers must use dir/p/b.
- Eleven new statistical cases cover 32 pre-refactor numerical results, every
  2x3 binary matrix, word crossings, cycle tails, saturation, and invalid sizes.
- Self-review documented in docs/self-review.md, including unresolved naming,
  nesting/layout work and confirmed false reports. Full gate still reports findings.
- Build-hook content fingerprints, atomic cache replacement, and failure propagation;
  shell regression cases cover stale timestamps, dependency/config changes, failed
  builds, malformed thresholds, CRLF, strings, and declaration boundaries.
- Source scans split from the statistics pipeline; corrected path-scoped input labels,
  deterministic local import depth, Git ignore negations, and source/test totals.
- Longest-run calculation uses shared helpers and probability tables, guards invalid
  block sizes, and checks block bounds with Var-Invariants.
- Routine roles, file descriptions, explicit variable defaults, and test-purpose
  markers brought up to date. Shared parsed-string insertion replaces three helpers.
- configs/default.toml owns metadata/build switches. Rune-Pragmas is directly pinned;
  Nimble-Tasks updated to include the shared preset reader. The selected debug and
  release test lists now match and include tracing and source-scan regressions.
- Constant-time check, `otter_repo_graph ct` (`src/protocols/machine_code*`):
    objdump.nim       objdump -d -M intel -l -> routines, instructions,
                      jump targets, source lines; _ZN names decoded
    instructions.nim  what each mnemonic reads/writes, sub-registers as
                      the full one, hidden registers (mul, div, push,
                      pop, call), cautious default counted in the report
    taint.nim         control-flow graph per routine, System V starting
                      marks (openArray = pointer marked, length public),
                      registers / flags / stack slots until nothing grows;
                      BRANCH, ADDRESS, DIVIDE, each with a trail back;
                      per-callee flow summaries (which args reach rax)
    census.nim        jumps vs Nim branch words per source line
    machine_code.nim  secret: pragmas from source, --routine:mod.name:args,
                      shipped build by default, --noinline opt-in,
                      "inlined from" / "inlined into"
  `secret: "a|b"` pragma added to Rune-Pragmas (aa16f89, pushed).
  Tyr, shipped build: constantTimeEqual, aes_core.init, expandKey128
  clean; encryptBlock one BRANCH on ctx.initialized (s* marks the whole
  object - see Issue Playbook); subByteFast (public-only path by design)
  flagged with --noinline; sboxCt clean with --noinline, inlined into
  expandKey128 / subBytes / encryptBlock in the shipped build.
- Every core used (Fylgia auto threader, `src/protocols/fylgia_threads.nim`):
    analyzeProject   three stages; every report inside one stage runs at once
    shape            duplicate pairs scored one row per core; the clumps
                     (Fylgia cloudNodes) no longer re-measure n x n per round
    checks           the hand-made threads and globals are gone
    parsing          every Nim file at once (`parseNimFiles`)
    secrets          one file per job; the folder and the history at once
    timeline         every picked commit read at once
    file walks       `ownFiles` never steps into a vendored folder (Tyr:
                     113 000 files under submodules/ and build/ skipped)
    outside programs `execCmdShared`: std/osproc is not safe across
                     threads (a test hung on a pipe its own process held)
  Tyr-Crypto, working tree: 14.5 s -> 2.4 s; fresh clone 7.5 s -> 1.1 s;
  report identical on Tyr, Fylgia and Bifrost.
  OTTER_THREADS=n (or FYLGIA_THREADS) caps it; `checks` without --parallel
  holds it at one.
- False findings fixed, all seen on Bifrost-ExchangeProtocols:
    secrets / embedded code   files `.gitignore` leaves out are skipped
                              (a vendored Android SDK gave 430 of 473)
    roles                     `proc f(L: T =` on its own line was read as the
                              body, so the role pragma after it was lost
    written and never read    reads through a call (`currentConfig().flag`),
                              a subscript (`tasks[i].hash`), a default
                              argument, a `seq[T]` parameter walked by `for`,
                              and `;`-separated parameters now count; tests
                              count as readers, never as writers
    one write lost            two calls in different branches of one
                              `if`/`case` never both run
    dead code                 a routine handed over by name
                              (`createThread(t, worker, a)`) is used
                              ... and so is a converter (the compiler calls
                              it), a generic call `decode[T](v)`, and an
                              operator (`$x`, `A[i]`)
                              ... and one passed on a continuation line
    placeholders              a no-input `default...`/`init...` routine hands
                              out a start value by design; a raise built
                              from the routine's own inputs is an error
                              helper, not a stub
    test coverage             `tests.untested` lists every routine no test
                              reaches; the walk follows routines passed by
                              name, starts from helpers in test files, and
                              no longer stops at a forward declaration
  Still unseen: reads inside `test "..."` blocks, which are not routines.
  Still unseen: which overload a call picks (the first is assumed), and
  calls made while compiling (`const x = f()`).
- report-once.sh prints a new finding under its heading and rule, with its
  detail lines; headings are never logged, details never printed alone.
- Agent hooks keep a local `.otter/reported-findings.log` in each checked
  repository. Previously recorded report rows stay out of later console
  output; removing a row makes Otter report it again.
- LAYOUT (`code_stats/layout.nim`): the first check that asks whether
  code is FINDABLE rather than whether it is right. Two findings from
  one idea -- a file has an order, and it is either telling you
  something or it is not.

    siblings apart  three routines that build the same thing, or three
                    steps one orchestrator calls, with a file of other
                    material between them
    a thin waist    a line in a long file where the top half stops
                    being needed by the bottom half, named with the
                    line number to cut at. Thin is both absolute and
                    proportional: twelve shared names is thin in a
                    file of thirty-six routines and fat in one of
                    fourteen.

- Visibility: `{.visGroup: 3.}` and `-d:otterVis:3` make a routine say
  when it starts, when it stops, and what every loop in it is doing,
  timed from the first message. With no group asked for the routine is
  handed back exactly as written and the runtime is not compiled in at
  all, so importing the module costs the same as not importing it.
- Multi-check runner: `otter_repo_graph checks . stats state ui
  yields:seal [--parallel]` reads the tree once for every check, builds
  only what is asked for, and can run the checks and the two readings
  at once. Serial and parallel give identical answers.
- Parser: a routine body ends at the routine's own indentation, not at
  the next routine. Tyr went from 3443 routines to 3883 - the 440 were
  written inside `when` blocks and had been swallowed whole.
- Usage counting: a macro applied as a pragma, and a call made from a
  module's own top level, both count as using a routine.
- Diff review: `otter_repo_graph diff` measures the tree twice - the
  working copy, and the tree at a revision unpacked into a scratch
  folder with `git archive` - and subtracts, so what comes back is what
  the change did rather than what the repository is like. Findings are
  matched by path, routine name and kind, never by line, so moved lines
  are not reported as new work.
- Contracts: moved out to the Var-Invariants repository and pinned back
  here as `submodules/Var-Invariants`. `needs` / `gives` / `keeps` and
  their `Run` tier are a library rather than a measurement, so they no
  longer sit in `src/protocols` and are no longer re-exported from the
  umbrella module. `config.nims` puts the submodule (or a sibling clone)
  on the path, so `import var_invariants` is all a routine here needs.
- Yield paths: `otter_repo_graph yields` names every way a routine can
  end, followed along the resolved call edges, with what stops the
  program told apart from what merely raises.
- State writes: `otter_repo_graph state` names who may change each entry
  of a shared object, and proves a lost write by naming the routine that
  calls two blind writers in a row.
- Code statistics: one pass over a tree gives per-file routine lengths
  and health bands, blocks inside blocks with the code in each last
  layer, declared-role tallies, unreachable routines, and how many
  tests reach each routine through the call graph.
- Test kinds: `testKind`, `covers`, and `pins` pragmas, read off
  annotated routines and off a marker comment above a `test "…"` block,
  with declared kinds counted apart from guessed ones.
- `stats` and `statsjson` nimble tasks and an `otter-repo-graph stats`
  command, with a JSON shape a window can draw straight from.
- Fixed the timing log writing blank rows: the exit hook runs after Nim
  has torn this module's globals down, so each finished line is now
  also kept in a flat block the module allocates itself and never frees.
- Initialized the repo layout from the shared template.
- Merged the former Sigma benchmark and statistical protocols directly into Otter.
- Removed the Sigma package and submodule dependency.
- Implemented timing state, logging, instrumentation macros, and smoke coverage.
- Added direct routine pragma coverage for `otterTimed` and the bench-named `otterBench` alias.
- Added source-aware debug enter/exit/exception tracing and the `otter-nim` CLI wrapper for plain Nim files.
- Merged the Ratatoskr-style repo parser, graph builder, role inference, exporters, and helper grouping into `src/protocols/repo_graph/`.
- Added sample function execution with generated argument objects and JSON results.
- Added a shared browser UI under `src/clients/webui/web/` plus a Nim WebUI host and a VS Code source extension shell.
- Restyled the shared WebUI menus with qlacier-style floating shells and collapsible action rails.
- Restored minimap rendering, offset-aware canvas scrolling, hover dropdowns, and aligned floating top controls.
- Reworked the visualizer chrome into one qlacier-style top row, restored separated left-rail groups, moved the active path chip to the canvas bottom-left, made wheel input zoom by default, and split frontend JS into focused loaded scripts.
- Added repo graph coverage in `tests/test_repo_graph.nim`.
- Added `.otterUiTest` metadata for menu, filters, panel grouping, and version tabs.
- Added automatic test-tree discovery, configured/fallback branding, custom CSS, and log output paths.
- Added a restartable WebUI host, independent spawner, isolated compile/run workers, cancellation, and atomic job states.
- Added `nimble testUi` and `nimble buildTestUi` plus grouped and standalone example tests.
- Added discovery, configuration, direct worker, and black-box spawner process tests.
- Adapted Tyr's dark interop-laboratory theme to the reusable Otter test dashboard while retaining Otter menus, filters, grouping, and version tabs.
- Added ordered per-panel version execution, status glyphs on version tabs, and an editable/native-picker output path carried into each worker.
- Consolidated dashboard customization into eleven solid semantic colors; Otter now derives all gradients, transparency, surfaces, glows, shadows, and state treatments internally.
- Added checkbox/card multi-selection with Ctrl/Cmd and Shift ranges, selected-card batch runs, structured worker failure details, source popups, and plain-text/JSON clipboard export.
- Added safe `autopush`, `switch`, and fast-forward-only `applyNightly` Nimble tasks (now from the Nimble-Tasks submodule) for the nightly development workflow.
- Split the Test UI runtime into a monitored main supervisor, direct WebUI host, relay-only orchestrator, persistent test backend, and disposable per-test workers.
- Made every `.otterUiTest` routine run on its own joined thread inside its isolated worker process.
- Added contracts proving distinct persistent process identities, dedicated test threads, worker-crash containment, and backend reuse after a test process exits.
- Added repository-wide optional `defined(...)` discovery, a startup compile-flag dropdown, backend allowlisting, worker `-d:` propagation, and nested-runner inheritance through `OTTER_UI_FLAGS`.
- Expanded card names to two compact lines and kept native/WASM target names normalized as lowercase version tabs.
- Added TOML `default_flags`, host-capability filtering for SIMD defaults, native compiler switches, WASM host-flag filtering, and explicit ARC/ORC selection without overriding Nim's default memory manager.
- Added non-destructive first-run generation of `tests/.otter/config.toml` and `config.css`, a runnable Test UI catalog example, and detailed README guidance for parent setup, flag flow, process isolation, and WebAssembly SIMD.
- Added wildcard safe defaults, separate compile/run timing, horizontally scrollable version tabs, and repeated-click card deselection.

Features (In Progress):
- Convention follow-up: 131 naming candidates and 291 nesting sites at depth 3+;
  state-write module split and other large-module refactors remain.
- Broader parent-repo integration patterns beyond single-file auto-wrapping.
- Deeper sample-object generation for harder Nim types and more private-function cases.
- Keep extending parent-repo test metadata and runtime flag coverage as new suites are adopted.

Notes:
- The updated compiler also exposed incorrect implicit-result values in trace
  logs. Explicit value capture before finally fixes the ordering; statement
  bodies keep their control flow. Expanded integration checks pass in both modes.
- Nim 2.4.0 exposed an existing machine-code test assumption about optimized
  source locations. The test now keeps the constant-time sample strict and uses
  a fixed regression fixture to require reporting a secret added branch. No
  production machine-code findings were suppressed or changed.
- Latest follow-up: 30 deeply nested sites and 10 naming candidates removed without
  changing checker thresholds. Remaining findings are explicit in docs/self-review.md.
- Follow-up validation: 20 programs / 275 unittest cases plus shell regressions;
  expanded statistical tests also pass in release mode. Existing probability
  models and valid-input results are preserved within numerical tolerance.
- Latest review: Otter's own heuristics produced false positives, and the build hook
  could report success using a stale binary. Both reliability problems were fixed
  with regression coverage. See docs/self-review.md for candidate-by-candidate
  interpretation, remaining work, and reproduction commands.
- Initial review validation (2026-10-29): 20 test programs / 263 unittest cases
  plus shell-hook regressions;
  matching release builds and CLI/WebUI builds. An isolated copy built and ran
  evaluation/statistics with pinned direct dependencies and no sibling repositories.
- The full convention gate is not clean: nesting, layout, naming, and known detector
  limitations are retained explicitly. Windows runtime and browser interactions
  were not exercised in this Linux session.

- Last change/problem: `ct` first reported four leaks in Tyr's sboxCt that
  were not there. gcc keeps a loop counter in rdx across a call to a
  routine it knows leaves rdx alone; reading every call as "all scratch
  registers become secret" marked the counter. Then the allocator on an
  error path looked like it handed back a secret pointer.
- Fix attempts: per-callee summaries - the registers a routine really
  writes, and which arguments reach rax, found by the same walk one
  argument at a time (lazy, cached, cautious on call loops). Worked: the
  false findings are gone, the three samples still answer right. Still
  open: one shared "other memory" mark (see Issue Playbook), and s* marks
  public fields of a secret object.
