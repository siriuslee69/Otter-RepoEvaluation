#!/usr/bin/env bash
# Keep each checked repository's Otter report rows, and print new rows once.
#
# The identity uses the repository path, source line text, and finding text
# when the report names a source location. Moving code therefore does not turn
# the same result into a new message. Rows without a source location use their
# full text.
set -uo pipefail

root="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      root="${2:-$root}"
      shift 2
      ;;
    --root=*)
      root="${1#*=}"
      shift
      ;;
    *)
      echo "usage: report-once.sh [--root REPO]" >&2
      exit 2
      ;;
  esac
done

repo=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || exit 2
repo=${repo%/}

case "${OTTER_REPORT_LOG:-}" in
  off|false|0)
    cat
    exit 0
    ;;
esac

log="$repo/.otter/reported-findings.log"
if [ -n "${OTTER_REPORT_LOG:-}" ]; then
  case "$OTTER_REPORT_LOG" in
    /*) log="$OTTER_REPORT_LOG" ;;
    *) log="$repo/$OTTER_REPORT_LOG" ;;
  esac
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "sha256sum is required to keep the Otter finding log" >&2
  exit 2
fi

mkdir -p "$(dirname "$log")" || exit 2
touch "$log" || exit 2
work=$(mktemp -d "${TMPDIR:-/tmp}/otter-report-once.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
input="$work/input"
fresh="$work/fresh"
cat > "$input" || exit 2
: > "$fresh"

# A heading starts with words in capitals, then may carry a remark in
# brackets:  "LAYOUT — ..."   "OVERSIZED FILES — ..."   "HINT (not a fault) — ..."
# Without the brackets part a hint inherited the heading above it, and
# was logged as "[OVERSIZED FILES]", a fault, when it is only a hint.
headingPattern='^[A-Z][A-Z[:space:]-]*( \([^)]*\))?$'

lineCount=0
oldCount=0
category="OTTER"

isReportRow() {
  local row="$1"
  if [[ "$row" == "  "* ]]; then
    return 0
  fi
  if [[ "$row" =~ ^[^[:space:]].*:[0-9]+[[:space:]][[:space:]] ]]; then
    return 0
  fi
  if [[ "$row" =~ ^[^[:space:]][^[:space:]]*[[:space:]][[:space:]][^[:space:]] ]]; then
    return 0
  fi
  if [[ "$row" == *" — "* ]]; then
    local heading="${row%% — *}"
    [[ "$heading" =~ $headingPattern ]] && return 0
  fi
  return 1
}

findingId() {
  local row="$1"
  local identity="$category"$'\034'"$row"
  local sourcePath=""
  local relativePath=""
  local sourceText=""
  local body=""
  local location=""
  local lineNumber=""
  local locationPattern='^([[:space:]]*)(.+):([0-9]+)[[:space:]]+(.*)$'

  if [[ "$row" =~ $locationPattern ]]; then
    location="${BASH_REMATCH[2]}"
    lineNumber="${BASH_REMATCH[3]}"
    body="${BASH_REMATCH[4]}"
    relativePath="$location"
    sourcePath="$location"
    case "$sourcePath" in
      "$repo"/*)
        relativePath="${sourcePath#"$repo"/}"
        ;;
      /*) ;;
      *) sourcePath="$repo/$sourcePath" ;;
    esac
    if [ -f "$sourcePath" ]; then
      sourceText=$(sed -n "${lineNumber}p" "$sourcePath" 2>/dev/null || true)
      identity="$category"$'\034'"$relativePath"$'\034'"$sourceText"$'\034'"$body"
    else
      identity="$category"$'\034'"$relativePath"$'\034'"$body"
    fi
  fi

  printf '%s' "$identity" | sha256sum | awk '{print $1}'
}

# A report is made of three kinds of line:
#
#   LAYOUT — 62 place(s) ...        heading: context, its counts change every
#     Rule: a routine belongs ...   run, so it is never a finding of its own
#     src/x.nim:640  SEAM — ...     finding: logged and printed once
#         -> cut at line 640 ...    detail (4+ spaces): belongs to the finding
#                                   above; printed with it, never alone
#
# A fresh finding is printed under its heading, so a row like
# "BifrostConfig.ameSignedExchanges" still says what is wrong with it.
heading=""
rule=""
headingShown=0
lastFresh=0

printHeading() {
  [ "$headingShown" = 1 ] && return
  headingShown=1
  [ -n "$heading" ] && printf '[%s] %s\n' "$category" "${heading#"$category — "}" >> "$fresh"
  [ -n "$rule" ] && printf '  %s\n' "$rule" >> "$fresh"
}

while IFS= read -r row || [ -n "$row" ]; do
  if [[ "$row" == *" — "* ]]; then
    lead="${row%% — *}"
    if [[ "$lead" =~ $headingPattern ]]; then
      category="$lead"
      heading="$row"
      rule=""
      headingShown=0
      lastFresh=0
      continue
    fi
  fi
  if [[ "$row" =~ ^[[:space:]]{2}Rule: ]]; then
    rule="${row#  }"
    continue
  fi
  if [[ "$row" =~ ^[[:space:]]{4,} ]]; then
    [ "$lastFresh" = 1 ] && printf '%s\n' "$row" >> "$fresh"
    continue
  fi

  if ! isReportRow "$row"; then
    continue
  fi

  id=$(findingId "$row")
  if grep -Fq -- "$id"$'\t' "$log"; then
    oldCount=$((oldCount + 1))
    lastFresh=0
    continue
  fi

  display="$row"
  logged="[$category] ${row#"${row%%[![:space:]]*}"}"
  if [[ "$row" == "  "* ]]; then
    printHeading
  else
    display="[NIM] $row"
    logged="$display"
  fi
  display=${display//$'\t'/ }
  printf '%s\t%s\n' "$id" "${logged//$'\t'/ }" >> "$log" || exit 2
  printf '%s\n' "$display" >> "$fresh"
  lineCount=$((lineCount + 1))
  lastFresh=1
done < "$input"

if [ "$lineCount" -gt 0 ]; then
  printf 'Otter: %s new report line(s). Log: %s\n' "$lineCount" "$log"
  cat "$fresh"
  exit 1
fi

if [ "$oldCount" -gt 0 ]; then
  printf 'Otter: no new report lines; %s already recorded. Log: %s\n' \
    "$oldCount" "$log"
  exit 0
fi

# A measurement with no findings still has useful summary lines. Keep those.
cat "$input"
exit 0
