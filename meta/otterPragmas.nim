## This file should be imported across all files inside src.
## Only the tags are meant to be changed! Everything else should be kept as is!
##
## The shape of this file comes from Proto-RepoTemplate/meta/metaPragmas.nim.
## Otter reads these pragmas out of every repository it is pointed at, so
## the names here and the names there have to stay the same word for word.
##
##   src/   -> role / input / risk / speed / metaTags   what a proc is
##   tests/ -> testKind / covers / pins                 what a test proves
type
    MetaRole* = enum
        helper, math,
        dataFetcher, decryptor, sanitizer, parser, truthBuilder, metaParser,
        actor, orchestrator, metaOrchestrator, encryptor, dataWriter,
        configurator,
        other,
        rawData, preparedData,
        truthState, memory

    MetaInput* = enum
        user, llm, thirdParty, trusted
    MetaRisk* = enum
        `low`, `medium`, `high`
    MetaSpeed* {.pure.} = enum
        fast, medium, long, `data-dependent`
    MetaIssue* = tuple
        name: string # short description or name
        id: uint64 #issues id/reference
    MetaIssues* = seq[MetaIssue]
    MetaTag* = enum
        tagExecution,
        tagGraph,
        tagImportContext,
        tagInstrumentation,
        tagParsing,
        tagLogging,
        tagParentIntegration,
        tagResolution,
        tagSigma,
        tagState,
        tagStats,
        tagTesting,
        tagTiming,
        tagUi,
        tagVsCode
    MetaTags* = set[MetaTag]

    MetaTestKind* = enum
        ## What one test is for. A test carries exactly one of these, so
        ## a suite can be read as a shape rather than a list of names.
        ##
        ##   tkUnit         one proc, ordinary input
        ##   tkEdgeCase     the ends of the range: empty, zero, one, huge
        ##   tkBenchmark    speed or size, measured rather than asserted
        ##   tkRegression   something that broke once and must not again
        ##   tkBugfix       one named bug, pinned by `pins`
        ##   tkIntegration  several parts together
        ##   tkFuzz         random or generated input
        ##   tkSmoke        the thing starts at all
        ##   tkProperty     a law that must hold for every input
        ##   tkOther        anything the list above does not cover
        tkUnit, tkEdgeCase, tkBenchmark, tkRegression, tkBugfix,
        tkIntegration, tkFuzz, tkSmoke, tkProperty, tkOther
    MetaTestKinds* = set[MetaTestKind]

    MetaStage* = enum
        ## How finished one routine is. A routine without this pragma is
        ## taken to be finished; the pragma exists so that a routine
        ## that is NOT finished can say so out loud, instead of being
        ## guessed at from the wording of its body.
        ##
        ##   stStubbed     declared, and does nothing yet
        ##   stPartial     some of it works, some of it does not
        ##   stDeprecated  still here, on its way out
        ##   stDone        finished, said explicitly
        stStubbed, stPartial, stDeprecated, stDone

template input*(x: MetaInput) {.pragma.}
template input*(x: set[MetaInput]) {.pragma.}
template role*(x: MetaRole) {.pragma.}
template role*(x: set[MetaRole]) {.pragma.}
template risk*(x: MetaRisk) {.pragma.}
template speed*(x: MetaSpeed) {.pragma.}
template issues*(x: MetaIssues) {.pragma.}
template metaTags*(x: MetaTags) {.pragma.}
template stage*(x: MetaStage) {.pragma.}

template testKind*(x: MetaTestKind) {.pragma.}
template testKind*(x: MetaTestKinds) {.pragma.}
template covers*(x: string) {.pragma.}
template covers*(x: seq[string]) {.pragma.}
template pins*(x: MetaIssue) {.pragma.}
template pins*(x: MetaIssues) {.pragma.}
