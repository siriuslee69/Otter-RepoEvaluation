## ----------------------------------------------------------------------
## Otter Test UI Example <- grouped native/wasm cards and optional flags
## ----------------------------------------------------------------------

import std/unittest

import otter_repo_evaluation

proc hashNative*() {.otterUiTest: ("Hash vectors", "Crypto",
    "functional, vectors, hash", "native").} =
  check "otter".len == 5
  when defined(exampleVerbose):
    echo "native example used exampleVerbose"

proc hashWasm*() {.otterUiTest: ("Hash vectors", "Crypto",
    "functional, vectors, hash, wasm", "wasm").} =
  ## A real parent project can delegate here to its Emscripten build helper.
  check 2 + 2 == 4

proc parserSmoke*() {.otterUiTest: ("Parser smoke", "Core",
    "functional, parser", "").} =
  check @[1, 2, 3].len == 3
