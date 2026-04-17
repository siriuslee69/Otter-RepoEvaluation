# Progress

Commit Message: add direct otter bench pragmas for routines

Features (Planned):
- Compile-time instrumentation blocks for parent repos.
- Monotonic function timing capture with start and end ticks.
- End-of-run timing log flush for test runs.
- Sigma benchmark helper re-exports for parent repos.

Features (Done):
- Initialized the repo layout from the shared template.
- Added Sigma as a vendored submodule dependency.
- Implemented timing state, logging, instrumentation macros, and smoke coverage.
- Added direct routine pragma coverage for `otterTimed` and a bench-named `otterBench` alias.

Features (In Progress):
- Broader parent-repo integration patterns beyond block-based wrapping.

Notes:
- Last change/problem: Parent repos had to shift entire proc blocks under `otterTimed:` even though Nim already supports routine macro-pragmas for single proc definitions.
- Fix attempts: Added and documented a bench-oriented pragma alias, updated smoke coverage to exercise direct proc pragmas, and added sibling Sigma path fallback plus repo-local nimcache usage for local verification.
