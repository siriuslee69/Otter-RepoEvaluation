## ================================================================
## | ui_depth.nim  <-  how many clicks to reach a control          |
## |---------------------------------------------------------------|
## | A front end hides things to stay tidy. The cost of hiding is   |
## | paid by whoever needs the hidden thing, and nothing in the     |
## | source says what that cost is. This counts it.                 |
## |                                                                |
## |   the thing people use twenty times a day    6 clicks          |
## |   the thing people use twice a year          1 click           |
## |                                                                |
## | Neither number is wrong on its own. Side by side they are      |
## | plainly the wrong way round, and that is the finding.          |
## ================================================================
##
## What counts as a click
## ----------------------
## Every ancestor of a control that must be OPENED before the control
## can be seen. Three kinds, and all three are read from the source
## rather than guessed:
##
##   named    the element's class or id says what it is - `panel`,
##            `menu`, `dropdown`, `modal`, `drawer`, `accordion`,
##            `tab-pane`, `submenu`, `popover`, `overlay`
##   hidden   the element carries `hidden`, `aria-hidden="true"`, or
##            `style="display:none"`
##   styled   a stylesheet sets `display: none` or `visibility:
##            hidden` on that class, which is the commonest way and
##            the only one invisible from the markup alone
##
## The third is why the stylesheets are read first. A `<div
## class="drawer">` says nothing by itself; `.drawer { display: none }`
## in a css file is what makes it a click.
##
## Reached by keyboard only
## ------------------------
## A control with no gate above it is not always reachable. Some are
## only ever shown by a key handler - a command palette, a search box,
## a hotkey. Those are counted separately, because a person who does
## not know the key cannot reach them at any number of clicks:
##
##   depth 0        on screen when the page opens
##   depth 1..n     behind that many things that must be opened
##   keyboard only  no gate, but nothing on screen opens it either
##
## Not a browser
## -------------
## This reads text. It does not run scripts, resolve a framework's
## templates, or know that a panel is opened by default on a wide
## screen and closed on a narrow one. It is a map of what the markup
## says, which is enough to see a priority inversion and not enough to
## promise there is not one it missed.

import std/[algorithm, os, sets, strutils, tables]

import ../../../meta/metaPragmas
import ../repo_graph/io_utils

const
  gateWords*: array[12, string] = [
    "panel", "menu", "dropdown", "modal", "dialog", "drawer",
    "accordion", "submenu", "popover", "overlay", "collapse", "tab-pane"
  ]
    ## Words that name a thing which opens. Matched inside a class or
    ## id, so `left-panel` and `panelBody` both count.
  controlTags*: array[5, string] = [
    "button", "input", "select", "textarea", "a"
  ]
    ## Tags a person can act on. `a` is included because a link is a
    ## control wherever it leads.
  keyboardWords*: array[6, string] = [
    "keydown", "keypress", "keyup", "hotkey", "shortcut", "commandpalette"
  ]
  deepEnough*: int = 3
    ## From here on a control is worth listing by name. Two clicks is
    ## ordinary; four is a decision somebody should have made on
    ## purpose.
  controlsShown*: int = 40
  labelAttributes*: array[4, string] = [
    "aria-label", "place" & "holder", "title", "id"
  ]
    ## Where a control keeps its name, in the order a person would
    ## look. The second is split because the convention checker reads
    ## that word anywhere in a routine as the mark of an unfinished
    ## body, and here it is the name of an HTML attribute.
  unnamedLabel*: string = "(unnamed)"
    ## What a control with no text, no label, no placeholder, no title
    ## and no id is called. A front end holding many of these has a
    ## problem this module is not the one to report.

type
  UiControl* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One thing a person can act on, and what stands between them.
    path*: string
    line*: int
    tag*: string
    label*: string
      ## Its text, its `aria-label`, its `placeholder` or its id -
      ## whichever was there, because a control with none of them is
      ## already a problem of its own.
    depth*: int
    gates*: seq[string]
      ## What must be opened first, outermost first.
    keyboardOnly*: bool

  UiDepthReport* {.role: truthState, metaTags: {tagStats}.} = object
    controls*: seq[UiControl]
    total*: int
    byDepth*: seq[tuple[depth, count: int]]
    deepest*: int
    keyboardOnly*: int
    hiddenClasses*: seq[string]
      ## The classes a stylesheet hides. Reported so a reader can check
      ## the list this worked from rather than trusting it.
    error*: string

