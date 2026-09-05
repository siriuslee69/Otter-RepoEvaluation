# ============================================================
# | Otter Test UI Failure Example                            |
# | -> Supplies structured assertion details to the popup    |
# ============================================================

import std/unittest

import otter_repo_evaluation

proc intentionalFailure*() {.otterUiTest: ("Failure details", "Examples",
    "failure, diagnostics", "Default").} =
  check 2 + 2 == 5
