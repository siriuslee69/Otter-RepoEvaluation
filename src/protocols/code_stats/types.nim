# ============================================================
# | Otter Code Statistics Types                              |
# | -> One repository measured: files, nesting, tests        |
# ============================================================
#
# Everything a window needs to draw a project is in ProjectStats.
# Nothing here reads a file; these are only the shapes.
#
#   ProjectStats
#     files    one cell in the grid, one row in the list
#     nest     the bar chart: templates, doubles, triples, deeper
#     tests    the two rings: how many tests reach each function
#
# The bands are the colours the window uses, named rather than
# numbered so a reader knows what "2" meant six months later.

import ./shape
import ./placeholders
import ./secrets
import ./embedded
import ./families
import ./state_writes
import ./config_touch
import ./timeline
import ./unused
import ./call_depth
import ./coupling

# The six reports become fields of `ProjectStats` below, so anything
# that reads a ProjectStats needs their types too. Re-exported here so
# that a caller importing this file gets the whole shape in one go.
export shape, placeholders, secrets, config_touch, timeline, unused
export call_depth, coupling
import ../../../meta/metaPragmas

type
  HealthBand* {.role: other, metaTags: {tagStats}.} = enum
    ## How long the average routine in one file is.
    ##
    ##   hbOk        short enough to read in one sitting
    ##   hbAlright   long, but still one idea
    ##   hbPoor      two or three ideas in one routine
    ##   hbCritical  nobody reads these top to bottom
    hbOk, hbAlright, hbPoor, hbCritical

  SizeBand* {.role: other, metaTags: {tagStats}.} = enum
    ## How big one file is against every other file in the same tree.
    ## Four bands, because the grid changes its row height every two
    ## rows and so has room for exactly four heights.
    sbHuge, sbBig, sbMid, sbSmall

  NameCount* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One label and how often it was seen. Used for role tallies and
    ## test kinds, so the window never has to know the enums.
    name*: string
    count*: int

  LangStat* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Language extension breakdown
    ext*: string
    files*: int
    lines*: int

  GitignoreStat* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Metrics for files ignored by .gitignore
    ignoredFiles*: int
    ignoredLines*: int

  InputFuncInfo* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Details of an input-accepting or sanitizer function
    name*: string
    path*: string
    line*: int
    lang*: string
    role*: string
    inputSource*: string
    sanitizerName*: string

  UnsafeFuncInfo* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Unsafe functions (cast, addr, uncheckedArray, etc.) and data reach
    name*: string
    path*: string
    line*: int
    lang*: string
    kind*: string
    touchesExternalData*: bool
    externalDataTrace*: string

  UnusedImportInfo* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Unused import location
    moduleName*: string
    path*: string
    line*: int

  WhenSite* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Conditional compilation sites
    path*: string
    line*: int
    condition*: string

  CircularImportInfo* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Dependency cycle detection
    cycle*: seq[string]

  SimdSite* {.role: preparedData, metaTags: {tagStats}.} = object
    ## SIMD usage sites
    path*: string
    line*: int
    feature*: string

  ProjectScopeStats* {.role: preparedData, metaTags: {tagStats}.} = object
    ## Summary metrics scoped by subtab (src, ALL, tests)
    files*: int
    lines*: int
    functions*: int
    templates*: int
    macros*: int
    inputFunctions*: int
    unsafeFunctions*: int
    avgLines*: float

  FileStat* {.role: truthState, metaTags: {tagStats}.} = object
    ## One source file, measured.
    ##
    ##   avgLines   the average length of the routines declared here
    ##   share      this file's length against the longest file, 0..1
    ##   inputs     routines that take user, network, or file input
    ##   templates  routines declared as `template`
    path*: string
    name*: string
    ext*: string
    lang*: string
    lines*: int
    functions*: int
    templates*: int
    macros*: int
    avgLines*: float
    maxLines*: int
    health*: HealthBand
    size*: SizeBand
    share*: float
    inputs*: int
    templateCalls*: int
    nested*: int
    deepest*: int
    untested*: int
    whenCount*: int
    unsafeCount*: int
    unusedImportsCount*: int
    isTest*: bool

  NestSite* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One place where a block sits inside another block.
    ##
    ##   depth       2 is a block in a block, 3 is one deeper again
    ##   innerLines  lines of code inside this block
    ##   leaf        true when nothing deeper sits inside it, which is
    ##               what "the last nesting layer" means
    path*: string
    fn*: string
    keyword*: string
    line*: int
    depth*: int
    innerLines*: int
    leaf*: bool

  NestStats* {.role: truthState, metaTags: {tagStats}.} = object
    ## The bar chart: how much of the tree is nested, and how deep.
    templateCalls*: int
    doubles*: int
    triples*: int
    deeper*: int
    nestedFunctions*: int
    nonMathNested*: int
    mathNested*: int
    innerBuckets*: array[6, int]
      ## Lines inside the last layer, bucketed 1-2, 3-5, 6-10, 11-20,
      ## 21-40, 41 and up.
    sites*: seq[NestSite]

  TestInfo* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One test, wherever it was written: a `test "..."` block, or a
    ## routine carrying a testKind pragma.
    ##
    ##   declared  true when a testKind pragma said what this is, false
    ##             when the kind was read out of the wording instead
    id*: string
    name*: string
    path*: string
    suite*: string
    line*: int
    kind*: string
    declared*: bool
    calls*: seq[string]
    reaches*: int

  TestStats* {.role: truthState, metaTags: {tagStats}.} = object
    ## The rings: how many tests reach each routine, and which kinds.
    ##
    ##   buckets  routines reached by 0, 1, 2, 3, 4, and 5 or more tests
    tests*: int
    declaredKinds*: int
    functions*: int
    buckets*: array[6, int]
    edgeCovered*: int
    benchCovered*: int
    regressionCovered*: int
    bugfixCovered*: int
    kinds*: seq[NameCount]

  ProjectStats* {.role: truthState, metaTags: {tagStats}.} = object
    ## One whole repository, measured.
    rootDir*: string
    isGitRepo*: bool
    files*: seq[FileStat]
    totalLines*: int
    functions*: int
    templates*: int
    macros*: int
    avgLines*: float
    inputFunctions*: int
    truthFunctions*: int
    mathFunctions*: int
    helperFunctions*: int
    unusedCount*: int
    unused*: seq[string]
    roles*: seq[NameCount]
    langStats*: seq[LangStat]
    gitignore*: GitignoreStat
    inputDetails*: seq[InputFuncInfo]
    unsafeDetails*: seq[UnsafeFuncInfo]
    unusedImports*: seq[UnusedImportInfo]
    whenSites*: seq[WhenSite]
    importGraphDepth*: int
    circularImports*: seq[CircularImportInfo]
    platformCoverage*: seq[NameCount]
    simdSites*: seq[SimdSite]
    srcStats*: ProjectScopeStats
    allStats*: ProjectScopeStats
    testStats*: ProjectScopeStats
    nest*: NestStats
    tests*: TestStats

    ## Everything below is worked out by the files beside this one.
    ## Each is a whole report rather than a handful of loose numbers,
    ## so a window can draw one section per report and a reader can
    ## follow each back to the file that produced it.
    shape*: ShapeReport
      ## routines placed by what they are built like: duplicates,
      ## and the point cloud. See `shape.nim`.
    placeholders*: PlaceholderReport
      ## routines that do not do anything yet. See `placeholders.nim`.
    secrets*: SecretReport
      ## keys and personal data, in the tree and in its history.
      ## See `secrets.nim`.
    config*: ConfigReport
      ## which settings anything actually reads. See `config_touch.nim`.
    timeline*: TimelineStats
      ## the repository through time. See `timeline.nim`.
    unusedFuncs*: UnusedReport
      ## routines nothing calls, with their size. See `unused.nim`.
    callDepth*: CallDepthStats
      ## how deep a chain of calls can get, and who sits at each
      ## depth. See `call_depth.nim`.
    families*: FamilyReport
      ## groups of sibling routines that are one routine with a knob
      ## on it. See `families.nim`.
    embedded*: EmbeddedReport
      ## strings that hold another language entirely, and which
      ## comment marks that language uses. See `embedded.nim`.
    state*: StateReport
      ## who may change each entry of a shared object, and where two
      ## of them lose each other's work. See `state_writes.nim`.
    coupling*: CouplingStats
      ## whether every routine taking input from outside is paired
      ## with a sanitizer, and whether those sanitizers are
      ## themselves tested. See `coupling.nim`.
    error*: string

