## ============================================================
## | Otter Continuity Tests                                   |
## | -> A press must not take its own button along            |
## ============================================================
##
## `examples/ui_continuity/` holds a page (html + css + js) and an
## owlkettle menu. Each has presses that teleport the user and presses
## that do not; every verdict here has an answer that can be read off
## the thirty lines of source in front of it.
##
##   press                      hides         button inside?   verdict
##   -------------------------  ------------  ---------------  -------
##   page  #open-settings       #overview     yes, on screen   goes
##   page  #tab-reports         #overview     no (the frame)   stays
##   page  #back                #settings     yes, but hidden
##                                            at the start     returns
##   menu  headerBar [Report]   headerBar    yes              goes
##   menu  homeColumns [Settings] homeColumns yes              goes
##   menu  frameTabs [Settings]  homeColumns  no               stays

import std/[os, sets, strutils, tables, unittest]

import ../../src/protocols/code_stats/continuity_types
import ../../src/protocols/code_stats/continuity_guard
import ../../src/protocols/code_stats/continuity_walk
import ../../src/protocols/code_stats/continuity
import ../../src/protocols/code_stats/ui_depth
import ../../src/protocols/code_stats/inventory
import runePragmas

proc exampleRoot(): string {.testKind: tkUnit, covers: "continuityOf".} =
  ## The example front end, found from this file.
  result = parentDir(parentDir(parentDir(currentSourcePath()))) /
    "examples" / "ui_continuity"

proc verdictOfControl(r: ContinuityReport, kind, control: string):
    ContinuityVerdict {.testKind: tkUnit, covers: "continuityOf".} =
  ## r: the answer   kind: web or owl   control: the button's name.
  ## The verdict of the first press by that button.
  result = cvSmall
  for p in r.presses:
    if p.kind == kind and p.control == control:
      return p.verdict
  doAssert false, "no press by " & control

proc tree(name: string, files: seq[tuple[path, text: string]]): string
    {.testKind: tkUnit, covers: "continuityOf".} =
  ## name: a folder name   files: what to write into it.
  ## A small repository in the temp folder, built for one test.
  result = getTempDir() / ("otter_continuity_" & name)
  removeDir(result)
  for f in files:
    createDir(parentDir(result / f.path))
    writeFile(result / f.path, f.text)

proc envFor(view: string): GuardEnv {.testKind: tkUnit,
    covers: "evalGuard".} =
  ## view: the view the question assumes `M.view` is set to.
  result = GuardEnv(members: toHashSet(["vHome", "vReport", "vSettings"]),
    fields: toHashSet(["view"]), assigned: {"view": view}.toTable,
    locals: {"bare": "M.view in {vReport}"}.toTable,
    funcs: {"isForm": HelperFn(param: "v",
      expr: "v in {vReport, vSettings}")}.toTable)

suite "continuity: the example page and menu":

  # {.testKind: tkIntegration.}
  test "the page: one teleport, a frame that stays, a back that returns":
    var r = continuityOf(exampleRoot(), listAllSourceFiles(exampleRoot()))
    check r.verdictOfControl("web", "#open-settings") == cvGoes
    check r.verdictOfControl("web", "#tab-reports") == cvStays
    check r.verdictOfControl("web", "#tab-overview") == cvStays
    check r.verdictOfControl("web", "#back") == cvReturn
    check r.verdictOfControl("web", "#dismiss-note") == cvSmall
    check r.verdictOfControl("web", "#close-about") == cvClose

  # {.testKind: tkIntegration.}
  test "the menu: two teleports, a frame that stays, a back that returns":
    var
      r = continuityOf(exampleRoot(), listAllSourceFiles(exampleRoot()))
      goes: int = 0
    check r.verdictOfControl("owl", "\"Report\"") == cvGoes
    check r.verdictOfControl("owl", "\"Back\"") == cvReturn
    for p in r.presses:
      if p.kind == "owl" and p.verdict == cvGoes:
        goes = goes + 1
    check goes == 2

  # {.testKind: tkIntegration.}
  test "what takes the room is named":
    var
      r = continuityOf(exampleRoot(), listAllSourceFiles(exampleRoot()))
      names: seq[string] = @[]
    for p in r.teleports():
      names.add(p.replacedBy)
    check "#settings" in names
    check "reportView" in names
    check "settingsView" in names

  # {.testKind: tkIntegration.}
  test "the report counts what it looked at, and the text says so":
    var
      r = continuityOf(exampleRoot(), listAllSourceFiles(exampleRoot()))
      text: string = ""
    text = continuityLines(r).join("\n")
    check r.webPresses == 6
    check r.owlPresses == 4
    check r.teleports().len == 3
    check "TELEPORT" in text
    check "takes the room: #settings" in text
    check "6 click handler(s)" in text

