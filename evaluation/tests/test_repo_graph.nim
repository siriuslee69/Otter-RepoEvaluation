# ============================================================
# | Otter Repo Graph Tests                                   |
# | -> Validate merged analysis and sample-runner flows      |
# ============================================================

import std/[json, os, tables, unittest]

import otter_repo_evaluation

suite "otter repo graph":
  test "analyze repo and build orchestrator groups":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_repo_graph_repo")
      srcDir: string = ""
      sampleFile: string = ""
      g: RepoGraph
      byName: Table[string, FunctionInfo]
      graphJson: JsonNode
    if dirExists(root):
      removeDir(root)
    srcDir = joinPath(root, "src")
    createDir(srcDir)
    sampleFile = joinPath(srcDir, "sample.nim")
    writeFile(sampleFile, """
## pipeline entry for the repo graph test
proc helperA*(a: int): int =
  ## first helper branch
  result = a + 1

proc helperB*(a: int): int =
  # helper note inside body
  result = helperA(a)

## top orchestration doc
proc runPipeline*(a: int): int =
  var t: int = helperA(a)
  t = helperB(t)
  result = t

proc socketShape*(a, b: int; c: string; d: var float; flag: bool = false): string =
  d = d + 1.0
  result = c
""")
    g = analyzeRepo(root)
    check g.functions.len >= 3
    check g.groups.len >= 1
    byName = initTable[string, FunctionInfo]()
    for f in g.functions:
      byName[f.name] = f
    check byName.hasKey("helperA")
    check byName["helperA"].returnType == "int"
    check byName["helperA"].sockets.len >= 2
    check byName["socketShape"].params == @["a", "b", "c", "d", "flag"]
    check byName["socketShape"].sockets.len >= 6
    check byName["socketShape"].sockets[0].name == "a"
    check byName["socketShape"].sockets[1].name == "b"
    check byName["socketShape"].sockets[2].name == "c"
    check byName["socketShape"].sockets[3].name == "d"
    check byName["socketShape"].sockets[3].direction == sdVarInput
    check byName["socketShape"].sockets[4].name == "flag"
    check byName["socketShape"].sockets[5].name == "result"
    check byName["runPipeline"].docCommentLines.len >= 1
    check byName["helperB"].innerCommentLines.len >= 1
    graphJson = parseJson(toGraphJson(g))
    check graphJson["groups"].len >= 1
    check graphJson["functions"].len >= 3
    removeDir(root)

  test "run exported function with generated sample args":
    var
      root: string = joinPath(getCurrentDir(), "build", "test_repo_graph_runner")
      srcDir: string = ""
      sampleFile: string = ""
      g: RepoGraph
      f: FunctionInfo
      r: RunSampleResult
    if dirExists(root):
      removeDir(root)
    srcDir = joinPath(root, "src")
    createDir(srcDir)
    sampleFile = joinPath(srcDir, "sample.nim")
    writeFile(sampleFile, """
proc addPair*(a: int, b: int): int =
  result = a + b
""")
    g = analyzeRepo(root)
    f = g.functions[0]
    r = runFunctionSample(root, f.id)
    check r.ok
    check r.resultText == "84"
    check r.generatedArgs.len >= 2
    removeDir(root)
