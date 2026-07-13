## This file should be imported across all files inside src.
## Only the tags are meant to be changed! Everything else should be kept as is!
type
    MetaRole* = enum
        helper, math,
        dataFetcher, decryptor, parser, truthBuilder, metaParser,
        actor, orchestrator, metaOrchestrator, encryptor, dataWriter,
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
        tagTesting,
        tagTiming,
        tagUi,
        tagVsCode
    MetaTags* = set[MetaTag]

template input*(x: set[MetaInput]) {.pragma.}
template role*(x: MetaRole) {.pragma.}
template risk*(x: MetaRisk) {.pragma.}
template speed*(x: MetaSpeed) {.pragma.}
template issues*(x: MetaIssues) {.pragma.}
template metaTags*(x: MetaTags) {.pragma.}
