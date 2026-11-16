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

import std/[os, sets, strutils, tables, times, unittest]

import ../../src/protocols/code_stats/continuity_types
import ../../src/protocols/code_stats/continuity_guard
import ../../src/protocols/code_stats/continuity_walk
import ../../src/protocols/code_stats/continuity_style
import ../../src/protocols/code_stats/continuity_score
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
    check r.verdictOfControl("web", "#open-b") == cvStays

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
    check r.webPresses == 7
    check r.owlPresses == 4
    check r.teleports().len == 3
    check "TELEPORT" in text
    check "takes the room: #settings" in text
    check "7 click handler(s)" in text

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

suite "continuity: files written by a stranger":

  # {.testKind: tkFuzz.}
  test "cut-off and broken text in every kind of file does not raise":
    ## Each piece ends where a reader would hope for more: a tag, a bracket,
    ## a quote, a keyword with nothing after it.
    var
      pages: seq[string] = @["<", "<a", "</", "<!--", "<script>", "<div id=\"",
        "<button id=x onclick=\"", "<p><p><p></div></div>", "<section hidden>",
        repeat("<div>", 2000), "<script src=", "<div class=\"a\" class=\"b\">"]
      scripts: seq[string] = @[".addEventListener(", ".addEventListener('click',",
        ".addEventListener('click', () => {", ".hidden=true", "x.hidden=",
        "document.getElementById(", "forEach(", ".forEach(p =>", "=>",
        "x.addEventListener('", "a.hidden='", ".style.display='",
        "function (", "function a(", ".onclick", ".onclick =",
        repeat("(", 5000), repeat("=> {", 3000), "a.classList.add(",
        "'", "\"\\", "const x = ", "const = ;", ".style.display="]
      sheets: seq[string] = @["{", "{{{{", ".a{transition:", ".a{background:var(--", "#",
        ".a, {} .b{", "}}}}", "--x:", ":root{--a:1;--a:", ".a{transition: 1e999s}",
        repeat(".a{background:#abc}\n", 3000), " {", "\\", ".\\.\\"]
      nims: seq[string] = @["import owlkettle\nproc clicked(", "= enum",
        "import owlkettle\ntype\n  V = enum", "import owlkettle\nif", "of",
        "import owlkettle\ncase", "import owlkettle\nproc clicked() = M.v =",
        "import owlkettle\n" & repeat("  if a:\n", 300), ":\n:\n:",
        "import owlkettle\ntype V = enum a, b\nproc f(M: V) =\n  proc clicked() =\n"]
      files: seq[tuple[path, text: string]] = @[]
      root: string = ""
    for i in 0 ..< pages.len:
      files.add((path: "p" & $i & ".html", text: pages[i]))
    for i in 0 ..< scripts.len:
      files.add((path: "s" & $i & ".js", text: scripts[i]))
    for i in 0 ..< nims.len:
      files.add((path: "n" & $i & ".nim", text: nims[i]))
    for i in 0 ..< sheets.len:
      files.add((path: "c" & $i & ".css", text: sheets[i]))
    root = tree("garbage", files)
    var r = continuityOf(root, listAllSourceFiles(root))
    check r.error.len == 0
    removeDir(root)

  # {.testKind: tkFuzz.}
  test "a big file of arrows and unclosed brackets is read in bounded time":
    ## pins: every `=>` looked for the end of its body, and with no closing
    ## bracket anywhere that is the rest of the file, once per arrow.
    var
      body: string = repeat("a => { ", 40000)
      root: string = tree("bigjs", @[(path: "a.js", text: body),
        (path: "a.html", text: "<button id=\"x\">x</button>")])
      began: float = epochTime()
      r = continuityOf(root, listAllSourceFiles(root))
    check r.error.len == 0
    check epochTime() - began < 20.0
    removeDir(root)

  # {.testKind: tkFuzz.}
  test "the example files cut off at every eleventh byte do not raise":
    ## A file that stops in the middle of a tag, a name or a bracket is what a
    ## half-saved edit looks like. Every cut is read, with the bounds checks on.
    var
      html: string = readFile(exampleRoot() / "web" / "index.html")
      js: string = readFile(exampleRoot() / "web" / "js" / "app.js")
      nim: string = readFile(exampleRoot() / "owl" / "menu.nim")
      root: string = ""
      r: ContinuityReport = ContinuityReport()
      reads: int = 0
    for cut in countup(0, html.len, 11):
      root = tree("cuthtml", @[(path: "a.html", text: html[0 ..< cut]),
        (path: "a.js", text: js)])
      r = continuityOf(root, listAllSourceFiles(root))
      reads = reads + 1
    for cut in countup(0, js.len, 11):
      root = tree("cutjs", @[(path: "a.html", text: html),
        (path: "a.js", text: js[0 ..< cut])])
      r = continuityOf(root, listAllSourceFiles(root))
      reads = reads + 1
    for cut in countup(0, nim.len, 11):
      root = tree("cutnim", @[(path: "a.nim", text: nim[0 ..< cut])])
      r = continuityOf(root, listAllSourceFiles(root))
      reads = reads + 1
    check reads > 100
    check r.error.len == 0
    removeDir(getTempDir() / "otter_continuity_cuthtml")
    removeDir(getTempDir() / "otter_continuity_cutjs")
    removeDir(getTempDir() / "otter_continuity_cutnim")