suite "continuity: when is a condition true":

  # {.testKind: tkUnit.}
  test "a view in a set, with the view assumed":
    check evalGuard("M.view in {vReport}", envFor("vReport")) == tTrue
    check evalGuard("M.view in {vReport}", envFor("vHome")) == tFalse
    check evalGuard("M.view notin {vReport}", envFor("vHome")) == tTrue
    check evalGuard("M.view == vHome", envFor("vHome")) == tTrue
    check evalGuard("M.view != vHome", envFor("vReport")) == tTrue

  # {.testKind: tkUnit.}
  test "a local name stands for what it was set to":
    check evalGuard("not bare", envFor("vReport")) == tFalse
    check evalGuard("not bare", envFor("vHome")) == tTrue

  # {.testKind: tkUnit.}
  test "a helper over a view is called both ways":
    check evalGuard("M.view.isForm()", envFor("vSettings")) == tTrue
    check evalGuard("isForm(M.view)", envFor("vSettings")) == tTrue
    check evalGuard("M.view.isForm()", envFor("vHome")) == tFalse

  # {.testKind: tkEdgeCase.}
  test "what it cannot read is unknown, and unknown does not decide":
    check evalGuard("x > 3", envFor("vHome")) == tUnknown
    check evalGuard("M.picker and M.view in {vReport}",
      envFor("vHome")) == tFalse
    check evalGuard("M.picker and M.view in {vReport}",
      envFor("vReport")) == tUnknown
    check evalGuard("M.picker or M.view in {vReport}",
      envFor("vReport")) == tTrue
    check evalGuard("", envFor("vHome")) == tUnknown

  # {.testKind: tkEdgeCase.}
  test "a set naming something that is not a view member is unknown":
    check evalGuard("M.view in {vHome, SomeConstant}",
      envFor("vHome")) == tUnknown

suite "continuity: the conditions over a line":

  # {.testKind: tkUnit.}
  test "an early return leaves its opposite over everything after it":
    var
      body: seq[string] = @["if M.picker:", "  return pickerView(M)",
        "case M.view", "of vReport: result = reportView(M)",
        "else: result = homeColumns(M)"]
      G = guardedLines(body)
    check G.len == 3
    check G[0].guards == @["M.picker"]
    check G[1].guards == @["not (M.picker)", "M.view in {vReport}"]
    check G[2].guards == @["not (M.picker)", "not (M.view in {vReport})"]

  # {.testKind: tkUnit.}
  test "elif and else read as the earlier branches not holding":
    var
      body: seq[string] = @["if a:", "  x()", "elif b:", "  y()", "else:",
        "  z()"]
      G = guardedLines(body)
    check G[0].guards == @["a"]
    check G[1].guards == @["not (a) and (b)"]
    check G[2].guards == @["not (a) and not (b)"]

