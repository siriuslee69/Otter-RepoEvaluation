# ============================================================
# | Otter Code Statistics Root                               |
# | -> Public exports for measuring one repository           |
# ============================================================
#
#   import otter_repo_evaluation
#   var s: ProjectStats = analyzeProject(".")
#   for line in summaryLines(s):
#     echo line

import ./code_stats/types
import ./code_stats/nesting
import ./code_stats/test_scan
import ./code_stats/pipeline
import ./code_stats/project
import ./code_stats/json_out

export types
export nesting
export test_scan
export pipeline
export project
export json_out
