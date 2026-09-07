## ================================================================
## | feed.nim  <-  a price feed with one entry that loses data     |
## |---------------------------------------------------------------|
## | Small on purpose. Every answer the state-writes module gives   |
## | about this file can be checked by reading the file.            |
## |                                                                |
## |   price     two writers, neither reads it first  -> LOST       |
## |   volume    two writers, one folds the old value -> safe       |
## |   lastSeen  two writers, nobody ever reads it    -> DEAD       |
## |   ticker    two writers, marked `otter:latest`   -> allowed    |
## |   depth     two writers, but read in between     -> safe       |
## ================================================================

type
  Feed* = object
    ## {.role: truthState.}
    price*: float
    volume*: int
    lastSeen*: string
    ticker*: string       ## otter:latest - only the newest symbol matters
    depth*: int

proc ingest*(S: var Feed, p: float) =
  ## S: the feed   p: the newest price.
  ## Replaces price outright: whatever was there is not looked at.
  S.price = p
  S.volume = 1
  S.lastSeen = "ingest"
  S.ticker = "AAA"

proc resample*(S: var Feed) =
  ## S: the feed. Replaces price again, also without reading it.
  S.price = 0.0
  S.lastSeen = "resample"
  S.ticker = "BBB"

proc accumulate*(S: var Feed) =
  ## S: the feed. Reads volume before writing it, so nothing is lost.
  S.volume = S.volume + 1

proc snapshot*(S: var Feed, n: int) =
  ## S: the feed   n: the new depth. A blind write.
  S.depth = n

proc rebase*(S: var Feed, n: int) =
  ## S: the feed   n: the new depth. A second blind write.
  S.depth = n

proc render*(S: Feed): string =
  ## S: the feed. Reads price and volume, and nothing else.
  result = $S.price & " " & $S.volume

proc showDepth*(S: Feed): string =
  ## S: the feed. Reads depth.
  result = $S.depth

proc runFeed*(S: var Feed) =
  ## S: the feed. Two blind writes of price, back to back. The price
  ## ingest stored never reaches render.
  ingest(S, 1.0)
  resample(S)
  discard render(S)

proc runSafe*(S: var Feed) =
  ## S: the feed. Two blind writes of depth, with a read between them,
  ## so the first value did reach somebody.
  snapshot(S, 1)
  discard showDepth(S)
  rebase(S, 2)
