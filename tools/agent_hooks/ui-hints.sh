#!/usr/bin/env bash
# Hints about a UI: "this might not be such a good idea".
#
#   ui-hints.sh [REPO]        -> hints on stdout (ui-check.sh calls this and
#                                prints them below its findings)
#
# Exit: 0 nothing to say | 1 hints printed | 2 the repo has no UI sources
#
# These are GUESSES made by reading the source: web (css, html), GTK through
# owlkettle (nim), Android (kotlin, layout xml). Each hint starts with MAYBE,
# names a rule of Agent-Conventions/UI.md and shows up to four places. A hint
# never stops a hand-over; an agent looks at the places and either changes them
# or says in one line why they are right.
#
#   hint            what was seen                                   UI.md
#   --------------  ----------------------------------------------  ----------------
#   PLAN PARTS      docs/ui-plan.md lacks one of the five ways      2.1 Five ways
#   CONTRAST        text and background in one rule, ratio < 4.5;   6. Colour
#                   a text colour that reads on no background of
#                   its theme
#   ROLES           colour variables, none named after a role       6. Colour
#   SMALL TEXT      text under 10 px / 11 sp                        5. The numbers
#   SMALL TARGET    something pressed that is under 24 px / 44 dp   5. The numbers
#   SLOW            a transition longer than 0.3 s                  5. Motion
#   SPACE           gaps and paddings that are not on the steps     5. The numbers
#   PADDING         padding in many layers (wrapper AND content)    8. Say it once
#   NAMED TWICE     a label AND a placeholder on the same fields    8. Say it once
#   CENTRED ROWS    rows of data that are centred                   4. Shared edges
#   HOVER ONLY      something shown on hover and never on focus     7. Mouse, finger
#   NAMELESS        glyph buttons with no tooltip / title / text    7. Mouse, finger
#                   for a screen reader
#   DEEP            boxes inside boxes, many levels                 3. Layout
#   INLINE          sizes and colours typed into the page itself    9. Files
#   NO GLYPH        buttons with and without a glyph side by side;  8. Glyphs
#                   signs taken from the machine's font
#   DEAD BUTTON     a control whose press does nothing              8. Settings
#   PLATFORM DIALOG the system's alert, toast or spinner            8. The parts
#   SETTINGS        the program has a thing (a password, data,      8. Settings
#                   sync, roles) and no control for it
set -uo pipefail

