## Otter checks its own conventions <- full findings plus a per-rule count.
## Run with nimble runStatistics. JSON is generated beside this source file.

import std/[json, os, strutils, tables]
import runePragmas
import otter_repo_evaluation

proc collectFindings(dir: string): seq[ConventionFinding] {.role: orchestrator.} =
  ## dir: root. Read own Nim files, including config.nims, and check the layout.
  result = scanLayout(dir)
  for p in ownFiles(dir):
    if extensionOf(p) in ["nim", "nims"]:
      result.add(scanConventions(normalizeSlashes(relativePath(p, dir)), readFile(p)))

proc writeFindings(F: seq[ConventionFinding], p: string) {.role: dataWriter.} =
  ## F: complete findings; p: generated JSON path.
  var
    rows: JsonNode = newJArray()
  for f in F:
    rows.add(%*{"checkId": f.checkId, "path": f.path, "line": f.line,
      "severity": $f.severity, "message": f.message})
  writeFile(p, pretty(rows) & "\n")

proc main() {.role: orchestrator, testKind: tkOther,
    covers: "scanConventions|scanLayout".} =
  ## Print counts; retain every location in the generated JSON report.
  var
    dir: string = currentSourcePath().parentDir.parentDir.parentDir
    F: seq[ConventionFinding] = collectFindings(dir)
    counts: CountTable[string] = initCountTable[string]()
    path: string = dir / "evaluation" / "statistics" / "conventions.json"
  for f in F:
    counts.inc(f.checkId)
  for r in conventionRules():
    echo align($counts.getOrDefault(r.id), 5) & "  " & r.title
  writeFindings(F, path)
  echo "Full findings: " & path

when isMainModule:
  main()
