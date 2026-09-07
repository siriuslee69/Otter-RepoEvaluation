# ============================================================
# | Otter UI Depth Tests                                     |
# | -> How many things must be opened to reach a control     |
# ============================================================
#
# `examples/ui_depth/` is a page with a deliberate inversion: the
# thing people need most sits three clicks down, and the thing they
# need least is on screen. Every number here has a right answer that
# can be checked by reading thirty lines of markup.

import std/[os, sets, strutils, unittest]

import ../../src/protocols/code_stats/ui_depth
import ../../src/protocols/code_stats/pipeline
import ../../meta/metaPragmas

proc sampleReport(): UiDepthReport {.testKind: tkUnit,
    covers: "uiDepthOf".} =
  ## The example front end, found from this file.
  var root: string = parentDir(parentDir(parentDir(
    currentSourcePath()))) / "examples" / "ui_depth"
  result = uiDepthOf(root, listAllSourceFiles(root))

suite "ui depth: how far away a control is":

  # {.testKind: tkIntegration.}
  test "a control on the page is at no depth, one in a panel at one":
    var r = sampleReport()
    check r.total == 6
    var atZero: int = 0
    for c in r.controls:
      if c.depth == 0:
        atZero = atZero + 1
    check atZero == 3

  # {.testKind: tkIntegration.}
  test "three nested gates read as three clicks, and are named":
    var
      r = sampleReport()
      deep: seq[UiControl] = @[]
    for c in r.controls:
      if c.depth == 3:
        deep.add(c)
    check deep.len == 1
    check "Export" in deep[0].label
    check deep[0].gates.len == 3

  # {.testKind: tkRegression.}
  test "a media query is a shape, not a click":
    ## pins: `@media (max-width: 40rem) { .stage { display: none } }`
    ## made every button in the main area look as if it sat behind a
    ## click, which inverted the whole answer.
    check "stage" notin hiddenClassesIn(readFile(
      parentDir(parentDir(parentDir(currentSourcePath()))) / "examples" /
      "ui_depth" / "web" / "css" / "app.css"))

  # {.testKind: tkRegression.}
  test "a rule that needs an ancestor state is not a blanket hide":
    ## `body.busy .stage { display: none }` hides the stage only while
    ## the body is busy, so the stage is not something to open.
    var
      stateRule: string = "body.busy .stage " & "{ display" & ": none; }"
      got = hiddenClassesIn(stateRule)
    check got.len == 0

  # {.testKind: tkRegression.}
  test "a comment in front of a rule does not swallow it":
    ## pins: everything between the previous brace and the next one is
    ## read as the selector, so a commented rule looked like a
    ## descendant selector and was dropped.
    var
      commented: string = "/* the drawer */\n.drawer " & "{ display" & ": none; }"
      got = hiddenClassesIn(commented)
    check "drawer" in got

  # {.testKind: tkUnit.}
  test "both ways of hiding count":
    var
      hideA: string = ".a " & "{ display" & ": none; }"
      hideB: string = ".b " & "{ visibility" & ": hidden; }"
      plainC: string = ".c " & "{ color" & ": red; }"
    check "a" in hiddenClassesIn(hideA)
    check "b" in hiddenClassesIn(hideB)
    check hiddenClassesIn(plainC).len == 0

  # {.testKind: tkIntegration.}
  test "a control only a key reveals is counted apart":
    ## It has no gate above it, so counting clicks would call it free.
    ## A person who does not know the key cannot reach it at all.
    var
      r = sampleReport()
      named: bool = false
    check r.keyboardOnly == 1
    for c in r.controls:
      if c.keyboardOnly and "command" in c.label.toLowerAscii():
        named = true
    check named

  # {.testKind: tkUnit.}
  test "a key handler gives up the ids it touches":
    var got: HashSet[string] = keyboardTargets(
      "document.addEventListener(\"keydown\", () => q(\"#palette\"));")
    check "palette" in got
    check keyboardTargets("const a = q(\"#palette\");").len == 0
