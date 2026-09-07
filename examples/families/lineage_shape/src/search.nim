## A repository shaped like Lineage before its two searches were
## rolled into one sum: a genetic algorithm and a particle swarm
## written separately, though each is the same line with different
## terms switched on.
##
##   x' = x + SUM over the terms that are on of  c_k * (t_k - x)
##
## The swarm uses `pbest` and `gbest`. The genetic algorithm uses
## `crossover`. Neither is a special case of the other; both are
## subsets of one sum, and a term is switched off with a coefficient
## of zero rather than by branching around it.
##
## Otter should call this family `term`.

type
  Individual* = object
    pos*: seq[float]
    pbest*: seq[float]

proc stepSwarm*(x: Individual, gbest, prev: seq[float],
    cInertia, cPersonal, cGlobal: float): seq[float] =
  var t: seq[float] = newSeq[float](x.pos.len)
  for i in 0 ..< x.pos.len:
    t[i] = x.pos[i]
    t[i] = t[i] + cInertia * (prev[i] - x.pos[i])
    t[i] = t[i] + cPersonal * (x.pbest[i] - x.pos[i])
    t[i] = t[i] + cGlobal * (gbest[i] - x.pos[i])
  result = t

proc stepGenetic*(x: Individual, partner, prev: seq[float],
    cInertia, cCross, cNoise: float): seq[float] =
  var t: seq[float] = newSeq[float](x.pos.len)
  for i in 0 ..< x.pos.len:
    t[i] = x.pos[i]
    t[i] = t[i] + cInertia * (prev[i] - x.pos[i])
    t[i] = t[i] + cCross * (partner[i] - x.pos[i])
    t[i] = t[i] + cNoise * (0.0 - x.pos[i])
  result = t

proc stepRepel*(x: Individual, worst, prev: seq[float],
    cInertia, cRepel: float): seq[float] =
  var t: seq[float] = newSeq[float](x.pos.len)
  for i in 0 ..< x.pos.len:
    t[i] = x.pos[i]
    t[i] = t[i] + cInertia * (prev[i] - x.pos[i])
    t[i] = t[i] - cRepel * (worst[i] - x.pos[i])
  result = t
