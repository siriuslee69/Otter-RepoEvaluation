# Progress

Commit Message: merge evaluation protocols into otter

Features (Planned):
- Compile-time instrumentation blocks for parent repos.
- Monotonic function timing capture with start and end ticks.
- End-of-run timing log flush for test runs.
- Built-in benchmark and binary-stream evaluation helpers for parent repos.
- Shared repo graph UI and extension polish beyond the first merged pass.

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

Features (In Progress):
- Broader parent-repo integration patterns beyond single-file auto-wrapping.
- Deeper sample-object generation for harder Nim types and more private-function cases.

Notes:
- Last change/problem: Parent repositories depended on both Otter and Sigma for related timing and benchmark work.
- Fix attempts: Merged Sigma's protocol modules into Otter, replaced its external timing helper with monotonic standard-library timing, and retained the benchmark API through Otter's public module.
