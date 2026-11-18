## ================================================================
## | similar.nim  <-  `otter_repo_graph similar`                   |
## |---------------------------------------------------------------|
## | Which code, across folders and across languages, is alike?     |
## |                                                                |
## |   folders ─► files ─► chunks ─► vectors ─► pairs ─► clusters   |
## |   (repos)    js ts    (routine   shape,    SimHash   union-    |
## |              rs go    sized)     words     buckets   find      |
## |              py c                                              |
## |                                                                |
## | Use: before writing shared code, look at what is already       |
## | written many times. A cluster across many repos is a routine   |
## | that wants one home; its two distances say how alike it is:    |
## |                                                                |
## |   shape  0.02   built the same way (renamed copies are ~0)     |
## |   words  0.35   the names mostly agree                         |
## |                                                                |
## | It is a hint, not proof: a wrong chunk cut or a common idiom   |
## | gives a false match, so a person reads the cluster. Nothing is |
## | written into the folders it reads.                             |
## ================================================================

import std/[algorithm, json, os, strutils]
import runePragmas
import ../repo_graph/io_utils
import similar_types
import similar_chunks
import similar_vector
import similar_index
import similar_cluster

const
  readExts: array[16, string] = ["js", "ts", "tsx", "jsx", "mjs", "cjs", "rs", "go",
    "c", "h", "cc", "cpp", "hpp", "java", "kt", "py"]
  maxFileBytes: int64 = 1_000_000
  maxLineChars: int = 1500
  memberRows: int = 12

proc repoNameOf(root: string): string {.role: parser.} =
  ## root: a folder. Its own name, whatever slashes end the path.
  result = lastPathPart(normalizedPath(absolutePath(root)))

proc wantedFile(p: string): bool {.role: parser.} =
  ## p: a path. Is it a source file in a language this reads, of a size that
  ## is plausibly written by hand?
  var
    ext: string = extensionOf(p)
  result = ext in readExts
  if result:
    result = getFileSize(p) <= maxFileBytes

proc looksMinified(L: seq[string]): bool {.role: parser.} =
  ## L: the lines of a file. Does any line look machine-made (very long)?
  result = false
  for l in L:
    if l.len > maxLineChars:
      return true

proc textOf(C: seq[string], d: Decl): string {.role: dataFetcher.} =
  ## C: cleaned lines of a file   d: a found piece. Its cleaned lines joined.
  result = C[d.first .. d.last].join("\n")

proc chunksOfFile(repo, root, path: string, o: SimilarOptions): seq[Chunk] {.
    role: truthBuilder.} =
  ## repo: the folder's name   root: the folder   path: one file in it
  ## o: the options. The measured chunks of this file; none when it looks
  ## machine-made.
  var
    L: seq[string] = readLinesSafe(path)
    ext: string = extensionOf(path)
    R: tuple[ranges: seq[Decl], clean: seq[string]] = (ranges: @[], clean: @[])
    c: Chunk = Chunk()
  result = @[]
  if looksMinified(L):
    return
  R = chunkRanges(L, ext, o.minLines, o.maxLines)
  for d in R.ranges:
    c = Chunk(repo: repo, path: normalizeSlashes(relativePath(path, root)),
      name: d.name, lang: ext, first: d.first + 1, last: d.last + 1,
      lines: d.last - d.first + 1)
    fillVectors(c, textOf(R.clean, d), d.isFunc)
    result.add(c)

proc filesOf(root: string): seq[string] {.role: dataFetcher.} =
  ## root: a folder. Its own source files in stable order.
  result = @[]
  for p in ownFiles(root):
    if wantedFile(p):
      result.add(p)
  result.sort()

proc gather(roots: seq[string], o: SimilarOptions): tuple[chunks: seq[Chunk], files: int] {.
    role: orchestrator.} =
  ## roots: the folders   o: the options. All chunks of all folders.
  var
    F: seq[string] = @[]
    repo: string = ""
  result = (chunks: @[], files: 0)
  for r in roots:
    repo = repoNameOf(r)
    F = filesOf(r)
    result.files = result.files + F.len
    for p in F:
      result.chunks.add(chunksOfFile(repo, r, p, o))
  finishVectors(result.chunks)

proc similarOf*(roots: seq[string], o: SimilarOptions): SimilarReport {.
    role: orchestrator, tag: "graph|stats".} =
  ## roots: one or more folders (each is a "repo" in the answer)
  ## o: the options. Chunks, close pairs and clusters.
  var
    g: tuple[chunks: seq[Chunk], files: int] = (chunks: @[], files: 0)
    f: tuple[pairs: seq[Pair], skipped: int] = (pairs: @[], skipped: 0)
  result = SimilarReport()
  for r in roots:
    if not dirExists(r):
      result.error = "not a folder: " & r
      return
  g = gather(roots, o)
  f = findPairs(g.chunks, o)
  result.chunks = g.chunks
  result.files = g.files
  result.repos = roots.len
  result.pairs = f.pairs
  result.skippedBuckets = f.skipped
  result.clusters = clustersOf(g.chunks, f.pairs, o.by)

