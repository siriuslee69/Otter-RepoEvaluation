## ================================================================
## | similar_types.nim  <-  the shapes `similar` passes around     |
## |---------------------------------------------------------------|
## | Words used in every similar_*.nim file, defined once:          |
## |                                                                |
## |   chunk    one routine-sized piece of one file (a function, a  |
## |            method, a struct). The unit that is compared.       |
## |   shape    what a chunk is BUILT like: its keywords, operators |
## |            and calls in order, with every name and value       |
## |            replaced by a class letter. Renamed copies match.   |
## |   words    the words inside the names of a chunk              |
## |            (`retypeText` -> retype, text). Different code      |
## |            about the same thing shares words.                  |
## |   vector   a chunk's shape (or words) as a fixed list of       |
## |            numbers, so two chunks can be measured apart        |
## |   distance 1 minus the cosine of two vectors: 0 is the same,   |
## |            1 is nothing in common                              |
## |   cluster  chunks joined by small distances into one group     |
## |                                                                |
## |   file ─► chunks ─► vectors ─► candidates ─► pairs ─► clusters |
## ================================================================

import runePragmas

const
  shapeDim*: int = 512
    ## Length of a shape vector. More places means fewer two runs of
    ## tokens landing in the same one by accident.
  wordsDim*: int = 256
    ## Length of a words vector.
  maxShapeKeep*: int = 6000
    ## A chunk with more tokens than this is read only up to here.

type
  Chunk* {.role: memory, expectedCount: [0, 200000], lifeCycle: lcSession.} = object
    ## One piece of code and what was measured about it.
    ## first/last are 1-based line numbers; lines counts only lines that
    ## hold code (no blanks, no comments).
    repo*: string
    path*: string
    name*: string
    lang*: string
    first*: int
    last*: int
    lines*: int
    tokens*: int
    shape*: seq[float32]
    words*: seq[float32]
    wordsOnly*: bool
    simhash*: uint64
    twin*: uint64

  Pair* = object
    ## Two chunks and how far apart they are. a and b index into the
    ## report's chunk list; a < b.
    a*: int
    b*: int
    shapeDist*: float
    wordsDist*: float
    twin*: bool
    byWords*: bool

  Cluster* = object
    ## Chunks that are all close to one another.
    members*: seq[int]
    repos*: seq[string]
    meanShape*: float
    meanWords*: float
    twins*: int
    centre*: int

  SimilarOptions* = object
    ## minLines, maxLines  size of a chunk worth comparing
    ## maxDist             pairs farther apart than this are dropped
    ## by                  "shape" | "words" | "both" (the larger of the two)
    ## across              only pairs from different repos
    ## top                 how many clusters to print (0 = all)
    ## pairsTop            how many of the closest pairs to print (0 = none)
    ## maxBucket           a bucket of candidates larger than this is skipped
    minLines*: int
    maxLines*: int
    maxDist*: float
    by*: string
    across*: bool
    top*: int
    pairsTop*: int
    maxBucket*: int

  SimilarReport* = object
    chunks*: seq[Chunk]
    pairs*: seq[Pair]
    clusters*: seq[Cluster]
    repos*: int
    files*: int
    skippedBuckets*: int
    skippedFiles*: int
    error*: string

proc defaultSimilarOptions*(): SimilarOptions {.role: configurator.} =
  ## The values a plain `similar` run starts with.
  result = SimilarOptions(minLines: 10, maxLines: 400, maxDist: 0.15,
    by: "shape", across: false, top: 30, pairsTop: 0, maxBucket: 3000)

proc metricOf*(p: Pair, by: string): float {.inline, role: math.} =
  ## p: a measured pair   by: "shape", "words" or "both".
  ## The number that decides whether the pair counts. A pair of type
  ## definitions or data tables has no shape worth reading, so it is
  ## always judged by its words.
  if p.byWords:
    result = p.wordsDist
  else:
    case by
    of "words": result = p.wordsDist
    of "both": result = max(p.shapeDist, p.wordsDist)
    else: result = p.shapeDist
