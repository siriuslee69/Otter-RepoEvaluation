# ============================================================
# | Otter Test UI Examples                                   |
# | -> Grouped versions and one tab-free standalone test     |
# ============================================================

import std/[os, strutils, unittest]

import otter_repo_evaluation

var
  MainThreadId: int = getThreadId()

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

proc threadedPath*() {.otterUiTest: ("Thread isolation", "Examples",
    "smoke, thread", "Default").} =
  check getThreadId() != MainThreadId
  echo "dedicated test thread passed"

proc optionalFlagPath*() {.otterUiTest: ("Optional flag", "Examples",
    "smoke, flags", "Default").} =
  when defined(otterOptionalTrace):
    echo "optional Otter flag passed"
  else:
    raise newException(ValueError, "otterOptionalTrace was not enabled")

proc heartbeatLeasePath*() {.otterUiTest: ("Heartbeat lease", "Examples",
    "lifecycle, heartbeat", "Default").} =
  sleep(10_000)
  echo "heartbeat lease test should have been stopped"