suite "continuity: a page read from its scripts":

  # {.testKind: tkRegression.}
  test "an id is not found inside data-id":
    ## pins: `find("id=")` found `data-id=` first, so a button with both
    ## was filed under the number in its data attribute.
    check attributeOf("button data-id=\"3\" id=\"x\"", "id") == "x"
    check attributeOf("button data-id=\"3\"", "id") == ""

  # {.testKind: tkIntegration.}
  test "a view switcher that hides every page and shows one by name":
    ## `onclick="showPage('b')"` calls a function that hides all `.page`
    ## elements and shows the one it is given by id. The button sits in page a.
    var
      cells: string = repeat("<span>x</span>", 12)
      root: string = tree("switcher", @[
        (path: "index.html", text: "<main><section class=\"page\" id=\"a\">" &
          "<button id=\"go-b\" onclick=\"showPage('b')\">B</button>" & cells &
          "</section><section class=\"page\" id=\"b\" hidden><p>1</p><p>2</p>" &
          "</section></main><script src=\"app.js\"></script>"),
        (path: "app.js", text: "function showPage(id) {\n" &
          "  document.querySelectorAll('.page').forEach(p => p.hidden = true);\n" &
          "  document.getElementById(id).hidden = false;\n}\n")])
      r = continuityOf(root, listAllSourceFiles(root))
    check r.teleports().len == 1
    check r.teleports()[0].control == "#go-b"
    check r.teleports()[0].replacedBy == "#b"
    removeDir(root)

  # {.testKind: tkRegression.}
  test "two pages with the same ids are told apart by the script each loads":
    ## pins: every script was matched against every page, so two copies of
    ## one example reported each press twice per page.
    var
      page: string = "<section id=\"wrap\"><button id=\"go\">Go</button>" &
        repeat("<i>x</i>", 12) & "</section><section id=\"next\" hidden>" &
        "<p>1</p><p>2</p></section><script src=\"app.js\"></script>"
      script: string = "document.getElementById('go').addEventListener('click'," &
        " () => {\n  document.getElementById('wrap').hidden = true;\n" &
        "  document.getElementById('next').hidden = false;\n});\n"
      root: string = tree("twopages", @[
        (path: "one/index.html", text: page), (path: "one/app.js", text: script),
        (path: "two/index.html", text: page), (path: "two/app.js", text: script)])
      r = continuityOf(root, listAllSourceFiles(root))
    check r.presses.len == 2
    check r.teleports().len == 2
    removeDir(root)

  # {.testKind: tkEdgeCase.}
  test "a press that hides something big and shows nothing is a close":
    var
      page: string = "<section id=\"panel\"><button id=\"shut\">x</button>" &
        repeat("<i>x</i>", 12) & "</section><script src=\"app.js\"></script>"
      root: string = tree("closeonly", @[
        (path: "index.html", text: page),
        (path: "app.js", text: "document.getElementById('shut')." &
          "addEventListener('click', () => { " &
          "document.getElementById('panel').hidden = true; });")])
      r = continuityOf(root, listAllSourceFiles(root))
    check r.teleports().len == 0
    check r.presses.len == 1
    check r.presses[0].verdict == cvClose
    removeDir(root)

suite "continuity: an owlkettle menu read from its states":

  # {.testKind: tkIntegration.}
  test "an early return in the body hides the list the button is in":
    ## `if M.view == vB: return detailView(M)` leaves the list view out when
    ## the view is vB, and the button that sets vB is in the list view.
    var
      widgets: string = repeat("      Label:\n        text = \"x\"\n", 13)
      root: string = tree("earlyreturn", @[
        (path: "menu.nim", text: "import owlkettle\n\n" &
          "type\n  View = enum\n    vA, vB\n  Memory = ref object\n" &
          "    view: View\n\n" &
          "proc listView(M: Memory): Widget =\n  result = gui:\n    Box:\n" &
          "      Button:\n        text = \"Open\"\n" &
          "        proc clicked() =\n          M.view = vB\n" & widgets & "\n" &
          "proc detailView(M: Memory): Widget =\n  result = gui:\n    Box:\n" &
          widgets & "\n" &
          "proc body(M: Memory): Widget =\n  if M.view == vB:\n" &
          "    return detailView(M)\n  result = listView(M)\n")])
      r = continuityOf(root, listAllSourceFiles(root))
    check r.teleports().len == 1
    check r.teleports()[0].hidden == "listView"
    check r.teleports()[0].replacedBy == "detailView"
    removeDir(root)

  # {.testKind: tkEdgeCase.}
  test "a repository without owlkettle is not read as one":
    var
      root: string = tree("noowl", @[
        (path: "a.nim", text: "type\n  V = enum\n    a, b\n" &
          "proc clicked() =\n  discard\n")])
      r = continuityOf(root, listAllSourceFiles(root))
    check r.owlPresses == 0
    check r.presses.len == 0
    removeDir(root)
