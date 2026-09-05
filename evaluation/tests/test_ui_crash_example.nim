# ============================================================
# | Otter Test UI Crash Example                              |
# | -> Process exit used to verify backend crash isolation   |
# ============================================================

import otter_repo_evaluation

proc intentionalProcessExit*() {.otterUiTest: ("Process exit", "Examples",
    "failure, crash", "Default").} =
  echo "intentional test process exit"
  quit(23)
