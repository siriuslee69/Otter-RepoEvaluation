## Tests for the six reports added beside the older statistics:
## shape, placeholders, secrets, config touch, timeline, unused.
##
## Each of these decides something about a person's code, so each is
## tested from both ends: it must fire on the thing it is looking for,
## and it must stay silent on the thing that merely resembles it. The
## second half matters more. A measure that cries wolf is turned off
## within a week, and then it is measuring nothing at all.

import std/[sets, strutils, tables, unittest]

import ../src/protocols/code_stats/shape
import ../src/protocols/code_stats/placeholders
import ../src/protocols/code_stats/secrets
import ../src/protocols/code_stats/config_touch
import ../src/protocols/code_stats/timeline
import ../src/protocols/code_stats/unused
import ../src/protocols/code_stats/call_depth
import ../src/protocols/code_stats/coupling
import ../src/protocols/repo_graph/types as graphTypes

proc fn(name: string, body: seq[string], params: seq[string] = @[],
    sockets: seq[FunctionSocket] = @[], ret: string = "",
    pragmas: seq[string] = @[], calls: seq[string] = @[],
    docs: seq[string] = @[]): FunctionInfo =
  ## A routine built by hand, so a test says exactly what it means
  ## without a file on disk to keep in step with it.
  result = default(FunctionInfo)
  result.id = "m::" & name
  result.name = name
  result.modulePath = "m"
  result.sourcePath = "src/m.nim"
  result.declKind = "proc"
  result.bodyLines = body
  result.params = params
  result.sockets = sockets
  result.returnType = ret
  result.pragmaTags = pragmas
  result.calls = calls
  result.docCommentLines = docs
  result.lineStart = 1
  result.lineEnd = 1 + body.len
  result.isExported = true

suite "shape: routines built alike":
  # {.testKind: tkUnit.}
  test "the skeleton keeps the order of what a routine does":
    check skeletonOf(@["var a = 1", "for x in y:", "  result = x"]) ==
      "VFR"

  # {.testKind: tkEdgeCase.}
  test "blank and comment lines leave no mark on the skeleton":
    check skeletonOf(@["", "# a note", "  ", "result = 1"]) == "R"

  # {.testKind: tkUnit.}
  test "two routines with the same order score a full shape match":
    check sequenceMatch("VIRK", "VIRK") == 1.0

  # {.testKind: tkUnit.}
  test "a shape match is measured against the longer of the two":
    ## `VIR` sits inside `VIRKR`: three shared letters of five.
    check abs(sequenceMatch("VIR", "VIRKR") - 0.6) < 0.001

  # {.testKind: tkEdgeCase.}
  test "nothing in common scores zero, and empty does not divide by zero":
    check sequenceMatch("FFF", "RRR") == 0.0
    check sequenceMatch("", "VIR") == 0.0

  # {.testKind: tkUnit.}
  test "names are compared word by word, not letter by letter":
    ## `parseUserName` and `parse_user_id` share `parse` and `user`
    ## out of four distinct words between them.
    check nameMatch("parseUserName", "parse_user_id") > 0.4
    check nameMatch("parseUserName", "parseUserName") == 1.0
    check nameMatch("alpha", "omega") == 0.0

  # {.testKind: tkUnit.}
  test "what a routine hands back is sorted into a kind":
    check returnKind("") == 0
    check returnKind("void") == 0
    check returnKind("int") == 1
    check returnKind("string") == 2
    check returnKind("seq[string]") == 3
    check returnKind("bool") == 4
    check returnKind("MyRecord") == 5

  # {.testKind: tkUnit.}
  test "a copied routine is found even after every name is changed":
    var
      a: FunctionInfo = fn("readSettings",
        @["var t = 0", "for row in A:", "  if row.ok:", "    t = t + 1",
          "  echo(row)", "result = t"])
      b: FunctionInfo = fn("countEntries",
        @["var n = 0", "for item in B:", "  if item.fine:",
          "    n = n + 1", "  echo(item)", "result = n"])
      A: seq[FunctionShape] = @[shapeOf(a, ""), shapeOf(b, "")]
      got: tuple[pairs: seq[DuplicatePair], total: int] =
        duplicatesOf(A, spaceOf(A))
    check got.total == 1
    check got.pairs[0].shapeMatch == 1.0

  # {.testKind: tkEdgeCase.}
  test "two tiny routines are not called copies of each other":
    ## Every three-line comparator in a repository looks like every
    ## other one. Saying so is noise, not a finding.
    var
      a: FunctionInfo = fn("byA", @["result = 1"])
      b: FunctionInfo = fn("byB", @["result = 2"])
      A: seq[FunctionShape] = @[shapeOf(a, ""), shapeOf(b, "")]
    check duplicatesOf(A, spaceOf(A)).total == 0

  # {.testKind: tkUnit.}
  test "loops stacked inside loops raise the loop depth":
    var
      f: FunctionInfo = fn("walk", @[
        "for a in A:", "  for b in B:", "    echo b", "for c in C:",
        "  echo c"])
      s: FunctionShape = shapeOf(f, "")
    check s.loops == 3
    check s.loopDepth == 2

