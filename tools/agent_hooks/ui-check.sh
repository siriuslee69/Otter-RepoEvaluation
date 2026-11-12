#!/usr/bin/env bash
# Check a repository's UI sources against the mistakes UI.md keeps naming.
#
#   ui-check.sh [REPO]          -> findings on stdout
#
# Exit: 0 nothing to report | 1 findings printed | 2 the repo has no UI sources
#
#   heading      what it found                                      UI.md
#   -----------  -------------------------------------------------  ----------------
#   COLOURS      colour values outside the theme files              UI Theming
#   HOVER        :hover rules with no :focus twin (Tab shows        keyboard use
#                nothing), hover colour equal to the base colour
#   STRETCH      rows and buttons told to expand                    fixed heights
#   PROCESSES    programs started as children of the UI             own process
#   CLICKS       handlers that stop a click from reaching its       open menus never
#                target                                             swallow a click
#   MOTION       no transition anywhere in the styles               0.3 s animations
set -uo pipefail

root="${1:-$PWD}"
root=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || exit 2
cd "$root" || exit 2
skip='nimcache|/build/|/build\.|node_modules|/submodules/|_backup/|\.stale|/ref[0-9]'
css=$(git ls-files '*.css' 2>/dev/null | grep -vE "$skip")
ui=$(git ls-files 'src/*.nim' 'src/*.js' 'src/*.html' 'assets/*.js' 'assets/*.html' 2>/dev/null | grep -vE "$skip" | grep -iE 'client|gtk|webui|owl|ui|menu|panel|assets' )
[ -n "$css$ui" ] || exit 2
out=""
add() { out="${out}$1
"; }

# --- COLOURS: one place defines them ------------------------------------------
themed='theme|palette|colou?rs?|contrast|tint|tokens'
# A line that DEFINES a colour (a CSS variable, @define-color, a Nim const) is the
# theme doing its job. Only colours typed where they are used are counted.
loose=$(printf '%s\n%s\n' "$css" "$ui" | grep -v '^$' | grep -viE "$themed" | while read -r f; do
    n=$(grep -E '#[0-9a-fA-F]{6}\b|rgba?\(' "$f" 2>/dev/null | grep -cvE '^[[:space:]]*(--[a-zA-Z0-9-]+ *:|@define-color|[a-zA-Z0-9_]+\*? *(: *string)? *= *")')
    [ "${n:-0}" -gt 8 ] && printf '  %s  %d colour value(s) typed where they are used\n' "$f" "$n"
  done | sort -t' ' -k4 -rn | head -6)
[ -n "$loose" ] && { add "COLOURS — colour values written outside the theme files. A colour named in one place switches with the theme; a colour typed in a widget does not, and shows as white on white in the other theme."; add "$loose"; }

# --- HOVER without FOCUS, hover that changes nothing ---------------------------
for f in $css; do
  hov=$(grep -c ':hover' "$f" 2>/dev/null); foc=$(grep -cE ':focus|:focus-visible|:selected|:checked' "$f" 2>/dev/null)
  [ "${hov:-0}" -gt 2 ] && [ "${foc:-0}" -eq 0 ] && add "HOVER — $f has $hov :hover rules and no :focus rule. Pressing Tab moves the focus and the user sees nothing."
done

# --- STRETCH ---------------------------------------------------------------------
stretch=$(printf '%s\n' "$ui" | xargs -r grep -cE '\b(hexpand|vexpand) *[=:] *true' 2>/dev/null | awk -F: '$2 > 4 {printf "  %s  %d expand flag(s)\n", $1, $2}' | head -5)
[ -n "$stretch" ] && { add "STRETCH — many widgets are told to expand. A list row or a button that expands fills the whole panel. Rows get a fixed height; only the one container that should grow expands."; add "$stretch"; }

# --- PROCESSES ---------------------------------------------------------------------
procs=$(printf '%s\n' "$ui" | grep -iE 'launch|menu|quick|start|desktop_entry' | xargs -r grep -HnE '\b(startProcess|execCmd|execShellCmd|execProcess)\(' 2>/dev/null | grep -vE 'poDaemon|setsid|nohup|systemd-run|detached' | cut -c1-140 | head -5)
[ -n "$procs" ] && { add "PROCESSES — programs the user launches, started without being detached. They die with the UI and write into its terminal. Start them in their own session (setsid / systemd-run --user / poDaemon)."; add "$(printf '%s' "$procs" | sed 's/^/  /')"; }

# --- CLICKS -----------------------------------------------------------------------
# Only the handlers that close things are looked at: a press or click listener on
# the whole page (document / window / body). A key or paste handler that stops its
# own event is not a swallowed click.
#   pass 1 (NR == FNR)  collect the names of the page-wide listeners
#   pass 2              inside such a listener (25 lines), report a stopped event
clickScan='
  function listener(line,   t) {
    if (!match(line, /(document|window|body)[A-Za-z.]*\.addEventListener\( *["\x27](pointerdown|mousedown|click)["\x27] *, */)) return ""
    t = substr(line, RSTART + RLENGTH)
    if (t ~ /^(function|async)[ (]/ || t ~ /^\(/ || t ~ /^[A-Za-z_$][A-Za-z0-9_$]* *=>/) return "+"
    if (match(t, /^[A-Za-z_$][A-Za-z0-9_$]*/)) return substr(t, RSTART, RLENGTH)
    return "+"
  }
  NR == FNR { t = listener($0); if (t != "" && t != "+") names[t] = 1; next }
  { t = listener($0)
    if (t == "+") { left = 25; next }
    if (match($0, /function +[A-Za-z_$][A-Za-z0-9_$]*/)) {
      n = substr($0, RSTART, RLENGTH); sub(/function +/, "", n)
      left = (n in names) ? 25 : 0; next }
    if (left > 0) { left--
      if ($0 ~ /preventDefault\(\)|stopPropagation\(\)/) printf "%s:%d:%s\n", FILENAME, FNR, $0 } }'
clicks=$(printf '%s\n' "$ui" | grep -E '\.(js|html)$' | while read -r f; do awk "$clickScan" "$f" "$f"; done | cut -c1-140 | head -5)
[ -n "$clicks" ] && { add "CLICKS — a page-wide press handler stops the event. An open menu must close AND let the click reach what it was aimed at (UI.md, \"Open menus never swallow a click\")."; add "$(printf '%s' "$clicks" | sed 's/^/  /')"; }

# --- MOTION -------------------------------------------------------------------------
if [ -n "$css" ] && ! printf '%s\n' "$css" | xargs -r grep -qE 'transition' 2>/dev/null; then
  add "MOTION — no transition in any style sheet. Hover, open and close want a short one (UI.md)."
fi

[ -n "${out//[[:space:]]/}" ] || exit 0
printf '%s' "$out"
exit 1
