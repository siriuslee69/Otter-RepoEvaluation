## ================================================================
## | config.nim  <-  five ways of ending, stacked on each other    |
## |---------------------------------------------------------------|
## | Each routine here ends differently, and every difference is    |
## | one the yield-paths module has to notice:                      |
## |                                                                |
## |   readRaw    an IOError comes out of the standard library      |
## |   parseWidth a ValueError does                                 |
## |   loadWidth  inherits both, and adds one of its own            |
## |   pickWidth  catches one of the three, and lets two through    |
## |   safeWidth  catches everything: nothing escapes it            |
## |   loadAll    hands failure back as a value, not as a throw     |
## |   demand     stops the program rather than raising             |
## ================================================================

import std/[strutils]

type
  Loaded* = object
    ## A carrier: failure arrives in a field rather than as a throw.
    width*: int
    error*: string

proc readRaw*(p: string): string =
  ## p: a file path. Whatever is in the file.
  result = readFile(p)

proc parseWidth*(s: string): int =
  ## s: the text of a number.
  result = parseInt(s)

proc loadWidth*(p: string): int =
  ## p: a file path. The width written in it.
  ## Adds a raise of its own on top of the two it inherits.
  result = parseWidth(readRaw(p).strip())
  if result <= 0:
    raise newException(RangeDefect, "width must be positive")

proc pickWidth*(p: string): int =
  ## p: a file path. Catches one of the three ways loadWidth can end,
  ## and lets the other two through.
  result = 80
  try:
    result = loadWidth(p)
  except ValueError:
    result = 80

proc safeWidth*(p: string): int =
  ## p: a file path. Catches everything, so nothing escapes it.
  result = 80
  try:
    result = loadWidth(p)
  except CatchableError:
    result = 80

proc loadAll*(p: string): Loaded =
  ## p: a file path. Failure comes back in the `error` field, so a
  ## caller that never looks at it will not be told anything went
  ## wrong.
  result = Loaded(width: 0, error: "")
  try:
    result.width = loadWidth(p)
  except CatchableError:
    result.error = "could not read " & p

proc demand*(p: string): int =
  ## p: a file path. Stops the program rather than raising, so no
  ## caller can catch this one.
  result = loadWidth(p)
  doAssert result > 0, "width must be positive"
