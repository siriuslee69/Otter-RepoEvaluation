# Progress

Commit Message: Ask whether a routine sits anywhere near the thing that uses it

Features (Planned):
- Compile-time instrumentation blocks for parent repos.
- Monotonic function timing capture with start and end ticks.
- End-of-run timing log flush for test runs.
- Built-in benchmark and binary-stream evaluation helpers for parent repos.
- Shared repo graph UI and extension polish beyond the first merged pass.
- Parent-repo adoption of the pragma-driven test UI after Otter example validation.

Features (Done):
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
- Added safe `autopush`, `switch`, and fast-forward-only `applynightly` Nimble tasks for the nightly development workflow.
- Split the Test UI runtime into a monitored main supervisor, direct WebUI host, relay-only orchestrator, persistent test backend, and disposable per-test workers.
- Made every `.otterUiTest` routine run on its own joined thread inside its isolated worker process.
- Added contracts proving distinct persistent process identities, dedicated test threads, worker-crash containment, and backend reuse after a test process exits.
- Added repository-wide optional `defined(...)` discovery, a startup compile-flag dropdown, backend allowlisting, worker `-d:` propagation, and nested-runner inheritance through `OTTER_UI_FLAGS`.
- Expanded card names to two compact lines and kept native/WASM target names normalized as lowercase version tabs.
- Added TOML `default_flags`, host-capability filtering for SIMD defaults, native compiler switches, WASM host-flag filtering, and explicit ARC/ORC selection without overriding Nim's default memory manager.
- Added non-destructive first-run generation of `tests/.otter/config.toml` and `config.css`, a runnable Test UI catalog example, and detailed README guidance for parent setup, flag flow, process isolation, and WebAssembly SIMD.
- Added wildcard safe defaults, separate compile/run timing, horizontally scrollable version tabs, and repeated-click card deselection.

Features (In Progress):
- Broader parent-repo integration patterns beyond single-file auto-wrapping.
- Deeper sample-object generation for harder Nim types and more private-function cases.
- Keep extending parent-repo test metadata and runtime flag coverage as new suites are adopted.

Notes:
- Last change/problem: both things left open last time are closed. The
  parser now ends a body where Nim ends it, which moved every number
  drawn from a body and uncovered 440 routines in Tyr that had never
  been found at all; and a macro used as a pragma now counts as used,
  which took reading each file as one piece rather than a line at a
  time, since a pragma written across two lines never meets its own
  closing brace otherwise.
- Fix attempts: the diff review was rebuilt around the diff instead of
  a second copy of the tree - `git archive | tar` is gone, along with
  the scratch folder and the `.git` it had to be given. It now measures
  once and lets the hunk ranges say which findings are the reader's,
  and catches the one far-reaching case a single measurement misses by
  reading the names on the lines the change removed. One thing stands
  open: building the whole measurement of Tyr takes 32 seconds by
  itself, which is most of any run, and nothing has been done about it.
- Last change: `src/protocols/invariants.nim`, its test, and its example
  left this repository for Var-Invariants. Nothing here used the pragmas
  - the two apparent call sites in `code_stats/project.nim` and
  `repo_graph/nim_parser.nim` turned out to be comments explaining why a
  pragma-applied macro must count as used - so removing the umbrella's
  `export invariants` broke nothing. 209 tests still pass.
- Fix made alongside: an explicit `stage: stDone` now clears the guessed
  placeholder signals in `code_stats/placeholders.nim`. Before, it only
  skipped the "a pragma says this is unfinished" shortcut, so a routine
  whose whole job is to raise - `contractFailed` was the one that
  surfaced it - scored 0.7 for "the body only refuses to work" no matter
  what it said about itself. A declared stage is a person's statement
  and now outranks every guess.
- Where LAYOUT came from, and how it was calibrated. It was written
  after splitting two files in Bifrost by hand -- a 1796-line
  `session.nim` and an 1835-line `handshake.nim` -- and the question
  was whether Otter could have found both without being told.

  It can. Measured against the commit BEFORE those splits, the four
  worst findings in the whole repository are:

    1. session.nim:706   SEAM, waist 12 of 36        <- the file split
    2. file_ops.nim:354  SEAM, waist 11 of 21
    3. handshake.nim:223 APART, the three            <- the exact thing
                         AmeAuthentication              found by hand
                         constructors, 86 strangers
    4. handshake.nim:345 APART, one orchestrator's   <- the other file
                         ten scattered steps            split

  Both hand-found problems are in the top four, and neither was known
  to the check. After the splits: scattered 72 -> 55.

  Four calibration traps, each found by running it and reading the
  output rather than by reasoning:

    a shared return type is far too weak on its own. Four routines
      returning `ByteSeq` are not alternatives, they are four
      encoders: a byte buffer is a MEDIUM, not an identity. The fix
      is that the names must also share a prefix or a suffix, which
      is the author saying "these are a set".
    a file's CURRENCY type says nothing. Where more than a quarter of
      a file's exported routines return the same type, that type
      cannot tell anybody apart. With a floor: below eight exported
      routines the share is a rounding error, not a ratio, and three
      out of three is 100%.
    four orchestrators calling the same five helpers is ONE thing out
      of place. Reported four times it buried everything else, so
      findings are merged by their member list -- and that several
      callers agreed is said out loud, because it is stronger
      evidence rather than weaker.
    balancing a cut by ROUTINE count alone is wrong. Fourteen small
      helpers at the top of a file are half its routines and a
      fourteenth of its lines. Both halves must carry 30% of the
      lines too.
    an ABSOLUTE waist cap alone is wrong for the same reason in the
      other direction. `nim_parser.nim` needed twelve of the fourteen
      routines above its best cut -- six of every seven -- and twelve
      was under the cap. The waist has to be a small SHARE of the
      routines above it as well. That one rule took the false
      positives on Bifrost's pre-split tree from two cuts to one: the
      one file that really was two.
- The waist is measured in the direction people do not expect. Nim
  declares before use, so "nothing above calls below" is true at
  almost every line in almost every file and is worth nothing as a
  signal. What discriminates is the other direction: how many of the
  routines ABOVE the cut the half BELOW it still needs. Twelve out of
  thirty-six is a seam; thirty out of thirty-six is one file.
- Findings are sorted worst-first with cuts ahead of scatters. That is
  not cosmetic: the gate prints the first five and nothing else, and
  before the sort existed it printed whatever the hash table happened
  to yield.
- `test_layout.nim` builds `FunctionInfo` records by hand rather than
  shaping an example repository, unlike `test_families.nim` next door.
  The check is a set of thresholds and a threshold is tested by
  standing on both sides of it, which is fiddly to arrange in real
  source and trivial in a record. Three of the sixteen tests are
  regressions pinning calibration traps above.
- Running it on Bifrost AFTER the two hand splits still reports a seam
  in each of the files that were split -- `handshake.nim:322` at the
  client/server boundary and `framing.nim:624` at the epoch-exchange
  boundary. Both are true: the splits were topical, and these are
  thinner seams the dominant one had been hiding. Files keep having
  seams until they are one thing.
