## ================================================================
## | continuity_page.nim  <-  a page as a tree of boxes             |
## |---------------------------------------------------------------|
## | The html side of the web reader. A page is read once into a    |
## | list of elements, parents before children, each knowing how    |
## | many elements sit inside it and whether it is hidden when the  |
## | page opens:                                                    |
## |                                                                |
## |   <section id="overview">          0  section#overview  13     |
## |     <h2>..</h2>                    1  h2                 1     |
## |     <ul><li>..</li> x6 </ul>       2  ul                 7     |
## |     <button id="open">             9  button#open        1     |
## |   </section>                                                   |
## |   <section id="settings" hidden>  10  section#settings   13  H |
## |                                                                |
## | (H = hidden at the start.) continuity_web.nim reads the        |
## | scripts and asks this tree where a pressed button stands.      |
## ================================================================

import std/[os, sets, strutils, tables]

import runePragmas
import ../repo_graph/io_utils
import ./ui_depth
import ./continuity_types
import ./continuity_style

const
  voidTags: array[14, string] = ["input", "img", "br", "hr", "meta", "link",
    "source", "col", "wbr", "area", "base", "embed", "param", "track"]
  hideWords*: array[3, string] = ["hidden", "is-hidden", "d-none"]
    ## Class names that hide an element whether or not a style sheet
    ## in the repository says so (the usual frameworks define them).

type
  Element* = object
    path*: string
    tag*: string
    id*: string
    classes*: seq[string]
    line*: int
    parent*: int
    size*: int
    startsHidden*: bool
    onclick*: string

  Script* = object
    path*: string
    line*: int
    text*: string
    pages*: seq[string]


# --- the page: elements ---------------------------------------------------

proc hiddenMark(tagText: string, classes: seq[string],
    hidden: HashSet[string]): bool {.role: parser, tag: "stats".} =
  ## tagText: one opening tag   classes: its classes   hidden: classes a
  ## style sheet hides. True when the element is hidden as the page opens.
  var
    low: string = tagText.toLowerAscii().multiReplace(("\n", " "),
      ("\t", " "))
  result = false
  for tok in low.split(' '):
    if tok == "hidden" or tok.startsWith("hidden="):
      result = true
  if "aria-hidden=\"true\"" in low or "display:none" in low.replace(" ", ""):
    result = true
  for c in classes:
    if c in hidden or c in hideWords:
      result = true

proc skipTo(html: string, at: int, marker: string): tuple[next, lines: int]
    {.role: parser, tag: "stats".} =
  ## html: the page   at: where to start   marker: the text that ends the span.
  ## The index after the marker, and how many newlines were passed.
  var
    stop: int = html.find(marker, at)
  if stop < 0:
    stop = html.len - marker.len
  result = (next: min(html.len, stop + marker.len),
    lines: html[at ..< min(html.len, stop + marker.len)].count('\n'))

proc newElement(tagText, path: string, line, parent: int,
    hidden: HashSet[string]): Element {.role: truthBuilder, tag: "stats".} =
  ## tagText: one opening tag   path/line: where   parent: index above it.
  var
    cls: string = attributeOf(tagText, "class")
  result = Element(path: path, tag: tagText.split({' ', '\t', '\n', '/'})[0]
    .toLowerAscii(), id: attributeOf(tagText, "id"), classes: @[],
    line: line, parent: parent, size: 1, startsHidden: false,
    onclick: attributeOf(tagText, "onclick"))
  for c in cls.toLowerAscii().split({' '}):
    if c.strip().len > 0:
      result.classes.add(c.strip())
  result.startsHidden = hiddenMark(tagText, result.classes, hidden)

proc popTo(stack: var seq[int], E: seq[Element], tagName: string)
    {.role: actor, tag: "stats".} =
  ## stack: the open elements   E: all so far   tagName: the one just closed.
  ## Closes the nearest open element of that name, and what was open inside it.
  var
    k: int = stack.len - 1
  while k >= 0 and E[stack[k]].tag != tagName:
    k = k - 1
  if k >= 0:
    stack.setLen(k)

proc noteScript(S: var seq[Script], srcs: var seq[string], tagName, tagText, path,
    html: string, line, a, b: int)
    {.role: actor, tag: "stats".} =
  ## S: scripts so far   tagName: script or style   tagText: the tag   path, line: where
  ## html: the page   a, b: the span between the tags.
  ## Keeps the text of a script written inside the page. One with a `src` is
  ## read from its own file; only its address is kept, so the file can be
  ## matched to the pages that load it.
  if tagName != "script":
    return
  if "src=" in tagText:
    srcs.add(attributeOf(tagText, "src"))
  else:
    S.add(Script(path: path, line: line, text: html[a ..< max(a, b)],
      pages: @[path]))

