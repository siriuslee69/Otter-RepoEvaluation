## ================================================================
## | similar_vector.nim  <-  a chunk as two lists of numbers        |
## |---------------------------------------------------------------|
## | SHAPE: read the chunk as a stream of small classes.            |
## |                                                                |
## |   for (let i = 0; i < n; i++) { out.push(a * b); }             |
## |     ──►  LOOP DECL I ASSIGN N I CMP I INC  I DOT C I MUL I     |
## |                                                                |
## |   names become I (a name) or C (a name that is called),        |
## |   numbers N, strings S; `for`, `loop`, `while` all become LOOP |
## |   and `fn`, `function`, `def`, `func` all become FUNC, so the  |
## |   same routine in another language reads almost the same.      |
## |   Brackets and separators are left out: they differ between    |
## |   languages and say little.                                    |
## |                                                                |
## |   Every run of 1, 2 and 3 classes is counted into one of 512   |
## |   places (the place is the run's hash). That list, with square |
## |   roots to tame big counts and scaled to length 1, is the      |
## |   shape vector.                                                |
## |                                                                |
## | WORDS: the names, cut into words and counted the same way:     |
## |   `retypeText` -> retype, text.                                |
## |                                                                |
## | WEIGHTS: a run that every routine has says nothing, a rare one  |
## |   does: each place is weighed by log(N / chunks that use it)    |
## |   once all chunks are known (finishVectors).                   |
## |                                                                |
## | SIMHASH: 64 bits that summarise the shape; chunks with alike   |
## |   shapes get alike bits. similar_index.nim uses it to find     |
## |   candidates without comparing everything with everything.     |
## |                                                                |
## | distance = 1 - cosine(a, b): 0 the same, 1 nothing in common.  |
## ================================================================

import std/[strutils, math]
import runePragmas
import similar_types

const
  tkName: uint8 = 1
  tkCall: uint8 = 2
  tkNumber: uint8 = 3
  tkString: uint8 = 4
  tkFunc: uint8 = 5
  tkDecl: uint8 = 6
  tkLoop: uint8 = 7
  tkIf: uint8 = 8
  tkElse: uint8 = 9
  tkMatch: uint8 = 10
  tkReturn: uint8 = 11
  tkTry: uint8 = 12
  tkType: uint8 = 14
  tkIn: uint8 = 15
  tkNew: uint8 = 16
  tkLit: uint8 = 17
  tkAnd: uint8 = 18
  tkOr: uint8 = 19
  tkNot: uint8 = 20
  tkDot: uint8 = 21
  tkAssign: uint8 = 22
  tkEq: uint8 = 23
  tkCmp: uint8 = 24
  tkAdd: uint8 = 25
  tkMul: uint8 = 26
  tkInc: uint8 = 27
  tkOpAssign: uint8 = 28
  tkLBrack: uint8 = 29
  tkRBrack: uint8 = 30
  tkRange: uint8 = 31
  tkQuery: uint8 = 32
  tkAmp: uint8 = 33
  tkPipe: uint8 = 34
  tkShift: uint8 = 35
  tkAwait: uint8 = 36
  tkSkip: uint8 = 0
  minTokens: int = 24
  dataShareLimit: int = 55
  minNames: int = 6
  stopWords: array[24, string] = ["self", "this", "true", "false", "null", "none",
    "undefined", "const", "string", "number", "int", "bool", "void", "return",
    "new", "var", "let", "len", "for", "the", "and", "not", "str", "usize"]

proc wordClass(w: string): uint8 {.role: parser.} =
  ## w: a name or keyword as written. The class it counts as in a shape.
  ## 0 means "leave it out"; 1 means an ordinary name.
  case w
  of "function", "fn", "func", "def", "lambda": result = tkFunc
  of "for", "while", "loop", "do", "foreach": result = tkLoop
  of "if", "elif", "unless": result = tkIf
  of "else": result = tkElse
  of "switch", "match", "when", "case": result = tkMatch
  of "return", "yield": result = tkReturn
  of "try", "catch", "except", "finally", "throw", "raise", "defer": result = tkTry
  of "class", "struct", "impl", "trait", "interface", "enum", "type": result = tkType
  of "in", "of": result = tkIn
  of "true", "false", "null", "nil", "None", "undefined": result = tkLit
  of "and": result = tkAnd
  of "or": result = tkOr
  of "not": result = tkNot
  of "let", "const", "var", "val", "auto", "new", "await", "dyn", "ref",
     "pub", "export", "public", "private", "protected", "static", "async", "mut",
     "self", "this", "use", "import", "from", "package", "mod", "as", "where",
     "pass", "with", "default", "final", "readonly", "unsafe", "extern", "inline",
     "get", "set", "override", "abstract", "declare":
    result = tkSkip
  else: result = tkName

