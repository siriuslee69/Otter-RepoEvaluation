## ================================================================
## | invariants.nim  <-  what a routine promises, written down     |
## |---------------------------------------------------------------|
## | A signature says what goes in and what comes out. It cannot    |
## | say `amount must not be more than balance`, so that sentence   |
## | ends up in a comment, where nothing checks it and it slowly    |
## | stops being true.                                              |
## |                                                                |
## |   proc withdraw(balance, amount: int): int {.                  |
## |     needs: amount <= balance,                               |
## |     gives: result >= 0                                       |
## |   .} =                                                         |
## |     balance - amount                                           |
## ================================================================
##
## The names, and why they are not the obvious ones
## ------------------------------------------------
## The obvious names are taken. `requires` and `ensures` are pragmas
## the Nim compiler already knows: they belong to DrNim, a separate
## build of the compiler that proves them with a solver. The ordinary
## compiler reads them, checks that what is written makes sense, and
## then does nothing with it.
##
## That is the worst possible middle ground for a promise. It looks
## checked. It compiles. Nothing is enforced, and nobody is told. So
## these are called something else, and a promise written with one of
## these names is a promise that is actually kept:
##
##   requires/ensures   the compiler's own. Read, then ignored.
##   needs/gives/keeps  this file's. Checked.
##
## Two tiers, and the difference is where the check happens
## -------------------------------------------------------
##
##   needs / gives / keeps          checked while building
##   needsRun / givesRun / keepsRun checked while building
##                                           AND while running
##
## The first three cost **nothing**. Not "almost nothing" - the check
## sits inside `when nimvm:`, a branch the compiler keeps for its own
## interpreter and never writes into the program. A repository that
## imports this and uses those three has a binary of exactly the size
## it had before. There is a test that compiles two programs and
## compares their sizes, because a promise like that is worth pinning
## down.
##
## So when does a build-time check actually run?
## --------------------------------------------
## Whenever the compiler itself runs the routine. That happens in a
## `const`, inside a `static:` block, and inside any macro:
##
##     static:
##       discard withdraw(100, 40)     <- checked, and passes
##       discard withdraw(40, 100)     <- the build stops here
##
## This is worth being plain about: a routine only called at run time
## is never checked by the first three. That is what the `Run` three
## are for. The two are meant to be used together - name the promise
## once with `needsRun`, get it checked in tests that run at build
## time and again in the program.
##
## Turning the running checks off
## ------------------------------
##
##   normal build         checks are on
##   -d:danger            off
##   -d:noOtterContracts  off
##   -d:otterContracts    on, whatever else was said
##
## Saying it about many values at once
## -----------------------------------
##
##     gives: forall(i in 1 ..< A.len, A[i - 1] <= A[i])
##     needs: exists(c in s, c == '=')
##
## `forall` is true when the second part holds for every one; `exists`
## when it holds for at least one. Both are ordinary expressions, so
## they work in either tier and can be joined with `and` and `or`.
##
## Talking about the value something had on the way in
## --------------------------------------------------
##
##     proc take(S: var Stack, n: int) {.
##       givesRun: S.len == old(S).len - n
##     .} = ...
##
## `old(x)` is the value `x` held when the routine started. It costs
## one copy, so it is only kept for the `Run` tier, where a copy was
## already being paid for.
##
## What `gives` had to do to your body, and the one case to watch
## ----------------------------------------------------------------
## A `gives` check has to happen after everything, including after
## an early `return`. So the body is wrapped in a block and every
## `return` in it is rewritten:
##
##     return x        becomes    result = x
##                                break otterContractBody
##
## A `return` inside a closure written inside the body is left alone,
## because that one returns from the closure. The rewrite does not
## reach into a nested routine of any kind.
##
## The body's last line is looked at once: if it is an expression the
## routine could return, it becomes `result = <it>`. The compiler
## decides that, not this file, through `when compiles(result = ...)`.
## The one case to watch is a last line that calls something marked
## `{.discardable.}` whose type happens to match: that value now
## becomes the result, where before it was thrown away.