proc scoreOfControl(r: ContinuityReport, kind, control: string):
    ContinuityScore {.testKind: tkUnit, covers: "continuityOf".} =
  ## r: the answer   kind: web or owl   control: the button's name.
  ## The score of the first scored press by that button.
  result = ContinuityScore(stay: -1, tie: -1, move: -1, overall: -1)
  for p in r.presses:
    if p.kind == kind and p.control == control and p.scored:
      return p.score
  doAssert false, "no scored press by " & control

suite "continuity: the score and its three metrics":

  # {.testKind: tkUnit.}
  test "each part, on the scale of UI.md 3":
    check keptOf(13, 70) > 0.8 and keptOf(13, 70) < 0.82
    check keptOf(70, 70) == 0.0
    check keptOf(5, 0) < 0.0
    check nearOf(2) == 1.0
    check nearOf(6) == 0.5
    check nearOf(10) == 0.0
    check nearOf(-1) < 0.0
    check moveOf(0.0) == 0.0
    check moveOf(0.15) == 1.0
    check moveOf(0.3) == 1.0
    check moveOf(0.45) > 0.6 and moveOf(0.45) < 0.7
    check moveOf(0.9) == 0.1
    check moveOf(-1.0) < 0.0

  # {.testKind: tkUnit.}
  test "alike is what two things share over everything they hold":
    var
      a: CountTable[string] = initCountTable[string]()
      b: CountTable[string] = initCountTable[string]()
    a.inc("t:div", 2)
    a.inc("c:col", 2)
    b.inc("t:div", 1)
    b.inc("c:panel", 1)
    check likeness(a, a) == 1.0
    check likeness(a, b) == 1.0 / 5.0
    check likeness(initCountTable[string](), initCountTable[string]()) < 0.0

  # {.testKind: tkUnit.}
  test "a shared colour joins, a colour that differs does not, no sheet says nothing":
    var
      green = toHashSet(["var:green", "#2e8b57"])
      alsoGreen = toHashSet(["#2e8b57"])
      blue = toHashSet(["#3b6fb6"])
    check joinedOf(green, alsoGreen, true) == 1.0
    check joinedOf(green, blue, true) == 0.0
    check joinedOf(green, alsoGreen, false) < 0.0

  # {.testKind: tkUnit.}
  test "the bundle is the mean of what was measured, and a teleport is capped":
    var
      good = noParts()
      cut = noParts()
    good.kept = 0.7
    good.alike = 0.5
    good.joined = 1.0
    good.near = 1.0
    good.seconds = 0.15
    check scoreOf(good).stay == 62
    check scoreOf(good).tie == 100
    check scoreOf(good).move == 100
    check scoreOf(good).overall == 87
    cut = good
    cut.teleport = true
    cut.kept = 1.0
    cut.alike = 1.0
    check scoreOf(cut).tie == 0
    check scoreOf(cut).overall <= teleportCap

  # {.testKind: tkEdgeCase.}
  test "a part nobody measured is left out, not counted as zero":
    var p = noParts()
    p.kept = 1.0
    check scoreOf(p).stay == 100
    check scoreOf(p).tie == -1
    check scoreOf(p).move == -1
    check scoreOf(p).overall == 100
    check scoreOf(noParts()).overall == -1
    check meanScore(@[ContinuityScore(stay: 80, tie: -1, move: 100, overall: 90),
      ContinuityScore(stay: 40, tie: 20, move: -1, overall: 30)]).tie == 20

