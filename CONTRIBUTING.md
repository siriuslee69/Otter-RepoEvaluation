# Contributing

Read `.iron/CONVENTIONS.md` first.

## Repo Intent
- Keep Otter small, deterministic, and library-only.
- Favor compile-time instrumentation that parent repos can switch on with `-d:otterTiming`.
- Keep the timing store simple: tuples in memory, one log flush on process exit.

## Safe Change Areas
- Add new wrappers around the vendored Sigma benchmark layer.
- Extend the timing log format if parent repos need more metadata.
- Improve instrumentation macros as long as the flag-off path stays inert.

## Review Focus
- Does the change preserve the `-d:otterTiming` gate?
- Does the log file still get written at process exit?
- Do instrumented routines preserve return values and exception flow?
- Did you update `README.md` and `.iron/PROGRESS.md` for public behavior changes?

## Commands
- `nimble test`
- `nimble build`
- `nimble find`