import std/[macros]

type
  ContractDefect* = object of Defect
    ## A promise that was written down and then broken. A defect
    ## rather than an error on purpose: this is a bug in the program,
    ## not a condition the program is meant to handle.

const
  otterContractsOn* = (not defined(danger) and
    not defined(noOtterContracts)) or defined(otterContracts)
    ## Whether the `Run` tier writes its checks into the program.

  bodyLabel* = "otterContractBody"
    ## The name of the block a `gives` wraps a body in. Written
    ## down here so that a person reading a stack trace, or a
    ## surprising `break`, can find out where it came from.

proc contractFailed*(msg: string) {.noinline, noreturn.} =
  ## msg: what was promised, and by whom.
  ## Raised when a promise is broken. While the compiler is running
  ## the routine this stops the build and prints the message; while
  ## the program is running it raises.
  raise newException(ContractDefect, msg)

proc routineName(def: NimNode): string {.compileTime.} =
  ## def: a routine as the compiler sees it. Its name as a person
  ## wrote it, for the message.
  result = "a routine"
  if def.len > 0 and def[0].kind == nnkPostfix and def[0].len > 1:
    result = def[0][1].strVal
  elif def.len > 0 and def[0].kind in {nnkIdent, nnkSym}:
    result = def[0].strVal

proc failCall(cond: NimNode, what, who: string): NimNode {.compileTime.} =
  ## cond: the promise   what: "needs" or "gives" or "keeps"
  ## who: the routine's name. `if not (cond): contractFailed(...)`.
  var
    msg: string = what & " failed in `" & who & "`: " & cond.repr
  result = newIfStmt((newCall(ident("not"), newPar(copyNimTree(cond))),
    newStmtList(newCall(ident("contractFailed"), newLit(msg)))))

proc checkNode(cond: NimNode, what, who: string, atRun: bool): NimNode
    {.compileTime.} =
  ## cond: the promise   what: which kind   who: the routine
  ## atRun: whether the program itself should carry the check.
  ##
  ## The whole zero-cost claim lives in these seven lines. The check
  ## goes in the `nimvm` branch, which the compiler keeps for its own
  ## interpreter and never writes out; the other branch is what the
  ## program gets, and for the first tier that branch is `discard`.
  var
    runBranch: NimNode = newStmtList(newNimNode(nnkDiscardStmt).add(
      newEmptyNode()))
  if atRun:
    runBranch = newStmtList(newNimNode(nnkWhenStmt).add(
      newNimNode(nnkElifBranch).add(ident("otterContractsOn"),
        newStmtList(failCall(cond, what, who))),
      newNimNode(nnkElse).add(newStmtList(
        newNimNode(nnkDiscardStmt).add(newEmptyNode())))))
  result = newNimNode(nnkWhenStmt).add(
    newNimNode(nnkElifBranch).add(ident("nimvm"),
      newStmtList(failCall(cond, what, who))),
    newNimNode(nnkElse).add(runBranch))

proc rewriteReturns(n: NimNode): NimNode {.compileTime.} =
  ## n: any part of a body.
  ##
  ## Every `return` in it turned into an assignment and a jump out of
  ## the contract block, so that the `gives` check below cannot be
  ## stepped over. A routine written inside the body is left whole:
  ## a `return` in there returns from that one, and rewriting it would
  ## be plainly wrong.
  if n.kind in {nnkProcDef, nnkFuncDef, nnkMethodDef, nnkIteratorDef,
      nnkConverterDef, nnkTemplateDef, nnkMacroDef, nnkLambda, nnkDo}:
    return n
  if n.kind == nnkReturnStmt:
    result = newStmtList()
    if n.len > 0 and n[0].kind != nnkEmpty:
      result.add(newNimNode(nnkAsgn).add(ident("result"), n[0]))
    result.add(newNimNode(nnkBreakStmt).add(ident(bodyLabel)))
    return
  result = copyNimNode(n)
  for child in n:
    result.add(rewriteReturns(child))