proc isStart(c: char): bool {.inline, role: helper.} =
  ## c: a character. Can it begin a name?
  result = c in {'a'..'z', 'A'..'Z', '_', '$'}

proc isPart(c: char): bool {.inline, role: helper.} =
  ## c: a character. Can it continue a name?
  result = c in {'a'..'z', 'A'..'Z', '0'..'9', '_', '$'}

proc nextNonBlank(t: string, from0: int): char {.role: parser.} =
  ## t: the text   from0: where to look from. The next character that is
  ## not a blank, or '\0'.
  var
    i: int = from0
  result = '\0'
  while i < t.len and t[i] in {' ', '\t', '\n', '\r'}:
    i = i + 1
  if i < t.len:
    result = t[i]

proc operatorClass(t: string, i: int): tuple[cls: uint8, width: int] {.role: parser.} =
  ## t: the text   i: index of a symbol. Its class (0 = leave out) and
  ## how many characters it takes.
  var
    c: char = t[i]
    n: char = (if i + 1 < t.len: t[i + 1] else: '\0')
    n2: char = (if i + 2 < t.len: t[i + 2] else: '\0')
  result = (cls: tkSkip, width: 1)
  if c == '&' and n == '&':
    result = (cls: tkAnd, width: 2)
  elif c == '|' and n == '|':
    result = (cls: tkOr, width: 2)
  elif (c == '=' and n == '=') or (c == '!' and n == '='):
    result = (cls: tkEq, width: (if n2 == '=': 3 else: 2))
  elif c == '=' and n == '>':
    result = (cls: tkSkip, width: 2)
  elif c == '-' and n == '>':
    result = (cls: tkSkip, width: 2)
  elif c == ':' and n == ':':
    result = (cls: tkDot, width: 2)
  elif c == '.' and n == '.':
    result = (cls: tkRange, width: (if n2 in {'.', '='}: 3 else: 2))
  elif (c == '+' and n == '+') or (c == '-' and n == '-'):
    result = (cls: tkInc, width: 2)
  elif (c == '<' and n == '<') or (c == '>' and n == '>'):
    result = (cls: tkShift, width: 2)
  elif c in {'+', '-', '*', '/', '%', '&', '|', '^'} and n == '=':
    result = (cls: tkOpAssign, width: 2)
  elif c in {'<', '>'}:
    result = (cls: tkCmp, width: (if n == '=': 2 else: 1))
  elif c == '=':
    result = (cls: tkAssign, width: 1)
  elif c in {'+', '-'}:
    result = (cls: tkAdd, width: 1)
  elif c in {'*', '/', '%'}:
    result = (cls: tkMul, width: 1)
  elif c == '.':
    result = (cls: tkDot, width: 1)
  elif c == '!':
    result = (cls: tkNot, width: 1)
  elif c == '[':
    result = (cls: tkLBrack, width: 1)
  elif c == ']':
    result = (cls: tkRBrack, width: 1)
  elif c == '?':
    result = (cls: tkQuery, width: 1)
  elif c == '&':
    result = (cls: tkAmp, width: 1)
  elif c == '|':
    result = (cls: tkPipe, width: 1)

proc pushWord(w: string, called: bool, S: var seq[uint8], N: var seq[string]) {.role: actor.} =
  ## w: a name or keyword   called: is it followed by `(`?
  ## S: shape classes so far   N: names so far. Adds what `w` counts as.
  var
    k: uint8 = wordClass(w)
  if w == "elif":
    S.add(tkElse)
    S.add(tkIf)
  elif k == tkName:
    S.add(if called: tkCall else: tkName)
    N.add(w)
  elif k != tkSkip:
    S.add(k)

proc skipBlanks(t: string, i: int): int {.role: parser.} =
  ## t: the text   i: a place. The place after any spaces and tabs.
  result = i
  while result < t.len and t[result] in {' ', '\t'}:
    result = result + 1

proc skipWordPath(t: string, i: int): int {.role: parser.} =
  ## t: the text   i: where a name starts. The place after the name and its
  ## `::` or `.` pieces (`std::vec::Vec`, `a.b.C`).
  result = i
  while result < t.len:
    if isPart(t[result]):
      result = result + 1
    elif t.continuesWith("::", result) and result + 2 < t.len and isStart(t[result + 2]):
      result = result + 2
    elif t[result] == '.' and result + 1 < t.len and isStart(t[result + 1]):
      result = result + 1
    else:
      break

