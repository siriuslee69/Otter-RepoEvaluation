#!/usr/bin/env bash
# Check one repository against the rules a single file cannot show.
#
#   repo-check.sh [REPO]        -> findings on stdout, grouped by heading
#
# Exit: 0 nothing to report | 1 findings printed | 2 not a repo with a .nimble
#
# Plain shell on purpose: it runs in under a second, so the stop hook and the
# gate can both afford it. What needs the call graph stays with Otter itself.
#
#   heading        what it found                                  rule
#   -------------  ---------------------------------------------  -----------------
#   BORDERS        an import the repo's own charter forbids,      WORKFLOW.md 2
#                  or no charter at all
#   PINS           a submodule pin that is not pushed             WORKFLOW.md 6
#   LEFTOVERS      *.trash, stray folders below submodules/       GUIDELINES.md
#   COPIES         one helper written out in three or more files  CONVENTIONS.md
#   LOCAL COPY     a file that also exists in a submodule         WORKFLOW.md 2
#   ERROR STYLE    exported routines where "" means success       WORKFLOW.md 4
#   ORPHAN TESTS   test files no nimble task runs                 TOOLS.md
#   UNFINISHED     TODO / FIXME / "not built yet" in src          WORKFLOW.md 5
#   OPEN ENDS      what the newest PROGRESS entry leaves open     WORKFLOW.md 5
#   HANDOFF        no examples, README parts missing, stale       PROJECTS.md
#                  PROGRESS
set -uo pipefail

