# ============================================================
# | Otter Embedded Code                                      |
# | -> Another language living inside a string literal       |
# ============================================================
#
# A string is usually text. Sometimes it is a whole program:
#
#   proc buildHtml(): string =
#     result = """<!doctype html>
#     <script>
#       const state = { sortKey: "avg_ns_per_op" };
#     </script>"""
#
# Three lines of that are JavaScript, and Nim knows nothing about it.
# Neither did Otter, and that cost something real: a `# otter:allow`
# comment written onto the `sortKey` line put a `#` into the generated
# page, where `#` is not a comment and the script stops working. The
# right marker there is `//`. Knowing which language a block is written
# in is what tells a person - or a tool - which one to use.
#
# What is found, and how
# ----------------------
# Only string literals that can hold more than one line are looked at,
# because a one-line string is almost never a program:
#
#   host      opens        closes
#   --------  -----------  -----------
#   nim       """          """
#   python    """ or '''   the same
#   js / ts   `            `
#   html      <script>     </script>
#             <style>      </style>
#
# Each block is then read for declarations only one language writes.
# `#include` is C and nothing else. `__kernel` is OpenCL. `<!doctype`
# is HTML. A block that matches nothing recognisable is still reported,
# as `other`, because the fact that it IS code is the useful part; which
# language it is written in comes second.
#
# This is not a parser and must not grow into one. It reads for a
# handful of give-away words and counts them.

import std/[algorithm, os, strutils, tables]

import otterPragmas
import ../repo_graph/io_utils

const
  minBlockLines*: int = 2
    ## A block shorter than this is a piece of text, not a program.
  strongScore*: int = 3
    ## What one give-away word is worth. `#include` settles a question
    ## that ten semicolons only hint at.
  weakScore*: int = 1
  reportFloor*: int = 3
    ## Below this the block is not called code at all. One weak hint is
    ## noise; one strong word, or three weak ones, is a finding.
  blocksShown*: int = 40
    ## How many blocks travel to a window. The rest are counted.

type
  EmbeddedBlock* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One run of foreign code found inside a string.
    path*: string
    line*: int
      ## Where the block opens, counting the line the delimiter sits on.
    lines*: int
    language*: string
    comment*: string
      ## How a comment is written in that language, so anything adding
      ## one to these lines uses the right marks. Empty when unknown.
    score*: int
    reasons*: seq[string]

  EmbeddedReport* {.role: truthState, metaTags: {tagStats}.} = object
    ## Every block found, and the shape of the pile.
    blocks*: seq[EmbeddedBlock]
    total*: int
    totalLines*: int
    byLanguage*: seq[tuple[name: string, count: int, lines: int]]
    error*: string

  Signature = tuple[name, comment: string, strong, weak: seq[string]]

  Classification* = tuple[language, comment: string, score: int,
    reasons: seq[string]]
    ## What one block was judged to be. `language` is empty when the
    ## block is not code at all.

