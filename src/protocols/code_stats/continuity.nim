## ================================================================
## | continuity.nim  <-  the user must never be teleported          |
## |---------------------------------------------------------------|
## | UI.md, "Continuity: nothing teleports": when a press changes   |
## | the view, the pressed thing stays on screen and the rest makes |
## | room. This finds the presses that break that on the cheapest   |
## | sign there is: the press hides a big thing that CONTAINS its   |
## | own button.                                                    |
## |                                                                |
## |   otter-repo-graph continuity .                                |
## |   otter-repo-graph continuity . --json                         |
## ================================================================
##
## Two readers, one answer
## -----------------------
##
##   html + css + js  ──▶ continuity_web.nim ──┐
##                                            ├──▶ ContinuityReport ──▶ text, json
##   owlkettle (Nim)  ──▶ continuity_owl.nim ──┘      (continuity_types.nim)
##
## What it cannot see is whether the pressed thing SLIDES to its new
## place or jumps there. It sees only the end: is the button still in
## the picture after the press? A finding is the strongest sign of a
## teleport; no finding is not a promise of a smooth one.

import std/[algorithm]

import runePragmas
import ./continuity_types
import ./continuity_web
import ./continuity_owl

proc byPlace(a, b: ContinuityPress): int {.role: helper, tag: "stats".} =
  ## a, b: two presses, in the order a reader walks the files.
  result = cmp(a.path, b.path)
  if result == 0:
    result = cmp(a.line, b.line)

proc continuityOf*(dir: string, files: seq[string]): ContinuityReport
    {.role: metaOrchestrator, input: thirdParty, tag: "stats".} =
  ## dir: the repository   files: every source file in it.
  ## Every press of the front end that hides something big, and where its
  ## button stands to what it hides.
  var
    web: tuple[presses: seq[ContinuityPress], handlers: int] = (presses: @[],
      handlers: 0)
    owl: tuple[presses: seq[ContinuityPress], handlers: int] = (presses: @[],
      handlers: 0)
  web = webPressesOf(dir, files)
  owl = owlPressesOf(dir, files)
  result = ContinuityReport(presses: web.presses & owl.presses,
    webPresses: web.handlers, owlPresses: owl.handlers, error: "")
  result.presses.sort(byPlace)

proc unitOf(p: ContinuityPress): string {.role: helper, tag: "stats".} =
  ## p: one press. What its size is counted in.
  result = (if p.kind == "owl": "widgets" else: "elements")

proc countOf(r: ContinuityReport, v: ContinuityVerdict): int {.role: parser,
    tag: "stats".} =
  ## r: the answer   v: one verdict. How many presses have it.
  result = 0
  for p in r.presses:
    if p.verdict == v:
      result = result + 1

proc continuityLines*(r: ContinuityReport): seq[string] {.role: dataWriter,
    tag: "stats".} =
  ## r: one answer, as a person reads it. The teleports first, each with the
  ## place of the press, what goes, and what takes the room; then the counts.
  var
    bad: seq[ContinuityPress] = r.teleports()
  result = @[]
  if r.error.len > 0:
    result.add("continuity: " & r.error)
    return
  result.add("continuity: " & $r.presses.len & " press(es) hide something " &
    "big, " & $bad.len & " of them take their own button along")
  result.add("  looked at: " & $r.webPresses & " click handler(s) in html/js, " &
    $r.owlPresses & " owlkettle click handler(s) that set a view")
  for p in bad:
    result.add("  TELEPORT  " & p.path & ":" & $p.line & "  " & p.control &
      "  " & p.action)
    result.add("      what goes: " & p.hidden & " (" & $p.hiddenSize & " " &
      unitOf(p) & ", " & p.hiddenAt & "); the button stands inside it")
    result.add("      takes the room: " & p.replacedBy)
  result.add("  the rest: " & $r.countOf(cvStays) & " stay (the frame is " &
    "outside what is hidden), " & $r.countOf(cvReturn) & " return, " &
    $r.countOf(cvClose) & " close, " & $r.countOf(cvSmall) & " small")
  if bad.len > 0:
    result.add("  Keep the pressed thing on screen and make room around it " &
      "(UI.md 3, \"Continuity\").")
