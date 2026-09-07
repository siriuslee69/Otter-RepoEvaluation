# ============================================================
# | Otter Embedded Code Tests                                |
# | -> A string that holds a program, and which one          |
# ============================================================
#
# The case that started this: a `# otter:allow` comment was written onto
# a line of JavaScript living inside a Nim string. `#` is not a comment
# in JavaScript, so the generated page stopped working. Naming the
# language names the comment marks, which is the whole point.

import std/[strutils, unittest]

import ../../src/protocols/code_stats/embedded
import ../../meta/metaPragmas

proc nimHosting(body: string): seq[EmbeddedBlock] {.testKind: tkUnit,
    covers: "blocksIn".} =
  ## body: lines to put inside a Nim triple-quoted string.
  result = blocksIn("proc f(): string =\n  result = \"\"\"\n" & body &
    "\n  \"\"\"\n", "host.nim", "nim")

suite "embedded: a string that holds a program":

  # {.testKind: tkRegression.}
  test "html inside a nim string is html, and says how to comment it":
    ## pins: a `#` comment written onto embedded JavaScript was emitted
    ## into the generated page, where `#` is not a comment.
    var got = nimHosting("""<!doctype html>
<html><head><title>x</title></head>
<body><div class="a">hi</div></body>""")
    check got.len == 1
    check got[0].language == "html"
    check got[0].comment == "<!-- -->"

  # {.testKind: tkUnit.}
  test "javascript is told apart from html and gets slashes":
    var got = nimHosting("""function draw() {
  document.querySelector("#x").addEventListener("click", () => {
    console.log("hi");
  });
}""")
    check got.len == 1
    check got[0].language == "javascript"
    check got[0].comment == "//"

  # {.testKind: tkUnit.}
  test "c reached through nim's emit is found":
    var got = nimHosting("""#include <stdio.h>
int main(void) {
  size_t n = 0;
  printf("%zu", n);
}""")
    check got.len == 1
    check got[0].language == "c"

  # {.testKind: tkUnit.}
  test "an opencl kernel is not mistaken for c":
    var got = nimHosting("""__kernel void add(__global float4 *a) {
  int i = get_global_id(0);
  a[i] = a[i] + 1.0f;
}""")
    check got.len == 1
    check got[0].language == "opencl"

  # {.testKind: tkUnit.}
  test "python, css, sql, shell and assembly each answer to their own name":
    check nimHosting("""def go(items):
    for x in items:
        if x is None:
            raise ValueError("no")
    return True""")[0].language == "python"
    check nimHosting("""@media (max-width: 40rem) {
  .card { padding: 0; margin: 0; color: red; }
}""")[0].language == "css"
    check nimHosting("""SELECT id, name
FROM people
WHERE id > 3""")[0].language == "sql"
    check nimHosting("""#!/bin/sh
for f in *.txt; do
  echo "$f"
done""")[0].language == "shell"
    check nimHosting(""".globl _start
_start:
  movq $1, %rax
  pushq %rax""")[0].language == "assembly"

  # {.testKind: tkEdgeCase.}
  test "a language nobody listed is still reported, as other":
    ## The point of the whole file is that a string holds code. Which
    ## language is the smaller half, so an unknown one is `other`, not
    ## silence.
    var got = nimHosting("""fn main() {
  let mut total = 0;
  for i in 0..10 {
    total += i;
  }
}""")
    check got.len == 1
    check got[0].language == "other"
    check got[0].lines == 6

  # {.testKind: tkEdgeCase.}
  test "ordinary prose in a long string is not called code":
    var got = nimHosting("""This is a paragraph of documentation.
It runs to several lines and mentions nothing in particular.
There is no program here at all, only sentences.""")
    check got.len == 0

  # {.testKind: tkRegression.}
  test "a file is not reported as embedding itself":
    ## pins: a stray backtick in a JavaScript file opened a block that
    ## ran to the next one, turning fifty ordinary lines into a finding.
    var got = blocksIn("const a = `x`;\nfunction f() {\n" &
      "  document.querySelector(\"a\");\n  console.log(1);\n}\n" &
      "const b = `y`;\n", "app.js", "js")
    check got.len == 0

  # {.testKind: tkUnit.}
  test "a script tag in a page is javascript, a style tag is css":
    var page = "<!doctype html>\n<html><style>\n" &
      ".a { color: red; padding: 0; }\n@media print { .a { color: blue; } }\n" &
      "</style>\n<script>\nfunction go() {\n" &
      "  document.addEventListener(\"x\", () => console.log(1));\n}\n" &
      "</script></html>\n"
    var got = blocksIn(page, "page.html", "html")
    check got.len == 2
    var names: seq[string] = @[]
    for b in got:
      names.add(b.language)
    check "javascript" in names
    check "css" in names

  # {.testKind: tkRegression.}
  test "a template literal closed on its own line opens nothing":
    ## pins: a backtick string finished on the line it started swallowed
    ## every line up to the next backtick, and five lines of ordinary
    ## JavaScript were reported as embedded code.
    var body = "function paint(state, details) {\n" &
      "  bubble.className = `bubble glass is-${state}`;\n" &
      "  if (details.message) show(details.message);\n" &
      "  if (details.key) show(details.key);\n" &
      "  if (details.result) show(details.result);\n" &
      "  el.textContent = `${details.duration} ms`;\n}\n"
    check blocksIn(body, "dashboard.js", "js").len == 0

  # {.testKind: tkEdgeCase.}
  test "a one-line string is left alone":
    check blocksIn("var a = \"\"\"one line\"\"\"\n", "h.nim", "nim").len == 0

  # {.testKind: tkEdgeCase.}
  test "a host with no multi-line string yields nothing":
    check blocksIn("int x = 1;\nint y = 2;\n", "a.c", "c").len == 0
