# ============================================================
# | Otter Repo Graph Types                                   |
# | -> Shared graph, socket, grouping, and tag primitives    |
# ============================================================

import std/[strutils]

import ../../../meta/metaPragmas

type
  FunctionRole* {.role: other, metaTags: {tagGraph, tagParsing}.} = enum
    frUnknown,
    frHelper,
    frWrapper,
    frParser,
    frTruthBuilder,
    frActor,
    frDataFetcher,
    frOrchestrator,
    frMetaOrchestrator,
    frStateController,
    frOther

  SocketDirection* {.role: other, metaTags: {tagGraph, tagParsing}.} = enum
    sdInput,
    sdVarInput,
    sdOutput

  RiskTag* {.role: other, metaTags: {tagGraph, tagParsing}.} = object
    key*: string
    value*: string

  ImportKind* {.role: other, metaTags: {tagGraph, tagImportContext}.} = enum
    ikModule,
    ikSymbol

  ImportBinding* {.role: memory, metaTags: {tagGraph, tagImportContext}.} = object
    kind*: ImportKind
    modulePath*: string
    localName*: string
    remoteName*: string

  FunctionSocket* {.role: truthState, metaTags: {tagGraph, tagParsing}.} = object
    name*: string
    typeName*: string
    direction*: SocketDirection
    sampleExpr*: string

  FunctionInfo* {.role: truthState, metaTags: {tagGraph, tagParsing, tagImportContext}.} = object
    id*: string
    declKind*: string
    modulePath*: string
    importModulePath*: string
    sourcePath*: string
    name*: string
    signature*: string
    params*: seq[string]
    sockets*: seq[FunctionSocket]
    returnType*: string
    isExported*: bool
    lineStart*: int
    lineEnd*: int
    bodyLines*: seq[string]
    calls*: seq[string]
    docCommentLines*: seq[string]
    leadingCommentLines*: seq[string]
    innerCommentLines*: seq[string]
    tooltipText*: string
    declaredRole*: FunctionRole
    role*: FunctionRole
    roleConfidence*: float
    roleReason*: string
    pragmaTags*: seq[string]
    riskTags*: seq[RiskTag]
    issueRefs*: seq[string]
    importBindings*: seq[ImportBinding]
    userInputDeclared*: bool
    handlesUserInput*: bool
    userInputSignals*: seq[string]
    userInputReason*: string

  CallEdge* {.role: truthState, metaTags: {tagGraph}.} = object
    callerId*: string
    calleeId*: string
    callName*: string

  OrchestratorGroup* {.role: truthState, metaTags: {tagGraph}.} = object
    id*: string
    orchestratorId*: string
    label*: string
    directMemberIds*: seq[string]
    memberIds*: seq[string]

  RepoGraph* {.role: truthState, metaTags: {tagGraph}.} = object
    rootDir*: string
    functions*: seq[FunctionInfo]
    edges*: seq[CallEdge]
    unresolvedCalls*: seq[string]
    groups*: seq[OrchestratorGroup]


proc roleToString*(r: FunctionRole): string {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  case r
  of frHelper:
    result = "helper"
  of frWrapper:
    result = "wrapper"
  of frParser:
    result = "parser"
  of frTruthBuilder:
    result = "truth_builder"
  of frActor:
    result = "actor"
  of frDataFetcher:
    result = "data_fetcher"
  of frOrchestrator:
    result = "orchestrator"
  of frMetaOrchestrator:
    result = "meta_orchestrator"
  of frStateController:
    result = "state_controller"
  of frOther:
    result = "other"
  else:
    result = "unknown"


proc parseRole*(s: string): FunctionRole {.role: parser, metaTags: {tagGraph, tagParsing}.} =
  var
    t: string = ""
  t = s.strip().toLowerAscii().replace("-", "_")
  case t
  of "helper":
    result = frHelper
  of "wrapper":
    result = frWrapper
  of "parser", "metaparser", "meta_parser":
    result = frParser
  of "truthbuilder", "truth_builder":
    result = frTruthBuilder
  of "actor":
    result = frActor
  of "datafetcher", "data_fetcher", "fetcher":
    result = frDataFetcher
  of "orchestrator":
    result = frOrchestrator
  of "metaorchestrator", "meta_orchestrator":
    result = frMetaOrchestrator
  of "state_controller", "statecontroller", "controller", "truthstate":
    result = frStateController
  of "other":
    result = frOther
  else:
    result = frUnknown


proc formatRiskTag*(r: RiskTag): string {.role: helper, metaTags: {tagGraph, tagParsing}.} =
  if r.value.len > 0:
    result = r.key & "=" & r.value
  else:
    result = r.key


proc socketDirectionToString*(d: SocketDirection): string {.role: helper, metaTags: {tagGraph}.} =
  case d
  of sdInput:
    result = "input"
  of sdVarInput:
    result = "var_input"
  of sdOutput:
    result = "output"


proc isOrchestratorLike*(r: FunctionRole): bool {.role: helper, metaTags: {tagGraph}.} =
  if r == frOrchestrator or r == frMetaOrchestrator:
    result = true
    return


proc isGroupableRole*(r: FunctionRole): bool {.role: helper, metaTags: {tagGraph}.} =
  case r
  of frHelper, frWrapper, frParser, frTruthBuilder, frActor, frDataFetcher, frOther, frUnknown:
    result = true
  else:
    result = false
