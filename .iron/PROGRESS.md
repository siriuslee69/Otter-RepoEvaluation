# Progress

Commit Message: repair webui minimap and infinite canvas controls

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
- Added repo graph coverage in `tests/test_repo_graph.nim`.

Features (In Progress):
- Broader parent-repo integration patterns beyond single-file auto-wrapping.
- Deeper sample-object generation for harder Nim types and more private-function cases.

Notes:
- Last change/problem: Minimap rendering could be cancelled before it removed `hidden`, and the canvas surface only grew right/down, so dragged nodes could become hard to reach.
- Fix attempts: Render minimap content immediately, translate graph world coordinates into a padded scroll surface, add edge-triggered canvas growth, and add Center/Minimize Distance controls.
