## A tree shaped to show what a blast radius answers. `store` is the
## routine somebody is about to edit; everything here exists to be
## found from it.
##
##   handle -> clean -> store        clean declares `sanitizer`, so
##   report -> store                 store must not clean again
##
## and at the call sites, `store` is handed the result of `trim(pad(s))`
## and the literals 1, 2 and 7, which is what its `int` parameter really
## holds.

import std/strutils

proc pad*(s: string): string {.role: helper.} =
  result = s & " "

proc trim*(s: string): string {.role: helper.} =
  result = s.strip()

proc clean*(s: string): string {.role: sanitizer.} =
  ## Removes what must never reach storage.
  result = s.replace("\0", "")

proc store*(s: string, slot: int): bool {.role: dataWriter.} =
  ## s: text already cleaned   slot: which shelf, 1..7
  result = s.len > 0 and slot > 0

proc handle*(raw: string): bool {.role: orchestrator.} =
  result = store(clean(trim(pad(raw))), 1)

proc report*(raw: string): bool {.role: orchestrator.} =
  result = store(trim(raw), 7)

proc retry*(raw: string): bool {.role: orchestrator.} =
  result = store(raw, 2)

proc runAll*(raw: string): bool {.role: metaOrchestrator.} =
  result = handle(raw) and report(raw) and retry(raw)
