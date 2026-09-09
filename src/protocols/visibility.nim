## ================================================================
## | visibility.nim  <-  echoes put in for you, and taken back out |
## |---------------------------------------------------------------|
## | The oldest way of finding out where a program stalls is to put |
## | an echo at the top of a routine, another at the bottom, and    |
## | one more inside the loop. Then to take all three out again,    |
## | and put them back a week later.                                |
## |                                                                |
## |   proc parseFrame(b: seq[byte]): Frame {.visGroup: 3.} =       |
## |     ...                                                        |
## ================================================================
##
## What it prints
## --------------
##
##   nim c -d:otterVis:3 app.nim
##
##   [vis 3]      0.000 ms  -> parseFrame            src/net.nim:88
##   [vis 3]      0.031 ms    | loop 1 begins        src/net.nim:94
##   [vis 3]   4102.884 ms    | loop 1 ended after 65536 turn(s)
##   [vis 3]   4102.901 ms  <- parseFrame  (4102.9 ms)
##
## The time is milliseconds since the first of these messages, so the
## gaps between two lines are the thing to read. A routine that never
## prints its `<-` line is the routine that stalled, and a loop that
## prints `begins` and never `ended` is the loop it stalled in.
##
## Turning it on, one group at a time
## ----------------------------------
## Every routine names a group, and a group is a plain number, so a
## whole path through a program can be lit up at once without touching
## anything else:
##
##   -d:otterVis:3        group 3 only
##   -d:otterVis:1,3,7    three groups
##   -d:otterVis:all      every group that carries the pragma
##   (nothing)            nothing at all
##
## Nothing at all means exactly that. The macro looks at the switch
## while it is building the program: with the group off it hands the
## routine back untouched, so there is no message, no timer, no branch
## and no string in the binary. This is not a check that is skipped at
## run time - the code was never written.
##
## Seeing inside a long loop
## -------------------------
## By default a loop says when it begins and, afterwards, how many
## turns it took. If it never finishes, the second line never comes,
## which is how it tells you where the program is stuck. When how far
## it got matters more:
##
##   -d:otterVisEvery:1000
##
##   [vis 3]   1204.771 ms    | loop 1 turn 1000     src/net.nim:94
##   [vis 3]   2410.008 ms    | loop 1 turn 2000     src/net.nim:94
##
## Leave it off unless it is wanted: a message per turn of a hot loop
## is slower than the loop.
##
## What it does to the routine
## ---------------------------
## The `<-` line is put in with `defer`, so it prints on an early
## `return` and on the way out of an exception too. That is on purpose:
## a routine that threw is a routine somebody wants to see leave.
##
## A loop written inside a routine written inside the body - a closure
## or a nested proc - is left alone. It belongs to that routine, and
## that routine can carry its own pragma if it wants one.

import std/[macros, strutils]

import runePragmas

const
  otterVis* {.strdefine.}: string = ""
    ## Which groups to print. A comma-separated list of numbers, or
    ## `all`. Empty means print nothing, and is the default.

  otterVisEvery* {.intdefine.}: int = 0
    ## Say something every this many turns of a loop. 0 means only
    ## when a loop begins and when it ends.

  visPrefix*: string = "[vis "
    ## The start of every line, so a reader can filter the output of a
    ## program with `grep`.

const
  visAnyOn* = otterVis.strip().len > 0
    ## Whether any group at all was asked for.
    ##
    ## The whole runtime below sits behind this. With no group asked
    ## for, a program that imports this module gets the macro and
    ## three constants and nothing else - no globals, no clock, no
    ## strings - so importing it costs the same as not importing it.
    ## Without this the pragma was free but the import was not, and
    ## "free" has to mean free.

