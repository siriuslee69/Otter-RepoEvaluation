#!/usr/bin/env bash
# Print the path to a current otter-repo-graph binary, compiling it on demand.
#
#   otter-build.sh            -> prints the binary path, builds only if stale
#   otter-build.sh --force    -> rebuilds unconditionally
#
# Exit: 0 current binary path on stdout | 2 current sources could not build.
#
# Otter's own source tree is found relative to this script, so a clone anywhere
# works. Override with OTTER_HOME, and the build location with OTTER_CACHE.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OTTER_HOME="${OTTER_HOME:-$(cd -- "$here/../.." && pwd)}"
CACHE="${OTTER_CACHE:-$HOME/.cache/otter-agent-hooks}"
BIN="$CACHE/otter-repo-graph"
SRC="$OTTER_HOME/src/clients/cli/otter_repo_graph.nim"
STAMP="$CACHE/source.sha256"

[ -f "$SRC" ] || { echo "otter: no source at $SRC" >&2; exit 2; }

force=0
[ "${1:-}" = "--force" ] && force=1

# Hash contents: a checkout can preserve timestamps older than the cached build.
# Configuration and shared dependency changes must invalidate the CLI too.
source_hash() {
  {
    nim --version || return 2
    for base in "$OTTER_HOME" "$OTTER_HOME/submodules/Fylgia-Utils" \
        "$OTTER_HOME/../Fylgia-Utils" "$OTTER_HOME/submodules/Var-Invariants" \
        "$OTTER_HOME/../Var-Invariants" "$OTTER_HOME/submodules/Rune-Pragmas" \
        "$OTTER_HOME/../Rune-Pragmas" "$OTTER_HOME/submodules/Nimble-Tasks" \
        "$OTTER_HOME/../Nimble-Tasks" \
        "$OTTER_HOME/submodules/Var-Invariants/submodules/Rune-Pragmas"; do
      for tree in "$base/src" "$base/meta" "$base/configs"; do
        [ -d "$tree" ] || continue
        find "$tree" -type f -print0 | sort -z | xargs -0 -r sha256sum || return 2
      done
      [ ! -f "$base/config.nims" ] || sha256sum "$base/config.nims" || return 2
    done
    sha256sum "${BASH_SOURCE[0]}"
  } | sha256sum | cut -d' ' -f1
}

fingerprint=$(source_hash) || { echo "otter: cannot fingerprint build inputs" >&2; exit 2; }
previous=""
[ ! -f "$STAMP" ] || read -r previous < "$STAMP"
if [ "$force" = 1 ] || [ ! -x "$BIN" ] || [ "$fingerprint" != "$previous" ]; then
  mkdir -p "$CACHE"
  pending=$(mktemp "$CACHE/otter-repo-graph.XXXXXX") || exit 2
  trap 'rm -f "$pending"' EXIT
  if ! nim c -d:release --hints:off --warnings:off \
        --path:"$OTTER_HOME/src" \
        --nimcache:"$CACHE/nimcache" \
        -o:"$pending" "$SRC" >"$CACHE/build.log" 2>&1; then
    echo "otter: build failed, see $CACHE/build.log" >&2
    exit 2
  fi
  [ -x "$pending" ] || { echo "otter: compiler produced no executable" >&2; exit 2; }
  mv -f "$pending" "$BIN" || exit 2
  printf '%s\n' "$fingerprint" > "$STAMP" || exit 2
fi

[ -x "$BIN" ] || exit 2
echo "$BIN"