root="${1:-$PWD}"
root=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || exit 2
cd "$root" || exit 2
skip='nimcache|/build/|/build\.|node_modules|/submodules/|_backup/|\.stale|/ref[0-9]|/minigames/|\.min\.'
have() { while read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done; }
css=$(git ls-files '*.css' 2>/dev/null | grep -vE "$skip" | have)
html=$(git ls-files '*.html' 2>/dev/null | grep -vE "$skip" | have)
kt=$(git ls-files '*.kt' 2>/dev/null | grep -vE "$skip|/evaluation/|/test/" | have)
xml=$(git ls-files '*/res/layout*/*.xml' 2>/dev/null | grep -vE "$skip" | have)
owl=$(git ls-files 'src/*.nim' 2>/dev/null | grep -vE "$skip" | have | xargs -r grep -lE '^import.*owlkettle|^ *gui:' 2>/dev/null)
[ -n "$css$html$kt$xml$owl" ] || exit 2
out=""
hint() { # name, sentence, places
  [ -n "$3" ] || return 0
  out="${out}MAYBE $1 — $2
$(printf '%s\n' "$3" | head -4 | cut -c1-150 | sed 's/^/  /')
"; }
# One style rule per line: "file <TAB> selector <TAB> declarations". Works on
# style sheets written on one line as well.
rules() { for f in $css; do
    tr '\n' ' ' < "$f" | sed -E 's#/\*[^*]*\*+([^/*][^*]*\*+)*/##g; s/\}/}\n/g' | awk -v f="$f" '
      { i = index($0, "{"); if (!i) next
        s = substr($0, 1, i - 1); b = substr($0, i + 1); sub(/\}.*/, "", b)
        gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
        printf "%s\t%s\t%s\n", f, s, b }'; done; }
tmp=$(mktemp "${TMPDIR:-/tmp}/otter-ui.XXXXXX") || exit 2
trap 'rm -f "$tmp"' EXIT
rules > "$tmp"

# --- PLAN PARTS: the five ways of thinking, each with its part in the plan ------------------------------
if [ -f docs/ui-plan.md ]; then
  lacks=""
  grep -qiE 'goal|intention|a user can'            docs/ui-plan.md || lacks="${lacks}way 1, intention: no goals (\"A user can ...\")
"
  grep -qiE 'prune|keep|extend|struck|neighbour'   docs/ui-plan.md || lacks="${lacks}way 2, copy, extend, prune: no list taken from a similar program
"
  grep -qiE 'walk'                                 docs/ui-plan.md || lacks="${lacks}way 3, walk: no walks with what each step needs
"
  grep -qiE 'parameter|setting'                    docs/ui-plan.md || lacks="${lacks}way 4, parameters: no table of settings
"
  grep -qiE 'complain|praise|review|issue|people'  docs/ui-plan.md || lacks="${lacks}way 5, other people's experience: no complaints, praise or common use
"
  hint "PLAN PARTS" "docs/ui-plan.md does not show all five ways of thinking (UI.md 2.1). Each finds what the others miss." "$lacks"
fi

# --- CONTRAST ------------------------------------------------------------------
#   how bright a colour is:  each of red, green, blue is made linear, then
#   0.2126 r + 0.7152 g + 0.0722 b.  ratio = (brighter + 0.05) / (darker + 0.05).
#   4.5 or more reads well; "muted" text is let through from 3.0.
contrast=$(awk -F'\t' '
  function hx(c,   v) { v = index("0123456789abcdef", tolower(c)) - 1; return v < 0 ? 0 : v }
  function lin(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : exp(2.4 * log((v + 0.055) / 1.055)) }
  function lum(h,   r, g, b) {
    h = substr(h, 2)
    if (length(h) == 3) h = substr(h,1,1) substr(h,1,1) substr(h,2,1) substr(h,2,1) substr(h,3,1) substr(h,3,1)
    r = hx(substr(h,1,1)) * 16 + hx(substr(h,2,1)); g = hx(substr(h,3,1)) * 16 + hx(substr(h,4,1)); b = hx(substr(h,5,1)) * 16 + hx(substr(h,6,1))
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
  function ratio(a, b,   x, y) { x = lum(a); y = lum(b); return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05) }
  { n = split($3, D, ";"); fg = ""; bg = ""; nf = 0; nb = 0
    for (i = 1; i <= n; i++) {
      k = D[i]; sub(/:.*/, "", k); gsub(/ /, "", k)
      v = D[i]; sub(/^[^:]*:/, "", v); gsub(/^ +| +$/, "", v); sub(/ *!important/, "", v)
      if (v !~ /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/) continue
      if (k == "color") fg = v
      else if (k == "background" || k == "background-color") bg = v
      else if (k ~ /^--/ && k ~ /(text|ink|muted)/ && k !~ /(faint|accent|hover)/) { F[++nf] = k; FV[nf] = v }
      else if (k ~ /^--/ && k ~ /(solid|surface|paper|panel|bg|background)/) { B[++nb] = v }
    }
    if (fg != "" && bg != "" && ratio(fg, bg) < 4.5 && $2 !~ /disabled|placeholder/)
      printf "%s  %s  text %s on %s  ratio %.1f\n", $1, substr($2, 1, 40), fg, bg, ratio(fg, bg)
    for (i = 1; i <= nf && nb > 0; i++) {
      best = 0; for (j = 1; j <= nb; j++) if (ratio(FV[i], B[j]) > best) best = ratio(FV[i], B[j])
      need = (F[i] ~ /muted/) ? 3.0 : 4.5
      if (best < need) printf "%s  %s  %s %s reads on none of this theme'"'"'s backgrounds  best ratio %.1f\n", $1, substr($2, 1, 30), F[i], FV[i], best
    } }' "$tmp")
hint CONTRAST "text that may be hard to read (ratio under 4.5). Check it in the light AND the dark theme; a test should hold this (UI.md 6)." "$contrast"

# --- ROLES -----------------------------------------------------------------------
if [ -n "$css" ] && grep -qE '^\s*--[a-zA-Z0-9-]+ *:' $css 2>/dev/null; then
  if ! grep -qiE -- '--[a-z0-9-]*(glue|separator|line|accent|recommend|active|muted)' $css 2>/dev/null; then
    hint ROLES "colour variables exist, but none is named after what it is FOR (glue, separator, recommendation/accent, tiny, active, muted). A name like --blue2 cannot switch with the theme (UI.md 6)." "$(grep -lE '^\s*--[a-zA-Z0-9-]+ *:' $css | head -3)"
  fi
fi

# --- SMALL TEXT ----------------------------------------------------------------
small=$(awk -F'\t' '{ n = split($3, D, ";"); for (i = 1; i <= n; i++) if (D[i] ~ /font-size *:/) {
      v = D[i]; sub(/.*: */, "", v)
      if ((v ~ /^[0-9.]+px/ && v + 0 < 10) || (v ~ /^[0-9.]+rem/ && v + 0 < 0.62) || (v ~ /^\.[0-9]+rem/ && ("0" v) + 0 < 0.62))
        printf "%s  %s  font-size %s\n", $1, substr($2, 1, 50), v } }' "$tmp")
smallkt=$(printf '%s\n' "$kt" | xargs -r grep -HnE 'textSize *= *[0-9](\.[0-9])?f\b|\bsp\(([0-9]|10)\)|setTextSize\([^,]*, *([0-9]|10)(\.[0-9])?f?\)' 2>/dev/null | cut -c1-140)
hint "SMALL TEXT" "text under 10 px (web, GTK) or 11 sp (Android). Small text is for times and counts, and even those are read (UI.md 5)." "$(printf '%s\n%s' "$small" "$smallkt" | grep -v '^$')"

# --- SMALL TARGET -----------------------------------------------------------------
target=$(awk -F'\t' '$2 ~ /(button|btn|\[role=.button|input\[type=.(checkbox|radio))/ && $2 !~ /(::|:before|:after|badge|dot|bar|line|track|thumb| svg$| img$| span$|svg,)/ {
    n = split($3, D, ";"); for (i = 1; i <= n; i++) if (D[i] ~ /^ *(min-)?height *: *[0-9]+px/) {
      v = D[i]; sub(/.*: */, "", v); if (v + 0 > 0 && v + 0 < 24) printf "%s  %s  height %s\n", $1, substr($2, 1, 50), v } }' "$tmp")
targetkt=$(printf '%s\n' "$kt" | xargs -r grep -HnE '(minimumHeight|minHeight|minimumWidth|minWidth) *= *dp\(([0-9]|[1-3][0-9]|4[0-3])\)' 2>/dev/null | grep -iE 'button|btn|click|tap|chip|toggle' | cut -c1-140)
hint "SMALL TARGET" "something that is pressed looks smaller than 24 px (mouse) or 44 dp (finger) (UI.md 5)." "$(printf '%s\n%s' "$target" "$targetkt" | grep -v '^$')"

# --- SLOW --------------------------------------------------------------------------
slow=$(awk -F'\t' '{ n = split($3, D, ";"); for (i = 1; i <= n; i++) if (D[i] ~ /^ *transition(-duration)? *:/) {
      v = D[i]; m = 0
      while (match(v, /[0-9]*\.?[0-9]+m?s/)) { t = substr(v, RSTART, RLENGTH); s = (t ~ /ms$/) ? t / 1000 : t + 0; if (s > m) m = s; v = substr(v, RSTART + RLENGTH) }
      if (m > 0.3) printf "%s  %s  %.2fs\n", $1, substr($2, 1, 50), m } }' "$tmp")
