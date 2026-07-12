# Contributing

Read `.iron/CONVENTIONS.md` first.

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
- Did you update `README.md` and `.iron/PROGRESS.md` for public behavior changes?

## Commands
- `nimble test`
- `nimble buildtests`
- `nimble buildgraphcli`
- `nimble buildwebui`
- `nimble buildvscode`
- `nimble find`