when visAnyOn:
  import std/[monotimes, times]
  # The generated code calls `getMonoTime`, so whoever writes the
  # pragma gets it without having to know that.
  export monotimes

  var
    visBegan: MonoTime = getMonoTime()
      ## When the first message was printed. Every time shown is counted
      ## from here, because what matters is the gaps.
    visDepth: int = 0
      ## How many instrumented routines are running, one inside another.
      ## Printed as indentation, so the shape of the calls can be read
      ## down the left-hand edge.

  proc visStamp(): string {.role: helper, tag: "logging".} =
    ## Milliseconds since the first message, to three places, right
    ## aligned so the column stays straight as the numbers grow.
    var
      ns: int64 = inNanoseconds(getMonoTime() - visBegan)
      ms: float = float(ns) / 1_000_000.0
    result = formatFloat(ms, ffDecimal, 3) & " ms"
    while result.len < 14:
      result = " " & result

  proc visEnter*(g: int, name, where: string) {.role: dataWriter, tag: "logging".} =
    ## g: the group   name: the routine   where: file and line.
    ## Says a routine has started, and counts one deeper.
    echo visPrefix, g, "] ", visStamp(), "  ", repeat("  ", visDepth),
      "-> ", name, "   ", where
    visDepth = visDepth + 1

  proc visLeave*(g: int, name: string, began: MonoTime) {.role: dataWriter, tag: "logging".} =
    ## g: the group   name: the routine   began: when it started.
    ## Says a routine has finished, and how long it took.
    var
      ms: float = float(inNanoseconds(getMonoTime() - began)) / 1_000_000.0
    if visDepth > 0:
      visDepth = visDepth - 1
    echo visPrefix, g, "] ", visStamp(), "  ", repeat("  ", visDepth),
      "<- ", name, "  (", formatFloat(ms, ffDecimal, 3), " ms)"

  proc visLoop*(g: int, what, where: string) {.role: dataWriter, tag: "logging".} =
    ## g: the group   what: what happened   where: file and line.
    ## Says something about a loop, indented under the routine it is in.
    echo visPrefix, g, "] ", visStamp(), "  ", repeat("  ", visDepth),
      "| ", what, "   ", where


proc visGroupOn*(g: int): bool {.compileTime.} =
  ## g: a group number.
  ##
  ## Whether this group was asked for. Answered while the program is
  ## being built, which is what makes an unasked-for group cost
  ## nothing: the macro below simply writes no code.
  var
    t: string = otterVis.strip()
  result = false
  if t.len == 0:
    return
  if t == "all":
    return true
  for piece in t.split(','):
    try:
      if parseInt(piece.strip()) == g:
        return true
    except ValueError:
      discard

proc whereOf(n: NimNode): string {.compileTime.} =
  ## n: any part of a routine. The file and line it was written on,
  ## short enough to sit at the end of a message.
  var
    info: LineInfo = n.lineInfoObj
    at: int = max(info.filename.rfind('/'), info.filename.rfind('\\'))
  result = info.filename
  if at >= 0:
    result = result[at + 1 .. ^1]
  result = result & ":" & $info.line

proc nameOf(def: NimNode): string {.compileTime.} =
  ## def: a routine as the compiler sees it. Its name as written.
  result = "a routine"
  if def.len > 0 and def[0].kind == nnkPostfix and def[0].len > 1:
    result = def[0][1].strVal
  elif def.len > 0 and def[0].kind in {nnkIdent, nnkSym}:
    result = def[0].strVal

proc loopSay(g, k, nest: int, what, where: string): NimNode
    {.compileTime.} =
  ## g: the group   k: which loop of this routine   nest: how many
  ## loops it sits inside   what: the words   where: file and line.
  ##
  ## One call to `visLoop`. The indentation for the loop's own depth is
  ## baked in here rather than counted at run time: it is known while
  ## the program is being built and never changes.
  result = newCall(ident("visLoop"), newLit(g),
    newLit(repeat("  ", nest) & "loop " & $k & " " & what), newLit(where))

