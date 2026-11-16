## ================================================================
## | continuity_score.nim  <-  the number behind "no teleport"      |
## |---------------------------------------------------------------|
## | UI.md 3, "Measuring continuity". Three metrics for one press,  |
## | each 0 to 100, bundled into one:                               |
## |                                                                |
## |   press ──▶ old thing goes, new thing comes                    |
## |                                                                |
## |   STAY  how little goes, how alike old and new are             |
## |   TIE   the pressed thing and the new one share a colour       |
## |         and stand close                                        |
## |   MOVE  a transition that is there and fast                    |
## |                                                                |
## |   continuity = the mean of what could be measured              |
## ================================================================
##
## The readers (continuity_web.nim, continuity_owl.nim) count the inputs
## from source; this module only turns inputs into numbers, so the
## formulas live in one place and the tests can say them in a line.
##
## Every input is a float where a negative value means "not measured". A
## part that was not measured is left out of its metric rather than
## counted as nothing: a UI with no style sheet is not a UI with no
## colour, it is a UI nobody measured.
##
##   input    0 means                      1 means                       range
##   -------  ---------------------------  ----------------------------  -----
##   kept     the old thing was the whole  the old thing was a speck     0..1
##            screen
##   alike    nothing in common            the same                      0..1
##   joined   different colours (or none)  one colour in common          0, 1
##   near     ten or more boxes between    next to each other (at most   0..1
##                                         two boxes between)
##   seconds  no transition                0.04 to 0.3 s                 >= 0

import std/[math, sets, tables]

import runePragmas
import ./continuity_types

const
  notMeasured*: float = -1.0

type
  ScoreParts* {.role: preparedData, tag: "stats".} = object
    ## What a reader counted for one press. Negative: not measured.
    kept*: float
    alike*: float
    joined*: float
    near*: float
    seconds*: float
    teleport*: bool
      ## The button went with the view: no tie, and the score is capped.

proc noParts*(): ScoreParts {.role: helper, tag: "stats".} =
  ## A press nothing has been measured for yet.
  result = ScoreParts(kept: notMeasured, alike: notMeasured,
    joined: notMeasured, near: notMeasured, seconds: notMeasured,
    teleport: false)

proc keptOf*(old, screen: int): float {.role: math, tag: "stats".} =
  ## old: the size of the thing that goes   screen: the size of the whole screen.
  ## 1 minus the share the old thing took; not measured when the screen is empty.
  result = notMeasured
  if screen > 0:
    result = clamp(1.0 - old.float / screen.float, 0.0, 1.0)

proc likeness*(a, b: CountTable[string]): float {.role: math, tag: "stats".} =
  ## a, b: what two things hold, counted by kind (tags, classes, colours).
  ## What they have in common over everything they hold between them:
  ## the sum of the smaller counts over the sum of the larger ones. Two
  ## empty things are not measured.
  var
    low: int = 0
    high: int = 0
    keys: HashSet[string] = initHashSet[string]()
  result = notMeasured
  for k in a.keys:
    keys.incl(k)
  for k in b.keys:
    keys.incl(k)
  for k in keys:
    low = low + min(a.getOrDefault(k), b.getOrDefault(k))
    high = high + max(a.getOrDefault(k), b.getOrDefault(k))
  if high > 0:
    result = low.float / high.float

proc joinedOf*(a, b: HashSet[string], known: bool): float {.role: math,
    tag: "stats".} =
  ## a, b: the colours of the pressed thing and of the new one
  ## known: whether any style sheet was read.
  ## 1 when they share a colour, 0 when they do not, not measured when there
  ## was nothing to read the colours from.
  result = notMeasured
  if known:
    result = (if card(a * b) > 0: 1.0 else: 0.0)

proc nearOf*(hops: int): float {.role: math, tag: "stats".} =
  ## hops: the boxes on the way from the pressed thing up to what holds both
  ## and down to the new thing (2 for neighbours). Negative: not measured.
  ## 1 up to two boxes, then 1/8 less for each box, 0 from ten.
  result = notMeasured
  if hops >= 0:
    result = clamp(1.0 - (hops - 2).float / 8.0, 0.0, 1.0)

