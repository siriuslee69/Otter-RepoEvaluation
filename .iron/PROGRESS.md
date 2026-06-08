# Progress

Commit Message: align webui chrome and split visualizer scripts

Features (Planned):
- Compile-time instrumentation blocks for parent repos.
- Monotonic function timing capture with start and end ticks.
- End-of-run timing log flush for test runs.
- Sigma benchmark helper re-exports for parent repos.
- Shared repo graph UI and extension polish beyond the first merged pass.

Features (Done):
- Initialized the repo layout from the shared template.
- Added Sigma as a vendored submodule dependency.
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

Features (In Progress):
- Broader parent-repo integration patterns beyond single-file auto-wrapping.
- Deeper sample-object generation for harder Nim types and more private-function cases.

Notes:
- Last change/problem: The visualizer chrome had conflicting absolute-positioned CSS layers, duplicate search fields, top-row padding drift, and overlapping left-rail groups.
- Fix attempts: Consolidated controls into one qlacier-style top wrapper, kept only the filter/search pair, moved active scope to a bottom-left dock, made wheel input zoom directly, and split core/chrome/layer/startup JS into separate loaded files.