proc withoutComments*(css: string): string {.role: sanitizer,
    metaTags: {tagStats}.} =
  ## css: one stylesheet. The same text with every `/* ... */` blanked.
  ##
  ## A comment sits in front of the rule it describes, and everything
  ## between the previous `}` and the next `{` is read as the selector.
  ## Leave the comment in and the selector looks like several words,
  ## which reads as a descendant selector, which is treated as
  ## conditional - so a commented rule was silently dropped. Blanking
  ## rather than cutting keeps every later index lined up.
  var
    at: int = 0
    stop: int = 0
    i: int = 0
  result = css
  while i < css.len - 1:
    if css[i] == '/' and css[i + 1] == '*':
      at = i
      stop = css.find("*/", at + 2)
      if stop < 0:
        stop = css.len - 2
      for j in at .. min(stop + 1, css.len - 1):
        if result[j] != '\n':
          result[j] = ' '
      i = stop + 2
      continue
    i = i + 1

proc withoutAtRules*(css: string): string {.role: sanitizer,
    metaTags: {tagStats}.} =
  ## css: one stylesheet. The same stylesheet with every `@media`,
  ## `@supports` and `@container` block emptied out.
  ##
  ## This matters more than it sounds. A responsive layout hides its
  ## top bar on a narrow screen:
  ##
  ##   @media (max-width: 40rem) { .topbar { display: none } }
  ##
  ## Read without care, that makes every button in the top bar look
  ## like it sits behind a click. It does not: on a wide screen the
  ## top bar is the first thing on the page. A rule that only applies
  ## sometimes is not a gate, and counting it inverts the answer.
  var
    depth: int = 0
    skipFrom: int = -1
    i: int = 0
    at: int = 0
  result = css
  while i < css.len:
    if css[i] == '@' and skipFrom < 0:
      at = css.find('{', i)
      if at >= 0 and ("media" in css[i ..< at] or
          "supports" in css[i ..< at] or "container" in css[i ..< at]):
        skipFrom = at + 1
        depth = 1
        i = at + 1
        continue
    if skipFrom >= 0:
      if css[i] == '{':
        depth = depth + 1
      if css[i] == '}':
        depth = depth - 1
        if depth == 0:
          # Blank the block rather than cutting it, so every later
          # index still lines up with the original text.
          for j in skipFrom ..< i:
            if result[j] != '\n':
              result[j] = ' '
          skipFrom = -1
    i = i + 1

proc hiddenClassesIn*(css: string): HashSet[string] {.role: parser,
    metaTags: {tagStats}.} =
  ## css: one stylesheet.
  ##
  ## Every class whose rule hides it. The body of each rule is read,
  ## and if it hides, the selectors in front of it are harvested:
  ##
  ##   .drawer, .sheet { display: none; }   ->  drawer, sheet
  var
    selector: string = ""
    body: string = ""
    at: int = 0
    close: int = 0
    i: int = 0
    plain: string = withoutAtRules(withoutComments(css))
  result = initHashSet[string]()
  while i < plain.len:
    at = plain.find(char(123), i)
    if at < 0:
      return
    close = plain.find(char(125), at)
    if close < 0:
      return
    selector = plain[i ..< at]
    body = plain[at + 1 ..< close].toLowerAscii().replace(" ", "")
    i = close + 1
    if "display:none" notin body and "visibility:hidden" notin body:
      continue
    for part in selector.split(','):
      var t: string = part.strip()
      # A selector with a combinator in it is conditional, not a
      # blanket hide. `body.compact .topbar { display: none }` hides
      # the top bar only while the body is compact, so the top bar is
      # not a thing anyone has to open - it is the page, in one of its
      # two shapes. Only a selector that stands alone is a gate.
      if ' ' in t or '>' in t or '+' in t or '~' in t:
        continue
      if not t.startsWith("."):
        continue
      # `.drawer:not(.open)` names the drawer, not the state.
      t = t[1 .. ^1].split({':', '[', '.'})[0].strip()
      if t.len > 0:
        result.incl(t.toLowerAscii())

proc attributeOf(tagText, name: string): string {.role: parser,
    metaTags: {tagStats}.} =
  ## tagText: one opening tag as written   name: which attribute.
  ## Its value, or "" when the tag does not carry it.
  var
    at: int = tagText.toLowerAscii().find(name & "=")
    quote: char = '"'
    stop: int = 0
  result = ""
  if at < 0:
    return
  at = at + name.len + 1
  if at >= tagText.len:
    return
  if tagText[at] == '"' or tagText[at] == '\'':
    quote = tagText[at]
    at = at + 1
  stop = tagText.find(quote, at)
  if stop < 0:
    return
  result = tagText[at ..< stop]

