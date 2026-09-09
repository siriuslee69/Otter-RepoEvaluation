# ============================================================
# | Otter Test UI Types                                      |
# | -> Discovered tests, display groups, and user settings   |
# ============================================================

import runePragmas

type
  OtterUiTestEntry* {.role: truthState, tag: "testing|ui".} = object
    id*: string
    testName*: string
    menu*: string
    filters*: seq[string]
    version*: string
    routine*: string
    line*: int
    sourcePath*: string
    relativePath*: string

  OtterUiConfig* {.role: truthState, tag: "testing|ui".} = object
    repoRoot*: string
    testsRoot*: string
    title*: string
    banner*: string
    outputPath*: string
    customCss*: string
    defaultFlags*: seq[string]

  OtterUiCatalog* {.role: truthState, tag: "testing|ui".} = object
    config*: OtterUiConfig
    entries*: seq[OtterUiTestEntry]
    availableFlags*: seq[string]
    defaultFlags*: seq[string]
