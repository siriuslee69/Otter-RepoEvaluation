#!/usr/bin/env bash
# Check one repository for the five door rules of Nebel's docs/attack_classes.md.
#
#   door-check.sh [REPO]        -> findings on stdout, one heading per rule
#
# Exit: 0 nothing to report | 1 findings printed | 2 not a Nim repo with src/
#
#   heading          what it found                                       class
#   ---------------  --------------------------------------------------  -----
#   OUTSIDE NUMBER   a number read from bytes sizes memory, a loop or a   1
#                    wait before it passed `bounded` or a refusing `if`
#   OPEN DOOR        a table that carries tag "doored" is changed by a    2
#                    routine with no `Admitted`; `admit` is called
#                    outside a routine tagged "door"
#   RE-READ          a text is asked about (isX, validX, checkX ...) and  3
#                    then given on as the ORIGINAL text
#   SECRET BRANCH    a secret compared with ==, or a loop over one that   4
#                    stops early
#   NO DEADLINE      recv, accept, connect or waitForExit with no time    6
#
# A site that is right for a reason says so on its line or the line above:
#     # otter: door <number|open|reread|secret|deadline> <the reason>
# and is counted, not listed.
#
# The program is Otter's own (`otter-repo-graph doors`, src/protocols/code_stats/
# doors.nim). It reads src/ only: tests, examples and dev tools are skipped.
set -uo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

root="${1:-$PWD}"
root=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || exit 2
ls "$root"/*.nimble >/dev/null 2>&1 || exit 2
[ -n "$(git -C "$root" ls-files 'src/*.nim' 2>/dev/null | head -1)" ] || exit 2

bin=$("$here/otter-build.sh") || exit 2
out=$(timeout "${OTTER_TIMEOUT:-240}" "$bin" doors "$root" 2>&1); rc=$?
case "$rc" in
  0) exit 0 ;;
  1) printf '%s\n' "$out"; exit 1 ;;
  *) echo "door-check: otter-repo-graph doors failed (exit $rc)" >&2; exit 2 ;;
esac