proc fmt2(x: float): string {.role: dataWriter.} =
  ## x: a distance. Two decimals.
  result = formatFloat(x, ffDecimal, 2)

proc placeOf(c: Chunk): string {.role: dataWriter.} =
  ## c: a chunk. "repo  path:first-last  name  (n lines)".
  result = c.repo.alignLeft(14) & " " & c.path & ":" & $c.first & "-" & $c.last & "  " &
    (if c.name.len > 0: c.name else: "(unnamed)") & "  (" & $c.lines & " lines)"

proc clusterLines(r: SimilarReport, k: int): seq[string] {.role: dataWriter.} =
  ## r: the answer   k: cluster number (0-based). Its printable lines.
  var
    c: Cluster = r.clusters[k]
    shown: int = min(memberRows, c.members.len)
  result = @["cluster " & $(k + 1) & ": " & $c.members.len & " chunks across " & $c.repos.len &
    " repos   shape " & fmt2(c.meanShape) & "  words " & fmt2(c.meanWords) &
    "  (" & $c.twins & " pairs of the same shape)"]
  result.add("  most typical: " & placeOf(r.chunks[c.centre]))
  for i in 0 ..< shown:
    result.add("    " & placeOf(r.chunks[c.members[i]]))
  if c.members.len > shown:
    result.add("    ... and " & $(c.members.len - shown) & " more")

proc pairLine(r: SimilarReport, p: Pair): string {.role: dataWriter.} =
  ## r: the answer   p: one pair. "shape words  a  <->  b".
  result = fmt2(p.shapeDist) & " " & fmt2(p.wordsDist) & "  " &
    placeOf(r.chunks[p.a]) & "  <->  " & placeOf(r.chunks[p.b])

proc similarLines*(r: SimilarReport, o: SimilarOptions): seq[string] {.
    role: dataWriter, tag: "graph|stats".} =
  ## r: the answer   o: the options. The report as printable lines.
  result = @[]
  if r.error.len > 0:
    return @["SIMILAR - " & r.error]
  result.add("SIMILAR - " & $r.chunks.len & " chunks in " & $r.repos & " folder(s) (" & $r.files &
    " files); " & $r.pairs.len & " pairs within " & fmt2(o.maxDist) & " by " & o.by &
    "; " & $r.clusters.len & " clusters")
  if r.skippedBuckets > 0:
    result.add("  " & $r.skippedBuckets & " bucket(s) skipped as too common to mean anything (--max-bucket)")
  result.add("  distance 0 = the same, 1 = nothing in common. shape: built alike. words: names agree.")
  for k in 0 ..< r.clusters.len:
    if o.top > 0 and k >= o.top:
      result.add("... " & $(r.clusters.len - o.top) & " more clusters (--top:0 shows all)")
      break
    result.add("")
    result.add(clusterLines(r, k))
  if o.pairsTop > 0:
    result.add("")
    result.add("closest pairs (shape words  a <-> b):")
    for i in 0 ..< min(o.pairsTop, r.pairs.len):
      result.add("  " & pairLine(r, r.pairs[i]))

proc chunkJson(c: Chunk): JsonNode {.role: dataWriter.} =
  ## c: a chunk. It as JSON.
  result = %*{"repo": c.repo, "path": c.path, "first": c.first, "last": c.last,
    "name": c.name, "lines": c.lines, "lang": c.lang}

proc clusterJson(r: SimilarReport, c: Cluster): JsonNode {.role: dataWriter.} =
  ## r: the answer   c: one cluster. It as JSON.
  var
    M: JsonNode = newJArray()
  for i in c.members:
    M.add(chunkJson(r.chunks[i]))
  result = %*{"repos": c.repos, "meanShape": c.meanShape, "meanWords": c.meanWords,
    "twins": c.twins, "centre": chunkJson(r.chunks[c.centre]), "members": M}

proc similarJson*(r: SimilarReport, o: SimilarOptions): string {.
    role: dataWriter, tag: "graph|stats".} =
  ## r: the answer   o: the options. The report as JSON text.
  var
    K: JsonNode = newJArray()
    P: JsonNode = newJArray()
  for k in 0 ..< r.clusters.len:
    if o.top > 0 and k >= o.top:
      break
    K.add(clusterJson(r, r.clusters[k]))
  for i in 0 ..< min(max(o.pairsTop, 0), r.pairs.len):
    P.add(%*{"shape": r.pairs[i].shapeDist, "words": r.pairs[i].wordsDist,
      "a": chunkJson(r.chunks[r.pairs[i].a]), "b": chunkJson(r.chunks[r.pairs[i].b])})
  result = pretty(%*{"error": r.error, "chunks": r.chunks.len, "folders": r.repos,
    "files": r.files, "pairs": r.pairs.len, "skippedBuckets": r.skippedBuckets,
    "maxDist": o.maxDist, "by": o.by, "clusters": K, "closest": P})
