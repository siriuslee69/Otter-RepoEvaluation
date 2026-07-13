# ============================================================
# | Otter Test UI Types                                      |
# | -> Discovered tests, display groups, and user settings   |
# ============================================================

import ../../../.iron/metaPragmas

type
  OtterUiTestEntry* {.role: truthState, metaTags: {tagTesting, tagUi}.} = object
    id*: string
    testName*: string
    menu*: string
    filters*: seq[string]
    version*: string
    routine*: string
    line*: int
    sourcePath*: string
    relativePath*: string

  OtterUiConfig* {.role: truthState, metaTags: {tagTesting, tagUi}.} = object
    repoRoot*: string
    testsRoot*: string
    title*: string
    banner*: string
    outputPath*: string
    customCss*: string

  OtterUiCatalog* {.role: truthState, metaTags: {tagTesting, tagUi}.} = object
    config*: OtterUiConfig
    entries*: seq[OtterUiTestEntry]