slowkt=$(printf '%s\n' "$kt" | xargs -r grep -HnE '(duration|setDuration\() *=? *\(?([4-9][0-9]{2}|[0-9]{4,})L?\b' 2>/dev/null | cut -c1-140)
hint SLOW "a transition longer than 0.3 s. Hover and press want 0.1 to 0.16 s, a menu 0.04 to 0.1 s; only a sliding panel may take 0.3 s (UI.md 5, Motion)." "$(printf '%s\n%s' "$slow" "$slowkt" | grep -v '^$')"

# --- SPACE: values off the steps (2 4 6 8 12 ...) --------------------------------------
space=$(awk -F'\t' '{ n = split($3, D, ";"); for (i = 1; i <= n; i++) if (D[i] ~ /^ *(gap|padding|margin)[a-z-]* *:/) {
      v = D[i]; sub(/.*: */, "", v); all[$1]++
      if (v ~ /(^| )(5|7|9|11|13|15|17|19)px/) off[$1]++ } }
  END { for (f in off) if (off[f] >= 6 && off[f] * 5 >= all[f]) printf "%s  %d of %d gaps and paddings are odd numbers (5, 7, 9 ... px)\n", f, off[f], all[f] }' "$tmp")
hint SPACE "space that is not taken from the steps 2 4 6 8 12. Nearly-equal gaps make nearly-aligned walls (UI.md 5)." "$space"

