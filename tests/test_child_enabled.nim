# ============================================================
# | Otter Timed Child                                       |
# | -> Child process used to verify exit-log flushing       |
# ============================================================

import ../.iron/metaPragmas
import otter_repo_evaluation

proc childLeaf*(a: int): int {.otterTimed, role: helper, metaTags: {tagTesting}.} =
  ## a: input value.
  var
    t: int = 0
  t = a + 2
  result = t


proc childBranch*(a: int): int {.otterBench, role: helper, metaTags: {tagTesting}.} =
  ## a: input value.
  var
    t: int = 0
  t = childLeaf(a)
  result = t * 2


when isMainModule:
  clearTimings()
  setLogPath("tests/build/otter_enabled.log")
  discard childBranch(3)
