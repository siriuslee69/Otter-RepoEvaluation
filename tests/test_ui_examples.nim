# ============================================================
# | Otter Test UI Examples                                   |
# | -> Grouped versions and one tab-free standalone test     |
# ============================================================

import std/[strutils, unittest]

import otter_repo_evaluation

proc textPathV1*() {.otterUiTest: ("Text paths", "Examples",
    "smoke, text", "Version 1").} =
  check "otter".toUpperAscii() == "OTTER"
  echo "text path version 1 passed"

proc textPathV2*() {.otterUiTest: ("Text paths", "Examples",
    "smoke, text", "Version 2").} =
  check "OTTER".toLowerAscii() == "otter"
  echo "text path version 2 passed"

proc arithmeticPath*() {.otterUiTest: ("Arithmetic path", "Examples",
    "smoke, arithmetic", "Default").} =
  check 6 * 7 == 42
  echo "arithmetic path passed"

proc combinedLeft*() {.otterUiTest: ("Combined paths", "Examples",
    "smoke, combined", "").} =
  check 10 - 3 == 7
  echo "combined left passed"

proc combinedRight*() {.otterUiTest: ("Combined paths", "Examples",
    "smoke, combined", "").} =
  check 10 + 3 == 13
  echo "combined right passed"