const
  healthNames*: array[HealthBand, string] = ["ok", "alright", "poor",
    "critical"]
  sizeNames*: array[SizeBand, string] = ["huge", "big", "mid", "small"]
  avgOkLines*: int = 12
    ## Up to this many lines on average, a file reads easily.
  avgAlrightLines*: int = 25
  avgPoorLines*: int = 45
    ## Past this the file is drawn red.
  maxSites*: int = 60
    ## How many nesting sites travel to the window. The deepest and
    ## longest ones are kept; the rest are only counted.

proc healthName*(b: HealthBand): string {.role: helper,
    metaTags: {tagStats}.} =
  result = healthNames[b]


proc sizeName*(b: SizeBand): string {.role: helper, metaTags: {tagStats}.} =
  result = sizeNames[b]


proc healthOf*(avg: float): HealthBand {.role: parser,
    metaTags: {tagStats}.} =
  ## avg: the average routine length in one file.
  result = hbCritical
  if avg <= avgOkLines.float:
    result = hbOk
  elif avg <= avgAlrightLines.float:
    result = hbAlright
  elif avg <= avgPoorLines.float:
    result = hbPoor


proc bucketOf*(innerLines: int): int {.role: parser, metaTags: {tagStats}.} =
  ## innerLines: code lines inside the last nesting layer.
  result = 5
  if innerLines <= 2:
    result = 0
  elif innerLines <= 5:
    result = 1
  elif innerLines <= 10:
    result = 2
  elif innerLines <= 20:
    result = 3
  elif innerLines <= 40:
    result = 4


proc addCount*(A: var seq[NameCount], name: string, n: int = 1)
    {.role: actor, metaTags: {tagStats}.} =
  ## A: tally being grown. name: the label. n: how much to add.
  var
    i: int = 0
  if name.len == 0:
    return
  while i < A.len:
    if A[i].name == name:
      A[i].count = A[i].count + n
      return
    i = i + 1
  A.add(NameCount(name: name, count: n))


proc countOf*(A: seq[NameCount], name: string): int {.role: parser,
    metaTags: {tagStats}.} =
  ## A: tally. name: the label wanted. Missing labels read as zero.
  result = 0
  for row in A:
    if row.name == name:
      result = row.count
      return