proc resultOrStatement(last: NimNode): NimNode {.compileTime.} =
  ## last: the final line of a body.
  ##
  ## Wrapping a body in a block would throw away a routine written as
  ## one expression - `balance - amount` - because the block's value
  ## goes nowhere. So the last line becomes `result = <it>` when that
  ## is something the compiler will accept, and stays as it was when
  ## it is not. The compiler decides; this file only asks.
  var
    res: NimNode = ident("result")
  result = newNimNode(nnkWhenStmt).add(
    newNimNode(nnkElifBranch).add(
      newCall(ident("compiles"), newNimNode(nnkAsgn).add(res,
        copyNimTree(last))),
      newStmtList(newNimNode(nnkAsgn).add(res, copyNimTree(last)))),
    newNimNode(nnkElse).add(newStmtList(copyNimTree(last))))

proc wrapBody(def: NimNode): NimNode {.compileTime.} =
  ## def: the routine. Its body inside the contract block, with every
  ## `return` rewritten and the last line handled.
  var
    inner: NimNode = newStmtList()
    body: NimNode = rewriteReturns(def.body)
    i: int = 0
  if body.kind != nnkStmtList:
    body = newStmtList(body)
  while i < body.len - 1:
    inner.add(body[i])
    i = i + 1
  if body.len > 0:
    inner.add(resultOrStatement(body[^1]))
  result = newNimNode(nnkBlockStmt).add(ident(bodyLabel), inner)

proc oldNames(n: NimNode, found: var seq[string]) {.compileTime.} =
  ## n: a promise   found: the names it asks the entry value of.
  ## Every `old(x)` written in it, so a copy of `x` can be kept before
  ## the body has a chance to change it.
  if n.kind == nnkCall and n.len == 2 and n[0].kind == nnkIdent and
      n[0].strVal == "old" and n[1].kind == nnkIdent:
    if n[1].strVal notin found:
      found.add(n[1].strVal)
    return
  for child in n:
    oldNames(child, found)

proc replaceOld(n: NimNode): NimNode {.compileTime.} =
  ## n: a promise. The same promise with every `old(x)` swapped for
  ## the name of the copy taken on the way in.
  if n.kind == nnkCall and n.len == 2 and n[0].kind == nnkIdent and
      n[0].strVal == "old" and n[1].kind == nnkIdent:
    return ident("otterOld_" & n[1].strVal)
  result = copyNimNode(n)
  for child in n:
    result.add(replaceOld(child))

proc oldSnapshots(cond: NimNode): NimNode {.compileTime.} =
  ## cond: a promise. The copies to take before the body runs.
  ##
  ## Taken without asking whether the checks are switched on, because
  ## a `when` around them would leave the promise talking about a name
  ## that is not there. The cost is one copy per name, and only in a
  ## routine that asked for one.
  var
    found: seq[string] = @[]
    section: NimNode = newNimNode(nnkVarSection)
  result = newStmtList()
  oldNames(cond, found)
  if found.len == 0:
    return
  for name in found:
    section.add(newIdentDefs(ident("otterOld_" & name), newEmptyNode(),
      ident(name)))
  result.add(section)

macro forall*(spec, pred: untyped): untyped =
  ## spec: `x in something`   pred: what must hold for every one.
  ##
  ##     forall(i in 1 ..< A.len, A[i - 1] <= A[i])   <- A is sorted
  ##
  ## An ordinary expression, so it works while building and while
  ## running, and can be joined to others with `and` and `or`. It stops
  ## at the first one that fails.
  expectKind(spec, nnkInfix)
  var
    ok: NimNode = ident("otterEvery")
    loop: NimNode = newNimNode(nnkForStmt).add(spec[1], spec[2],
      newStmtList(newIfStmt((newCall(ident("not"), newPar(pred)),
        newStmtList(newNimNode(nnkAsgn).add(ok, ident("false")),
          newNimNode(nnkBreakStmt).add(newEmptyNode()))))))
  result = newNimNode(nnkBlockStmt).add(newEmptyNode(), newStmtList(
    newNimNode(nnkVarSection).add(newIdentDefs(ok, ident("bool"),
      ident("true"))), loop, ok))

