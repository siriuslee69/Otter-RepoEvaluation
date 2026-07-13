# Progress

Commit Message: add nightly git workflow tasks

Features (Planned):
- Compile-time instrumentation blocks for parent repos.
- Monotonic function timing capture with start and end ticks.
- End-of-run timing log flush for test runs.
- Built-in benchmark and binary-stream evaluation helpers for parent repos.
- Shared repo graph UI and extension polish beyond the first merged pass.
- Parent-repo adoption of the pragma-driven test UI after Otter example validation.

Features (Done):
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

Features (In Progress):
- Broader parent-repo integration patterns beyond single-file auto-wrapping.
- Deeper sample-object generation for harder Nim types and more private-function cases.
- Trial the test UI against Otter examples before replacing any Tyr test catalog or WebUI code.

Notes:
- Last change/problem: Otter's first generic test dashboard worked but lacked Tyr's clearer dark laboratory hierarchy and state styling.
- Fix attempts: Kept Tyr unchanged and adapted its layered background, glass rails, hero circuit, cyan/pink accents, dense cards, glowing states, and responsive behavior to Otter's generic test model.
