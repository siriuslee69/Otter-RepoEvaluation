## ============================================================
## | Otter Similar Tests                                      |
## | -> alike code is found, unlike code is not, nothing      |
## |    crashes on rubbish                                    |
## ============================================================
##
## `examples/similar/` holds one routine written four times (ts, js,
## rs, py) and one unrelated routine. Every verdict below can be read
## off those thirty lines.
##
##   pair                          shape      meaning
##   ----------------------------  ---------  -----------------------
##   blend.ts  <-> mix.js          ~0         renamed copy
##   blend.ts  <-> blend.rs / .py  < 0.4      same idea, other language
##   blend.ts  <-> readHeader      > 0.4      unrelated

import std/[json, os, strutils, unittest]

import ../../src/protocols/code_stats/similar_types
import ../../src/protocols/code_stats/similar_chunks
import ../../src/protocols/code_stats/similar_vector
import ../../src/protocols/code_stats/similar_cluster
import ../../src/protocols/code_stats/similar
import runePragmas

proc exampleRoot(): string {.testKind: tkUnit, covers: "similarOf".} =
  ## The example folders, found from this file.
  result = parentDir(parentDir(parentDir(currentSourcePath()))) / "examples" / "similar"

proc exampleRoots(): seq[string] {.testKind: tkUnit, covers: "similarOf".} =
  ## repoA, repoB, repoC of the example.
  result = @[exampleRoot() / "repoA", exampleRoot() / "repoB", exampleRoot() / "repoC"]

proc exampleOptions(): SimilarOptions {.testKind: tkUnit, covers: "similarOf".} =
  ## The options the example README uses.
  result = defaultSimilarOptions()
  result.minLines = 8
  result.maxDist = 0.4
  result.across = true

proc rangesOf(src, ext: string): seq[Decl] {.testKind: tkUnit, covers: "chunkRanges".} =
  ## src: source text   ext: file ending. The pieces found, minimum 2 lines.
  result = chunkRanges(src.splitLines(), ext, 2, 400).ranges

proc shapeOf(src: string): seq[uint8] {.testKind: tkUnit, covers: "tokenize".} =
  ## src: one piece of code. Its shape classes.
  result = tokenize(src).shape

suite "similar - cutting files":
  # {.testKind: tkUnit.}
  test "brace languages: functions are found with their names":
    var
      D: seq[Decl] = rangesOf("function a(x) {\n  return x;\n}\n\nexport async function b(y) {\n  return y + 1;\n}\n", "js")
    check D.len == 2
    check D[0].name == "a" and D[1].name == "b"
    D = rangesOf("const add = (p, q) => {\n  return p + q;\n};\n", "ts")
    check D.len == 1 and D[0].name == "add"
    D = rangesOf("fn b(y: i32) -> i32 {\n  let z = y;\n  z + 1\n}\n", "rs")
    check D.len == 1 and D[0].name == "b"
    D = rangesOf("func (r *T) Run(n int) int {\n  n++\n  return n\n}\n", "go")
    check D.len == 1 and D[0].name == "Run"

  # {.testKind: tkUnit.}
  test "python: the block ends where the indent ends":
    var
      D: seq[Decl] = rangesOf("def f(a):\n    x = a\n    return x\n\nz = 1\n", "py")
    check D.len == 1 and D[0].first == 0 and D[0].last == 2

  # {.testKind: tkUnit.}
  test "a class that holds methods gives way to its methods":
    var
      D: seq[Decl] = rangesOf("class K {\n  a() {\n    return 1;\n  }\n  b() {\n    return 2;\n  }\n}\n", "ts")
    check D.len == 2
    check D[0].name == "a" and D[1].name == "b"

  # {.testKind: tkEdgeCase.}
  test "a brace inside a string or a comment does not count":
    var
      D: seq[Decl] = rangesOf("function a() {\n  var s = \"}}}\";\n  // }\n  /* } */\n  return s;\n}\n", "js")
    check D.len == 1 and D[0].last == 5

  # {.testKind: tkEdgeCase.}
  test "rust lifetimes and character literals do not open a string":
    var
      D: seq[Decl] = rangesOf("fn pick<'a>(x: &'a str) -> &'a str {\n  let c = '{';\n  x\n}\n", "rs")
    check D.len == 1 and D[0].last == 3

  # {.testKind: tkEdgeCase.}
  test "an unclosed brace drops the piece instead of swallowing the file":
    check rangesOf("function a() {\n  return 1;\n", "js").len == 0

  # {.testKind: tkEdgeCase.}
  test "an empty file and a file of blanks give nothing":
    check rangesOf("", "js").len == 0
    check rangesOf("\n\n   \n", "py").len == 0