suite "placeholders: routines that do nothing yet":
  # {.testKind: tkUnit.}
  test "a pragma is believed outright":
    var
      f: FunctionInfo = fn("later", @["result = 1"],
        pragmas = @["stage:stStubbed"])
    check scoreOf(f, true).score == 1.0

  # {.testKind: tkUnit.}
  test "an empty body is very likely a placeholder":
    check scoreOf(fn("nothing", @["discard"]), true).score >= 0.7

  # {.testKind: tkUnit.}
  test "a body that only refuses is very likely a placeholder":
    check scoreOf(fn("nope",
      @["raise newException(ValueError, \"not implemented\")"]),
      true).score >= 0.7

  # {.testKind: tkUnit.}
  test "an answer that ignores everything handed in is suspect":
    var
      f: FunctionInfo = fn("widthOf", @["result = 80"],
        params = @["s"], ret = "int")
    check scoreOf(f, true).score >= 0.5

  # {.testKind: tkRegression.}
  test "a routine that changes what it was handed is not a placeholder":
    ## pins: a `proc fill(S: var seq[int])` hands nothing back, so the
    ## constant-answer test used to flag every one of them.
    var
      f: FunctionInfo = fn("fill", @["S.add(1)"], params = @["S"],
        sockets = @[FunctionSocket(name: "S", typeName: "seq[int]",
          direction: sdVarInput)])
    check scoreOf(f, true).score < placeholderFloor

  # {.testKind: tkRegression.}
  test "a routine taking nothing in but doing real work is not flagged":
    ## pins: `proc webRoot(): string = result = currentSourcePath()`
    ## uses no argument, so the constant-answer test used to fire on
    ## every routine that takes no arguments.
    var
      f: FunctionInfo = fn("webRoot", @["result = getCurrentDir()"],
        ret = "string", calls = @["getCurrentDir"])
    check scoreOf(f, true).score < placeholderFloor

  # {.testKind: tkRegression.}
  test "a pragma-defining template is not a placeholder":
    ## pins: `template role*(x: MetaRole) {.pragma.}` has no body by
    ## design, and a repository's pragma file used to read as forty
    ## placeholders, burying every real one.
    var
      f: FunctionInfo = fn("role", @[], pragmas = @["pragma"])
    check scoreOf(f, false).score == 0.0

  # {.testKind: tkEdgeCase.}
  test "a forward declaration is not a placeholder":
    check scoreOf(fn("declaredAbove", @[]), true).score == 0.0

  # {.testKind: tkUnit.}
  test "an unfinished note raises the score but does not decide it":
    var
      plain: FunctionInfo = fn("thing", @["result = compute()"],
        calls = @["compute"])
      noted: FunctionInfo = fn("thing", @["result = compute()"],
        calls = @["compute"], docs = @["## TODO: work this out"])
    check scoreOf(noted, true).score > scoreOf(plain, true).score

