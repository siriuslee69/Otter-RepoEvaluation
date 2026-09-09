# ============================================================
# | Otter Code Statistics JSON                               |
# | -> One measured repository, written out for a window     |
# ============================================================
#
# The field names here are the contract every front end reads, so they
# change only when the shape they describe does.

import std/[json]

import ./types
import ./embedded
import ./families
import ./blast
import ./state_writes
import ./yields
import ./diff_review
import ./ui_depth
import runePragmas

proc fileJson*(f: FileStat): JsonNode {.role: dataWriter,
    tag: "stats".} =
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
    tag: "stats".} =
  ## s: one place where a block sits inside another block.
  result = %*{
    "path": s.path, "fn": s.fn, "keyword": s.keyword, "line": s.line,
    "depth": s.depth, "innerLines": s.innerLines, "leaf": s.leaf
  }


proc countsJson*(A: seq[NameCount]): JsonNode {.role: dataWriter,
    tag: "stats".} =
  ## A: any tally of labels.
  result = newJArray()
  for row in A:
    result.add(%*{"name": row.name, "count": row.count})


proc scopeJson*(s: ProjectScopeStats): JsonNode {.role: dataWriter,
    tag: "stats".} =
  ## s: metrics for a subtab scope
  result = %*{
    "files": s.files, "lines": s.lines, "functions": s.functions,
    "templates": s.templates, "macros": s.macros,
    "inputFunctions": s.inputFunctions, "unsafeFunctions": s.unsafeFunctions,
    "avgLines": s.avgLines
  }


proc nestJson*(n: NestStats): JsonNode {.role: dataWriter,
    tag: "stats".} =
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
    tag: "stats".} =
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
    tag: "stats".} =
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

proc familyJson*(S: FamilyReport): JsonNode {.role: dataWriter,
    tag: "stats".} =
  ## S: groups of siblings that are one routine with a knob on it.
  var
    items: JsonNode = newJArray()
    axisNames: array[FamilyAxis, string] = ["type", "value", "term"]
  for row in S.families:
    items.add(%*{
      "level": row.level, "members": row.members, "paths": row.paths,
      "lines": row.lines, "axis": axisNames[row.axis],
      "axisNames": row.axisNames, "varyingDims": row.varyingDims,
      "agreement": row.agreement, "totalLines": row.totalLines,
      "collapsedLines": row.collapsedLines, "score": row.score,
      "remedy": row.remedy, "evidence": row.evidence,
      "byDispatch": row.byDispatch
    })
  result = %*{
    "items": items, "total": S.total,
    "routinesInFamilies": S.routinesInFamilies,
    "linesSaved": S.linesSaved, "error": S.error
  }

proc embeddedJson*(S: EmbeddedReport): JsonNode {.role: dataWriter,
    tag: "stats".} =
  ## S: strings that hold another language.
  var
    items: JsonNode = newJArray()
    langs: JsonNode = newJArray()
  for row in S.blocks:
    items.add(%*{
      "path": row.path, "line": row.line, "lines": row.lines,
      "language": row.language, "comment": row.comment,
      "score": row.score, "reasons": row.reasons
    })
  for row in S.byLanguage:
    langs.add(%*{
      "language": row.name, "blocks": row.count, "lines": row.lines
    })
  result = %*{
    "items": items, "byLanguage": langs, "total": S.total,
    "totalLines": S.totalLines, "error": S.error
  }

proc placeholderJson*(S: PlaceholderReport): JsonNode {.role: dataWriter,
    tag: "stats".} =
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
    tag: "stats".} =
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
    tag: "stats".} =
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
    tag: "stats".} =
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
    tag: "stats".} =
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
    tag: "stats".} =
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
    tag: "stats".} =
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

proc statsJsonAborts(s: ProjectStats): JsonNode {.role: dataWriter,
    tag: "graph".} =
  ## s: one measured repository. The routines that can stop the
  ## program because of something well below them.
  var
    rows: JsonNode = newJArray()
  for a in s.aborts:
    rows.add(%*{"routine": a.routine, "path": a.path, "line": a.line,
      "how": a.how, "via": a.via})
  result = rows

proc statsJsonState(s: ProjectStats): JsonNode {.role: dataWriter,
    tag: "graph|state".} =
  ## s: one measured repository. Its state findings, trimmed to what a
  ## reader has to act on: the proven losses and the dead entries.
  var
    hazards: JsonNode = newJArray()
  for h in s.state.hazards:
    if h.witness.len == 0:
      continue
    hazards.add(%*{"type": h.typeName, "field": h.field, "first": h.first,
      "second": h.second, "witness": h.witness, "path": h.path,
      "firstLine": h.firstLine, "secondLine": h.secondLine})
  result = %*{"proven": hazards, "unread": s.state.unread,
    "states": s.state.states.len}

proc statsJson*(S: ProjectStats): JsonNode {.role: dataWriter,
    tag: "stats".} =
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
    "embedded": embeddedJson(S.embedded),
    "families": familyJson(S.families),
    "state": statsJsonState(S),
    "aborts": statsJsonAborts(S),
    "secrets": secretsJson(S.secrets),
    "config": configJson(S.config),
    "timeline": timelineJson(S.timeline),
    "unusedFuncs": unusedFuncsJson(S.unusedFuncs),
    "callDepth": callDepthJson(S.callDepth),
    "coupling": couplingJson(S.coupling)
  }

