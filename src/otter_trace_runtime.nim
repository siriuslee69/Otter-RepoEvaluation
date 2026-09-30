## otter_trace_runtime.nim <- what a module wrapped by `otter trace` imports
##
## A unique name on purpose: a traced project may have its own
## protocols/tracing.nim, and this must never be confused with it.
## The call counts are printed when the traced program ends.

import std/exitprocs
import protocols/tracing
export tracing

when OtterTraceEnabled:
  addExitProc(otterTraceSummary)