suite "secrets: things that should never have been typed in":
  # {.testKind: tkUnit.}
  test "jumbledness tells noise from words":
    check entropyOf("aaaaaaaaaaaaaaaa") == 0.0
    check entropyOf("the quick brown fox") < 3.9
    check entropyOf("kJ8x2Qm9Zp4Lw7Nv") > 3.5

  # {.testKind: tkEdgeCase.}
  test "jumbledness of nothing is nothing, not a crash":
    check entropyOf("") == 0.0

  # {.testKind: tkUnit.}
  test "a real looking key clears the threshold":
    check scoreValue("apiKey",
      "sk-live-4f9a2b8c7d6e5f0a1b2c3d4e5f60718293a4b5c6").score >=
      secretFloor

  # {.testKind: tkUnit.}
  test "a value that says it is an example is pulled back down":
    check scoreValue("apiKey", "your_api_key_example_here_xxxx").score <
      secretFloor

  # {.testKind: tkRegression.}
  test "a file path is not reported as key material":
    ## pins: a long path scores on every test a key scores on, and
    ## `/home/anna/.config/state.json` was reported as a probable key
    ## on top of being reported, correctly, as a personal path.
    check scoreValue("homeDir", "/home/anna/.config/otter/state.json").score <
      secretFloor
    check scoreValue("asset", "src/clients/web/js/app.js").score <
      secretFloor

  # {.testKind: tkUnit.}
  test "ordinary prose in a string is not key material":
    check scoreValue("greeting",
      "Hello there, this is ordinary prose.").score < secretFloor

  # {.testKind: tkUnit.}
  test "a home folder gives up whose it is":
    check userPathOf("readFile(\"/home/anna/keys\")").who == "anna"
    check userPathOf("path = \"C:\\\\Users\\\\Anna\\\\keys\"").hit

  # {.testKind: tkEdgeCase.}
  test "a home folder belonging to nobody in particular is ignored":
    check not userPathOf("\"/home/user/projects\"").hit
    check not userPathOf("\"/home/runner/work\"").hit

  # {.testKind: tkUnit.}
  test "a value is never repeated back in full":
    var
      whole: string = "sk-live-4f9a2b8c7d6e5f0a"
      shown: string = maskOf(whole)
    check whole notin shown
    check shown.startsWith("sk-l")

  # {.testKind: tkUnit.}
  test "the name of a thing is read word by word":
    check nameLooksSecret("apiKey")
    check nameLooksSecret("user_password")
    check nameLooksSecret("sk")
    check not nameLooksSecret("taskList")
    check not nameLooksSecret("speaker")

suite "config: which settings anything reads":
  # {.testKind: tkUnit.}
  test "a settings type is known by how its name ends":
    check isConfigType("OtterUiConfig")
    check isConfigType("AppSettings")
    check isConfigType("RenderOptions")

  # {.testKind: tkRegression.}
  test "a report about settings is not itself a settings type":
    ## pins: matching `config` anywhere in a name turned `ConfigField`,
    ## `ConfigReport` and every similar record into a settings object,
    ## and the whole measure became meaningless.
    check not isConfigType("ConfigField")
    check not isConfigType("ConfigReport")
    check not isConfigType("ConfigConflict")

  # {.testKind: tkUnit.}
  test "a type saying it is a configurator is taken at its word":
    check isConfigType("Knobs", "Knobs* {.role: configurator.} = object")

  # {.testKind: tkUnit.}
  test "reading and writing a setting are told apart":
    var
      seat: HashSet[string] = ["cfg"].toHashSet()
    check touchesIn("cfg.useCache = true", "useCache", seat).write
    check touchesIn("if cfg.useCache:", "useCache", seat).read
    check not touchesIn("if cfg.useCache:", "useCache", seat).write

  # {.testKind: tkRegression.}
  test "a field on something that is not settings is not counted":
    ## pins: settings have ordinary field names — `name`, `line`,
    ## `kind` — so a search for a bare `.name` matched every object in
    ## a repository and one setting read as having ninety readers.
    var
      seat: HashSet[string] = ["cfg"].toHashSet()
    check not touchesIn("echo other.name", "name", seat).read
    check touchesIn("echo cfg.name", "name", seat).read

  # {.testKind: tkEdgeCase.}
  test "a longer name is not mistaken for the setting inside it":
    var
      seat: HashSet[string] = ["cfg"].toHashSet()
    check not touchesIn("echo cfg.useCacheLater", "useCache", seat).read

  # {.testKind: tkRegression.}
  test "a settings builder writing into result counts as setting them":
    ## pins: settings are usually written only by the routine that
    ## builds them, through `result.field = ...`, and missing that
    ## made every setting in a repository read as "never set".
    var
      f: FunctionInfo = fn("loadConfig", @["result.repoRoot = dir"],
        ret = "AppSettings")
    check "result" in receiversIn(f, "AppSettings")

  # {.testKind: tkUnit.}
  test "settings handed in to be changed are found through the sockets":
    var
      f: FunctionInfo = fn("assign", @["S.title = value"],
        params = @["S", "value"],
        sockets = @[FunctionSocket(name: "S", typeName: "AppSettings",
          direction: sdVarInput)])
    check "S" in receiversIn(f, "AppSettings")

  # {.testKind: tkUnit.}
  test "a setting read by nobody is called out":
    check verdictOf(ConfigField(readCount: 0, writeCount: 2)) ==
      "does nothing"
    check verdictOf(ConfigField(readCount: 3, writeCount: 0,
      hasDefault: false)) == "never set"
    check verdictOf(ConfigField(readCount: 3, writeCount: 4)) ==
      "contested"
    check verdictOf(ConfigField(readCount: 3, writeCount: 1)) == "fine"

