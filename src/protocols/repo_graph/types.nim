# ============================================================
# | Otter Repo Graph Types                                   |
# | -> Shared graph, socket, grouping, and tag primitives    |
# ============================================================

import std/[strutils]

import runePragmas

type
  FunctionRole* {.role: other, tag: "graph|parsing".} = enum
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

  SocketDirection* {.role: other, tag: "graph|parsing".} = enum
    sdInput,
    sdVarInput,
    sdOutput

  RiskTag* {.role: other, tag: "graph|parsing".} = object
    key*: string
    value*: string

  ImportKind* {.role: other, tag: "graph|importContext".} = enum
    ikModule,
    ikSymbol

  ImportBinding* {.role: memory, tag: "graph|importContext".} = object
    kind*: ImportKind
    modulePath*: string
    localName*: string
    remoteName*: string

  FunctionSocket* {.role: truthState, tag: "graph|parsing".} = object
    name*: string
    typeName*: string
    direction*: SocketDirection
    sampleExpr*: string

  FunctionInfo* {.role: truthState, tag: "graph|parsing|importContext".} = object
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

  CallEdge* {.role: truthState, tag: "graph".} = object
    callerId*: string
    calleeId*: string
    callName*: string

  OrchestratorGroup* {.role: truthState, tag: "graph".} = object
    id*: string
    orchestratorId*: string
    label*: string
    directMemberIds*: seq[string]
    memberIds*: seq[string]

  RepoGraph* {.role: truthState, tag: "graph".} = object
    rootDir*: string
    functions*: seq[FunctionInfo]
    edges*: seq[CallEdge]
    unresolvedCalls*: seq[string]
    groups*: seq[OrchestratorGroup]


proc roleToString*(r: FunctionRole): string {.role: helper, tag: "graph|parsing".} =
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


proc parseRole*(s: string): FunctionRole {.role: parser, tag: "graph|parsing".} =
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


proc formatRiskTag*(r: RiskTag): string {.role: helper, tag: "graph|parsing".} =
  if r.value.len > 0:
    result = r.key & "=" & r.value
  else:
    result = r.key


proc socketDirectionToString*(d: SocketDirection): string {.role: helper, tag: "graph".} =
  case d
  of sdInput:
    result = "input"
  of sdVarInput:
    result = "var_input"
  of sdOutput:
    result = "output"


proc isOrchestratorLike*(r: FunctionRole): bool {.role: helper, tag: "graph".} =
  if r == frOrchestrator or r == frMetaOrchestrator:
    result = true
    return


proc isGroupableRole*(r: FunctionRole): bool {.role: helper, tag: "graph".} =
  case r
  of frHelper, frWrapper, frParser, frTruthBuilder, frActor, frDataFetcher, frOther, frUnknown:
    result = true
  else:
    result = false
