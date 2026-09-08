# ============================================================
# | Otter State Writes Tests                                 |
# | -> Who may change an entry, and when a write is lost     |
# ============================================================
#
# `examples/state_writes/` is one file of eight routines, written so
# that every answer here can be checked by reading it. Its doc box
# names the expected verdict for each of the five entries.

import std/[os, sets, strutils, unittest]

import ../../src/protocols/repo_graph
import ../../src/protocols/code_stats/state_writes
import otterPragmas

proc sampleGraph(): RepoGraph {.testKind: tkUnit, covers: "stateWritesOf".} =
  ## The example tree, found from this file so the test runs anywhere.
  result = analyzeRepo(parentDir(parentDir(parentDir(
    currentSourcePath()))) / "examples" / "state_writes")

proc entryOf(r: StateReport, field: string): FieldTraffic
    {.testKind: tkUnit, covers: "stateWritesOf".} =
  ## r: one answer   field: the entry wanted.
  result = FieldTraffic()
  for st in r.states:
    for e in st.entries:
      if e.field == field:
        return e

suite "state writes: who may change an entry":

  # {.testKind: tkIntegration.}
  test "a state type is found with its entries and its role":
    var r = stateWritesOf(sampleGraph())
    check r.error.len == 0
    check r.states.len == 1
    check r.states[0].name == "Feed"
    check r.states[0].role == "truthstate"
    check r.states[0].entries.len == 5

  # {.testKind: tkUnit.}
  test "a writer that reads first is folding, one that does not is blind":
    var r = stateWritesOf(sampleGraph())
    check entryOf(r, "price").blindWriters == @["ingest", "resample"]
    check entryOf(r, "volume").blindWriters == @["ingest"]
    check entryOf(r, "volume").foldingWriters == @["accumulate"]

  # {.testKind: tkIntegration.}
  test "a proven loss names the routine and both lines":
    ## runFeed calls ingest then resample with no read between them.
    var
      r = stateWritesOf(sampleGraph())
      found: bool = false
    for h in r.hazards:
      if h.field != "price":
        continue
      found = true
      check h.witness == "runFeed"
      check h.first == "ingest"
      check h.second == "resample"
      check h.secondLine == h.firstLine + 1
    check found

  # {.testKind: tkRegression.}
  test "a read between the two writes is not a loss":
    ## runSafe calls snapshot, reads depth, then calls rebase. Both
    ## writes are blind, so without the read this would be reported.
    ## Pins the first thing this got wrong: it said "nothing was seen
    ## calling two of them in a row" for a pair it had in fact seen.
    var r = stateWritesOf(sampleGraph())
    for h in r.hazards:
      check h.field != "depth"

  # {.testKind: tkUnit.}
  test "an entry marked otter:latest is left alone":
    var r = stateWritesOf(sampleGraph())
    check entryOf(r, "ticker").allowed
    check entryOf(r, "ticker").blindWriters.len == 2
    for h in r.hazards:
      check h.field != "ticker"

  # {.testKind: tkUnit.}
  test "an entry nothing reads is reported as dead, not as an overwrite":
    var r = stateWritesOf(sampleGraph())
    check "Feed.lastSeen" in r.unread
    for h in r.hazards:
      check h.field != "lastSeen"

  # {.testKind: tkEdgeCase.}
  test "a name is judged by what follows it":
    var recvs = ["S"].toHashSet()
    check fieldUses("S.price = 1.0", recvs, "price").writes == 1
    check fieldUses("S.price = S.price + 1", recvs, "price").writes == 1
    check fieldUses("S.price = S.price + 1", recvs, "price").reads == 1
    check fieldUses("if S.price == 1.0:", recvs, "price").reads == 1
    check fieldUses("S.price += 1.0", recvs, "price").folds == 1
    check fieldUses("S.rows[i] = v", recvs, "rows").folds == 1
    check fieldUses("S.rows.add(v)", recvs, "rows").folds == 1
    check fieldUses("S.rows.setLen(0)", recvs, "rows").writes == 1

  # {.testKind: tkEdgeCase.}
  test "a name that only ends in the entry name is a different name":
    var recvs = ["S"].toHashSet()
    check fieldUses("S.priceLimit = 1.0", recvs, "price").writes == 0
    check fieldUses("other.price = 1.0", recvs, "price").writes == 0

  # {.testKind: tkRegression.}
  test "a routine building its own object is not writing anybody's state":
    ## Pins the second thing this got wrong. Every "make one and fill
    ## it in" routine counted as a writer, which turned sixty ordinary
    ## constructors into writers of every entry they touched.
    var f: FunctionInfo = FunctionInfo()
    f.name = "build"
    f.signature = "proc build(): Feed ="
    f.returnType = "Feed"
    f.bodyLines = @["  result.price = p"]
    check writeReceivers(f, "Feed", initHashSet[string]()).len == 0
    check "result" in readReceivers(f, "Feed", initHashSet[string](),
      initHashSet[string]())

  # {.testKind: tkUnit.}
  test "only var, ptr and ref parameters can write the caller's object":
    var
      shared = FunctionInfo(name: "fill",
        signature: "proc fill(S: var Feed, p: float) =", bodyLines: @[])
      copied = FunctionInfo(name: "show",
        signature: "proc show(S: Feed): string =", bodyLines: @[])
    check "S" in writeReceivers(shared, "Feed", initHashSet[string]())
    check writeReceivers(copied, "Feed", initHashSet[string]()).len == 0
    check "S" in readReceivers(copied, "Feed", initHashSet[string](),
      initHashSet[string]())

  # {.testKind: tkRegression.}
  test "a wipe routine is not a second writer that loses work":
    ## Pins the third. `clear(S)` then `init(S, key)` was reported as a
    ## loss across a whole cryptography library, when throwing the old
    ## value away is exactly what `clear` is for.
    check isResetter("gimliClear")
    check isResetter("falconTyrClearKeypair")
    check not isResetter("ingest")

  # {.testKind: tkUnit.}
  test "a comment cannot make a line look like a write":
    var recvs = ["S"].toHashSet()
    check fieldUses("  discard  # S.price = 1.0", recvs, "price").writes == 0
    check codeOf("""  S.name = "a#b"  # note""").strip() ==
      "S.name = \"a#b\""

  # {.testKind: tkIntegration.}
  test "measuring this repository stays quick and says something":
    ## A guard on the shape of the walk rather than on its answers: it
    ## once read every routine once per type and took half a minute.
    var r = stateWritesOf(analyzeRepo(parentDir(parentDir(parentDir(
      currentSourcePath())))))
    check r.error.len == 0
    check r.states.len > 0