suite "timeline: the repository through time":
  # {.testKind: tkUnit.}
  test "the first and the last moment are always kept":
    check sampleAt(100, 10, 0)
    check sampleAt(100, 10, 99)

  # {.testKind: tkEdgeCase.}
  test "a history shorter than what was asked for is kept whole":
    var
      i: int = 0
    while i < 5:
      check sampleAt(5, 20, i)
      i = i + 1

  # {.testKind: tkUnit.}
  test "a long history is thinned out rather than read in full":
    var
      kept: int = 0
      i: int = 0
    while i < 1000:
      if sampleAt(1000, 40, i):
        kept = kept + 1
      i = i + 1
    check kept > 30
    check kept < 60

  # {.testKind: tkEdgeCase.}
  test "a folder that is not a repository says so instead of failing":
    check timelineOf("/definitely/not/here").error.len > 0

suite "unused: routines nothing calls":
  # {.testKind: tkUnit.}
  test "a big uncalled routine reads as a leftover, a small one as a start":
    var
      big: FunctionInfo = fn("oldEngine", @[])
      small: FunctionInfo = fn("newIdea", @[])
    big.lineEnd = big.lineStart + 60
    small.lineEnd = small.lineStart + 3
    check classify(big, false) == ukLeftover
    check classify(small, false) == ukPrepared

  # {.testKind: tkUnit.}
  test "an exported routine in a library has its callers elsewhere":
    var
      f: FunctionInfo = fn("publicThing", @[])
    f.lineEnd = f.lineStart + 60
    check classify(f, true) == ukPublic

  # {.testKind: tkUnit.}
  test "dead weight is added up so a clean-up can be judged":
    var
      a: FunctionInfo = fn("oldOne", @[])
      b: FunctionInfo = fn("oldTwo", @[])
      got: UnusedReport
    a.isExported = false
    b.isExported = false
    a.lineEnd = a.lineStart + 40
    b.lineEnd = b.lineStart + 30
    got = unusedReportOf(@[a, b], initHashSet[string](), "")
    check got.leftoverCount == 2
    check got.leftoverLines == 72

  # {.testKind: tkEdgeCase.}
  test "a routine that is called does not appear at all":
    var
      f: FunctionInfo = fn("used", @[])
    check unusedReportOf(@[f], ["used"].toHashSet(), "").total == 0

