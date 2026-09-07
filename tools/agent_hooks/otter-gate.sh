#!/usr/bin/env bash
# Measure a repo with Otter once enough lines have changed, and say what to fix.
#
#   otter-gate.sh                    -> check the repo holding the working directory
#   otter-gate.sh /path/to/repo      -> check that repo
#   otter-gate.sh --force /path      -> measure now, whatever the line count
#   otter-gate.sh --threshold 400 .  -> use a different line budget
#
# Exit: 0 nothing to report | 1 report printed on stdout | 2 not applicable.
#
# The gate counts lines added or removed since an anchor — across any number of
# commits, plus uncommitted work. The anchor also stores the churn already
# present when it was set, so a repo that was dirty to begin with does not trip
# the threshold on its first edit.
#
# Env: OTTER_LINE_THRESHOLD (150), OTTER_SKIP_ROOTS, OTTER_CACHE, OTTER_HOME.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
THRESHOLD="${OTTER_LINE_THRESHOLD:-150}"
CACHE="${OTTER_CACHE:-$HOME/.cache/otter-agent-hooks}"
STATE="$CACHE/state"
# Workspace roots holding many sibling projects — measuring them means nothing.
SKIP_ROOTS="${OTTER_SKIP_ROOTS:-/mnt/temp/CodingMain}"

force=0
target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --threshold) THRESHOLD="${2:-$THRESHOLD}"; shift 2 ;;
    --threshold=*) THRESHOLD="${1#*=}"; shift ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) target="$1"; shift ;;
  esac
done
[ -n "$target" ] || target="$PWD"
[ -d "$target" ] || target=$(dirname "$target")
[ -d "$target" ] || exit 2

root=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null) || exit 2
for skip in $SKIP_ROOTS; do [ "$root" = "$skip" ] && exit 2; done
# Only meaningful on Nim repos.
[ -n "$(find "$root" -maxdepth 2 -name '*.nimble' -print -quit 2>/dev/null)" ] || exit 2

mkdir -p "$STATE"
key=$(printf '%s' "$root" | sha1sum | cut -c1-16)
mark="$STATE/$key.sha"
head=$(git -C "$root" rev-parse HEAD 2>/dev/null) || exit 2

# Lines touched between a commit and the current working tree.
churn_since() {
  git -C "$root" diff --numstat "$1" -- 2>/dev/null \
    | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {a += $1 + $2} END {print a + 0}'
}
anchor_here() { printf '%s %s' "$head" "$(churn_since "$head")" > "$mark"; }

changed=0
if [ "$force" = 0 ]; then
  [ -f "$mark" ] || { anchor_here; exit 0; }
  read -r base baseline < "$mark"
  : "${baseline:=0}"
  git -C "$root" cat-file -e "$base^{commit}" 2>/dev/null || { anchor_here; exit 0; }
  changed=$(( $(churn_since "$base") - baseline ))
  [ "$changed" -ge "$THRESHOLD" ] 2>/dev/null || exit 0
fi

bin=$("$here/otter-build.sh" 2>/dev/null) || exit 2
json="$CACHE/last-stats-$key.json"
timeout "${OTTER_TIMEOUT:-240}" "$bin" stats "$root" --json > "$json" 2>/dev/null || exit 2
jq -e . "$json" >/dev/null 2>&1 || exit 2

# Anchor forward so the next window starts here, whatever the findings are.
anchor_here

REPO="$root" CHANGED="$changed" THRESH="$THRESHOLD" FORCED="$force" jq -r '
  def top(n): .[0:n];
  def nz(x): if (x // 0) > 0 then true else false end;
  [
    (if env.FORCED == "1"
       then "Otter measured \(env.REPO)."
       else "Otter measured \(env.REPO) after \(env.CHANGED) changed lines (threshold \(env.THRESH))." end),
    "Fix what is listed here before moving on; each item maps to a rule in CONVENTIONS.md.",
    ""
  ]
  + (if nz(.secrets.total) then
      ["SECRETS — \(.secrets.total) candidate(s). Remove or move behind config:"]
      + ([.secrets.items[]? | "  \(.path):\(.line)  \(.kind)  \(.preview)"] | top(8))
     else [] end)
  + (if nz([.embedded.items[]? | select((.path // "") | test("\\.(html|htm|css)$") | not)] | length) then
      ["EMBEDDED CODE — \(.embedded.total) string(s) hold another language (\(.embedded.totalLines) line(s)).",
       "  Rule: another language belongs in its own file. While it is inline, a comment on those lines is written the way THAT language writes one."]
      + ([.embedded.items[]? | select((.path // "") | test("\\.(html|htm|css)$") | not)
          | "  \(.path):\(.line)  \(.lines) line(s) of \(.language), comments are \(if (.comment // "") == "" then "not known - check before adding one" else .comment end)"] | top(8))
     else [] end)
  + (if nz(.placeholders.total) then
      ["PLACEHOLDERS — \(.placeholders.total) routine(s) that do not do the job yet.",
       "  Rule: a placeholder MUST be named with a ph_ prefix, or be finished."]
      + ([.placeholders.items[]? | select((.name // "") | startswith("ph_") | not)
          | "  \(.path):\(.line)  \(.name)"] | top(10))
     else [] end)
  + (if nz(.nest.triples + .nest.deeper) then
      ["NESTING — \(.nest.triples) triple and \(.nest.deeper) deeper site(s).",
       "  Rule: no loop nesting, no if nesting. Pull the inner block into an inline proc or a template."]
      + ([.nest.sites[]? | select((.depth // 0) >= 3)
          | "  \(.path):\(.line)  \(.fn)  depth \(.depth) (\(.keyword))"] | top(10))
     else [] end)
  + (if nz(.unusedFuncs.leftoverCount + .unusedFuncs.publicCount) then
      ["DEAD CODE — \(.unusedFuncs.leftoverCount) leftover (\(.unusedFuncs.leftoverLines) lines), \(.unusedFuncs.publicCount) unused public.",
       "  Rule: no backwards-compatibility shims or dead API. Delete it."]
      + ([.unusedFuncs.items[]? | select(.kind == "leftover")
          | "  \(.path):\(.line)  \(.name)  \(.lines) lines"] | top(8))
     else [] end)
  + (if nz([.roles[]? | select(.name == "undeclared") | .count] | first) then
      ["ROLES — \([.roles[]? | select(.name == "undeclared") | .count] | first) routine(s) declare no role pragma.",
       "  Rule: functions need custom pragmas (role/metaTags). Otter drops undeclared code from every chart."]
     else [] end)
  + (if nz(.config.deadCount + .config.unsetCount) then
      ["CONFIG — \(.config.deadCount) dead and \(.config.unsetCount) never-set field(s) on configurator types."]
     else [] end)
  + (if nz([.files[]? | select(.health == "poor")] | length) then
      ["OVERSIZED FILES — split these; routines are long and the file is dense:"]
      + ([.files[]? | select(.health == "poor")
          | "  \(.path)  \(.lines) lines, \(.functions) routines, avg \(.avgLines | floor), deepest \(.deepest)"] | top(6))
     else [] end)
  + ["",
     "Coverage: \(.tests.buckets[0] // 0) of \(.functions) routines untested; \(.tests.tests) tests, \(.tests.declaredKinds) with a declared testKind.",
     "Shape: \(.totalLines) lines, \(.functions) routines, avg \(.avgLines | floor)."]
  | join("\n")
' "$json" 2>/dev/null

exit 1
