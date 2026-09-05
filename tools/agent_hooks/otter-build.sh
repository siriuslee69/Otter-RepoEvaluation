#!/usr/bin/env bash
# Print the path to a current otter-repo-graph binary, compiling it on demand.
#
#   otter-build.sh            -> prints the binary path, builds only if stale
#   otter-build.sh --force    -> rebuilds unconditionally
#
# Exit: 0 path on stdout | 2 could not build and no usable binary exists.
#
# Otter's own source tree is found relative to this script, so a clone anywhere
# works. Override with OTTER_HOME, and the build location with OTTER_CACHE.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OTTER_HOME="${OTTER_HOME:-$(cd -- "$here/../.." && pwd)}"
CACHE="${OTTER_CACHE:-$HOME/.cache/otter-agent-hooks}"
BIN="$CACHE/otter-repo-graph"
SRC="$OTTER_HOME/src/clients/cli/otter_repo_graph.nim"

[ -f "$SRC" ] || { echo "otter: no source at $SRC" >&2; exit 2; }

force=0
[ "${1:-}" = "--force" ] && force=1

# Rebuild when forced, when the binary is missing, or when any source is newer.
stale=""
[ -x "$BIN" ] && stale=$(find "$OTTER_HOME/src" -name '*.nim' -newer "$BIN" -print -quit 2>/dev/null)
if [ "$force" = 1 ] || [ ! -x "$BIN" ] || [ -n "$stale" ]; then
  mkdir -p "$CACHE"
  if ! nim c -d:release --hints:off --warnings:off \
        --path:"$OTTER_HOME/src" \
        --nimcache:"$CACHE/nimcache" \
        -o:"$BIN" "$SRC" >"$CACHE/build.log" 2>&1; then
    echo "otter: build failed, see $CACHE/build.log" >&2
    [ -x "$BIN" ] || exit 2   # a stale binary still beats nothing
  fi
fi

[ -x "$BIN" ] || exit 2
echo "$BIN"
