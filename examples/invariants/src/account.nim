## ================================================================
## | account.nim  <-  promises written where they can be checked   |
## |---------------------------------------------------------------|
## | Every routine here says something a signature cannot say, and  |
## | each one shows a different way of saying it:                   |
## |                                                                |
## |   withdraw   a promise on the way in, and one on the way out   |
## |   classify   a promise that survives an early `return`         |
## |   isSorted   a promise about every item at once                |
## |   push       a promise about the value something used to have  |
## |   trim       a promise checked at both ends, not just one     |
## |   drain      a promise the running program carries too         |
## ================================================================

import ../../../src/protocols/invariants

proc withdraw*(balance, amount: int): int {.needs: amount <= balance,
    gives: result >= 0.} =
  ## balance: what is there   amount: what is being taken.
  ## Checked while the compiler runs this, and free in the program.
  balance - amount

proc classify*(a: int): string {.gives: result.len > 0.} =
  ## a: any number. A word for it, never an empty one.
  ## The early `return` does not step over the promise.
  if a > 0:
    return "high"
  result = "low"

proc isSorted*(A: seq[int]): bool {.gives: result == forall(i in 1 ..< A.len,
    A[i - 1] <= A[i]).} =
  ## A: a list of numbers. Whether each one is at least the one before.
  ## The promise says the same thing the body does, in one line, so
  ## the two have to agree.
  result = true
  for i in 1 ..< A.len:
    if A[i - 1] > A[i]:
      result = false

proc trim*(S: var seq[int]) {.keeps: S.len < 1000.} =
  ## S: the list. Drops its last item if it has one.
  ##
  ## `keeps` is `needs` and `gives` in one word, and the difference is
  ## worth being clear about:
  ##
  ##   needs   checked on the way in only.  "I refuse bad input."
  ##   gives   checked on the way out only. "I promise good output."
  ##   keeps   checked at both ends.        "I do not break this."
  ##
  ## The same sentence at both ends is what makes it an invariant: it
  ## was true when we arrived, and this routine has not broken it.
  if S.len > 0:
    S.setLen(S.len - 1)

proc push*(S: var seq[int], v: int) {.givesRun: S.len == old(S).len + 1.} =
  ## S: the list   v: what to put on it.
  ## `old(S)` is the list as it arrived, so the promise can compare
  ## the two.
  S.add(v)

proc drain*(S: var seq[int]): int {.needsRun: S.len > 0,
    keepsRun: S.len >= 0.} =
  ## S: the list. The last item, taken off.
  ## The running program carries both checks, so an empty list raises
  ## instead of reading past the end.
  result = S[^1]
  S.setLen(S.len - 1)

when isMainModule:
  ## The build stops on `withdraw(40, 100)` if that line is unquoted:
  ## the promise is checked wherever the compiler runs the routine.
  static:
    doAssert withdraw(100, 40) == 60
    doAssert classify(-1) == "low"
    doAssert isSorted(@[1, 2, 3])
  var S: seq[int] = @[]
  push(S, 7)
  push(S, 8)
  trim(S)
  echo drain(S)
