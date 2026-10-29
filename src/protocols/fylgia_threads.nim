## ============================================================
## | Otter -> Fylgia auto threader                            |
## | -> the one place that knows where Fylgia is sitting      |
## ============================================================
##
## Every Otter module that spreads work over the cores imports this
## file and nothing else, so the "which copy of Fylgia" question is
## answered once:
##
##   submodules/Fylgia-Utils   the pinned copy, when Otter builds alone
##   ../Fylgia-Utils           a sibling clone, used while several of
##                             the repositories are worked on together
##
## config.nims sets `otterFylgiaSubmodule` only when the pinned copy is
## there AND carries the threader.
##
##   parallelMap(A, f)        f on every item at once, answers in order
##   parallelRange(n, c, f)   f(c, i) for every i at once
##   together:                every line of the block at once
##
## OTTER_THREADS=n caps how many threads Otter uses (FYLGIA_THREADS
## does the same, and wins when both are set).

import std/[os, strutils]
import runePragmas

when defined(otterFylgiaSubmodule):
  import "../../submodules/Fylgia-Utils/src/protocols/threads/auto_thread"
else:
  import "../../../Fylgia-Utils/src/protocols/threads/auto_thread"

export auto_thread

proc otterThreadsFromEnv*() {.role: configurator, tag: "threads".} =
  ## Reads OTTER_THREADS once, at start-up, into the shared budget.
  ## Without it the budget is one thread per processor core.
  if existsEnv("OTTER_THREADS") and not existsEnv("FYLGIA_THREADS"):
    setThreadLimit(parseInt(getEnv("OTTER_THREADS").strip()))