proc blastJson*(r: BlastRadius): JsonNode {.role: dataWriter,
    tag: "graph".} =
  ## r: one blast radius, as a tool reads it.
  var
    callers: JsonNode = newJArray()
    feeders: JsonNode = newJArray()
    producers: JsonNode = newJArray()
    consumers: JsonNode = newJArray()
    arguments: JsonNode = newJArray()
  for row in r.callers:
    callers.add(%*{"name": row.name, "path": row.path, "line": row.line,
      "depth": row.depth, "role": row.role})
  for row in r.feeders:
    feeders.add(%*{"name": row.name, "path": row.path, "line": row.line,
      "depth": row.depth})
  for row in r.producers:
    producers.add(%*{"name": row.name, "path": row.path, "line": row.line})
  for row in r.consumers:
    consumers.add(%*{"name": row.name, "path": row.path, "line": row.line})
  for row in r.arguments:
    arguments.add(%*{"position": row.position, "literals": row.literals,
      "fromVariables": row.fromVariables})
  result = %*{
    "target": r.target, "kind": r.kind, "path": r.path, "line": r.line,
    "callerDepth": r.callerDepth, "feederDepth": r.feederDepth,
    "callers": callers, "feeders": feeders, "producers": producers,
    "consumers": consumers, "arguments": arguments,
    "sanitizersAbove": r.sanitizersAbove, "notes": r.notes,
    "error": r.error
  }

proc uiDepthJson*(r: UiDepthReport): JsonNode {.role: dataWriter,
    tag: "stats".} =
  ## r: how deeply the controls of a front end are buried.
  var
    controls: JsonNode = newJArray()
    depths: JsonNode = newJArray()
  for c in r.controls:
    controls.add(%*{"path": c.path, "line": c.line, "tag": c.tag,
      "label": c.label, "depth": c.depth, "gates": c.gates,
      "keyboardOnly": c.keyboardOnly})
  for d in r.byDepth:
    depths.add(%*{"depth": d.depth, "count": d.count})
  result = %*{
    "controls": controls, "byDepth": depths, "total": r.total,
    "deepest": r.deepest, "keyboardOnly": r.keyboardOnly,
    "hiddenClasses": r.hiddenClasses, "error": r.error
  }

proc stateJson*(r: StateReport): JsonNode {.role: dataWriter,
    tag: "graph|state".} =
  ## r: one state-writes answer, as a tool reads it.
  var
    states: JsonNode = newJArray()
    entries: JsonNode = newJArray()
    hazards: JsonNode = newJArray()
  for st in r.states:
    entries = newJArray()
    for e in st.entries:
      entries.add(%*{"field": e.field, "type": e.typeName, "line": e.line,
        "replacedBy": e.blindWriters, "foldedBy": e.foldingWriters,
        "readBy": e.readers, "allowed": e.allowed, "hazard": e.hazard})
    states.add(%*{"name": st.name, "path": st.path, "line": st.line,
      "role": st.role, "entries": entries,
      "wholeWriters": st.wholeWriters})
  for h in r.hazards:
    hazards.add(%*{"type": h.typeName, "field": h.field, "first": h.first,
      "second": h.second, "witness": h.witness, "path": h.path,
      "firstLine": h.firstLine, "secondLine": h.secondLine})
  result = %*{
    "rootDir": r.rootDir, "states": states, "hazards": hazards,
    "unread": r.unread, "notes": r.notes, "error": r.error
  }

proc yieldJson*(r: YieldPaths): JsonNode {.role: dataWriter,
    tag: "graph".} =
  ## r: one yield-paths answer, as a tool reads it.
  var
    outcomes: JsonNode = newJArray()
  for o in r.outcomes:
    outcomes.add(%*{"name": o.name,
      "kind": (if o.kind == okAbort: "abort" else: "raise"),
      "via": o.via, "source": o.source})
  result = %*{
    "target": r.target, "path": r.path, "line": r.line,
    "returnType": r.returnType, "carriesError": r.carriesError,
    "errorField": r.errorField, "outcomes": outcomes,
    "caught": r.caught, "barrier": r.barrier, "declared": r.declared,
    "notes": r.notes, "error": r.error
  }

proc diffJson*(r: DiffReview): JsonNode {.role: dataWriter,
    tag: "stats".} =
  ## r: one diff review, as a tool reads it.
  var
    yours: JsonNode = newJArray()
    nearby: JsonNode = newJArray()
    orphaned: JsonNode = newJArray()
    reach: JsonNode = newJArray()
    hot: JsonNode = newJArray()
  for f in r.yours:
    yours.add(%*{"kind": f.kind, "what": f.what, "path": f.path,
      "line": f.line, "command": f.command})
  for f in r.nearby:
    nearby.add(%*{"kind": f.kind, "what": f.what, "path": f.path,
      "line": f.line, "command": f.command})
  for f in r.orphaned:
    orphaned.add(%*{"kind": f.kind, "what": f.what, "path": f.path,
      "line": f.line, "command": f.command})
  for row in r.reach:
    reach.add(%*{"routine": row.routine, "path": row.path, "line": row.line,
      "callers": row.callers, "names": row.names, "notes": row.notes,
      "command": row.command})
  for f in r.hotFiles:
    hot.add(%*{"path": f.path, "yours": f.yours, "nearby": f.nearby})
  result = %*{
    "rootDir": r.rootDir, "baseRev": r.baseRev, "files": r.files,
    "hunks": r.hunks, "added": r.added, "removed": r.removed,
    "yours": yours, "nearby": nearby, "orphaned": orphaned,
    "reach": reach, "hotFiles": hot, "notes": r.notes, "error": r.error
  }
