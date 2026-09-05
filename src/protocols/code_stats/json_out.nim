# ============================================================
# | Otter Code Statistics JSON                               |
# | -> One measured repository, written out for a window     |
# ============================================================
#
# The field names here are the contract every front end reads, so they
# change only when the shape they describe does.

import std/[json]

import ./types
import ../../../meta/metaPragmas

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


# ---- the six reports, written out ------------------------------------
#
# One writer per report, each named for the file that produced it, so
# that a field on screen can be traced back to the line of Nim that
# worked it out without reading anything in between.

proc shapeJson*(S: ShapeReport): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## S: routines placed by what they are built like.
  var
    dupes: JsonNode = newJArray()
    points: JsonNode = newJArray()
    groups: JsonNode = newJArray()
  for row in S.duplicates:
    dupes.add(%*{
      "aName": row.aName, "aPath": row.aPath, "aLine": row.aLine,
      "bName": row.bName, "bPath": row.bPath, "bLine": row.bLine,
      "score": row.score, "closeness": row.closeness,
      "shapeMatch": row.shapeMatch, "nameMatch": row.nameMatch,
      "sameModule": row.sameModule, "sameParams": row.sameParams,
      "hint": row.hint
    })
  for row in S.points:
    points.add(%*{
      "id": row.id, "name": row.name, "path": row.path,
      "role": row.role, "x": row.x, "y": row.y, "lines": row.lines
    })
  for row in S.groups:
    groups.add(%*{
      "id": row.id, "label": row.label, "x": row.x, "y": row.y,
      "radius": row.radius, "members": row.members
    })
  result = %*{
    "dims": S.dims, "duplicates": dupes,
    "duplicateCount": S.duplicateCount,
    "points": points, "groups": groups
  }

proc placeholderJson*(S: PlaceholderReport): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## S: routines that do not do anything yet.
  var
    items: JsonNode = newJArray()
  for row in S.items:
    items.add(%*{
      "name": row.name, "path": row.path, "line": row.line,
      "lines": row.lines, "kind": row.kind, "stage": row.stage,
      "score": row.score, "declared": row.declared,
      "called": row.called, "reasons": row.reasons
    })
  result = %*{
    "items": items, "total": S.total,
    "declaredCount": S.declaredCount, "guessedCount": S.guessedCount,
    "uncalledCount": S.uncalledCount
  }

proc secretsJson*(S: SecretReport): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## S: keys and personal data. Only masked previews travel, never a
  ## value in full: this is written into a page and a log, and a
  ## secret repeated there has been leaked a second time.
  var
    items: JsonNode = newJArray()
  for row in S.items:
    items.add(%*{
      "kind": row.kind, "name": row.name, "preview": row.preview,
      "path": row.path, "line": row.line, "commit": row.commit,
      "length": row.length, "score": row.score,
      "entropy": row.entropy, "inHistory": row.inHistory,
      "reasons": row.reasons
    })
  result = %*{
    "items": items, "total": S.total, "keyCount": S.keyCount,
    "userDataCount": S.userDataCount, "historyCount": S.historyCount,
    "commitsRead": S.commitsRead, "error": S.error
  }

proc configJson*(S: ConfigReport): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## S: which settings anything actually reads.
  var
    fields: JsonNode = newJArray()
    conflicts: JsonNode = newJArray()
  for row in S.fields:
    fields.add(%*{
      "name": row.name, "typeName": row.typeName,
      "fieldType": row.fieldType, "verdict": row.verdict,
      "path": row.path, "line": row.line,
      "readCount": row.readCount, "writeCount": row.writeCount,
      "hasDefault": row.hasDefault,
      "readers": row.readers, "writers": row.writers
    })
  for row in S.conflicts:
    conflicts.add(%*{
      "a": row.a, "b": row.b, "kind": row.kind, "detail": row.detail,
      "path": row.path, "line": row.line, "certainty": row.certainty
    })
  result = %*{
    "types": S.types, "fields": fields, "conflicts": conflicts,
    "fieldCount": S.fieldCount, "deadCount": S.deadCount,
    "unsetCount": S.unsetCount, "contestedCount": S.contestedCount,
    "touchingFunctions": S.touchingFunctions
  }

