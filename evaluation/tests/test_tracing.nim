## test_tracing.nim <- `otter trace` on a fixture with every awkward routine kind
##
##   func / raises: [] / var output / exception / "_" parameter / compile-time
##   use / template - all must compile traced, and the trace must show them.

import std/[os, strutils, unittest]
import ../../src/protocols/trace_run

const
  fixture: string = currentSourcePath().parentDir / "fixtures" / "trace_probe"
  otterSrc: string = currentSourcePath().parentDir.parentDir.parentDir / "src"

suite "otter trace":
  # {.testKind: tkIntegration.}
  test "every awkward routine kind compiles traced and shows up":
    var
      o: (string, int) = runTrace(fixture, "probe_test.nim", otterSrc, 300)
    checkpoint(o[0])
    check o[1] == 0
    check o[0].contains("[trace] > fill  P=(c: [0, 0, 0, 0]) v=2000")
    check o[0].contains("[trace] < fill  P=(c: [-1329, -1329, -1329, -1329])")
    check o[0].contains("< pure  3")
    check o[0].contains("< noRaise  6")
    check o[0].contains("! bad  raised: too big: 9")
    check o[0].contains("caught")
    check o[0].contains("[trace] calls:")
    check not dirExists(traceCopyPath(fixture))        # cleaned up afterwards

  # {.testKind: tkEdgeCase.}
  test "only a marked trace copy is ever deleted":
    var
      d: string = getTempDir() / "not_a_trace_copy__otter_trace"
    createDir(d)
    expect IOError:
      removeTraceCopy(d)                                # no marker: refused
    check dirExists(d)
    removeDir(d)
    expect IOError:
      removeTraceCopy(fixture)                          # wrong name: refused
    check dirExists(fixture)