proc genericSpan(t: string, i: int): int {.role: parser.} =
  ## t: the text   i: index of a `<`. The place after the matching `>` when
  ## this is a type argument list (`Vec<f32>`, `Map<string, int>`), or -1
  ## when it is a comparison. A comparison has spaces around `<`.
  var
    depth: int = 0
    j: int = i + 1
    stop: int = min(t.len - 1, i + 80)
  result = -1
  if i == 0 or i + 1 >= t.len:
    return
  if not (isPart(t[i - 1]) or t[i - 1] == ':'):
    return
  if not (isStart(t[i + 1]) or t[i + 1] in {'&', '\'', '*'}):
    return
  depth = 1
  while j <= stop and result < 0:
    if t[j] == '<':
      depth = depth + 1
    elif t[j] == '>':
      depth = depth - 1
      if depth == 0:
        result = j + 1
    elif not (isPart(t[j]) or t[j] in {' ', ',', ':', '&', '*', '\'', '[', ']', '.', '|'}):
      return -1
    j = j + 1

proc skipSuffixes(t: string, i: int): int {.role: parser.} =
  ## t: the text   i: the place after a type's name. The place after what
  ## hangs on it: `<...>`, `[]`, `[3]` and `?`.
  var
    j: int = i
    k: int = 0
    more: bool = true
  while more and j < t.len:
    more = false
    if t[j] == '<':
      k = genericSpan(t, j)
      more = k > 0
      j = (if more: k else: j)
    elif t[j] == '[' and t.find(']', j) in j + 1 .. j + 6:
      j = t.find(']', j) + 1
      more = true
    elif t[j] == '?':
      j = j + 1
      more = true
  result = j

proc skipType*(t: string, i0: int): int {.role: parser.} =
  ## t: the text   i0: where a type starts (after `:` or `->`).
  ## The place after the type, unions (`a | b`) and references included.
  ## It never reads more than a few pieces.
  var
    i: int = skipBlanks(t, i0)
    j: int = 0
    guard: int = 0
    more: bool = true
  while more and guard < 8:
    guard = guard + 1
    while i < t.len and t[i] in {'&', '*'}:
      i = i + 1
    if t.continuesWith("mut ", i):
      i = i + 4
    if i < t.len and t[i] == '\'':
      i = skipBlanks(t, skipWordPath(t, i + 1))
    i = skipSuffixes(t, skipWordPath(t, i))
    j = skipBlanks(t, i)
    more = j + 1 < t.len and t[j] == '|' and t[j + 1] != '|' and isStart(t[skipBlanks(t, j + 1)])
    if more:
      i = skipBlanks(t, j + 1)
  result = i

proc typeMarkerWidth(t: string, i: int): int {.role: parser.} =
  ## t: the text   i: index of a symbol. How many characters of marker come
  ## before a type that is only a note for the compiler (`name: Type`,
  ## `) -> Type`), or 0 when this is not such a marker.
  var
    prev: char = (if i > 0: t[i - 1] else: ' ')
    j: int = 0
  result = 0
  if t[i] == ':' and i + 2 < t.len and t[i + 1] == ' ' and t[i + 2] != ':':
    if prev != ':' and (isPart(prev) or prev in {')', '?'}) and (isStart(t[i + 2]) or t[i + 2] in {'&', '*', '\'', '['}):
      j = i + 2
      while j < t.len and isPart(t[j]):
        j = j + 1
      if t[i + 2] notin {'a'..'z', 'A'..'Z', '_', '$'} or wordClass(t[i + 2 ..< j]) == tkName:
        result = 1
  elif t.continuesWith("-> ", i):
    result = 2

proc tokenize*(text: string): tuple[shape: seq[uint8], names: seq[string]] {.role: parser.} =
  ## text: cleaned source of one chunk.
  ## The shape classes in order, and the names in order. Stops reading at
  ## maxShapeKeep classes.
  var
    i: int = 0
    j: int = 0
    o: tuple[cls: uint8, width: int] = (cls: tkSkip, width: 1)
  result = (shape: @[], names: @[])
  while i < text.len and result.shape.len < maxShapeKeep:
    if isStart(text[i]):
      j = i
      while j < text.len and isPart(text[j]):
        j = j + 1
      pushWord(text[i ..< j], nextNonBlank(text, j) == '(', result.shape, result.names)
      i = j
    elif text[i] in {'0'..'9'}:
      while i < text.len and (text[i] in {'0'..'9', '.', '_', 'x', 'X'} or text[i] in {'a'..'f', 'A'..'F'}):
        i = i + 1
      result.shape.add(tkNumber)
    elif text[i] == '"' and text.continuesWith("\"s\"", i):
      result.shape.add(tkString)
      i = i + 3
    elif typeMarkerWidth(text, i) > 0:
      i = skipType(text, i + typeMarkerWidth(text, i))
    elif text[i] == '<' and genericSpan(text, i) > 0:
      i = genericSpan(text, i)
    else:
      o = operatorClass(text, i)
      if o.cls != tkSkip:
        result.shape.add(o.cls)
      i = i + o.width

