# ============================================================
# | Otter Code Statistics JSON                               |
# | -> One measured repository, written out for a window     |
# ============================================================
#
# The field names here are the contract every front end reads, so they
# change only when the shape they describe does.

import std/[json]

import ./types
import ../../../.iron/metaPragmas

proc fileJson*(f: FileStat): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## f: one measured file.
  result = %*{
    "path": f.path, "name": f.name, "ext": f.ext, "lang": f.lang, "lines": f.lines,
    "functions": f.functions, "templates": f.templates, "macros": f.macros,
    "avgLines": f.avgLines, "maxLines": f.maxLines,
    "health": healthName(f.health), "size": sizeName(f.size),
    "share": f.share, "inputs": f.inputs, "templateCalls": f.templateCalls,
    "nested": f.nested, "deepest": f.deepest, "untested": f.untested,
    "whenCount": f.whenCount, "unsafeCount": f.unsafeCount,
    "unusedImportsCount": f.unusedImportsCount,
    "isTest": f.isTest
  }


proc siteJson*(s: NestSite): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## s: one place where a block sits inside another block.
  result = %*{
    "path": s.path, "fn": s.fn, "keyword": s.keyword, "line": s.line,
    "depth": s.depth, "innerLines": s.innerLines, "leaf": s.leaf
  }


proc countsJson*(A: seq[NameCount]): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## A: any tally of labels.
  result = newJArray()
  for row in A:
    result.add(%*{"name": row.name, "count": row.count})


proc scopeJson*(s: ProjectScopeStats): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## s: metrics for a subtab scope
  result = %*{
    "files": s.files, "lines": s.lines, "functions": s.functions,
    "templates": s.templates, "macros": s.macros,
    "inputFunctions": s.inputFunctions, "unsafeFunctions": s.unsafeFunctions,
    "avgLines": s.avgLines
  }


proc nestJson*(n: NestStats): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## n: the nesting tally of one repository.
  var
    sites: JsonNode = newJArray()
    buckets: JsonNode = newJArray()
  for row in n.sites:
    sites.add(siteJson(row))
  for row in n.innerBuckets:
    buckets.add(%row)
  result = %*{
    "templateCalls": n.templateCalls, "doubles": n.doubles,
    "triples": n.triples, "deeper": n.deeper,
    "nestedFunctions": n.nestedFunctions, "nonMathNested": n.nonMathNested,
    "mathNested": n.mathNested, "innerBuckets": buckets, "sites": sites
  }


proc testsJson*(t: TestStats): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## t: how much of one repository the tests reach.
  var
    buckets: JsonNode = newJArray()
  for row in t.buckets:
    buckets.add(%row)
  result = %*{
    "tests": t.tests, "declaredKinds": t.declaredKinds,
    "functions": t.functions, "buckets": buckets,
    "edgeCovered": t.edgeCovered, "benchCovered": t.benchCovered,
    "regressionCovered": t.regressionCovered,
    "bugfixCovered": t.bugfixCovered, "kinds": countsJson(t.kinds)
  }


proc statsJson*(S: ProjectStats): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## S: one whole measured repository.
  var
    files: JsonNode = newJArray()
    langStats: JsonNode = newJArray()
    inputDetails: JsonNode = newJArray()
    unsafeDetails: JsonNode = newJArray()
    unusedImports: JsonNode = newJArray()
    whenSites: JsonNode = newJArray()
    circularImports: JsonNode = newJArray()
    simdSites: JsonNode = newJArray()
  for row in S.files:
    files.add(fileJson(row))
  for row in S.langStats:
    langStats.add(%*{"ext": row.ext, "files": row.files, "lines": row.lines})
  for row in S.inputDetails:
    inputDetails.add(%*{
      "name": row.name, "path": row.path, "line": row.line,
      "lang": row.lang, "role": row.role, "inputSource": row.inputSource,
      "sanitizerName": row.sanitizerName
    })
  for row in S.unsafeDetails:
    unsafeDetails.add(%*{
      "name": row.name, "path": row.path, "line": row.line,
      "lang": row.lang, "kind": row.kind,
      "touchesExternalData": row.touchesExternalData,
      "externalDataTrace": row.externalDataTrace
    })
  for row in S.unusedImports:
    unusedImports.add(%*{
      "moduleName": row.moduleName, "path": row.path, "line": row.line
    })
  for row in S.whenSites:
    whenSites.add(%*{
      "path": row.path, "line": row.line, "condition": row.condition
    })
  for row in S.circularImports:
    circularImports.add(%*{"cycle": row.cycle})
  for row in S.simdSites:
    simdSites.add(%*{
      "path": row.path, "line": row.line, "feature": row.feature
    })
  result = %*{
    "rootDir": S.rootDir, "isGitRepo": S.isGitRepo, "error": S.error,
    "files": files,
    "totalLines": S.totalLines, "functions": S.functions,
    "templates": S.templates, "macros": S.macros, "avgLines": S.avgLines,
    "inputFunctions": S.inputFunctions, "truthFunctions": S.truthFunctions,
    "mathFunctions": S.mathFunctions, "helperFunctions": S.helperFunctions,
    "unusedCount": S.unusedCount, "unused": S.unused,
    "roles": countsJson(S.roles),
    "langStats": langStats,
    "gitignore": {
      "ignoredFiles": S.gitignore.ignoredFiles,
      "ignoredLines": S.gitignore.ignoredLines
    },
    "inputDetails": inputDetails,
    "unsafeDetails": unsafeDetails,
    "unusedImports": unusedImports,
    "whenSites": whenSites,
    "importGraphDepth": S.importGraphDepth,
    "circularImports": circularImports,
    "platformCoverage": countsJson(S.platformCoverage),
    "simdSites": simdSites,
    "srcStats": scopeJson(S.srcStats),
    "allStats": scopeJson(S.allStats),
    "testStats": scopeJson(S.testStats),
    "nest": nestJson(S.nest),
    "tests": testsJson(S.tests)
  }
