# Otter-RepoEvaluation

Compile-time timing instrumentation for Nim repos.

## Purpose
- Let a parent repo enable function-level timing with one additional compile flag: `-d:otterTiming`.
- Inject start and end timing capture around wrapped parent-repo routines.
- Store captured data in an in-memory object that holds tuples of `functionName`, `startTick`, and `endTick`.
- Flush that timing state to a log file when the test process exits.
- Reuse the benchmark layer vendored from `Sigma-BenchAndEval`.

## Repo Boundary
- Owns compile-time instrumentation macros and the in-memory timing store.
- Owns end-of-run log flushing for instrumented test binaries.
- Re-exports Sigma benchmark helpers for local timing comparisons in parent repos.
- Does not rewrite foreign source files on disk.

## Parent Repo Flow
1. Add `Otter-RepoEvaluation` as a dependency or submodule.
2. Import `otter_repo_evaluation`.
3. Wrap the routines you want to instrument with `otterInstrument:` or `otterTimed:`.
4. Run the parent repo tests with `-d:otterTiming`.
5. Otter writes `build/otter_timings.log` on process exit unless the parent test code overrides the path with `setLogPath(...)`.

## Example
```nim
import otter_repo_evaluation

otterInstrument:
  proc parseInput*(s: string): int =
    var
      t: int = 0
    t = s.len
    result = t

  proc runCase*(s: string): int =
    var
      t: int = 0
    t = parseInput(s)
    result = t + 1
```

Run the parent test binary with:

```sh
nim c --path:src -d:otterTiming -r tests/test_smoke.nim
```

If you want a different log target:

```nim
setLogPath("build/my_repo_otter.log")
```

## Main State
- `OtterTimingTuple`
  - one captured timing span.
- `OtterTimingMemory`
  - in-memory store with all timing tuples plus log metadata.

## Main Orchestrators
- `recordTiming`
  - append one captured function span.
- `flushTimingLog`
  - write the full timing object to the log file.
- `otterInstrument`
  - compile-time macro that wraps procs and funcs in a statement list.
- `otterTimed`
  - alias macro for the same instrumentation flow.

## Repo Layout
- `src/otter_repo_evaluation.nim`
  - public library surface.
- `src/otter_repo_evaluation/types.nim`
  - timing tuple and memory types.
- `src/otter_repo_evaluation/state.nim`
  - timing store, exit-hook registration, and log flushing.
- `src/otter_repo_evaluation/instrumentation.nim`
  - compile-time injection macros.
- `src/otter_repo_evaluation/sigma_bridge.nim`
  - Sigma benchmark wrappers and shared monotonic clock helpers.
- `tests/test_smoke.nim`
  - smoke coverage plus an end-of-run log verification.

## Commands
- `nimble test`
  - run the smoke tests.
- `nimble build`
  - compile the smoke test in release mode.
- `nimble find`
  - switch submodule URLs to local sibling clones when available.

## License
Released under [The Unlicense](LICENSE.txt).

## Development Conventions (Short)
- Keep Otter focused on instrumentation and timing state only.
- Keep timing capture monotonic and process-local.
- Prefer compile-time wrapping over runtime reflection tricks.
- Update `.iron/PROGRESS.md` and this README when the public API changes.
- Follow the full workspace rules in `.iron/CONVENTIONS.md`.