proc pageOf*(html, path: string, hidden: HashSet[string]): tuple[
    E: seq[Element], scripts: seq[Script], srcs: seq[string]] {.role: parser, tag: "stats".} =
  ## html: one page   path: what to report it as   hidden: hidden classes.
  ## Its elements in document order (parent before child), and the text
  ## of every script written inside it.
  var
    stack: seq[int] = @[]
    i: int = 0
    stop: int = 0
    line: int = 1
    tagText: string = ""
    tagName: string = ""
    skip: tuple[next, lines: int] = (next: 0, lines: 0)
    parent: int = -1
  result = (E: @[], scripts: @[], srcs: @[])
  while i < html.len:
    if html[i] == '\n':
      line = line + 1
    if html[i] != '<':
      i = i + 1
      continue
    if html.continuesWith("<!--", i):
      skip = skipTo(html, i, "-->")
      line = line + skip.lines
      i = skip.next
      continue
    stop = html.find('>', i)
    if stop < 0:
      return
    tagText = html[i + 1 ..< stop]
    line = line + tagText.count('\n')
    i = stop + 1
    if tagText.startsWith("!") or tagText.startsWith("?"):
      continue
    if tagText.startsWith("/"):
      popTo(stack, result.E, tagText[1 .. ^1].strip().toLowerAscii())
      continue
    tagName = tagText.split({' ', '\t', '\n', '/'})[0].toLowerAscii()
    if tagName in ["script", "style"]:
      skip = skipTo(html, i, "</" & tagName)
      noteScript(result.scripts, result.srcs, tagName, tagText, path, html, line,
        i, skip.next - tagName.len - 2)
      line = line + skip.lines
      i = skip.next
      continue
    parent = -1
    if stack.len > 0:
      parent = stack[^1]
    result.E.add(newElement(tagText, path, line, parent, hidden))
    if not tagText.endsWith("/") and tagName notin voidTags:
      stack.add(result.E.high)

proc sizesOf*(E: var seq[Element]) {.role: actor, tag: "stats".} =
  ## E: every element, parents before children. Fills in `size`: how many
  ## elements sit in each one, itself included.
  for i in countdown(E.high, 0):
    if E[i].parent >= 0:
      E[E[i].parent].size = E[E[i].parent].size + E[i].size

proc isInside*(E: seq[Element], child, box: int): bool {.role: parser,
    tag: "stats".} =
  ## E: every element   child, box: two of them.
  ## True when `child` is `box` or stands somewhere inside it.
  var
    k: int = child
  result = false
  while k >= 0:
    if k == box:
      return true
    k = E[k].parent

proc onScreenAtStart*(E: seq[Element], i: int): bool {.role: parser,
    tag: "stats".} =
  ## E: every element   i: one of them.
  ## False when it, or anything around it, is hidden as the page opens.
  var
    k: int = i
  result = true
  while k >= 0:
    if E[k].startsHidden:
      return false
    k = E[k].parent

proc nameOf*(e: Element): string {.role: helper, tag: "stats".} =
  ## e: one element. Its id as `#id`, else its first class, else its tag.
  if e.id.len > 0:
    result = "#" & e.id
  elif e.classes.len > 0:
    result = e.tag & "." & e.classes[0]
  else:
    result = "<" & e.tag & ">"


proc readText*(path: string): string {.role: dataFetcher, tag: "stats".} =
  ## path: one file. Its text, or "" when it cannot be read or is bigger than
  ## `maxFileBytes`.
  result = ""
  try:
    if getFileSize(path) <= maxFileBytes:
      result = readFile(path)
  except OSError, IOError:
    result = ""

proc addPage*(E: var seq[Element], more: seq[Element]) {.role: actor,
    tag: "stats".} =
  ## E: the elements so far   more: one more page's elements, parents before
  ## children. Adds them; their parent numbers move to stand after the earlier pages.
  var
    base: int = E.len
  for e in more:
    E.add(e)
    if e.parent >= 0:
      E[^1].parent = e.parent + base

proc hiddenByStyles*(files: seq[string]): HashSet[string] {.role: parser,
    input: thirdParty, tag: "stats".} =
  ## files: every source file. The classes a style sheet hides.
  result = initHashSet[string]()
  for p in files:
    if extensionOf(p) == "css":
      result.incl(hiddenClassesIn(readText(p)))

proc refKey(pagePath, src: string): string {.role: helper, tag: "stats".} =
  ## pagePath: a page, relative to the repository   src: a `<script src>` in it.
  ## The script's path relative to the repository, written the way the file
  ## list writes it.
  result = normalizeSlashes(normalizedPath(parentDir(pagePath) / src))

proc noteRefs*(R: var Table[string, seq[string]], pagePath: string,
    srcs: seq[string]) {.role: actor, tag: "stats".} =
  ## R: script path -> the pages that load it   pagePath, srcs: one page and
  ## the scripts it loads. Addresses on the web are not files of the repository.
  var
    key: string = ""
  for src in srcs:
    key = refKey(pagePath, src)
    if src.startsWith("http") or src.startsWith("//"):
      continue
    if key notin R:
      R[key] = @[]
    if pagePath notin R[key]:
      R[key].add(pagePath)


proc screensOf*(E: seq[Element]): Table[string, int] {.role: parser,
    tag: "stats".} =
  ## E: every element. For each page, how many elements are on screen as it opens
  ## (not hidden, and nothing around them hidden): the whole screen a press is
  ## measured against.
  result = initTable[string, int]()
  for i in 0 ..< E.len:
    if onScreenAtStart(E, i):
      result[E[i].path] = result.getOrDefault(E[i].path) + 1

proc hopsBetween*(E: seq[Element], a, b: int): int {.role: parser,
    tag: "stats".} =
  ## E: every element   a, b: two of them.
  ## The boxes on the way from a up to what holds both and down to b: 2 for
  ## neighbours, 0 for the same box, 10 when no box holds both (two pages).
  var
    chain: seq[int] = @[]
    k: int = a
    j: int = 0
  result = 10
  while k >= 0 and chain.len < 64:
    chain.add(k)
    k = E[k].parent
  k = b
  while k >= 0 and j < 64:
    if k in chain:
      return chain.find(k) + j
    k = E[k].parent
    j = j + 1

proc styleRulesOf*(files: seq[string]): seq[StyleRule] {.role: parser,
    input: thirdParty, tag: "stats".} =
  ## files: every source file. The rules of every style sheet among them.
  result = @[]
  for p in files:
    if extensionOf(p) == "css" and result.len < maxRules:
      result.add(styleRulesIn(readText(p)))
