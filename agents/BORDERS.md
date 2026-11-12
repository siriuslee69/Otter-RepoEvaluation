# Borders

job: measure a repository and say what to fix: its structure, its tests, its speed, and whether a hand-over is finished.
not its job: the pragmas it reads -> Rune-Pragmas. The promises a routine makes -> Var-Invariants. The nimble tasks that call it -> Nimble-Tasks. The rules themselves -> Agent-Conventions. Reading JSON on the command line -> Null-QueryAPIs.
never imports: nebel, geist, bifrost, atlas, avalon
may be imported by: every repo, for its benchmarks and statistics
planned cut: Open (needs your decision): src/ holds 23 000 lines and three jobs. Recommended: the machine-code reader (src/protocols/machine_code) and the statistical tests on binary streams each become a repo of their own; Otter keeps the repository measurements and the agent hooks.

Otter only reads the repos it measures. It never writes into one.