suite "similar - shapes":
  # {.testKind: tkUnit.}
  test "type annotations and generics do not change the shape":
    check shapeOf("function f(a: number[], b: Map<string, number>): number { return a; }") ==
      shapeOf("function f(a, b) { return a; }")
    check shapeOf("fn f(a: &[f32]) -> Vec<f32> { a }") == shapeOf("fn f(a) { a }")

  # {.testKind: tkUnit.}
  test "renaming every name leaves the shape alone":
    check shapeOf("for (i = 0; i < n; i++) { s = s + a[i]; }") ==
      shapeOf("for (k = 0; k < m; k++) { t = t + b[k]; }")

  # {.testKind: tkUnit.}
  test "words: names are cut at capitals and underscores":
    check splitWords("retypeText") == @["retype", "text"]
    check splitWords("blend_rows") == @["blend", "rows"]
    check splitWords("i") == newSeq[string]()

suite "similar - the example":
  # {.testKind: tkIntegration.}
  test "the four blend routines form one cluster, the header reader stays out":
    var
      r: SimilarReport = similarOf(exampleRoots(), exampleOptions())
    check r.error == ""
    check r.chunks.len == 5
    check r.clusters.len == 1
    check r.clusters[0].members.len == 4
    check r.clusters[0].repos == @["repoA", "repoB", "repoC"]

  # {.testKind: tkIntegration.}
  test "a renamed copy is at shape distance zero, another language is near":
    var
      r: SimilarReport = similarOf(exampleRoots(), exampleOptions())
      best: float = 1.0
    check r.pairs.len > 0
    for p in r.pairs:
      best = min(best, p.shapeDist)
    check best < 0.01
    check r.pairs[0].twin

  # {.testKind: tkEdgeCase.}
  test "across keeps only pairs from different folders":
    var
      o: SimilarOptions = exampleOptions()
      r: SimilarReport = SimilarReport()
    o.across = true
    r = similarOf(exampleRoots(), o)
    for p in r.pairs:
      check r.chunks[p.a].repo != r.chunks[p.b].repo

  # {.testKind: tkEdgeCase.}
  test "a missing folder is an error, not a crash":
    check similarOf(@["/no/such/folder"], defaultSimilarOptions()).error.len > 0

  # {.testKind: tkUnit.}
  test "the json answer parses and names the clusters":
    var
      r: SimilarReport = similarOf(exampleRoots(), exampleOptions())
      j: JsonNode = parseJson(similarJson(r, exampleOptions()))
    check j["clusters"].len == 1
    check j["clusters"][0]["members"].len == 4

suite "similar - rubbish in":
  # {.testKind: tkFuzz.}
  test "random punctuation never raises or hangs":
    var
      seed: uint32 = 12345
      src: string = ""
      D: tuple[ranges: seq[Decl], clean: seq[string]] = (ranges: @[], clean: @[])
    for round in 0 ..< 60:
      src = ""
      for k in 0 ..< 400:
        seed = seed * 1664525'u32 + 1013904223'u32
        src.add("{}()[]<>:;\"'`/*#\\ \nabc fn def function class 12=>-"[int(seed shr 24) mod 48])
      for ext in ["js", "rs", "py", "go", "c"]:
        D = chunkRanges(src.splitLines(), ext, 2, 400)
        discard tokenize(src)
        check D.ranges.len >= 0

  # {.testKind: tkEdgeCase.}
  test "binary-looking text is read without a crash":
    var
      src: string = ""
    for i in 0 ..< 3000:
      src.add(char(i mod 251 + 1))
    check chunkRanges(src.splitLines(), "c", 2, 400).ranges.len >= 0

proc writeSample(root, repo, name, body: string) {.testKind: tkUnit, covers: "similarOf".} =
  ## root: a scratch folder   repo: the folder inside it   name: the file
  ## body: its text. Writes one sample file.
  createDir(root / repo)
  writeFile(root / repo / name, body)