root="${1:-$PWD}"
root=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || exit 2
ls "$root"/*.nimble >/dev/null 2>&1 || exit 2
cd "$root" || exit 2
out=""
add() { out="${out}$1
"; }

srcs() { git ls-files 'src/*.nim' 2>/dev/null; }

# --- BORDERS: agents/BORDERS.md says what this repo never imports -----------
charter="agents/BORDERS.md"
if [ ! -f "$charter" ]; then
  add "BORDERS — no $charter. Write down this repo's job, what is NOT its job, and what it never imports (WORKFLOW.md 2)."
else
  never=$(grep -iE '^never imports:' "$charter" | head -1 | cut -d: -f2- | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true)
  hits=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    h=$(srcs | xargs -r grep -nEi "^[[:space:]]*(import|from|include)[[:space:]].*\b${name}" 2>/dev/null | head -4)
    [ -n "$h" ] && hits="${hits}${h}
"
    grep -qiE "(path|url).*${name}" .gitmodules 2>/dev/null && hits="${hits}.gitmodules names ${name}
"
  done <<< "$never"
  if [ -n "$hits" ]; then
    add "BORDERS — this repo imports what its own charter ($charter) forbids. Move the code to the repo whose job it is; do not widen the charter to fit."
    add "$(printf '%s' "$hits" | sed 's/^/  /' | head -8)"
  fi
fi

# --- PINS: a pinned commit nobody else can fetch ----------------------------
pins=""
while read -r _ _ sha path; do
  [ -n "${path:-}" ] || continue
  sib="../$(basename "$path")"
  [ -d "$sib/.git" ] || continue
  if ! git -C "$sib" cat-file -e "$sha^{commit}" 2>/dev/null; then
    pins="${pins}  $path -> ${sha:0:7}  unknown to $sib
"
  elif [ -z "$(git -C "$sib" branch -r --contains "$sha" 2>/dev/null | head -1)" ]; then
    pins="${pins}  $path -> ${sha:0:7}  not on any remote branch of $sib
"
  fi
done < <(git ls-tree HEAD submodules/ 2>/dev/null | grep ' commit ')
[ -n "$pins" ] && { add "PINS — a fresh clone cannot build: these submodule pins are not pushed. Say so in the report, or push when the user allowed it."; add "${pins%$'\n'}"; }

# --- LEFTOVERS ---------------------------------------------------------------
trash=$(find . -maxdepth 6 -name '*.trash' -not -path './.git/*' -not -path '*/nimcache/*' 2>/dev/null | head -8)
stray=$(git status --short submodules 2>/dev/null | grep '^??' | head -4)
old=$(git ls-files 2>/dev/null | grep -oE '^.*(_backup|_old|\.stale[^/]*|\.bak)(/|$)' | sort -u | head -6)
[ -n "$trash$stray$old" ] && { add "LEFTOVERS — renamed, stray or backup files still here. Look at each, then remove them with ONE rm at the end of the task. An older version lives in git, not in a _backup folder."; add "$(printf '%s\n%s\n%s' "$trash" "$stray" "$old" | grep -v '^$' | sed 's/^/  /')"; }

# --- COPIES: one private helper, three or more files ------------------------
# Counted by the whole first line, so two routines that only share a name do not count.
copies=$(srcs | xargs -r grep -E '^proc [a-zA-Z0-9_]+\(' 2>/dev/null | grep -v '^[^:]*:proc main(' | sort -u \
  | awk '{i = index($0, ":"); file = substr($0, 1, i - 1); sig = substr($0, i + 1); n[sig]++; f[sig] = f[sig] " " file}
         END {for (k in n) if (n[k] >= 3) printf "  %s\n      in %d files:%s\n", substr(k, 1, 90), n[k], f[k]}' | cut -c1-220 | head -12)
[ -n "$copies" ] && { add "COPIES — the same helper is written out in three or more files. Put it in ONE module and import it."; add "$copies"; }

# --- LOCAL COPY: a file that also lives in a submodule -----------------------
local=""
for f in $(srcs | grep -vE '/(types|config|main|utils|protocols|app)\.nim$'); do
  b=$(basename "$f")
  hit=$(ls submodules/*/src/*/*/"$b" submodules/*/src/*/"$b" submodules/*/src/"$b" 2>/dev/null | head -1)
  [ -n "$hit" ] || continue
  total=$(grep -cvE '^[[:space:]]*(#|$)' "$f"); same=$(grep -vE '^[[:space:]]*(#|$)' "$f" | grep -Fxc -f - "$hit" 2>/dev/null || echo 0)
  [ "$total" -gt 20 ] && [ $((same * 100 / total)) -ge 60 ] && local="${local}  $f  also exists as $hit
"
done 2>/dev/null
[ -n "$local" ] && { add "LOCAL COPY — a file here is mostly the same as a file in a submodule. Delete the copy and import the submodule; a copy drifts, and the fix made there never arrives here."; add "$(printf '%s' "$local" | head -6)"; }

# --- ERROR STYLE: exported, returns string, \"\" means it worked --------------
style=$(srcs | xargs -r awk '
  FNR == 1 { p = 0 }
  /^proc [A-Za-z0-9_`]+\*/ { p = FNR; name = $2; sub(/\*.*/, "", name); s = 0 }
  p && FNR - p <= 4 && /\): string \{\./ { s = FNR }
  s && FNR - s <= 6 && name !~ /(Error|Reason|Text|Name)$/ && /^  ##.*("" (or|when|if) (what|why|it |recorded|ready|nothing)|or why not|"" = ok|"" means)/ { printf "  %s:%d  %s\n", FILENAME, p, name; p = 0; s = 0 }
' 2>/dev/null | head -8)
[ -n "$style" ] && { add "ERROR STYLE — exported routines that answer \"\" for success. A caller reads \`if x.len == 0\` as \"nothing came back\". Answer with ok/err (tuple[ok: bool, err: string], or the repo's Outcome)."; add "$style"; }

# --- ORPHAN TESTS -------------------------------------------------------------
if grep -qE '^task test\b|ownTasks.*"test"' ./*.nimble 2>/dev/null; then
  orphans=""
  for t in $(git ls-files 'evaluation/tests/test_*.nim' 2>/dev/null); do
    n=$(basename "$t" .nim)
    grep -q "$n" ./*.nimble || orphans="${orphans}  $t
"
  done
  [ -n "$orphans" ] && { add "ORPHAN TESTS — the .nimble file names its tests one by one, and these are in none of its tasks, so nobody runs them:"; add "$(printf '%s' "$orphans" | head -8)"; }
fi

# --- UNFINISHED ----------------------------------------------------------------
todo=$(srcs | xargs -r grep -nE '(#|##)[^"]*\b(TODO|FIXME|XXX|not (built|implemented|done) yet|not yet (built|implemented|done)|later work)\b' 2>/dev/null | cut -c1-140 | head -8)
[ -n "$todo" ] && { add "UNFINISHED — the source says work is missing. Finish it, or name the routine ph_ and list it in the README's issue playbook."; add "$(printf '%s' "$todo" | sed 's/^/  /')"; }

# --- OPEN ENDS: the newest PROGRESS entry --------------------------------------
if [ -f agents/PROGRESS.md ]; then
  open=$(awk '/^## /{n++} n==1' agents/PROGRESS.md | grep -nEi '^(- )?(not done|not built|left open|still open|open:|todo)' | grep -viE 'needs (your|the user|a decision)|because' | cut -c1-160 | head -6)
  [ -n "$open" ] && { add "OPEN ENDS — the newest PROGRESS entry leaves work open. For each line: do it now, or rewrite it as \"Open (needs your decision): <the one question>\". \"Not done\" with no reason is not a hand-over."; add "$(printf '%s' "$open" | sed 's/^/  /')"; }
  last=$(git log -1 --format=%H -- agents/PROGRESS.md 2>/dev/null)
  if [ -n "$last" ]; then
    behind=$(git rev-list "$last"..HEAD -- src 2>/dev/null | wc -l)
    [ "$behind" -gt 5 ] && add "HANDOFF — agents/PROGRESS.md is $behind source commits behind. Update it: what was asked, what was built, what was decided and why."
  fi
else
  add "HANDOFF — no agents/PROGRESS.md."
fi

# --- HANDOFF: what a reader needs first ----------------------------------------
[ -n "$(ls examples/*.nim 2>/dev/null | head -1)" ] || add "HANDOFF — no examples/*.nim. Write the example first; it is the API the user will judge (PROJECTS.md)."
if [ -f README.md ]; then
  grep -qi '^#.*installation' README.md || add "HANDOFF — README.md has no Installation section at the top."
  grep -qi 'issue playbook' README.md || add "HANDOFF — README.md has no Issue playbook."
else
  add "HANDOFF — no README.md."
fi

[ -n "${out//[[:space:]]/}" ] || exit 0
printf '%s' "$out"
exit 1
