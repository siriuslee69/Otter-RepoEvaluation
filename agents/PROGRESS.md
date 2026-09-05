# Progress

Commit Message: move the repository onto the conventional layout.

Features (Planned):
- Compile-time instrumentation blocks for parent repos.
- Monotonic function timing capture with start and end ticks.
- End-of-run timing log flush for test runs.
- Built-in benchmark and binary-stream evaluation helpers for parent repos.
- Shared repo graph UI and extension polish beyond the first merged pass.
- Parent-repo adoption of the pragma-driven test UI after Otter example validation.

Features (Done):
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
- Last change/problem: Test runners could not expose optional compile-time branches, and long card names were truncated before distinguishing native and WASM targets.
- Fix attempts: Added validated project-flag discovery and selection, propagated flags through isolated workers and nested runners, and gave card names a smaller two-line area above target tabs.
