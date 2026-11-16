## ================================================================
## | continuity_types.nim  <-  what the continuity check answers   |
## |---------------------------------------------------------------|
## | One press, one answer. The readers (continuity_web.nim for     |
## | js + html, continuity_owl.nim for owlkettle) fill the same     |
## | record, so the text and the JSON are written once.             |
## ================================================================
##
## What is asked of every press
## ----------------------------
##
##   press  ──▶  does it hide something BIG?  ──no──▶  not asked again
##                       │yes
##                       ▼
##   is the pressed button INSIDE what is hidden?
##        │no                         │yes
##        ▼                           ▼
##     STAYS                 was the button on screen at the start,
##   (a tab bar, a frame:    and does something else take the room?
##    fine)                       │no                   │yes
##                                ▼                     ▼
##                      RETURN / CLOSE / SMALL        GOES  <- TELEPORT
##                      (Back, a close button,        (the button goes
##                       a small note: fine)           with the view)
##
## Big is a number, `bigSize`: elements (web) or widgets (owlkettle) in
## the thing that is hidden. Twelve is a column of a menu; a small note
## or a button strip stays under it.

import std/[strutils]

import runePragmas

const
  bigSize*: int = 12
    ## From this many elements (web) or widgets (owlkettle) a hidden
    ## thing is a view. Below it the user does not lose their place.
  maxFileBytes*: int = 1_000_000
    ## A file bigger than this is not read: the reader is for hand-written
    ## front ends, and a megabyte is a very large one.
  maxMatches*: int = 4000
    ## How many times one file may be asked the same question (arrows,
    ## listeners, hides). More than this is not a front end.
  maxSpan*: int = 20_000
    ## How far a bracket is followed to find its other half.
  maxTrails*: int = 200
    ## How many ways up through the builders are followed for one button.
  teleportCap*: int = 39
    ## A press that takes its own button along scores no more than this.
  weightKept*: float = 0.6
  weightAlike*: float = 0.4
  weightJoined*: float = 0.5
  weightNear*: float = 0.5
    ## Inside stay (kept, alike) and inside tie (joined, near); see UI.md 3,
    ## "Measuring continuity". The three metrics then count one third each.
  jumpBelow*: int = 50
    ## A press that is not a teleport but scores under this is a jump.
  floatingWords*: array[7, string] = [
    "modal", "dialog", "popover", "dropdown", "tooltip", "toast", "popup"
  ]
    ## A thing named like this floats over the page: hiding it gives
    ## the page back, it does not replace the page.

type
  ContinuityVerdict* {.role: other, tag: "stats".} = enum
    cvGoes,     ## the button is inside what its press hides: a teleport
    cvStays,    ## the button is outside what is hidden: the frame stays
    cvReturn,   ## the button was not on screen at the start: it is a way back
    cvClose,    ## nothing else takes the room: a close
    cvSmall     ## what goes is too small to lose the user's place

  ContinuityScore* {.role: preparedData, tag: "stats".} = object
    ## The three metrics and their bundle for one press, each 0 to 100.
    ## A metric nothing could be measured for is -1.
    stay*: int
    tie*: int
    move*: int
    overall*: int

  ContinuityPress* {.role: preparedData, tag: "stats".} = object
    ## One press that hides something big (or that was too small to).
    kind*: string
      ## "web" or "owl".
    path*: string
    line*: int
    control*: string
      ## The pressed button as the page or menu names it.
    action*: string
      ## What the press does, in words: `hides #overview`, `sets view = vReport`.
    hidden*: string
      ## What goes: an element, or a builder routine.
    hiddenAt*: string
      ## Where that is, as path:line.
    hiddenSize*: int
    replacedBy*: string
      ## What takes the room; empty when nothing does.
    verdict*: ContinuityVerdict
    scored*: bool
      ## True when the press has an old and a new thing to compare.
    score*: ContinuityScore

  ContinuityReport* {.role: truthState, tag: "stats".} = object
    presses*: seq[ContinuityPress]
    score*: ContinuityScore
      ## The mean over every scored press: the continuity of the whole UI.
    scoredPresses*: int
    webPresses*: int
      ## How many click handlers the web reader looked at.
    owlPresses*: int
      ## How many owlkettle click handlers that set a view it looked at.
    error*: string

proc verdictName*(v: ContinuityVerdict): string {.role: helper,
    tag: "stats".} =
  ## v: one verdict. The word the text and the JSON use for it.
  case v
  of cvGoes:
    result = "goes"
  of cvStays:
    result = "stays"
  of cvReturn:
    result = "returns"
  of cvClose:
    result = "closes"
  of cvSmall:
    result = "small"

proc isFloating*(name: string): bool {.role: parser, tag: "stats".} =
  ## name: an id, a class list or a builder's name.
  ## True when it names something that floats over the page.
  var
    low: string = name.toLowerAscii()
  result = false
  for w in floatingWords:
    if w in low:
      result = true

proc teleports*(r: ContinuityReport): seq[ContinuityPress] {.role: parser,
    tag: "stats".} =
  ## r: the whole answer. Only the presses whose button goes with its view.
  result = @[]
  for p in r.presses:
    if p.verdict == cvGoes:
      result.add(p)