const
  signatures: array[11, Signature] = [
    ("html", "<!-- -->",
      @["<!doctype", "<html", "<body", "<head>", "</div>", "</span>"],
      @["<div", "<p>", "<a ", "<table", "class=", "href=", "</"]),
    ("css", "/* */",
      @["@media", "@keyframes", "!important"],
      @["px;", "rem;", "margin:", "padding:", "color:", "background:",
        "display:", "border:"]),
    ("javascript", "//",
      @["function ", "=>", "document.", "console.", "addEventListener",
        "querySelector"],
      @["const ", "let ", "var ", "return ", "null", "undefined",
        "typeof ", "new Set(", "JSON."]),
    ("typescript", "//",
      @["interface ", "implements ", "as const", ": Promise<",
        "readonly "],
      @[": string", ": number", ": boolean", "export type", "<T>"]),
    ("c", "//",
      @["#include", "int main(", "printf(", "malloc(", "size_t ",
        "typedef struct"],
      @["unsigned ", "->", "NULL", "sizeof(", "static void", "char *"]),
    ("opencl", "//",
      @["__kernel", "get_global_id", "__global", "__local",
        "barrier(CLK"],
      @["float4", "int4", "uchar", "clEnqueue"]),
    ("objectivec", "//",
      @["@interface", "@implementation", "NSString", "@autoreleasepool",
        "nonatomic"],
      @["[[", "alloc]", "@property", "NSObject"]),
    ("python", "#",
      @["def ", "elif ", "__init__", "self.", "lambda ", "if __name__"],
      @["None", "True", "False", "print(", "import ", "except ",
        "raise "]),
    ("assembly", ";",
      @[".globl", ".section", "movq ", "pushq ", "%rax", "%rsp",
        "xmm0"],
      @["mov ", "push ", "pop ", "jmp ", "ret", "call ", "nop"]),
    ("sql", "--",
      @["select ", "insert into", "create table", "left join"],
      @[" from ", " where ", " group by ", " order by "]),
    ("shell", "#",
      @["#!/bin/sh", "#!/bin/bash", "esac", "fi;"],
      @["echo ", "$(", "then", "done", "elif "])
  ]
    ## Words that only one language writes. Order does not matter: every
    ## signature is scored and the best one wins.

  hostDelimiters: array[7, tuple[ext, opens, closes: string]] = [
    ("nim", "\"\"\"", "\"\"\""),
    ("py", "\"\"\"", "\"\"\""),
    ("py", "'''", "'''"),
    ("js", "`", "`"),
    ("ts", "`", "`"),
    ("html", "<script", "</script>"),
    ("html", "<style", "</style>")
  ]
    ## Where a multi-line string can start, per host language. A host
    ## with two ways of opening one appears twice, and both are read.

  hostLanguages: array[5, tuple[ext, language: string]] = [
    ("js", "javascript"),
    ("ts", "typescript"),
    ("py", "python"),
    ("html", "html"),
    ("css", "css")
  ]
    ## What each host is written in. A block that reads as the language
    ## of the file holding it is not embedded code, it is the file, and
    ## saying otherwise is how a stray backtick in a JavaScript file
    ## turns fifty ordinary lines into a finding.

proc delimitersFor(ext: string): seq[tuple[opens, closes: string]]
    {.role: parser, metaTags: {tagStats}.} =
  ## ext: a file ending, lower case and without its dot.
  ## Every pair that opens and closes a multi-line string in that host.
  ## Empty when the host has none worth reading.
  result = @[]
  for row in hostDelimiters:
    if row.ext == ext:
      result.add((opens: row.opens, closes: row.closes))

proc languageOfHost(ext: string): string {.role: parser,
    metaTags: {tagStats}.} =
  ## ext: a file ending. What that file itself is written in, or "".
  result = ""
  for row in hostLanguages:
    if row.ext == ext:
      return row.language

proc scoreAgainst(text: string, s: Signature): tuple[score: int,
    reasons: seq[string]] {.role: math, metaTags: {tagStats}.} =
  ## text: the block, already lower case.
  ## s: one language's give-away words.
  ## How much this block looks like that language, and which words said
  ## so. Words are counted once each: ten semicolons are one hint about
  ## the language, not ten.
  var
    total: int = 0
    reasons: seq[string] = @[]
  for row in s.strong:
    if row.toLowerAscii() in text:
      total = total + strongScore
      reasons.add(row.strip())
  for row in s.weak:
    if row.toLowerAscii() in text:
      total = total + weakScore
  result = (score: total, reasons: reasons)

proc looksLikeCode*(text: string): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## text: one block of string contents.
  ##
  ## Whether the block is SHAPED like a program, without caring which
  ## language it is. This is what catches the ones the word lists miss -
  ## Rust, Lua, Zig, a shader language nobody here has heard of - so that
  ## such a block is reported as `other` rather than not at all. Knowing
  ## a string holds code is the useful part; the name comes second.
  ##
  ## Prose does not end its lines this way, and code mostly does:
  ##
  ##   a line ending in ; { } : or holding () or " = "   <- coded
  ##   half the non-empty lines or more are coded        <- a program
  var
    seen: int = 0
    coded: int = 0
    t: string = ""
  for line in text.splitLines():
    t = line.strip()
    if t.len == 0:
      continue
    seen = seen + 1
    if t.endsWith(";") or t.endsWith("{") or t.endsWith("}") or
        t.endsWith(":") or ("(" in t and ")" in t) or " = " in t:
      coded = coded + 1
  result = seen >= minBlockLines and coded * 2 >= seen

