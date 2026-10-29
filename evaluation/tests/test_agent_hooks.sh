#!/usr/bin/env bash
# Regression checks for cached builds and single-file convention reports.
# {.testKind: tkRegression, covers: "otter-build.sh|nim-check.sh".}
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/otter-hooks.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
export OTTER_HOME="$fixture/repo" OTTER_CACHE="$fixture/cache"
export OTTER_TEST_COUNT="$fixture/builds" OTTER_REPORT_LOG=off
mkdir -p "$OTTER_HOME/src/clients/cli" "$fixture/bin"
cp "$root/evaluation/tests/fixtures/agent_hooks/nim.sh" "$fixture/bin/nim"
chmod +x "$fixture/bin/nim"
export PATH="$fixture/bin:$PATH"
printf 'discard\n' > "$OTTER_HOME/src/clients/cli/otter_repo_graph.nim"
builder="$root/tools/agent_hooks/otter-build.sh"
checker="$root/tools/agent_hooks/nim-check.sh"
binary=$(bash "$builder")
[ "$binary" = "$OTTER_CACHE/otter-repo-graph" ] && [ -x "$binary" ]
[ "$(wc -l < "$OTTER_TEST_COUNT")" -eq 1 ]
[ "$(bash "$builder")" = "$binary" ]
[ "$(wc -l < "$OTTER_TEST_COUNT")" -eq 1 ]
printf 'echo 1\n' > "$OTTER_HOME/src/clients/cli/otter_repo_graph.nim"
touch -r "$binary" "$OTTER_HOME/src/clients/cli/otter_repo_graph.nim"
bash "$builder" > /dev/null
[ "$(wc -l < "$OTTER_TEST_COUNT")" -eq 2 ]
printf '# new configuration\n' > "$OTTER_HOME/config.nims"
bash "$builder" > /dev/null
[ "$(wc -l < "$OTTER_TEST_COUNT")" -eq 3 ]
mkdir -p "$OTTER_HOME/submodules/Rune-Pragmas/meta"
printf '# new dependency\n' > "$OTTER_HOME/submodules/Rune-Pragmas/meta/runePragmas.nim"
bash "$builder" > /dev/null
[ "$(wc -l < "$OTTER_TEST_COUNT")" -eq 4 ]
previous=$(sha256sum "$binary" "$OTTER_CACHE/source.sha256")
rc=0
OTTER_TEST_FAIL=1 bash "$builder" --force > "$fixture/stdout" 2> "$fixture/stderr" || rc=$?
[ "$rc" -eq 2 ] && [ ! -s "$fixture/stdout" ]
[ "$(sha256sum "$binary" "$OTTER_CACHE/source.sha256")" = "$previous" ]
bash "$builder" --force > /dev/null
[ "$(wc -l < "$OTTER_TEST_COUNT")" -eq 6 ]

# Colons inside initialized strings and fields inside constructors are values.
printf '%s\r\n' 'var prefix: string = "--flag:"' > "$fixture/clean.nim"
printf '%s\n' 'var' '  row = Node(' '    field: "value")' >> "$fixture/clean.nim"
printf '%s\n' 'proc rule() =' '  ## Detect a placeholder body.' '  discard' >> "$fixture/clean.nim"
printf '%s\n' 'var code = """' 'let x = 1' 'var y: int' '"""' >> "$fixture/clean.nim"
bash "$checker" "$fixture/clean.nim" > "$fixture/findings"
[ ! -s "$fixture/findings" ]
printf '%s\r\n' 'var' '  missing: int' > "$fixture/bad.nim"
printf '%s\n' 'proc width(): int =' '  result = 5 # placeholder' >> "$fixture/bad.nim"
printf '%s\n' 'proc f() {.tags: "x".} = discard' >> "$fixture/bad.nim"
rc=0
bash "$checker" "$fixture/bad.nim" > "$fixture/findings" || rc=$?
[ "$rc" -eq 1 ]
grep -q ':2 .*without a default' "$fixture/findings"
grep -q 'placeholder body in `width`' "$fixture/findings"
grep -q 'use `tag:`' "$fixture/findings"

# A malformed line budget must return, rather than repeat a failed shift forever.
rc=0
bash "$root/tools/agent_hooks/otter-gate.sh" --threshold > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ]
rc=0
bash "$root/tools/agent_hooks/otter-gate.sh" --threshold nope > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ]

# A missing/broken checker is a failed check, never a clean file.
printf '#!/bin/sh\nexit 2\n' > "$fixture/bin/awk"
chmod +x "$fixture/bin/awk"
rc=0
bash "$checker" "$fixture/clean.nim" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ]
printf 'agent hook regressions passed\n'