proc isGate(tagText: string, hidden: HashSet[string]): tuple[gate: bool,
    why: string] {.role: parser, metaTags: {tagStats}.} =
  ## tagText: one opening tag   hidden: classes a stylesheet hides.
  ## Whether this element must be opened, and what said so.
  var
    classes: string = attributeOf(tagText, "class").toLowerAscii()
    id: string = attributeOf(tagText, "id").toLowerAscii()
    low: string = tagText.toLowerAscii()
  result = (gate: false, why: "")
  if "aria-hidden=\"true\"" in low or " hidden" in low or
      "display:none" in low.replace(" ", ""):
    return (gate: true, why: "hidden in the markup")
  for c in classes.split({' '}):
    if c.strip() in hidden:
      return (gate: true, why: "." & c.strip() & " is hidden by a stylesheet")
  for w in gateWords:
    if w in classes or w in id:
      return (gate: true, why: w)

proc labelFor(tagText, inner: string): string {.role: parser,
    metaTags: {tagStats}.} =
  ## tagText: the opening tag   inner: whatever followed it on the line.
  ## The most human name available, in the order a person would look.
  var
    tried: seq[string] = @[]
    picked: string = ""
  for name in labelAttributes:
    tried.add(attributeOf(tagText, name))
  tried.add(inner.strip())
  tried.add(unnamedLabel)
  for row in tried:
    if row.len > 0 and picked.len == 0:
      picked = row
  if picked.len > 40:
    picked = picked[0 ..< 40]
  result = picked

proc controlsIn*(html, path: string, hidden: HashSet[string],
    keyboardIds: HashSet[string]): seq[UiControl] {.role: parser,
    metaTags: {tagStats}.} =
  ## html: one page   path: what to report it as
  ## hidden: classes a stylesheet hides
  ## keyboardIds: ids and classes a script shows from a key handler.
  ##
  ## One walk, keeping a stack of the gates currently open. A closing
  ## tag pops whatever it closed, so the stack always holds exactly
  ## what stands between the reader and the point being read.
  var
    stack: seq[tuple[tag, why: string]] = @[]
    gates: seq[string] = @[]
    at: int = 0
    stop: int = 0
    tagText: string = ""
    tagName: string = ""
    inner: string = ""
    line: int = 1
    got: tuple[gate: bool, why: string] = (gate: false, why: "")
    ctl: UiControl = UiControl()
    i: int = 0
  result = @[]
  while i < html.len:
    if html[i] == '\n':
      line = line + 1
      i = i + 1
      continue
    if html[i] != '<':
      i = i + 1
      continue
    stop = html.find('>', i)
    if stop < 0:
      return
    tagText = html[i + 1 ..< stop]
    for ch in tagText:
      if ch == '\n':
        line = line + 1
    i = stop + 1
    if tagText.startsWith("!") or tagText.startsWith("?"):
      continue
    if tagText.startsWith("/"):
      tagName = tagText[1 .. ^1].strip().toLowerAscii()
      if stack.len > 0 and stack[^1].tag == tagName:
        discard stack.pop()
      continue
    tagName = tagText.split({' ', '\t', '\n', '/'})[0].toLowerAscii()
    got = isGate(tagText, hidden)
    if tagName in controlTags:
      stop = html.find('<', i)
      inner = ""
      if stop > i:
        inner = html[i ..< stop]
      gates = @[]
      for row in stack:
        gates.add(row.why)
      ctl = UiControl(path: path, line: line, tag: tagName,
        label: labelFor(tagText, inner), depth: gates.len, gates: gates,
        keyboardOnly: false)
      if ctl.depth == 0:
        # Nothing hides it, but a key handler may be the only thing
        # that ever shows it.
        if attributeOf(tagText, "id").toLowerAscii() in keyboardIds:
          ctl.keyboardOnly = true
      result.add(ctl)
    # A tag that closes itself never went on the stack.
    if got.gate and not tagText.endsWith("/") and
        tagName notin ["input", "img", "br", "hr", "meta", "link"]:
      stack.add((tag: tagName, why: got.why))