# --- PADDING in many layers -----------------------------------------------------------
pad=$(awk -F'\t' '{ all[$1]++; if ($3 ~ /(^|;) *padding[a-z-]* *: *[1-9]/) p[$1]++ }
  END { for (f in p) if (p[f] >= 20 && p[f] * 100 >= all[f] * 45) printf "%s  %d of %d rules set a padding\n", f, p[f], all[f] }' "$tmp")
padkt=$(printf '%s\n' "$kt" | while read -r f; do [ -n "$f" ] || continue; n=$(grep -cE 'setPadding\(|\.padding\(|updatePadding\(' "$f"); [ "$n" -ge 25 ] && printf '%s  %d calls that set a padding\n' "$f" "$n"; done)
padowl=$(printf '%s\n' "$owl" | while read -r f; do [ -n "$f" ] || continue; n=$(grep -cE '^\s+margin *= *[1-9]|Margin\(' "$f"); [ "$n" -ge 25 ] && printf '%s  %d margins set\n' "$f" "$n"; done)
hint PADDING "padding is set in many layers. When a wrapper AND what is in it both hold an inset, the insets add up and the text leaves its wall. One box holds the inset: the one that draws the background (UI.md 8, Say it once)." "$(printf '%s\n%s\n%s' "$pad" "$padkt" "$padowl" | grep -v '^$')"

# --- NAMED TWICE --------------------------------------------------------------------------
twice=$(for f in $html; do l=$(grep -oE '<label[ >]' "$f" | wc -l); p=$(grep -oE '<(input|textarea)[^>]*placeholder=' "$f" | wc -l); [ "$l" -ge 2 ] && [ "$p" -ge 2 ] && printf '%s  %d <label> and %d placeholders\n' "$f" "$l" "$p"; done)
twicekt=$(printf '%s\n' "$kt" | while read -r f; do [ -n "$f" ] || continue; h=$(grep -cE '\.hint *=|setHint\(' "$f"); t=$(grep -cE 'TextView\(' "$f"); [ "$h" -ge 4 ] && [ "$t" -ge $((h * 3)) ] && printf '%s  %d hints and %d text views — is a field named by both?\n' "$f" "$h" "$t"; done)
hint "NAMED TWICE" "fields that may be named twice: a label AND a placeholder (or a glyph above AND beside). One name, best a glyph inside the field (UI.md 8, Say it once)." "$(printf '%s\n%s' "$twice" "$twicekt" | grep -v '^$')"

# --- CENTRED ROWS ----------------------------------------------------------------------------
centred=$(awk -F'\t' '$2 ~ /(row|item|entry|cell|list|line|record)/ && $2 !~ /(empty|icon|glyph|badge|avatar|btn|button|tab|chip)/ && $3 ~ /(text-align *: *center|justify-content *: *center)/ { printf "%s  %s\n", $1, substr($2, 1, 60) }' "$tmp")
hint "CENTRED ROWS" "rows of data that are centred. Things of one kind stop at one shared edge: text at the left, numbers and times at the right (UI.md 4)." "$centred"

# --- HOVER ONLY ---------------------------------------------------------------------------------
hoveronly=$(awk -F'\t' '
  { key = $1 "\t" $2 }
  $2 ~ /:hover/ && $2 !~ /:focus/ && $3 ~ /(^|;) *(display|visibility|opacity|max-height|max-width) *:/ { h[key] = $2; hf[key] = $1 }
  $2 ~ /:focus/ { base = $2; gsub(/:focus(-visible|-within)?/, "", base); foc[$1 "\t" base] = 1 }
  END { for (k in h) { base = h[k]; gsub(/:hover/, "", base); if (!((hf[k] "\t" base) in foc)) printf "%s  %s\n", hf[k], substr(h[k], 1, 70) } }' "$tmp")
hint "HOVER ONLY" "something is shown or opened on hover and has no :focus twin. A phone has no hover and Tab shows nothing (UI.md 7)." "$hoveronly"

# --- NAMELESS -------------------------------------------------------------------------------------
nameless=$(for f in $html; do n=$(tr '\n' ' ' < "$f" | grep -oE '<button[^>]*>[^<]{0,3}</button>' | grep -vcE 'title=|aria-label='); [ "${n:-0}" -ge 2 ] && printf '%s  %d glyph button(s) without title or aria-label\n' "$f" "$n"; done)
namelesskt=$(printf '%s\n' "$kt" | while read -r f; do [ -n "$f" ] || continue; b=$(grep -cE 'ImageButton\(|ImageView\(' "$f"); d=$(grep -cE 'contentDescription|tooltipText' "$f"); [ "$b" -ge 4 ] && [ "$d" -lt $((b / 2)) ] && printf '%s  %d picture buttons, %d descriptions\n' "$f" "$b" "$d"; done)
namelessowl=$(printf '%s\n' "$owl" | while read -r f; do [ -n "$f" ] || continue; b=$(grep -cE '^\s+Button(\(| *:|$)|^\s+icon *=' "$f"); d=$(grep -cE '^\s+tooltip *=' "$f"); [ "$b" -ge 8 ] && [ "$d" -eq 0 ] && printf '%s  %d buttons, no tooltip\n' "$f" "$b"; done)
hint NAMELESS "glyph buttons with no words behind them. The tooltip (mouse), the hold (finger) and a screen reader all need a name (UI.md 7 and 8)." "$(printf '%s\n%s\n%s' "$nameless" "$namelesskt" "$namelessowl" | grep -v '^$')"

# --- DEEP: boxes inside boxes --------------------------------------------------------------------------
deephtml=$(for f in $html; do awk -v f="$f" '
    { line = $0
      while (match(line, /<\/?[a-zA-Z][a-zA-Z0-9]*[^>]*>/)) { t = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
        if (t ~ /^<\//) d--; else if (t !~ /\/>$/ && t !~ /^<(br|hr|img|input|meta|link|source|path|circle|rect|line|use|col|wbr)[ >\/]/) { d++; if (d > m) { m = d; at = NR } } } }
    END { if (m >= 14) printf "%s:%d  %d boxes inside each other\n", f, at, m }' "$f"; done)
deepowl=$(printf '%s\n' "$owl" | while read -r f; do [ -n "$f" ] || continue; awk -v f="$f" '
    /^ *gui:/ { base = match($0, /[^ ]/); on = 1; next }
    on && /^ *[A-Z][A-Za-z]*(\(.*\))? *:? *$/ { d = (match($0, /[^ ]/) - base) / 2; if (d > m) { m = d; at = FNR } }
    on && /^[^ ]/ { on = 0 }
    END { if (m >= 9) printf "%s:%d  %d widgets inside each other\n", f, at, m }' "$f"; done)
deepxml=$(for f in $xml; do awk -v f="$f" '/<[A-Za-z.]*(Layout|ScrollView|CardView)[ >]/ { d++; if (d > m) m = d } /<\/[A-Za-z.]*(Layout|ScrollView|CardView)>/ { d-- } END { if (m >= 6) printf "%s  %d layouts inside each other\n", f, m }' "$f"; done)
hint DEEP "boxes inside boxes, many levels deep. Every level adds an inset and a place a wall can break; a wrapper that only groups can often go (UI.md 3, 8)." "$(printf '%s\n%s\n%s' "$deephtml" "$deepowl" "$deepxml" | grep -v '^$')"

# --- INLINE ------------------------------------------------------------------------------------------------
inline=$(for f in $html; do n=$(grep -oE ' style="[^"]*(color|padding|margin|font-size|width|height)' "$f" | wc -l); [ "$n" -ge 6 ] && printf '%s  %d style="..." with sizes or colours\n' "$f" "$n"; done)
important=$(for f in $css; do n=$(grep -o '!important' "$f" | wc -l); [ "$n" -ge 15 ] && printf '%s  %d times !important — two rules fight over one thing\n' "$f" "$n"; done)
hint INLINE "sizes and colours typed into the page, or forced with !important. They cannot be themed and nobody finds them (UI.md 6, 9)." "$(printf '%s\n%s' "$inline" "$important" | grep -v '^$')"

# --- NO GLYPH: some buttons have a glyph, their neighbours do not ----------------------------------------
noglyphhtml=$(for f in $html; do tr '\n' ' ' < "$f" | grep -oE '<button[^>]*>.{0,200}</button>' | awk -v f="$f" '
    { if ($0 ~ /<(svg|img|i|use)[ >]|class="[^"]*(icon|glyph)/ || $0 ~ /[^\001-\177]/) g++; else w++ }
    END { if (g >= 3 && w >= 3) printf "%s  %d buttons with a glyph, %d with words only\n", f, g, w }'; done)
noglyphowl=$(printf '%s\n' "$owl" | while read -r f; do [ -n "$f" ] || continue; t=$(grep -cE '^\s+text *= *"' "$f"); i=$(grep -cE '^\s+icon *= *|Icon\(|Picture\(|glyph' "$f"); [ "$t" -ge 10 ] && [ "$i" -eq 0 ] && printf '%s  %d texts set, no glyph anywhere\n' "$f" "$t"; done)
fontglyph=$(printf '%s\n%s\n' "$kt" "$owl" | grep -v '^$' | xargs -r grep -HnE '"[^"]{0,3}[\x{2190}-\x{21FF}\x{2300}-\x{23FF}\x{25A0}-\x{27BF}\x{2B00}-\x{2BFF}\x{1F300}-\x{1FAFF}][^"]{0,3}"' 2>/dev/null | grep -viE 'glyphs?\.(kt|nim)|icons?\.(kt|nim)|test' | cut -c1-120 | head -3)
hint "NO GLYPH" "glyphs may be missing: some buttons have one and their neighbours do not, or a sign is taken from the machine's font (it shows as an empty box where the font lacks it). Every kind of thing has ONE glyph, from the program's own set (UI.md 8, Glyphs)." "$(printf '%s\n%s\n%s' "$noglyphhtml" "$noglyphowl" "$fontglyph" | grep -v '^$')"

# --- DEAD BUTTON: a control that does nothing ------------------------------------------------------------
js=$(git ls-files 'src/*.js' 'assets/*.js' 2>/dev/null | grep -vE "$skip" | have)
dead=$(printf '%s\n%s\n%s\n' "$kt" "$js" "$owl" | grep -v '^$' | xargs -r grep -HnE 'setOnClickListener *\{ *\}|onClick *= *\{ *\}|addEventListener\( *["\x27]click["\x27] *, *(\(\) *=> *\{ *\}|function *\(\) *\{ *\})|proc *\(\) *= *discard *$|onclick=""' 2>/dev/null | cut -c1-140)
hint "DEAD BUTTON" "a control whose press does nothing. A setting or button is wired through, or it is not drawn (UI.md 8, Settings)." "$dead"

# --- PLATFORM DIALOG ---------------------------------------------------------------------------------------
plat=$(printf '%s\n%s\n' "$kt" "$js" | grep -v '^$' | xargs -r grep -HnE 'AlertDialog\.Builder|Toast\.makeText|ProgressDialog|(^|[^.A-Za-z_])(alert|confirm|prompt)\(' 2>/dev/null | grep -vE '^\S+:[0-9]+: *(//|\*)' | cut -c1-130)
hint "PLATFORM DIALOG" "the system's own alert, toast or spinner is used. It ignores the theme and looks like another program; dialogs and notices are the app's own (UI.md 8)." "$plat"

# --- SETTINGS: what the program has, and no control for it ---------------------------------------------------
#   has (seen in src/)                  wants (seen in a UI file)
src=$(git ls-files 'src/*' 2>/dev/null | grep -E '\.(nim|kt|js|html)$' | grep -vE "$skip" | have)
uifiles=$(printf '%s\n%s\n%s\n%s\n' "$html" "$kt" "$js" "$owl" | grep -v '^$')
settings=""
if [ -n "$uifiles" ] && printf '%s\n' "$uifiles" | grep -qiE 'setting|prefs|config'; then
  want() { # has-regex, wants-regex, words
    printf '%s\n' "$src" | xargs -r grep -qiE "$1" 2>/dev/null || return 0
    printf '%s\n' "$uifiles" | xargs -r grep -qiE "$2" 2>/dev/null || settings="${settings}$3
"; }
  want 'password|passphrase'            'change.?(the )?(password|passphrase)|new.?password|passwort ändern' 'has a password, but no "change password" was found'
  want 'profile|account'                'sign.?out|log.?out|abmelden'                                        'has profiles or accounts, but no "sign out" was found'
  want 'profile|account'                'delete.?(the )?(account|profile)|konto löschen'                     'has profiles or accounts, but no "delete account" was found'
  want 'e-?mail'                        'change.?(the )?e-?mail|new.?e-?mail'                                'has an e-mail address, but no "change e-mail" was found'
  want 'vault|entries|records|cards|messages|notes' 'export'                                                 'has data the user made, but no "export" was found'
  want 'vault|entries|records|cards|messages|notes' 'import|restore'                                         'has data the user made, but no "import" or "restore" was found'
  want 'sync|replica|federat'           'sync|last.?sync|devices'                                            'syncs, but the UI shows no sync setting or device list'
  want 'theme|dark|light'               'theme'                                                              'has themes, but no theme control was found'
  want 'role|permission|member'         'role|permission'                                                    'has roles or members, but no role or permission control was found'
  want 'notif'                          'notif|quiet|mute'                                                   'sends notices, but no notice setting was found'
  want 'lock|unlock'                    'auto.?lock|lock.?after|timeout|lock now'                            'locks, but no "lock after" or "lock now" was found'
  want 'forward'                        'forward'                                                            'forwards, but the UI has no forwarding setting'
  keys=$(awk '/^\[(runtime|settings|ui)[^]]*\]/ { on = 1; next } /^\[/ { on = 0 } on && /^[A-Za-z_][A-Za-z0-9_]* *=/ { k = $1; sub(/=.*/, "", k); print k }' configs/default.toml 2>/dev/null)
  for k in $keys; do printf '%s\n' "$uifiles" | xargs -r grep -qF "$k" 2>/dev/null || settings="${settings}configs/default.toml: ${k} has no control in the UI
"; done
fi
hint SETTINGS "settings that may be missing (found by what the program has; UI.md 2.1 and 8). Each is built through all six steps, or struck out in docs/ui-plan.md with a reason." "$(printf '%s' "$settings" | head -6)"

[ -n "${out//[[:space:]]/}" ] || exit 0
printf '%s' "$out"
exit 1