proc moveOf*(seconds: float): float {.role: math, tag: "stats".} =
  ## seconds: the longest transition on the old, the new or the pressed thing.
  ## Negative: not measured. 0: a cut. A ramp up to 0.04 s, 1 up to 0.3 s,
  ## falling to 0.3 at 0.6 s, and 0.1 beyond (UI.md 5, "Motion").
  result = notMeasured
  if seconds < 0.0:
    return
  if seconds < 0.04:
    result = seconds / 0.04
  elif seconds <= 0.3:
    result = 1.0
  elif seconds <= 0.6:
    result = 1.0 - 0.7 * (seconds - 0.3) / 0.3
  else:
    result = 0.1

proc weighted(a, b, wa, wb: float): float {.role: math, tag: "stats".} =
  ## a, b: two parts (negative: not measured)   wa, wb: their weights.
  ## The weighted mean of the parts that were measured.
  var
    sum: float = 0.0
    total: float = 0.0
  if a >= 0.0:
    sum = sum + a * wa
    total = total + wa
  if b >= 0.0:
    sum = sum + b * wb
    total = total + wb
  result = (if total > 0.0: sum / total else: notMeasured)

proc hundred(x: float): int {.role: math, tag: "stats".} =
  ## x: a part from 0 to 1, or negative. It on a scale of 100; -1 when not measured.
  result = (if x < 0.0: -1 else: int(round(x * 100.0)))

proc scoreOf*(p: ScoreParts): ContinuityScore {.role: math, tag: "stats".} =
  ## p: what was counted for one press.
  ## stay = kept and alike; tie = joined and near; move = the transition. The
  ## overall is the mean of the metrics that exist. A press that took its own
  ## button along has no tie and is capped at `teleportCap`.
  var
    stay: float = weighted(p.kept, p.alike, weightKept, weightAlike)
    tie: float = (if p.teleport: 0.0
      else: weighted(p.joined, p.near, weightJoined, weightNear))
    move: float = moveOf(p.seconds)
    sum: int = 0
    n: int = 0
  result = ContinuityScore(stay: hundred(stay), tie: hundred(tie),
    move: hundred(move), overall: -1)
  for m in [result.stay, result.tie, result.move]:
    if m >= 0:
      sum = sum + m
      n = n + 1
  if n > 0:
    result.overall = int(round(sum.float / n.float))
  if p.teleport and result.overall > teleportCap:
    result.overall = teleportCap

proc tally(sum, n: var array[4, int], s: ContinuityScore) {.role: actor,
    tag: "stats".} =
  ## sum, n: running totals and counts of stay, tie, move, overall   s: one score.
  ## Adds each of its metrics that was measured.
  var
    v: array[4, int] = [s.stay, s.tie, s.move, s.overall]
  for k in 0 .. 3:
    if v[k] >= 0:
      sum[k] = sum[k] + v[k]
      n[k] = n[k] + 1

proc meanScore*(S: seq[ContinuityScore]): ContinuityScore {.role: math,
    tag: "stats".} =
  ## S: the scores of many presses.
  ## The mean of each metric over the presses it was measured for; -1 where
  ## none was.
  var
    sum: array[4, int] = [0, 0, 0, 0]
    n: array[4, int] = [0, 0, 0, 0]
  result = ContinuityScore(stay: -1, tie: -1, move: -1, overall: -1)
  for s in S:
    tally(sum, n, s)
  if n[0] > 0:
    result.stay = int(round(sum[0].float / n[0].float))
  if n[1] > 0:
    result.tie = int(round(sum[1].float / n[1].float))
  if n[2] > 0:
    result.move = int(round(sum[2].float / n[2].float))
  if n[3] > 0:
    result.overall = int(round(sum[3].float / n[3].float))
