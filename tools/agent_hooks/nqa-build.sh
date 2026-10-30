#!/usr/bin/env bash
# Print the path to a current nqa binary, compiling it on demand.
#
#   nqa-build.sh            -> prints the binary path, builds only if stale
#   nqa-build.sh --force    -> rebuilds unconditionally
#
# Exit: 0 current binary path on stdout | 2 the sources could not be found or built.
#
# nqa is the jq-compatible command of the Null-QueryAPIs repository (nimble buildCli
# there). The hook scripts call it instead of jq, so nothing else has to be installed.
# The repository is found beside this Otter checkout (../Null-QueryAPIs). Override with
# NQA_HOME, and the build location with OTTER_CACHE.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
NQA_HOME="${NQA_HOME:-$(cd -- "$here/../../.." && pwd)/Null-QueryAPIs}"
CACHE="${OTTER_CACHE:-$HOME/.cache/otter-agent-hooks}"
BIN="$CACHE/nqa"
SRC="$NQA_HOME/src/clients/cli/app_cli.nim"
STAMP="$CACHE/nqa.sha256"

[ -f "$SRC" ] || { echo "nqa: no source at $SRC (set NQA_HOME)" >&2; exit 2; }

force=0
[ "${1:-}" = "--force" ] && force=1

# Hash contents: a checkout can preserve timestamps older than the cached build.
# The shared pragma package and this script are part of the inputs too.
source_hash() {
  {
    nim --version || return 2
    find "$NQA_HOME/src" -type f -print0 | sort -z | xargs -0 -r sha256sum || return 2
    [ ! -f "$NQA_HOME/config.nims" ] || sha256sum "$NQA_HOME/config.nims" || return 2
    for pragmas in "$NQA_HOME/../Rune-Pragmas/meta" "$NQA_HOME/submodules/Rune-Pragmas/meta"; do
      [ -d "$pragmas" ] || continue
      find "$pragmas" -type f -print0 | sort -z | xargs -0 -r sha256sum || return 2
      break
    done
    sha256sum "${BASH_SOURCE[0]}"
  } | sha256sum | cut -d' ' -f1
}

fingerprint=$(source_hash) || { echo "nqa: cannot fingerprint the sources" >&2; exit 2; }
previous=""
[ ! -f "$STAMP" ] || read -r previous < "$STAMP"
if [ "$force" = 1 ] || [ ! -x "$BIN" ] || [ "$fingerprint" != "$previous" ]; then
  mkdir -p "$CACHE"
  pending=$(mktemp "$CACHE/nqa.XXXXXX") || exit 2
  trap 'rm -f "$pending"' EXIT
  # The compiler must run inside the repository, so its config.nims adds the library paths.
  if ! (cd "$NQA_HOME" && nim c -d:release --hints:off --warnings:off \
        --nimcache:"$CACHE/nimcache-nqa" -o:"$pending" "src/clients/cli/app_cli.nim") \
        >"$CACHE/nqa-build.log" 2>&1; then
    echo "nqa: build failed, see $CACHE/nqa-build.log" >&2
    exit 2
  fi
  [ -x "$pending" ] || { echo "nqa: compiler produced no executable" >&2; exit 2; }
  mv -f "$pending" "$BIN" || exit 2
  printf '%s\n' "$fingerprint" > "$STAMP" || exit 2
fi

[ -x "$BIN" ] || exit 2
echo "$BIN"