proc timelineJson*(S: TimelineStats): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## S: the repository at a spread of past moments.
  var
    points: JsonNode = newJArray()
  for row in S.points:
    points.add(%*{
      "sha": row.sha, "subject": row.subject, "unix": row.unix,
      "srcFiles": row.srcFiles, "testFiles": row.testFiles,
      "trackedFiles": row.trackedFiles,
      "ignoredFiles": row.ignoredFiles, "bytes": row.bytes,
      "working": row.working
    })
  result = %*{
    "points": points, "commits": S.commits,
    "firstUnix": S.firstUnix, "lastUnix": S.lastUnix,
    "error": S.error
  }

proc unusedFuncsJson*(S: UnusedReport): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## S: routines nothing calls, with their size.
  var
    items: JsonNode = newJArray()
  for row in S.items:
    items.add(%*{
      "name": row.name, "path": row.path, "line": row.line,
      "lines": row.lines, "kind": row.kind, "declKind": row.declKind,
      "exported": row.exported, "hint": row.hint
    })
  result = %*{
    "items": items, "total": S.total,
    "leftoverCount": S.leftoverCount,
    "preparedCount": S.preparedCount, "publicCount": S.publicCount,
    "leftoverLines": S.leftoverLines
  }

proc callDepthJson*(S: CallDepthStats): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## S: how deep the calls go, and who sits at each depth.
  var
    buckets: JsonNode = newJArray()
    deepest: JsonNode = newJArray()
    rings: JsonNode = newJArray()
    roles: JsonNode = newJArray()
  for row in S.buckets:
    roles = newJArray()
    for pair in row.roles:
      roles.add(%*{"name": pair.name, "count": pair.count})
    buckets.add(%*{"depth": row.depth, "count": row.count,
      "roles": roles})
  for row in S.deepest:
    deepest.add(%*{"name": row.name, "path": row.path, "role": row.role,
      "line": row.line, "depth": row.depth, "chain": row.chain})
  for row in S.rings:
    rings.add(%*{"members": row.members})
  result = %*{
    "buckets": buckets, "deepest": deepest, "rings": rings,
    "maxDepth": S.maxDepth, "avgDepth": S.avgDepth,
    "counted": S.counted
  }

proc couplingJson*(S: CouplingStats): JsonNode {.role: dataWriter,
    metaTags: {tagStats}.} =
  ## S: whether every door has a guard, and whether the guards are
  ## themselves tested.
  var
    inputs: JsonNode = newJArray()
    guards: JsonNode = newJArray()
  for row in S.inputs:
    inputs.add(%*{
      "name": row.name, "path": row.path, "line": row.line,
      "role": row.role, "kind": row.kind, "guard": row.guard,
      "via": row.via, "hops": row.hops, "guarded": row.guarded
    })
  for row in S.sanitizers:
    guards.add(%*{
      "name": row.name, "path": row.path, "line": row.line,
      "verdict": row.verdict, "tests": row.tests, "edge": row.edge,
      "regression": row.regression, "bugfix": row.bugfix,
      "guards": row.guards
    })
  result = %*{
    "inputs": inputs, "sanitizers": guards,
    "inputCount": S.inputCount, "guardedCount": S.guardedCount,
    "openCount": S.openCount, "sanitizerCount": S.sanitizerCount,
    "uncheckedCount": S.uncheckedCount,
    "shallowCount": S.shallowCount, "solidCount": S.solidCount,
    "edgeCovered": S.edgeCovered,
    "regressionCovered": S.regressionCovered
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
    "tests": testsJson(S.tests),
    "shape": shapeJson(S.shape),
    "placeholders": placeholderJson(S.placeholders),
    "secrets": secretsJson(S.secrets),
    "config": configJson(S.config),
    "timeline": timelineJson(S.timeline),
    "unusedFuncs": unusedFuncsJson(S.unusedFuncs),
    "callDepth": callDepthJson(S.callDepth),
    "coupling": couplingJson(S.coupling)
  }