suite "similar - type definitions":
  # {.testKind: tkIntegration.}
  test "types with the same fields match by their words; others do not":
    var
      root: string = getTempDir() / ("otter_similar_types_" & $getCurrentProcessId())
      o: SimilarOptions = defaultSimilarOptions()
      r: SimilarReport = SimilarReport()
    writeSample(root, "one", "a.ts", "export interface Layer {\n  id: string;\n  name: string;\n  opacity: number;\n  blendMode: string;\n  visible: boolean;\n  locked: boolean;\n  maskId: string;\n  parentId: string;\n  order: number;\n  createdAt: number;\n}\n")
    writeSample(root, "two", "b.ts", "export interface LayerItem {\n  id: string;\n  name: string;\n  opacity: number;\n  blendMode: string;\n  visible: boolean;\n  locked: boolean;\n  maskId: string;\n  parentId: string;\n  order: number;\n  updatedAt: number;\n}\n")
    writeSample(root, "three", "c.ts", "export interface Invoice {\n  amount: number;\n  currency: string;\n  customer: string;\n  address: string;\n  dueDate: number;\n  taxRate: number;\n  reference: string;\n  paid: boolean;\n  reminder: number;\n  notes: string;\n}\n")
    o.across = true
    o.maxDist = 0.3
    o.minLines = 10
    r = similarOf(@[root / "one", root / "two", root / "three"], o)
    removeDir(root)
    check r.chunks.len == 3
    check r.clusters.len == 1
    check r.clusters[0].members.len == 2
    check r.pairs[0].byWords

  # {.testKind: tkEdgeCase.}
  test "a type is never paired with a routine":
    var
      root: string = getTempDir() / ("otter_similar_mixed_" & $getCurrentProcessId())
      o: SimilarOptions = defaultSimilarOptions()
      r: SimilarReport = SimilarReport()
    writeSample(root, "one", "a.ts", "export interface Layer {\n  id: string;\n  name: string;\n  opacity: number;\n  blendMode: string;\n  visible: boolean;\n  locked: boolean;\n  maskId: string;\n  parentId: string;\n  order: number;\n  createdAt: number;\n}\n")
    writeSample(root, "two", "b.ts", "export function layerName(id: string): string {\n  var out = \"\";\n  for (var i = 0; i < id.length; i++) {\n    if (id[i] != \"-\") {\n      out = out + id[i];\n    }\n  }\n  var blendMode = out;\n  return blendMode;\n}\n")
    o.across = true
    o.maxDist = 0.9
    o.minLines = 8
    r = similarOf(@[root / "one", root / "two"], o)
    removeDir(root)
    check r.pairs.len == 0

suite "similar - groups do not chain":
  # {.testKind: tkProperty.}
  test "a long chain of close pairs never becomes one big group":
    var
      C: seq[Chunk] = @[]
      P: seq[Pair] = @[]
      K: seq[Cluster] = @[]
      widest: int = 0
    for i in 0 ..< 12:
      C.add(Chunk(repo: "r" & $i, path: "f" & $i, name: "n" & $i, lines: 10))
    for i in 0 ..< 11:
      P.add(Pair(a: i, b: i + 1, shapeDist: 0.1, wordsDist: 0.1, twin: false, byWords: false))
    K = clustersOf(C, P, "shape")
    for k in K:
      widest = max(widest, k.members.len)
    check K.len >= 3
    check widest <= 3

  # {.testKind: tkUnit.}
  test "a centre and its partners form one group with its numbers":
    var
      C: seq[Chunk] = @[]
      P: seq[Pair] = @[]
      K: seq[Cluster] = @[]
    for i in 0 ..< 4:
      C.add(Chunk(repo: (if i < 2: "a" else: "b"), path: "f" & $i, name: "n", lines: 10))
    P.add(Pair(a: 0, b: 1, shapeDist: 0.0, wordsDist: 0.2, twin: true, byWords: false))
    P.add(Pair(a: 0, b: 2, shapeDist: 0.1, wordsDist: 0.4, twin: false, byWords: false))
    P.add(Pair(a: 0, b: 3, shapeDist: 0.1, wordsDist: 0.6, twin: false, byWords: false))
    K = clustersOf(C, P, "shape")
    check K.len == 1
    check K[0].centre == 0
    check K[0].members == @[0, 1, 2, 3]
    check K[0].repos == @["a", "b"]
    check K[0].twins == 1