suite "call depth: how deep the stack can get":
  proc calls(name: string, to: seq[string]): FunctionInfo =
    ## A routine that calls the named others, for building a shape of
    ## call graph by hand.
    result = fn(name, @[])
    result.id = name

  proc edgesOf(A: openArray[array[2, string]]): seq[CallEdge] =
    result = @[]
    for row in A:
      result.add(CallEdge(callerId: row[0], calleeId: row[1],
        callName: row[1]))

  # {.testKind: tkUnit.}
  test "a routine calling nothing is one deep":
    var
      got: CallDepthStats = callDepthOf(@[calls("alone", @[])], @[], "")
    check got.maxDepth == 1
    check got.avgDepth == 1.0

  # {.testKind: tkUnit.}
  test "depth counts the longest chain below a routine":
    ## a -> b -> c -> d, so `a` is four deep and `d` is one.
    var
      A: seq[FunctionInfo] = @[calls("a", @[]), calls("b", @[]),
        calls("c", @[]), calls("d", @[])]
      E: seq[CallEdge] = edgesOf([["a", "b"], ["b", "c"], ["c", "d"]])
      got: CallDepthStats = callDepthOf(A, E, "")
    check got.maxDepth == 4
    check got.counted == 4
    check got.buckets.len == 4

  # {.testKind: tkUnit.}
  test "the longest of two branches decides the depth":
    ## a calls both a short branch and a long one.
    var
      A: seq[FunctionInfo] = @[calls("a", @[]), calls("s", @[]),
        calls("x", @[]), calls("y", @[])]
      E: seq[CallEdge] = edgesOf([["a", "s"], ["a", "x"], ["x", "y"]])
      got: CallDepthStats = callDepthOf(A, E, "")
    check got.maxDepth == 3

  # {.testKind: tkEdgeCase.}
  test "a routine calling itself does not count forever":
    var
      A: seq[FunctionInfo] = @[calls("loop", @[])]
      E: seq[CallEdge] = edgesOf([["loop", "loop"]])
      got: CallDepthStats = callDepthOf(A, E, "")
    check got.maxDepth >= 1
    check got.rings.len > 0

  # {.testKind: tkEdgeCase.}
  test "a ring of three does not count forever either":
    var
      A: seq[FunctionInfo] = @[calls("a", @[]), calls("b", @[]),
        calls("c", @[])]
      E: seq[CallEdge] = edgesOf([["a", "b"], ["b", "c"], ["c", "a"]])
      got: CallDepthStats = callDepthOf(A, E, "")
    check got.maxDepth <= depthCap
    check got.rings.len > 0

  # {.testKind: tkRegression.}
  test "a call out of this tree does not add depth":
    ## pins: calls into the standard library are in the edge list too,
    ## and counting them made every routine look one deeper than it is.
    var
      A: seq[FunctionInfo] = @[calls("a", @[])]
      E: seq[CallEdge] = edgesOf([["a", "echo"]])
      got: CallDepthStats = callDepthOf(A, E, "")
    check got.maxDepth == 1

  # {.testKind: tkUnit.}
  test "each depth is split by what the routines there are":
    var
      A: seq[FunctionInfo] = @[calls("a", @[]), calls("b", @[])]
      got: CallDepthStats
    A[0].role = frHelper
    A[1].role = frHelper
    got = callDepthOf(A, @[], "")
    check got.buckets.len == 1
    check got.buckets[0].roles.len == 1
    check got.buckets[0].roles[0].name == "helper"
    check got.buckets[0].roles[0].count == 2

  # {.testKind: tkEdgeCase.}
  test "an empty tree answers without failing":
    var
      got: CallDepthStats = callDepthOf(@[], @[], "")
    check got.maxDepth == 0
    check got.buckets.len == 0