suite "continuity: what a style sheet says":

  # {.testKind: tkUnit.}
  test "colours are found by name and by value, and a variable meets its value":
    var
      css: string = ":root { --green: #2E8B57; }\n" &
        ".opener { background: var(--green); }\n" &
        ".edge { border-left: 4px solid #2e8b57; transition: opacity 150ms; }\n"
      R = styleRulesIn(css)
      a = lookOf(R, "button", "", @["opener"])
      b = lookOf(R, "div", "", @["edge"])
    check "#2e8b57" in a.colours
    check "var:green" in a.colours
    check card(a.colours * b.colours) > 0
    check b.seconds > 0.14 and b.seconds < 0.16
    check a.seconds == 0.0
    check a.known

  # {.testKind: tkEdgeCase.}
  test "text colour, hover rules and media blocks say nothing about the look":
    var
      css: string = ".a { color: #ff0000; }\n.b:hover { background: #00ff00; }\n" &
        "@media (max-width: 40rem) { .c { background: #0000ff; } }\n"
      R = styleRulesIn(css)
    check lookOf(R, "", "", @["a"]).colours.len == 0
    check lookOf(R, "", "", @["b"]).colours.len == 0
    check lookOf(R, "", "", @["c"]).colours.len == 0

  # {.testKind: tkEdgeCase.}
  test "no style sheet at all is not the same as a style sheet with nothing in it":
    check not lookOf(@[], "div", "", @["x"]).known
    check lookOf(styleRulesIn(".y { margin: 0; }"), "div", "", @["x"]).known

suite "continuity: the example, press by press":

  # {.testKind: tkIntegration.}
  test "the green opener with a fade beside it scores as calm":
    var
      r = continuityOf(exampleRoot(), listAllSourceFiles(exampleRoot()))
      s: ContinuityScore = ContinuityScore()
    s = r.scoreOfControl("web", "#open-b")
    check s.overall >= 80
    check s.tie >= 90
    check s.move == 100

  # {.testKind: tkIntegration.}
  test "a press that takes its button along has no tie and is capped":
    var
      r = continuityOf(exampleRoot(), listAllSourceFiles(exampleRoot()))
      s: ContinuityScore = ContinuityScore()
      o: ContinuityScore = ContinuityScore()
    s = r.scoreOfControl("web", "#open-settings")
    check s.tie == 0
    check s.overall <= teleportCap
    o = r.scoreOfControl("owl", "\"Report\"")
    check o.tie == 0
    check o.overall <= teleportCap

  # {.testKind: tkIntegration.}
  test "the same opener in owlkettle: colour, closeness and a fade all count":
    ## The frame's Settings button has the style class open-green, the
    ## settings view has pane-green; menu.css gives both one colour and the
    ## view a 150 ms transition.
    var
      r = continuityOf(exampleRoot(), listAllSourceFiles(exampleRoot()))
      best: ContinuityScore = ContinuityScore(stay: -1, tie: -1, move: -1,
        overall: -1)
    for p in r.presses:
      if p.kind == "owl" and p.verdict == cvStays and p.scored:
        best = p.score
    check best.overall >= 80
    check best.tie >= 90
    check best.move == 100

  # {.testKind: tkIntegration.}
  test "a cut between tabs is a jump, and the report names it":
    var
      r = continuityOf(exampleRoot(), listAllSourceFiles(exampleRoot()))
      s = r.scoreOfControl("web", "#tab-reports")
      text: string = continuityLines(r).join("\n")
    check s.move == 0
    check s.overall < jumpBelow
    check "JUMP  web/js/app.js:22" in text
    check "JUMP  web/js/app.js:47" notin text

  # {.testKind: tkIntegration.}
  test "the whole UI has one number, the mean of its presses":
    var r = continuityOf(exampleRoot(), listAllSourceFiles(exampleRoot()))
    check r.scoredPresses >= 9
    check r.score.overall > 0 and r.score.overall < 100
    check "continuity score " & $r.score.overall in
      continuityLines(r).join("\n")

  # {.testKind: tkEdgeCase.}
  test "a page with no style sheet has no tie colour and no move, only stay":
    ## pins: no sheet at all read as "no colour and a cut", which scored a
    ## page nobody had measured as a jump.
    var
      cells: string = repeat("<i>x</i>", 12)
      root: string = tree("nosheet", @[
        (path: "index.html", text: "<section id=\"a\"><button id=\"go\">Go" &
          "</button>" & cells & "</section><section id=\"b\" hidden><p>1</p>" &
          "<p>2</p></section><button id=\"out\">Out</button>" &
          "<script src=\"app.js\"></script>"),
        (path: "app.js", text: "document.getElementById('out')." &
          "addEventListener('click', () => {\n" &
          "  document.getElementById('a').hidden = true;\n" &
          "  document.getElementById('b').hidden = false;\n});\n")])
      r = continuityOf(root, listAllSourceFiles(root))
    check r.presses.len == 1
    check r.presses[0].scored
    check r.presses[0].score.move == -1
    check r.presses[0].score.stay >= 0
    removeDir(root)
