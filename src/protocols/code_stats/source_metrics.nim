## Source metrics <- platform switches, SIMD mentions, and scope totals.
## Platform and SIMD results are text candidates, not compiler decisions.

import std/[os, strutils]
import runePragmas
import ./types
import ../repo_graph/io_utils

type
  PlatformScan = object
    sites: seq[WhenSite]
    counts: array[4, int]
    simd: seq[SimdSite]

const
  platforms: array[4, string] = ["windows", "linux", "nixos", "posix"]

proc countPlatforms(S: var PlatformScan, s: string) {.role: actor, inline.} =
  ## S: counters; s: lower-case conditional compilation line.
  if "windows" in s or "_win32" in s: inc S.counts[0]
  if "linux" in s or "__linux__" in s: inc S.counts[1]
  if "nixos" in s or "nix" in s: inc S.counts[2]
  if "posix" in s: inc S.counts[3]

proc simdFeature(s: string): string {.role: parser, inline.} =
  ## s: source line. Empty when there is no known SIMD mention.
  if "avx" in s: return "AVX"
  if "sse" in s: return "SSE"
  if "neon" in s: return "NEON"
  if "nimsimd" in s or "vector" in s: return "SIMD"
  result = ""

proc scanPlatformLine(S: var PlatformScan, p, s: string, n: int)
    {.role: actor, inline.} =
  ## S: report; p: relative path; s: line n, numbered from one.
  var
    t: string = s.strip()
    f: string = simdFeature(s)
  if t.startsWith("when ") or t.startsWith("#ifdef ") or t.startsWith("#if "):
    S.sites.add(WhenSite(path: p, line: n, condition: t))
    countPlatforms(S, t.toLowerAscii())
  if f.len > 0:
    S.simd.add(SimdSite(path: p, line: n, feature: f))

proc scanPlatformFile(S: var PlatformScan, dir, p: string) {.role: actor.} =
  ## S: report; dir: root; p: file to read.
  var
    r: string = normalizeSlashes(relativePath(p, dir))
    n: int = 0
  for s in readLinesSafe(p):
    inc n
    scanPlatformLine(S, r, s, n)

proc scanWhenSitesAndPlatformCoverage*(dir: string, P: seq[string]): tuple[
    sites: seq[WhenSite], platforms: seq[NameCount], simd: seq[SimdSite]]
    {.role: truthBuilder.} =
  ## dir: root; P: source files. Results retain file order and platform order.
  var
    scan: PlatformScan = PlatformScan()
    counts: seq[NameCount] = @[]
  for p in P:
    scanPlatformFile(scan, dir, p)
  for i, p in platforms:
    counts.add(NameCount(name: p, count: scan.counts[i]))
  result = (scan.sites, counts, scan.simd)

proc addScope(S: var ProjectScopeStats, f: FileStat) {.role: actor, inline.} =
  ## S: one scope's totals; f: the next file in it.
  inc S.files
  S.lines += f.lines
  S.functions += f.functions
  S.templates += f.templates
  S.macros += f.macros
  S.inputFunctions += f.inputs
  S.unsafeFunctions += f.unsafeCount

proc finishScope(S: var ProjectScopeStats) {.role: actor, inline.} =
  ## S: summed files. A scope without routines keeps a zero average.
  if S.functions > 0:
    S.avgLines = S.lines.float / S.functions.float

proc calculateScopeStats*(F: seq[FileStat]): tuple[
    src, all, test: ProjectScopeStats] {.role: truthBuilder.} =
  ## F: file rows. Test files belong to the test scope even inside src/.
  result = (ProjectScopeStats(), ProjectScopeStats(), ProjectScopeStats())
  for f in F:
    addScope(result.all, f)
    if f.isTest or isTestPath(f.path):
      addScope(result.test, f)
    else:
      addScope(result.src, f)
  finishScope(result.src)
  finishScope(result.all)
  finishScope(result.test)
