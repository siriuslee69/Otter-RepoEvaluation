# Contributing

Read the Agent-Conventions repo first.

The current self-review and remaining work are in [docs/self-review.md](docs/self-review.md).
Run `nimble test` for the full selected suite, `nimble runStatistics` for file
conventions, and `tools/agent_hooks/otter-gate.sh --force .` for graph findings.
Check individual changed Nim files with `tools/agent_hooks/nim-check.sh`.
A check returning 2 failed to run; it is not a passing result.

The statistics code follows this flow:

```text
inventory -> parsed routines -> call graph and test walk -> reports
    |                                                   |
    +-> input_scan, imports, source_metrics -------------+
```

Keep file scans in those focused modules. `code_stats/pipeline.nim` owns the
shared routine, file, and coverage calculations. `code_stats/project.nim`
coordinates the passes. The public `code_stats.nim` module exports their APIs.
Source-reading heuristics need both a positive case and a nearby valid case
that stays quiet; otherwise a plausible report can teach callers to ignore it.

## Repo Intent
- Keep Otter deterministic and easy to read.
- Favor compile-time instrumentation that parent repos can switch on with `-d:otterTiming`.
- Keep the timing store simple: tuples in memory, one log flush on process exit.
- Keep the repo-graph layer shared across CLI, WebUI, and VS Code instead of forking frontend-specific parsers.

## Safe Change Areas
- Extend the internal evaluation protocols and benchmark helpers.
- Extend the timing log format if parent repos need more metadata.
- Improve instrumentation macros as long as the flag-off path stays inert.
- Extend repo graph parsing, grouping, or sample-run heuristics.
- Improve the shared browser client in `src/clients/webui/web/` as long as the VS Code and WebUI hosts keep using the same files.

## Review Focus
- Does the change preserve the `-d:otterTiming` gate?
- Does the log file still get written at process exit?
- Do instrumented routines preserve return values and exception flow?
- Does the repo graph stay deterministic on the same source tree?
- Do helper groups stay subordinate to orchestrators instead of flattening the whole repo?
- Does the VS Code bridge still fall back cleanly when Codex commands are unavailable?
- Did you update `README.md` and `agents/PROGRESS.md` for public behavior changes?

## Commands
- `nimble test`
- `nimble buildtests`
- `nimble buildCli`
- `nimble buildWebui`
- `nimble buildvscode`
- `nimble find`