proc mix64(x: uint64): uint64 {.inline, role: math.} =
  ## x: a number. A well-scrambled copy of it (splitmix64 finishing steps).
  var
    z: uint64 = x
  z = (z xor (z shr 30)) * 0xbf58476d1ce4e5b9'u64
  z = (z xor (z shr 27)) * 0x94d049bb133111eb'u64
  result = z xor (z shr 31)

proc hashStep(h: uint64, t: uint64): uint64 {.inline, role: math.} =
  ## h: the hash so far   t: the next class. The hash after adding it.
  result = (h xor (t + 0x9e3779b97f4a7c15'u64)) * 0x100000001b3'u64

proc splitWords*(name: string): seq[string] {.role: parser.} =
  ## name: `retypeText`, `blend_rows`, `HTTPServer`. Its words, lower case,
  ## each of three letters or more and not a filler word.
  var
    cur: string = ""
    prevLower: bool = false
  result = @[]
  for c in name:
    if c in {'_', '$', '-'} or (c in {'A'..'Z'} and prevLower):
      if cur.len >= 3 and cur notin stopWords:
        result.add(cur)
      cur = ""
    if c notin {'_', '$', '-'}:
      cur.add(c.toLowerAscii())
    prevLower = c in {'a'..'z', '0'..'9'}
  if cur.len >= 3 and cur notin stopWords:
    result.add(cur)

proc normalize(V: var seq[float32]) {.role: math.} =
  ## V: counts. Replaces each by its square root and scales the list to
  ## length 1, so a long chunk and a short one built alike are close.
  var
    t: float = 0.0
  for i in 0 ..< V.len:
    V[i] = sqrt(V[i])
    t = t + float(V[i]) * float(V[i])
  if t > 0.0:
    t = sqrt(t)
    for i in 0 ..< V.len:
      V[i] = float32(float(V[i]) / t)

proc shapeVector(S: seq[uint8]): tuple[v: seq[float32], twin: uint64] {.role: math.} =
  ## S: the shape classes. The shape vector (before the corpus weighting of
  ## `finishVectors`), and one hash of the whole sequence (equal for chunks
  ## of exactly the same shape).
  var
    V: seq[float32] = newSeq[float32](shapeDim)
    h1: uint64 = 0
    h2: uint64 = 0
    h3: uint64 = 0
    t: uint64 = 0
    all: uint64 = 1469598103934665603'u64
  for i in 0 ..< S.len:
    t = uint64(S[i])
    all = hashStep(all, t)
    h1 = mix64(hashStep(7'u64, t))
    V[int(h1 mod uint64(shapeDim))] += 1.0'f32
    if i + 1 < S.len:
      h2 = mix64(hashStep(h1, uint64(S[i + 1])))
      V[int(h2 mod uint64(shapeDim))] += 1.0'f32
    if i + 2 < S.len:
      h3 = mix64(hashStep(h2, uint64(S[i + 2])))
      V[int(h3 mod uint64(shapeDim))] += 1.0'f32
  normalize(V)
  result = (v: V, twin: all)

proc wordsVector(N: seq[string], chunkName: string): seq[float32] {.role: math.} =
  ## N: the names in a chunk   chunkName: the chunk's own name (counts double).
  ## The words vector.
  var
    V: seq[float32] = newSeq[float32](wordsDim)
    h: uint64 = 0
  for n in N:
    for w in splitWords(n):
      h = 1469598103934665603'u64
      for c in w:
        h = hashStep(h, uint64(ord(c)))
      V[int(mix64(h) mod uint64(wordsDim))] += 1.0'f32
  for w in splitWords(chunkName):
    h = 1469598103934665603'u64
    for c in w:
      h = hashStep(h, uint64(ord(c)))
    V[int(mix64(h) mod uint64(wordsDim))] += 2.0'f32
  normalize(V)
  result = V

proc dataTokens(S: seq[uint8]): int {.role: math.} =
  ## S: shape classes. How many are strings or numbers (a table of values
  ## has little structure to compare).
  result = 0
  for t in S:
    if t == tkString or t == tkNumber:
      result = result + 1

proc fillVectors*(c: var Chunk, text: string, isFunc: bool) {.role: actor.} =
  ## c: a chunk with repo, path, name and lines set   text: its cleaned code
  ## isFunc: a routine (true) or a type definition (false).
  ## Fills tokens, shape, words and twin. A type definition or a table of
  ## values is marked `wordsOnly`: its names are compared, not its shape.
  ## The SimHash waits for `finishVectors`, which needs every chunk.
  var
    k: tuple[shape: seq[uint8], names: seq[string]] = tokenize(text)
    s: tuple[v: seq[float32], twin: uint64] = (v: @[], twin: 0'u64)
    enough: bool = false
  c.tokens = k.shape.len
  c.wordsOnly = (not isFunc) or dataTokens(k.shape) * 100 > dataShareLimit * c.tokens
  if c.wordsOnly:
    enough = k.names.len >= minNames
  else:
    enough = c.tokens >= minTokens
  if enough:
    s = shapeVector(k.shape)
    c.shape = s.v
    c.twin = s.twin
    c.words = wordsVector(k.names, c.name)

proc idfWeights(C: seq[Chunk], useShape: bool, dim: int): seq[float32] {.role: math.} =
  ## C: all chunks   useShape: shape (true) or words (false)   dim: its length.
  ## One weight per place: log((N + 1) / (how many chunks use the place + 1)) + 1.
  ## Run-of-the-mill runs that every chunk has weigh 1; rare ones weigh more.
  var
    df: seq[int] = newSeq[int](dim)
    n: int = 0
    V: ptr seq[float32] = nil
  result = newSeq[float32](dim)
  for c in C:
    if c.shape.len == shapeDim:
      n = n + 1
      for d in 0 ..< dim:
        V = (if useShape: unsafeAddr c.shape else: unsafeAddr c.words)
        df[d] = df[d] + (if V[][d] > 0.0'f32: 1 else: 0)
  for d in 0 ..< dim:
    result[d] = float32(ln(float(n + 1) / float(df[d] + 1)) + 1.0)

proc reweigh(V: var seq[float32], W: seq[float32]) {.role: math.} =
  ## V: a vector   W: the weight per place. Multiplies and scales back to
  ## length 1.
  var
    t: float = 0.0
  for d in 0 ..< V.len:
    V[d] = V[d] * W[d]
    t = t + float(V[d]) * float(V[d])
  if t > 0.0:
    t = sqrt(t)
    for d in 0 ..< V.len:
      V[d] = float32(float(V[d]) / t)

proc simhashOf*(V: seq[float32]): uint64 {.role: math.} =
  ## V: a vector scaled to length 1. 64 bits, each telling on which side of
  ## a fixed random plane the vector lies: vectors that point the same way
  ## agree on most bits (the fewer bits differ, the smaller the angle).
  var
    B: array[64, float32] = default(array[64, float32])
    bits: uint64 = 0
  result = 0'u64
  for d in 0 ..< V.len:
    if V[d] != 0.0'f32:
      bits = mix64(uint64(d) + 0x2545f4914f6cdd1d'u64)
      for b in 0 ..< 64:
        B[b] = B[b] + (if ((bits shr uint64(b)) and 1'u64) == 1'u64: V[d] else: -V[d])
  for b in 0 ..< 64:
    if B[b] > 0.0'f32:
      result = result or (1'u64 shl uint64(b))

proc finishVectors*(C: var seq[Chunk]) {.role: orchestrator.} =
  ## C: every chunk of every folder, after `fillVectors`.
  ## Weighs each vector by how rare its places are across ALL chunks (a run
  ## every routine has says nothing; a rare one does), then sets the SimHash.
  var
    ws: seq[float32] = idfWeights(C, true, shapeDim)
    ww: seq[float32] = idfWeights(C, false, wordsDim)
  for i in 0 ..< C.len:
    if C[i].shape.len == shapeDim:
      reweigh(C[i].shape, ws)
      reweigh(C[i].words, ww)
      C[i].simhash = simhashOf(if C[i].wordsOnly: C[i].words else: C[i].shape)

proc cosineDist*(a, b: seq[float32]): float {.role: math.} =
  ## a, b: two vectors of the same length, each scaled to length 1.
  ## 0 for the same direction, 1 for nothing in common.
  var
    dot: float32 = 0.0'f32
    n: int = min(a.len, b.len)
  for i in 0 ..< n:
    dot = dot + a[i] * b[i]
  result = max(0.0, 1.0 - float(dot))
