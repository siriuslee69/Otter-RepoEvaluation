## ================================================================
## | pipeline.nim  <-  three routines that can be made to talk     |
## |---------------------------------------------------------------|
## | Run it silently:                                               |
## |                                                                |
## |   nim c -r src/pipeline.nim                                    |
## |                                                                |
## | Run it with the reading group talking:                         |
## |                                                                |
## |   nim c -d:otterVis:1 -r src/pipeline.nim                      |
## |                                                                |
## | Run it with both groups, and a word every 1000 turns:          |
## |                                                                |
## |   nim c -d:otterVis:1,2 -d:otterVisEvery:1000 -r src/pipeline.nim |
## ================================================================

import ../../../src/protocols/visibility

proc readRows*(n: int): seq[int] {.visGroup: 1.} =
  ## n: how many rows to make up.
  ## Group 1 is the reading half of the program.
  result = @[]
  for i in 0 ..< n:
    result.add(i)


proc addUp*(A: seq[int]): int {.visGroup: 2.} =
  ## A: the rows. Group 2 is the working half.
  ##
  ## Two loops, one inside the other, so the trace shows the inner one
  ## indented under the outer one and numbered after it.
  result = 0
  for a in A:
    for k in 0 .. 1:
      result = result + a * k

proc run*(n: int): int {.visGroup: 2.} =
  ## n: how many rows. What they add up to.
  ## An early `return` on purpose: the `<-` line still prints, because
  ## it is put in with `defer`.
  if n <= 0:
    return 0
  result = addUp(readRows(n))

when isMainModule:
  echo "total ", run(2000)