proc everyTurn(g, k, nest: int, counter: NimNode, where: string): NimNode
    {.compileTime.} =
  ## g: the group   k: which loop   counter: the turn count
  ## where: file and line.
  ##
  ## Says something every `otterVisEvery` turns, and nothing at all
  ## when that was left at zero - in which case this whole branch is
  ## never written into the program.
  result = newStmtList()
  if otterVisEvery <= 0:
    return
  result = newIfStmt((
    infix(infix(counter, "mod", newLit(otterVisEvery)), "==", newLit(0)),
    newStmtList(newCall(ident("visLoop"), newLit(g),
      infix(newLit(repeat("  ", nest) & "loop " & $k & " turn "), "&",
        newCall(ident("$"), counter)), newLit(where)))))

proc instrumentLoops(n: NimNode, g: int, k: var int, nest: int): NimNode
    {.compileTime.} =
  ## n: part of a routine's body   g: the group
  ## k: how many loops have been numbered so far, carried along.
  ##
  ## Every `for` and `while` gets a line before it, a turn count, and
  ## a line after it. A routine written inside the body is handed back
  ## whole: its loops are its own, and it may carry its own pragma.
  var
    counter: NimNode = nil
    inner: NimNode = nil
    where: string = ""
    mine: int = 0
  if n.kind in {nnkProcDef, nnkFuncDef, nnkMethodDef, nnkIteratorDef,
      nnkConverterDef, nnkTemplateDef, nnkMacroDef, nnkLambda, nnkDo}:
    return n
  if n.kind notin {nnkForStmt, nnkWhileStmt}:
    result = copyNimNode(n)
    for child in n:
      result.add(instrumentLoops(child, g, k, nest))
    return
  # The number is taken now, before walking into the body. A loop
  # inside this one raises the count too, and reading it afterwards
  # gave both loops the inner one's number.
  k = k + 1
  mine = k
  where = whereOf(n)
  counter = ident("otterTurns" & $mine)
  result = copyNimNode(n)
  for i in 0 ..< n.len - 1:
    result.add(instrumentLoops(n[i], g, k, nest))
  inner = newStmtList(
    newNimNode(nnkAsgn).add(counter, infix(counter, "+", newLit(1))),
    everyTurn(g, mine, nest, counter, where))
  for child in instrumentLoops(n[^1], g, k, nest + 1):
    inner.add(child)
  result.add(inner)
  result = newStmtList(
    newNimNode(nnkVarSection).add(newIdentDefs(counter, ident("int"),
      newLit(0))),
    loopSay(g, mine, nest, "begins", where),
    result,
    newCall(ident("visLoop"), newLit(g),
      infix(infix(newLit(repeat("  ", nest) & "loop " & $mine &
        " ended after "), "&", newCall(ident("$"), counter)), "&",
        newLit(" turn(s)")),
      newLit(where)))

macro visGroup*(g: untyped, def: untyped): untyped =
  ## g: which group this routine belongs to   def: the routine.
  ##
  ## With the group switched off, the routine is handed back exactly
  ## as it was written. Nothing is emitted - not a branch, not a
  ## string, not a timer - because the decision is made here, while
  ## the program is being built, rather than in the program.
  ##
  ##   proc parseFrame(b: seq[byte]): Frame {.visGroup: 3.} =
  ##
  ## With it on, the routine says when it starts and when it stops,
  ## every loop in it says when it begins and how many turns it took,
  ## and the whole trace is timed from the first message.
  var
    group: int = 0
    name: string = ""
    began: NimNode = ident("otterBegan")
    counted: int = 0
  expectKind(g, nnkIntLit)
  group = int(g.intVal)
  if not visGroupOn(group):
    return def
  name = nameOf(def)
  result = def
  result.body = newStmtList(
    newCall(ident("visEnter"), newLit(group), newLit(name),
      newLit(whereOf(def))),
    newNimNode(nnkVarSection).add(newIdentDefs(began, newEmptyNode(),
      newCall(ident("getMonoTime")))),
    newNimNode(nnkDefer).add(newStmtList(newCall(ident("visLeave"),
      newLit(group), newLit(name), began))),
    instrumentLoops(def.body, group, counted, 0))