macro exists*(spec, pred: untyped): untyped =
  ## spec: `x in something`   pred: what must hold for at least one.
  ##
  ##     exists(c in s, c == '=')   <- there is an equals sign in s
  ##
  ## The mirror of `forall`, and it stops at the first one that holds.
  expectKind(spec, nnkInfix)
  var
    ok: NimNode = ident("otterAny")
    loop: NimNode = newNimNode(nnkForStmt).add(spec[1], spec[2],
      newStmtList(newIfStmt((newPar(pred),
        newStmtList(newNimNode(nnkAsgn).add(ok, ident("true")),
          newNimNode(nnkBreakStmt).add(newEmptyNode()))))))
  result = newNimNode(nnkBlockStmt).add(newEmptyNode(), newStmtList(
    newNimNode(nnkVarSection).add(newIdentDefs(ok, ident("bool"),
      ident("false"))), loop, ok))

proc buildRequires(cond, def: NimNode, atRun: bool): NimNode
    {.compileTime.} =
  ## cond: what must hold on the way in   def: the routine
  ## atRun: whether the program carries the check.
  ## The check goes first, before anything can act on a bad value.
  result = def
  result.body = newStmtList(checkNode(cond, "needs",
    routineName(def), atRun), def.body)

proc buildEnsures(cond, def: NimNode, atRun: bool): NimNode
    {.compileTime.} =
  ## cond: what must hold on the way out   def: the routine
  ## atRun: whether the program carries the check.
  var
    who: string = routineName(def)
    wrapped: NimNode = wrapBody(def)
  result = def
  result.body = newStmtList(oldSnapshots(cond), wrapped,
    checkNode(replaceOld(cond), "gives", who, atRun))

proc buildInvariant(cond, def: NimNode, atRun: bool): NimNode
    {.compileTime.} =
  ## cond: what must hold at both ends   def: the routine
  ## atRun: whether the program carries the checks.
  ##
  ## Two checks from one sentence. Said at both ends because that is
  ## what makes it an invariant rather than a precondition: it was
  ## true when we arrived and it is still true now.
  var
    who: string = routineName(def)
    wrapped: NimNode = wrapBody(def)
  result = def
  result.body = newStmtList(
    checkNode(cond, "keeps on entry", who, atRun),
    wrapped,
    checkNode(cond, "keeps on exit", who, atRun))

macro needs*(cond: untyped, def: untyped): untyped =
  ## cond: what must hold before the body runs.
  ## Checked while the compiler runs the routine. Costs nothing.
  result = buildRequires(cond, def, atRun = false)

macro gives*(cond: untyped, def: untyped): untyped =
  ## cond: what must hold once the body has run. `result` names what
  ## comes back. Checked while the compiler runs the routine.
  result = buildEnsures(cond, def, atRun = false)

macro keeps*(cond: untyped, def: untyped): untyped =
  ## cond: what must hold both before and after. Checked while the
  ## compiler runs the routine.
  result = buildInvariant(cond, def, atRun = false)

macro needsRun*(cond: untyped, def: untyped): untyped =
  ## cond: what must hold before the body runs.
  ## Checked while the compiler runs the routine, and again in the
  ## program itself unless the checks are switched off.
  result = buildRequires(cond, def, atRun = true)

macro givesRun*(cond: untyped, def: untyped): untyped =
  ## cond: what must hold once the body has run. `old(x)` names the
  ## value `x` held on the way in.
  ## Checked while building and again while running.
  result = buildEnsures(cond, def, atRun = true)

macro keepsRun*(cond: untyped, def: untyped): untyped =
  ## cond: what must hold both before and after.
  ## Checked while building and again while running.
  result = buildInvariant(cond, def, atRun = true)
