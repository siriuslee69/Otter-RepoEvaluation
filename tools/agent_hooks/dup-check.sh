#!/usr/bin/env bash
# Find routines that were written more than once.
#
#   dup-check.sh [REPO]               -> twins inside one repo
#   dup-check.sh --workspace [REPO]   -> also: routines of this repo that a
#                                        neighbour repo (../*/src) holds too
#
# Exit: 0 nothing to report | 1 findings printed | 2 not a Nim repo
#
# A routine is read as its BODY, not its name. Comments, blank lines and the
# spacing are thrown away first, so two copies that were only re-indented or
# re-commented still match.
#
#   heading       what matched                                  what to do
#   ------------  --------------------------------------------  -------------------------
#   TWINS         the same body, 3 lines or more, in two or     keep one, import it
#                 more places (the name may differ)
#   SAME SHAPE    the same body once every variable name is     one routine with a
#                 replaced by a number (6 lines or more)        parameter, or a generic
#   ELSEWHERE     a body of 5 lines or more that a neighbour    move it to Fylgia-Utils
#                 repo also holds (--workspace only)            (or the repo that owns it)
#
#   proc padLeft(s: string, n: int): string =      proc fill(t: string, w: int): string =
#     var r: string = s                              var o: string = t
#     while r.len < n:                               while o.len < w:
#       r = " " & r                                    o = " " & o
#     result = r                                     result = o
#                       `--------- SAME SHAPE: only the names differ ---------'
#
# Calls (`name(`) and fields (`.name`) keep their names when the shape is taken,
# so `x.len` and `x.high` stay different.
set -uo pipefail

workspace=0
[ "${1:-}" = "--workspace" ] && { workspace=1; shift; }
root="${1:-$PWD}"
root=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || exit 2
ls "$root"/*.nimble >/dev/null 2>&1 || exit 2
cd "$root" || exit 2

# One line per routine:  kind <TAB> key <TAB> file:line <TAB> name <TAB> lines
#   kind E = the exact body, kind S = the shape (names replaced by numbers)
scan='
function flush(   i, body, shape, t, rest, tok, pre, nxt, n) {
  if (name == "" || nb < 3) { name = ""; nb = 0; return }
  body = ""
  for (i = 1; i <= nb; i++) body = body B[i] "\001"
  printf "E\t%s\t%s:%d\t%s\t%d\n", body, FILENAME, at, name, nb
  if (nb >= 6) {
    split("", seen); n = 0; shape = ""; rest = body
    while (match(rest, /[A-Za-z_][A-Za-z0-9_]*/)) {
      pre = substr(rest, 1, RSTART - 1); tok = substr(rest, RSTART, RLENGTH)
      nxt = substr(rest, RSTART + RLENGTH, 1)
      rest = substr(rest, RSTART + RLENGTH)
      if (tok in kw || nxt == "(" || substr(pre, length(pre), 1) == "." || substr(pre, length(pre), 1) == "\"") shape = shape pre tok
      else { if (!(tok in seen)) seen[tok] = ++n; shape = shape pre "$" seen[tok] }
    }
    printf "S\t%s\t%s:%d\t%s\t%d\n", shape rest, FILENAME, at, name, nb
  }
  name = ""; nb = 0
}
BEGIN {
  split("if elif else while for in notin is isnot of case when try except finally raise return result var let const and or not xor div mod shl shr discard break continue block defer yield true false nil string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float bool char byte seq array openArray tuple object ref ptr void auto echo proc func template iterator as from import", K, " ")
  for (i in K) kw[K[i]] = 1
}
FNR == 1 { flush(); head = 0 }
/^(proc|func|template|iterator|method) / {
  flush()
  name = $2; sub(/[*\[(:`].*/, "", name); at = FNR; nb = 0
  head = ($0 ~ /= *$/) ? 0 : 1
  next
}
name != "" && head { if ($0 ~ /= *$/) head = 0; next }
name != "" && /^[^ \t]/ { flush(); next }
name != "" {
  t = $0
  if (t ~ /^[ \t]*(#|$)/) next
  gsub(/[ \t]+/, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
  B[++nb] = t
}
END { flush() }'

own=$(git ls-files 'src/*.nim' 2>/dev/null | while read -r f; do [ -f "$f" ] && printf "%s\n" "$f"; done)
[ -n "$own" ] || exit 0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/otter-dup.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC2086
awk "$scan" $own > "$tmp/own" 2>/dev/null

# Groups of two or more with one key. A SAME SHAPE group that is already a TWINS
# group (the same places) is not said twice.
group='
BEGIN { FS = "\t" }
$1 == want { n[$2]++; where[$2] = where[$2] "\002" $4 "  " $3; len[$2] = $5; places[$2] = places[$2] " " $3 }
END { for (k in n) if (n[k] >= 2) printf "%d\t%s\t%s\n", len[k], places[k], where[k] }'
# One group per line: lines <TAB> places <TAB> entries, each entry after a \002.
show() { sort -t"$(printf '\t')" -k1,1rn | awk -F'\t' -v max="$1" '
  { shown++; if (shown > max) { more++; next }
    printf "  %d lines, written out here:\n", $1
    m = split($3, W, "\002"); for (i = 2; i <= m; i++) printf "      %s\n", W[i] }
  END { if (more) printf "  ... and %d more group(s)\n", more }'; }
out=""
twins=$(awk -v want=E "$group" "$tmp/own")
[ -n "$twins" ] && out="${out}TWINS — the same routine body stands in two or more places. Keep ONE, export it, import it where the others were.
$(printf '%s\n' "$twins" | show 8)
"
taken=$(printf "%s\n" "$twins" | cut -f2)
shapes=$(awk -v want=S "$group" "$tmp/own" | awk -F'\t' -v taken="$taken" '
  BEGIN { n = split(taken, T, "\n"); for (i = 1; i <= n; i++) have[T[i]] = 1 }
  !($2 in have) { print }')
[ -n "$shapes" ] && out="${out}SAME SHAPE — these routines differ only in the names of their variables. Write ONE routine with a parameter (or a generic) and call it.
$(printf '%s\n' "$shapes" | show 8)
"

if [ "$workspace" = 1 ]; then
  me=$(basename "$root")
  for d in "$root"/../*/; do
    r=$(basename "$d"); [ "$r" = "$me" ] && continue
    [ -d "$d/src" ] || continue
    case "$r" in *.trash|*_backup|*.local-backup*) continue ;; esac
    ( cd "$d" && git ls-files "src/*.nim" 2>/dev/null | while read -r f; do [ -f "$f" ] && printf "../%s/%s\n" "$r" "$f"; done )
  done > "$tmp/others"
  if [ -s "$tmp/others" ]; then
    xargs -r awk "$scan" < "$tmp/others" > "$tmp/theirs" 2>/dev/null
    else_=$(awk -F'\t' '
      $1 != "E" || $5 < 5 { next }
      NR == FNR { mine[$2] = "\002" $4 "  " $3; len[$2] = $5; next }
      ($2 in mine) { hit[$2] = hit[$2] "\002" $4 "  " $3 }
      END { for (k in hit) printf "%d\t-\t%s%s\n", len[k], mine[k], hit[k] }' "$tmp/own" "$tmp/theirs")
    [ -n "$else_" ] && out="${out}ELSEWHERE — a routine of this repo is also written out in a neighbour repo. A helper two repos need lives in Fylgia-Utils (or in the repo whose job it is) and is imported by both.
$(printf '%s\n' "$else_" | show 10)
"
  fi
fi

[ -n "${out//[[:space:]]/}" ] || exit 0
printf '%s' "$out"
exit 1