proc classify*(text: string): Classification {.role: truthBuilder,
    metaTags: {tagStats}.} =
  ## text: one block of string contents.
  ##
  ## The best-scoring language, or `other` when nothing recognisable is
  ## there but the block still reads as code. `other` is a real answer:
  ## the point is that a string holds a program, and naming the language
  ## is the smaller half of that.
  var
    low: string = text.toLowerAscii()
    best: int = 0
    bestName: string = ""
    bestComment: string = ""
    bestReasons: seq[string] = @[]
    got: tuple[score: int, reasons: seq[string]] = (score: 0, reasons: @[])
  result = (language: "", comment: "", score: 0, reasons: @[])
  for s in signatures:
    got = scoreAgainst(low, s)
    if got.score > best:
      best = got.score
      bestName = s.name
      bestComment = s.comment
      bestReasons = got.reasons
  if best < reportFloor:
    # No vocabulary matched. If the shape is a program's shape, say so
    # and leave the language open rather than throwing the block away.
    if looksLikeCode(text):
      return (language: "other", comment: "", score: reportFloor,
        reasons: @["shaped like code, no language recognised"])
    return
  result = (language: bestName, comment: bestComment, score: best,
    reasons: bestReasons)

proc blocksFor(text, path, host: string,
    d: tuple[opens, closes: string]): seq[EmbeddedBlock] {.role: parser,
    metaTags: {tagStats}.} =
  ## text: one whole file   path: what to report it as
  ## host: what the file itself is written in, or ""
  ## d: the pair that opens and closes one kind of multi-line string.
  ##
  ## Walks the file once, opening a block at the delimiter and closing it
  ## at the next one. A delimiter that opens and closes on the same line
  ## holds a one-line string, which is left alone.
  var
    inside: bool = false
    startLine: int = 0
    body: seq[string] = @[]
    n: int = 0
    got: Classification = (language: "", comment: "", score: 0, reasons: @[])
  result = @[]
  for line in text.splitLines():
    n = n + 1
    if not inside:
      if d.opens notin line:
        continue
      # A string that opens and closes on one line holds no program, and
      # opening a block on it swallows everything up to the next
      # delimiter. `const a = ` + backtick + `x` + backtick + `;` did
      # exactly that, turning five ordinary lines into a finding.
      if d.opens == d.closes and line.count(d.opens) mod 2 == 0:
        continue
      if d.opens != d.closes and d.closes in line:
        continue
      inside = true
      startLine = n
      body = @[]
      continue
    if d.closes notin line:
      body.add(line)
      continue
    inside = false
    if body.len < minBlockLines:
      continue
    got = classify(body.join("\n"))
    if got.score < reportFloor or got.language == host:
      continue
    result.add(EmbeddedBlock(path: path, line: startLine,
      lines: body.len, language: got.language, comment: got.comment,
      score: got.score, reasons: got.reasons))

proc blocksIn*(text, path, ext: string): seq[EmbeddedBlock]
    {.role: parser, metaTags: {tagStats}.} =
  ## text: one whole file   path: what to report it as
  ## ext: the host's file ending.
  ## Every foreign block in the file, across every kind of multi-line
  ## string the host writes.
  var
    host: string = languageOfHost(ext)
  result = @[]
  for d in delimitersFor(ext):
    result.add(blocksFor(text, path, host, d))

proc byScoreThenSize(a, b: EmbeddedBlock): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b: two blocks, the most certain and the largest first.
  result = cmp(b.score, a.score)
  if result == 0:
    result = cmp(b.lines, a.lines)
  if result == 0:
    result = cmp(a.path, b.path)

proc embeddedOf*(dir: string, files: seq[string]): EmbeddedReport
    {.role: metaOrchestrator, input: thirdParty, metaTags: {tagStats}.} =
  ## dir: the repository   files: every source file in it
  ## Every string in the tree that holds a program.
  var
    found: seq[EmbeddedBlock] = @[]
    rel: string = ""
    text: string = ""
    counts = initTable[string, tuple[count, lines: int]]()
    row: tuple[count, lines: int] = (count: 0, lines: 0)
  result = EmbeddedReport(blocks: @[], total: 0, totalLines: 0,
    byLanguage: @[], error: "")
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
    found.add(blocksIn(text, rel, extensionOf(rel)))
  found.sort(byScoreThenSize)
  result.total = found.len
  for b in found:
    result.totalLines = result.totalLines + b.lines
    row = counts.getOrDefault(b.language, (count: 0, lines: 0))
    row.count = row.count + 1
    row.lines = row.lines + b.lines
    counts[b.language] = row
  for name, v in counts:
    result.byLanguage.add((name: name, count: v.count, lines: v.lines))
  result.byLanguage.sort(proc (a, b: tuple[name: string, count,
      lines: int]): int = cmp(b.lines, a.lines))
  if found.len > blocksShown:
    found.setLen(blocksShown)
  result.blocks = found
