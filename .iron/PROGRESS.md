# Progress

Commit Message: initialize otter timing instrumentation library

Features (Planned):
- Compile-time instrumentation blocks for parent repos.
- Monotonic function timing capture with start and end ticks.
- End-of-run timing log flush for test runs.
- Sigma benchmark helper re-exports for parent repos.

Features (Done):
- Initialized the repo layout from the shared template.
- Added Sigma as a vendored submodule dependency.
- Implemented timing state, logging, instrumentation macros, and smoke coverage.

Features (In Progress):
- Broader parent-repo integration patterns beyond block-based wrapping.

Notes:
- Last change/problem: Otter started as an empty git repo and needed a full Nim library bootstrap plus an internal Sigma dependency layout that works for downstream callers.
- Fix attempts: Bootstrapped the library structure, vendored Sigma, and used relative imports so parent repos only need Otter on their path.
