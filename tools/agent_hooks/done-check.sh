#!/usr/bin/env bash
# "Am I done?" — everything an agent must pass before it reports back.
#
#   done-check.sh [REPO]            all checks, the tests included
#   done-check.sh --quick [REPO]    without the tests and without Otter's statistics
#
# Exit: 0 every line says ok | 1 at least one line says FIX | 2 not a repo
#
#   line        what it runs                     FIX means
#   ----------  -------------------------------  --------------------------------
#   tree        git status                       uncommitted work
#   repo        repo-check.sh                    borders, leftovers, open ends, ...
#                                                (pins and older error style: a note)
#   ui          ui-check.sh (UI repos only)      colours, focus, stretch, ...
#   files       nim-check.sh on changed files    single-file convention rules
#   otter       otter-gate.sh --force            nesting, placeholders, dead code
#   tests       nimble test                      a test failed, or none ran
#   examples    nimble runExamples               an example no longer runs
#   unpushed    git rev-list                     (never FIX: say it in the report)
#
# Fix every FIX line, run this again, and only then write the report. A line that
# cannot be fixed without the user goes into the report as ONE question.
set -uo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
quick=0
[ "${1:-}" = "--quick" ] && { quick=1; shift; }
root="${1:-$PWD}"
root=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || exit 2
cd "$root" || exit 2
log=$(mktemp -d "${TMPDIR:-/tmp}/otter-done.XXXXXX") || exit 2
bad=0
line() { printf '%-9s %-4s %s\n' "$1" "$2" "$3"; [ "$2" = "FIX" ] && bad=1; return 0; }
details=""
keep() { details="${details}
---- $1
$(cut -c1-220 "$2" | head -"${3:-40}")"; }

dirty=$(git status --short | grep -vE '^\?\? \.otter/| submodules/' | head -20)
if [ -n "$dirty" ]; then line tree FIX "$(printf '%s\n' "$dirty" | wc -l) uncommitted path(s)"; printf '%s\n' "$dirty" > "$log/tree"; keep tree "$log/tree" 12
else line tree ok "clean"; fi

OTTER_REPORT_LOG=off "$here/repo-check.sh" "$root" > "$log/repo" 2>&1; rc=$?
# Headings an agent can always fix itself stop a hand-over. PINS needs a push the
# user must allow, and ERROR STYLE / COPIES in older code are a task of their own:
# those are shown, and must be named in the report, but do not block.
must=$(grep -cE "^(BORDERS|LEFTOVERS|LOCAL COPY|ORPHAN TESTS|UNFINISHED|OPEN ENDS|HANDOFF) — " "$log/repo" 2>/dev/null || true)
if [ $rc -eq 1 ] && [ "${must:-0}" -gt 0 ]; then line repo FIX "$must heading(s) to fix"; keep repo "$log/repo" 60
elif [ $rc -eq 1 ]; then line repo note "$(grep -oE "^(PINS|ERROR STYLE|COPIES)" "$log/repo" | sort -u | tr "\n" " ")— name these in the report"; keep repo "$log/repo" 30
else line repo ok "nothing to report"; fi

"$here/ui-check.sh" "$root" > "$log/ui" 2>&1; rc=$?
[ $rc -eq 1 ] && { line ui FIX "$(grep -cE '^[A-Z]+ — ' "$log/ui") heading(s)"; keep ui "$log/ui" 40; }
[ $rc -eq 0 ] && line ui ok "nothing to report"

base=$(git merge-base HEAD origin/HEAD 2>/dev/null || git rev-parse HEAD~10 2>/dev/null || echo HEAD)
changed=$(git diff --name-only "$base" HEAD -- '*.nim' '*.nims' 2>/dev/null | while read -r f; do [ -f "$f" ] && echo "$f"; done)
if [ -n "$changed" ]; then
  # shellcheck disable=SC2086
  OTTER_REPORT_LOG=off "$here/nim-check.sh" $changed > "$log/files" 2>&1; rc=$?
  # Findings in src/ stop a hand-over. In tests the single-file rules misread some
  # multi-line fixtures, so those are shown as a note.
  insrc=$(grep -cE '^(\./)?src/' "$log/files" 2>/dev/null || true)
  if [ $rc -eq 1 ] && [ "${insrc:-0}" -gt 0 ]; then line files FIX "$insrc finding(s) in changed source files"; keep files "$log/files" 30
  elif [ $rc -eq 1 ]; then line files note "$(wc -l < "$log/files") finding(s) in changed test files"; keep files "$log/files" 12
  else line files ok "$(printf '%s\n' "$changed" | wc -l) changed file(s) clean"; fi
fi

if [ "$quick" = 0 ]; then
  OTTER_REPORT_LOG=off "$here/otter-gate.sh" --force "$root" > "$log/otter" 2>&1
  must=$(grep -cE '^(NESTING|PLACEHOLDERS|DEAD CODE|ENDINGS|ROLES|SECRETS) — |^\[(NESTING|PLACEHOLDERS|DEAD CODE|ENDINGS|ROLES|SECRETS)\]' "$log/otter")
  [ "${must:-0}" -gt 0 ] && { line otter FIX "$must section(s): $(grep -oE '^\[?(NESTING|PLACEHOLDERS|DEAD CODE|ENDINGS|ROLES|SECRETS)' "$log/otter" | tr -d '[' | tr '\n' ' ')"; keep otter "$log/otter" 70; } || line otter ok "no nesting, placeholders, dead code or leaked keys"

  if grep -qE 'task test|nimbleTasks' ./*.nimble 2>/dev/null; then
    timeout "${DONE_TEST_TIMEOUT:-1500}" nimble test > "$log/tests" 2>&1; rc=$?
    okc=$(grep -c '\[OK\]' "$log/tests"); failc=$(grep -c '\[FAILED\]' "$log/tests")
    if [ $rc -ne 0 ] || [ "$failc" -gt 0 ]; then line tests FIX "exit $rc, $okc ok, $failc failed"; grep -nE '\[FAILED\]|Check failed|rror:' "$log/tests" > "$log/testfail"; keep tests "$log/testfail" 30
    elif [ "$okc" -eq 0 ]; then line tests FIX "nimble test ran no test"
    else line tests ok "$okc passed"; fi
  else line tests FIX "the .nimble file has no test task"; fi

  if [ -n "$(ls examples/*.nim 2>/dev/null | head -1)" ]; then
    timeout "${DONE_EXAMPLE_TIMEOUT:-900}" nimble runExamples > "$log/examples" 2>&1; rc=$?
    [ $rc -ne 0 ] && { line examples FIX "an example failed (exit $rc)"; tail -15 "$log/examples" > "$log/exfail"; keep examples "$log/exfail" 15; } || line examples ok "all ran"
  fi
fi

ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo "?")
line unpushed note "$ahead commit(s) ahead of the remote — name this in the report"

[ -n "$details" ] && printf '%s\n' "$details"
rm -rf "$log"
[ "$bad" = 0 ] && { echo; echo "done-check: every line is ok. Now read your own work once as the user would (WORKFLOW.md 5), then report."; exit 0; }
echo; echo "done-check: not done. Fix each FIX line and run this again before reporting."
exit 1