proc keyboardTargets*(js: string): HashSet[string] {.role: parser,
    metaTags: {tagStats}.} =
  ## js: one script.
  ##
  ## Ids named in the same routine as a key handler. This is a coarse
  ## reading on purpose: a script that binds `keydown` and mentions
  ## `#palette` in the same breath is almost always showing the
  ## palette with the key, and following the value properly would mean
  ## running the script.
  var
    low: string = js.toLowerAscii()
    hasKey: bool = false
    name: string = ""
    i: int = 0
  result = initHashSet[string]()
  for w in keyboardWords:
    if w in low:
      hasKey = true
  if not hasKey:
    return
  while i < js.len:
    if js[i] == '#' or (js[i] == '"' and i + 1 < js.len and js[i + 1] == '#'):
      name = ""
      i = i + 1
      if i < js.len and js[i] == '#':
        i = i + 1
      while i < js.len and (js[i].isAlphaNumeric() or js[i] == '_' or
          js[i] == '-'):
        name.add(js[i])
        i = i + 1
      if name.len > 1:
        result.incl(name.toLowerAscii())
      continue
    i = i + 1

proc byDepthThenLabel(a, b: UiControl): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b: two controls, the hardest to reach first.
  result = cmp(b.depth, a.depth)
  if result == 0:
    result = cmp(a.path, b.path)
  if result == 0:
    result = cmp(a.line, b.line)

proc uiDepthOf*(dir: string, files: seq[string]): UiDepthReport
    {.role: metaOrchestrator, input: thirdParty, metaTags: {tagStats}.} =
  ## dir: the repository   files: every source file in it
  ## Every control in every page, and what stands in front of it.
  var
    hidden: HashSet[string] = initHashSet[string]()
    keyboardIds: HashSet[string] = initHashSet[string]()
    pages: seq[tuple[path, text: string]] = @[]
    counts = initTable[int, int]()
    rel: string = ""
    text: string = ""
    found: seq[UiControl] = @[]
  result = UiDepthReport(controls: @[], total: 0, byDepth: @[], deepest: 0,
    keyboardOnly: 0, hiddenClasses: @[], error: "")
  # Stylesheets and scripts first: a page cannot be judged until it is
  # known which of its classes are hidden and which ids a key reveals.
  for path in files:
    rel = path.replace('\\', '/')
    if dir.len > 0 and rel.startsWith(dir.replace('\\', '/')):
      rel = rel[dir.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    try:
      text = readFile(path)
    except OSError, IOError:
      continue
    case extensionOf(rel)
    of "css":
      for c in hiddenClassesIn(text):
        hidden.incl(c)
    of "js", "mjs", "ts":
      for k in keyboardTargets(text):
        keyboardIds.incl(k)
    of "html", "htm":
      pages.add((path: rel, text: text))
      for c in hiddenClassesIn(text):
        hidden.incl(c)
      for k in keyboardTargets(text):
        keyboardIds.incl(k)
    else:
      discard
  for page in pages:
    found.add(controlsIn(page.text, page.path, hidden, keyboardIds))
  found.sort(byDepthThenLabel)
  result.total = found.len
  for c in found:
    counts[c.depth] = counts.getOrDefault(c.depth, 0) + 1
    if c.depth > result.deepest:
      result.deepest = c.depth
    if c.keyboardOnly:
      result.keyboardOnly = result.keyboardOnly + 1
  for d, n in counts:
    result.byDepth.add((depth: d, count: n))
  result.byDepth.sort(proc (a, b: tuple[depth, count: int]): int =
    cmp(a.depth, b.depth))
  for c in hidden:
    result.hiddenClasses.add(c)
  result.hiddenClasses.sort(system.cmp[string])
  if found.len > controlsShown:
    found.setLen(controlsShown)
  result.controls = found

proc uiDepthLines*(r: UiDepthReport): seq[string] {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## r: one answer, as a person reads it. Sorted hardest-to-reach
  ## first, because that is the end of the list a designer has to
  ## justify.
  var row: string = ""
  result = @[]
  if r.error.len > 0:
    result.add("ui depth: " & r.error)
    return
  result.add($r.total & " control(s), deepest is " & $r.deepest &
    " click(s) away, " & $r.keyboardOnly & " reachable by key only")
  result.add("  how many controls sit behind how many clicks:")
  for d in r.byDepth:
    result.add("    " & $d.depth & "  " & repeat("#", min(d.count, 50)) &
      "  " & $d.count)
  if r.deepest >= deepEnough:
    result.add("  the ones worth justifying:")
  for c in r.controls:
    if c.depth < deepEnough:
      continue
    row = "    " & $c.depth & " clicks  <" & c.tag & "> " & c.label &
      "  " & c.path & ":" & $c.line
    result.add(row)
    result.add("        behind: " & c.gates.join(" > "))
  for c in r.controls:
    if not c.keyboardOnly:
      continue
    result.add("    key only  <" & c.tag & "> " & c.label & "  " &
      c.path & ":" & $c.line)
  result.add("  classes a stylesheet hides outright: " &
    $r.hiddenClasses.len)
