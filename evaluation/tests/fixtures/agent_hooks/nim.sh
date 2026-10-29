#!/usr/bin/env bash
# Test compiler: count builds and optionally fail after touching the output.
# {.role: actor.}
set -eu
if [ "${1:-}" = --version ]; then
  echo 'Nim fixture compiler 1'
  exit 0
fi
printf 'build\n' >> "$OTTER_TEST_COUNT"
for arg in "$@"; do
  case "$arg" in -o:*) output=${arg#-o:} ;; esac
done
printf '#!/bin/sh\nexit 0\n' > "$output"
chmod +x "$output"
[ "${OTTER_TEST_FAIL:-0}" = 0 ]
