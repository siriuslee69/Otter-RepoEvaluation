## ============================================================
## | Otter Code Statistics Root                               |
## | -> Public exports for measuring one repository           |
## ============================================================
##
##   import otter_repo_evaluation
##   var s: ProjectStats = analyzeProject(".")
##   for line in summaryLines(s):
##     echo line

import ./code_stats/types
import ./code_stats/embedded
import ./code_stats/families
import ./code_stats/layout
import ./code_stats/blast
import ./code_stats/state_writes
import ./code_stats/yields
import ./code_stats/diff_review
import ./code_stats/checks
import ./code_stats/conventions
import ./code_stats/ui_depth
import ./code_stats/nesting
import ./code_stats/test_scan
import ./code_stats/pipeline
import ./code_stats/inventory
import ./code_stats/input_scan
import ./code_stats/imports
import ./code_stats/source_metrics
import ./code_stats/project
import ./code_stats/json_out

export types
export embedded
export families
export layout
export blast
export state_writes
export yields
export diff_review
export checks
export conventions
export ui_depth
export nesting
export test_scan
export pipeline
export inventory
export input_scan
export imports
export source_metrics
export project
export json_out
