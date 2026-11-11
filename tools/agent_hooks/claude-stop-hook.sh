#!/usr/bin/env bash
# Claude Code Stop hook: do not let a hand-over go out with open ends.
#
#   { "type": "command",
#     "command": "<OTTER_HOME>/tools/agent_hooks/claude-stop-hook.sh",
#     "timeout": 60 }
#
# When the agent wants to stop, this runs `done-check.sh --quick` on the repo it
# worked in. If a line says FIX, the stop is refused ONCE and the lines are handed
# back as the reason, so the agent fixes them or says why it cannot.
#
# It stays out of the way when:
#   - the agent is already answering a refused stop  (stop_hook_active)
#   - the folder is not a repo with a .nimble file
#   - nothing was touched in the last 45 minutes     (a question, not work)
#   - OTTER_STOP_HOOK=off
#
# It never runs the tests: a stop must stay fast. `done-check.sh` without --quick
# is the agent's own job before it reports (WORKFLOW.md 5).
set -uo pipefail
[ "${OTTER_STOP_HOOK:-}" = "off" ] && exit 0
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
query=$("$here/nqa-build.sh" 2>/dev/null) || exit 0
payload=$(cat 2>/dev/null || true)
active=$(printf '%s' "$payload" | "$query" -r '.stop_hook_active // false' 2>/dev/null)
[ "$active" = "true" ] && exit 0
cwd=$(printf '%s' "$payload" | "$query" -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
ls "$root"/*.nimble >/dev/null 2>&1 || exit 0

# Was this repo worked on just now?
dirty=$(git -C "$root" status --short | grep -vE '^\?\? \.otter/' | head -1)
lastCommit=$(git -C "$root" log -1 --format=%ct 2>/dev/null || echo 0)
age=$(( $(date +%s) - lastCommit ))
[ -n "$dirty" ] || [ "$age" -lt 2700 ] || exit 0

out=$("$here/done-check.sh" --quick "$root" 2>&1); rc=$?
[ $rc -eq 1 ] || exit 0
{
  echo "Otter: this is not a finished hand-over yet ($root)."
  printf '%s\n' "$out" | head -70
  echo
  echo "Fix the FIX lines now. If one of them truly needs the user, say which and ask ONE question; do not list it as 'not done'."
} >&2
exit 2
