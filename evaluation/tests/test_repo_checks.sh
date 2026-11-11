#!/usr/bin/env bash
# Regression checks for the whole-repo, UI and stop-hook checks.
# {.testKind: tkRegression, covers: "repo-check.sh|ui-check.sh|done-check.sh|claude-stop-hook.sh".}
#
# A small repository is built with ONE of each mistake in it. Every heading must
# appear for the broken repo, and none for the repaired one.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
hooks="$root/tools/agent_hooks"
fx=$(mktemp -d "${TMPDIR:-/tmp}/otter-repo-checks.XXXXXX")
trap 'rm -rf "$fx"' EXIT
export OTTER_REPORT_LOG=off

r="$fx/Demo-Repo"
mkdir -p "$r/src/demo" "$r/src/clients/gtk" "$r/agents" "$r/evaluation/tests"
cd "$r"
git init -q . && git config user.email t@example.org && git config user.name t
printf 'task test, "x":\n  exec "nim c -r evaluation/tests/test_one.nim"\n' > demo.nimble
printf 'discard\n' > evaluation/tests/test_one.nim
printf 'discard\n' > evaluation/tests/test_two.nim
printf '# Borders\njob: keep demo data\nnever imports: bifrost, nebel\n' > agents/BORDERS.md
printf '# Progress\n\n## today\n- Not done: the second half\n' > agents/PROGRESS.md
printf 'import bifrost/wire\nproc pad(s: string): string =\n  result = s\n' > src/demo/a.nim
printf 'proc pad(s: string): string =\n  result = s\n# TODO finish this\n' > src/demo/b.nim
printf 'proc pad(s: string): string =\n  result = s\nproc save*(p: string): string {.inline.} =\n  ## p: the path. "" when it worked, else why not.\n  result = ""\n' > src/demo/c.nim
for i in 1 2 3 4 5 6 7 8 9 10; do printf '  paint(row, "#11223%s")\n' "$((i % 10))"; done > src/clients/gtk/row.nim
printf '.a:hover { color: red; }\n.b:hover { color: red; }\n.c:hover { color: red; }\n' > src/clients/gtk/style.css
printf 'old\n' > notes.md.trash
git add -A . && git commit -qm first

out=$(bash "$hooks/repo-check.sh" "$r" || true)
for h in "BORDERS — this repo imports" "LEFTOVERS" "COPIES" "ERROR STYLE" "ORPHAN TESTS" "UNFINISHED" "OPEN ENDS" "no examples" "no README.md"; do
  printf '%s' "$out" | grep -q "$h" || { echo "repo-check missed: $h"; printf '%s\n' "$out"; exit 1; }
done
ui=$(bash "$hooks/ui-check.sh" "$r" || true)
for h in "COLOURS" "HOVER" "MOTION"; do
  printf '%s' "$ui" | grep -q "$h" || { echo "ui-check missed: $h"; printf '%s\n' "$ui"; exit 1; }
done

# The stop hook refuses a hand-over with FIX lines, once, and says why.
payload=$(printf '{"cwd":"%s","stop_hook_active":false}' "$r")
rc=0; printf '%s' "$payload" | bash "$hooks/claude-stop-hook.sh" > /dev/null 2> "$fx/stop" || rc=$?
[ "$rc" -eq 2 ] && grep -q "not a finished hand-over" "$fx/stop"
rc=0; printf '{"cwd":"%s","stop_hook_active":true}' "$r" | bash "$hooks/claude-stop-hook.sh" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ]
rc=0; printf '%s' "$payload" | OTTER_STOP_HOOK=off bash "$hooks/claude-stop-hook.sh" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ]

# Repaired: every heading is gone.
rm notes.md.trash evaluation/tests/test_two.nim src/demo/b.nim
mkdir -p examples
printf 'echo 1\n' > examples/demo.nim
printf '# Demo\n## Installation\nx\n## Issue playbook\nnone\n' > README.md
printf '# Progress\n\n## today\n- Open (needs your decision): should the second half exist at all?\n' > agents/PROGRESS.md
printf 'proc pad*(s: string): string =\n  result = s\n' > src/demo/a.nim
printf 'import ./a\nproc save*(p: string): tuple[ok: bool, err: string] =\n  ## p: the path.\n  result = (pad(p).len > 0, "")\n' > src/demo/c.nim
printf 'const rowTint* = "#112233"\n' > src/clients/gtk/row.nim
printf '.a:hover, .a:focus { color: red; transition: color 0.3s; }\n' > src/clients/gtk/style.css
git add -A . && git commit -qm repaired
rc=0; out=$(bash "$hooks/repo-check.sh" "$r") || rc=$?
[ "$rc" -eq 0 ] || { echo "repo-check still reports:"; printf '%s\n' "$out"; exit 1; }
rc=0; ui=$(bash "$hooks/ui-check.sh" "$r") || rc=$?
[ "$rc" -eq 0 ] || { echo "ui-check still reports:"; printf '%s\n' "$ui"; exit 1; }
rc=0; bash "$hooks/done-check.sh" --quick "$r" > "$fx/done" || rc=$?
[ "$rc" -eq 0 ] || { cat "$fx/done"; exit 1; }

# A folder that is no repo with a .nimble is left alone.
rc=0; bash "$hooks/repo-check.sh" "$fx" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ]
printf 'repo check regressions passed\n'
