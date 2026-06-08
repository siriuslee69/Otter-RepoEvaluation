# Progress

Commit Message: merge ratatoskr graph tooling into otter and add shared web graph clients

Features (Planned):
- Compile-time instrumentation blocks for parent repos.
- Monotonic function timing capture with start and end ticks.
- End-of-run timing log flush for test runs.
- Sigma benchmark helper re-exports for parent repos.
- Shared repo graph UI/extension polish beyond the first merged pass.

Features (Done):
- Initialized the repo layout from the shared template.
- Added Sigma as a vendored submodule dependency.
- Implemented timing state, logging, instrumentation macros, and smoke coverage.
- Added direct routine pragma coverage for `otterTimed` and a bench-named `otterBench` alias.
- Added source-aware debug enter/exit/exception tracing and the `otter-nim` CLI wrapper for plain Nim files.
- Merged the Ratatoskr-style repo parser, graph builder, role inference, exporters, and helper grouping into `src/protocols/repo_graph/`.
- Added sample function execution with generated argument objects and JSON results.
- Added a shared browser UI under `src/clients/webui/web/` plus a Nim WebUI host and a VS Code source extension shell.
- Added repo graph coverage in `tests/test_repo_graph.nim`.

Features (In Progress):
- Broader parent-repo integration patterns beyond single-file auto-wrapping.
- Deeper sample-object generation for harder Nim types and more private-function cases.

Notes:
- Last change/problem: Otter had instrumentation but no merged Ratatoskr-grade repo graph, and the requested UI needed one shared graph model for WebUI and VS Code.
- Fix attempts: Ported the graph pipeline into Otter, added a sample runner and group model, built the shared browser client once, and then attached host-specific bridges for Nim WebUI and VS Code/Codex handoff.
