#!/usr/bin/env bash
# Check Nim sources against the single-file rules in CONVENTIONS.md.
#
#   nim-check.sh FILE...        -> one line per finding on stdout
#   nim-check.sh $(git ls-files '*.nim')
#   OTTER_REPORT_LOG=off ...    -> print findings without de-duplication
#
# Exit: 0 nothing to report | 1 findings printed | 2 nothing checkable given.
#
# Only the rules decidable from one file live here. Everything needing the whole
# call graph — nesting depth, dead code, roles, scored placeholders — belongs to
# `otter-gate.sh`, which asks Otter itself.
set -uo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

[ $# -gt 0 ] || { echo "usage: nim-check.sh FILE..." >&2; exit 2; }

MAX_PER_FILE="${NIM_CHECK_MAX:-24}"
found=0
checked=0
root=""
report=$(mktemp "${TMPDIR:-/tmp}/otter-nim-check.XXXXXX") || exit 2
trap 'rm -f "$report"' EXIT

for f in "$@"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.nim|*.nims) ;;
    *) continue ;;
  esac
  checked=$((checked + 1))

  if [ -z "$root" ]; then
    fileDir=$(cd -- "$(dirname -- "$f")" 2>/dev/null && pwd)
    if [ -n "$fileDir" ]; then
      root=$(git -C "$fileDir" rev-parse --show-toplevel 2>/dev/null || true)
    fi
  fi

  out=$(MAXN="$MAX_PER_FILE" awk '
  function flag(line, msg) { if (n < max) { n++; printf "%s:%d  %s\n", FILENAME, line, msg } }
  BEGIN { max = ENVIRON["MAXN"] + 0; if (max <= 0) max = 24 }
  FNR == 1 { inBlock = 0; open = 0 }

  # How many brackets a line leaves open; strings and comments do not count.
  #   "parts: tuple[a: int, b: int] = ("   -> 1   the value goes on below
  function openOf(s,   t, o, c) {
    t = s; gsub(/"[^"]*"/, "", t); sub(/#.*/, "", t)
    o = gsub(/[([{]/, "", t); c = gsub(/[])}]/, "", t); return o - c
  }
  # One whole declaration, joined over its lines, is judged once:
  #   scopes: tuple[src: Stats,          <- no "=" yet, brackets still open
  #     all: Stats] = (src: Stats(),     <- a continuation, not a new var
  #     all: Stats())                    <- closed: judged, has a value
  function judgeDecl() {
    open = 0
    if (declText !~ /=/) flag(declLine, "`var` without a default value — initialize it")
  }

  # --- placeholder bodies must carry the ph_ prefix ---
  /^[[:space:]]*(proc|func|method|iterator|template|macro)[[:space:]]+/ {
    match($0, /(proc|func|method|iterator|template|macro)[[:space:]]+`?[A-Za-z_][A-Za-z0-9_]*/)
    d = substr($0, RSTART, RLENGTH); sub(/^[a-z]+[[:space:]]+/, "", d); gsub(/`/, "", d)
    curName = d; curLine = NR; phDone = 0
  }
  { low = tolower($0) }
  # "placeholder" as a word, not the field `S.placeholders` or a name
  # like `placeholderWords` that merely contains it.
  (low ~ /(^|[^a-z_.])placeholder([^a-z_]|$)|not implemented|unimplemented|[^a-z]stub[^a-z]|for now/) && curName != "" && !phDone {
    if (curName !~ /^ph_/) {
      flag(curLine, "placeholder body in `" curName "` — rename to `ph_" curName "` or finish it")
      phDone = 1
    }
  }

  # --- `tags` collides with Nim built-in; the shared pragma is metaTags ---
  /\{\.[[:space:]]*tags[[:space:]]*:/ || /,[[:space:]]*tags[[:space:]]*:/ {
    flag(NR, "`tags:` pragma collides with Nim built-in — use `metaTags:`")
  }

  # --- the .iron/ directory was removed; state lives in agents/PROGRESS.md ---
  /\.iron\// { flag(NR, "`.iron/` was removed — use agents/PROGRESS.md and meta/metaPragmas.nim") }

  # --- flagged vocabulary ---
  low ~ /aud[i]t/ { flag(NR, "avoid that word — use evaluate / benchmark / harden / check / verify") }

  # --- declaration blocks ---
  /^[[:space:]]*(var|let|const|type)[[:space:]]*$/ {
    match($0, /^[[:space:]]*/); blockKw = $1; blockIndent = RLENGTH; inBlock = 1; next
  }
  inBlock {
    if ($0 ~ /^[[:space:]]*$/) next
    match($0, /^[[:space:]]*/)
    if (RLENGTH <= blockIndent) { inBlock = 0; open = 0 }
    else {
      if (open > 0) {
        declText = declText " " $0; open += openOf($0)
        if (open <= 0) judgeDecl()
        next
      }
      if (blockKw == "let") flag(NR, "`let` in a block — use `var` or `const` unless this is a many-branch init")
      if ((blockKw == "var") && $0 ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_,[:space:]]*:/) {
        declText = $0; declLine = NR; open = openOf($0)
        if (open <= 0) judgeDecl()
      }
      next
    }
  }

  # --- single-line declarations ---
  /^[[:space:]]*let[[:space:]]+[A-Za-z_]/ {
    flag(NR, "`let` declaration — use `var` or `const` unless this is a many-branch init")
  }
  /^[[:space:]]*(var|const)[[:space:]]+[A-Za-z_]/ {
    match($0, /^[[:space:]]*/); ind = RLENGTH; kw = $1
    if (kw == prevKw && ind == prevInd && NR == prevNR + 1)
      flag(NR, "repeated `" kw "` on consecutive lines — indent them into one `" kw ":` block")
    prevKw = kw; prevInd = ind; prevNR = NR
    if (kw == "var" && $0 ~ /:[[:space:]]*[^=]+$/) flag(NR, "`var` without a default value — initialize it")
    next
  }
  { if ($0 !~ /^[[:space:]]*$/) prevKw = "" }
  ' "$f" 2>/dev/null)

  # --- layout rules, read from the path rather than the contents ---
  case "$f" in
    */evaluation/*|evaluation/*) ;;
    *)
      case "$(basename "$f")" in
        test_*.nim|*_test.nim)
          out="${out:+$out
}$f  tests belong under evaluation/tests/" ;;
        bench_*.nim|*_bench.nim|benchmark_*.nim)
          out="${out:+$out
}$f  benchmarks belong under evaluation/benchmarks/" ;;
      esac ;;
  esac

  if [ -n "${out//[[:space:]]/}" ]; then
    printf '%s\n' "$out" >> "$report"
    found=1
  fi
done

[ "$checked" -gt 0 ] || exit 2
[ "$found" = 0 ] && exit 0
if [ -n "$root" ]; then
  bash "$here/report-once.sh" --root "$root" < "$report"
else
  cat "$report"
fi
exit 1