suite "coupling: is every door guarded":
  proc door(name: string): FunctionInfo =
    result = fn(name, @[], pragmas = @["role:datafetcher"])
    result.id = name

  proc guard(name: string): FunctionInfo =
    result = fn(name, @[], pragmas = @["role:sanitizer"])
    result.id = name

  proc plain(name: string): FunctionInfo =
    result = fn(name, @[], pragmas = @["role:parser"])
    result.id = name

  proc edgesOf(A: openArray[array[2, string]]): seq[CallEdge] =
    result = @[]
    for row in A:
      result.add(CallEdge(callerId: row[0], calleeId: row[1],
        callName: row[1]))

  proc empty(): CountTable[string] = initCountTable[string]()
  proc none(): HashSet[string] = initHashSet[string]()

  # {.testKind: tkUnit.}
  test "a declared role decides what a routine is":
    check isSanitizer(guard("clean"))
    check isDoor(door("readIt"))
    check not isDoor(guard("clean"))

  # {.testKind: tkRegression.}
  test "a sanitizer is not itself counted as a door":
    ## pins: a sanitizer usually reads its own input, so it used to be
    ## counted as a door and then asked whether it was guarded — a
    ## question with no useful answer.
    var
      got: CouplingStats = couplingOf(@[guard("clean")], @[], "",
        empty(), none(), none(), none())
    check got.inputCount == 0
    check got.sanitizerCount == 1

  # {.testKind: tkUnit.}
  test "a door calling a guard is guarded, one hop away":
    var
      A: seq[FunctionInfo] = @[door("readHeader"), guard("sanitizeName")]
      E: seq[CallEdge] = edgesOf([["readHeader", "sanitizeName"]])
      got: CouplingStats = couplingOf(A, E, "", empty(), none(), none(),
        none())
    check got.guardedCount == 1
    check got.openCount == 0
    check got.inputs[0].hops == 1
    check got.inputs[0].guard == "sanitizeName"

  # {.testKind: tkUnit.}
  test "a guard further down still guards, and the route is named":
    var
      A: seq[FunctionInfo] = @[door("readRequest"), plain("parseBody"),
        guard("sanitizeName")]
      E: seq[CallEdge] = edgesOf([["readRequest", "parseBody"],
        ["parseBody", "sanitizeName"]])
      got: CouplingStats = couplingOf(A, E, "", empty(), none(), none(),
        none())
    check got.guardedCount == 1
    check got.inputs[0].hops == 2
    check got.inputs[0].via == @["readRequest", "parseBody",
      "sanitizeName"]

  # {.testKind: tkUnit.}
  test "a door reaching no guard is reported open":
    var
      A: seq[FunctionInfo] = @[door("readCookie"), plain("shout")]
      E: seq[CallEdge] = edgesOf([["readCookie", "shout"]])
      got: CouplingStats = couplingOf(A, E, "", empty(), none(), none(),
        none())
    check got.openCount == 1
    check not got.inputs[0].guarded
    check got.inputs[0].guard.len == 0

  # {.testKind: tkEdgeCase.}
  test "a guard too many calls away does not count as one":
    ## Four hops, and the search only looks three out.
    var
      A: seq[FunctionInfo] = @[door("d"), plain("p1"), plain("p2"),
        plain("p3"), guard("clean")]
      E: seq[CallEdge] = edgesOf([["d", "p1"], ["p1", "p2"],
        ["p2", "p3"], ["p3", "clean"]])
      got: CouplingStats = couplingOf(A, E, "", empty(), none(), none(),
        none())
    check got.openCount == 1

suite "coupling: are the guards themselves checked":
  # {.testKind: tkUnit.}
  test "a guard nothing tests is unchecked":
    check verdictOf(0, false, false) == "unchecked"

  # {.testKind: tkUnit.}
  test "a guard tested only against what was expected is shallow":
    check verdictOf(4, false, false) == "shallow"

  # {.testKind: tkUnit.}
  test "an edge case or a regression makes a guard solid":
    check verdictOf(1, true, false) == "solid"
    check verdictOf(1, false, true) == "solid"

  # {.testKind: tkRegression.}
  test "test reach is read by id, not by name":
    ## pins: the walk over the tests keys everything by a routine's id.
    ## Reading it by name credited a guard with the tests of an
    ## unrelated routine that happened to share its name.
    var
      g: FunctionInfo = fn("clean", @[], pragmas = @["role:sanitizer"])
      hits: CountTable[string] = initCountTable[string]()
      edge: HashSet[string] = initHashSet[string]()
      got: CouplingStats
    g.id = "mod-a::clean"
    hits.inc("mod-a::clean", 5)
    edge.incl("mod-a::clean")
    got = couplingOf(@[g], @[], "", hits, edge, initHashSet[string](),
      initHashSet[string]())
    check got.sanitizers[0].tests == 5
    check got.sanitizers[0].edge
    check got.sanitizers[0].verdict == "solid"
    check got.edgeCovered == 1
