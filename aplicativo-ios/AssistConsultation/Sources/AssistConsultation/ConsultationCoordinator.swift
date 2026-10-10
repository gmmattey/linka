import Foundation

/// Estados locais e determinísticos da consulta. Este coordenador não possui
/// transporte, provider, banco ou executor de teste: ele somente aceita eventos
/// já validados e exige um gesto explícito antes de expor uma execução física.
public enum InvestigationState: String, Codable, CaseIterable, Sendable {
    case idle
    case collectingContext = "collecting_context"
    case awaitingConsent = "awaiting_consent"
    case planning
    case awaitingUserAnswer = "awaiting_user_answer"
    case awaitingTestPermission = "awaiting_test_permission"
    case executingTest = "executing_test"
    case generatingResult = "generating_result"
    case showingResult = "showing_result"
    case actionPending = "action_pending"
    case awaitingRetest = "awaiting_retest"
    case completed, paused, cancelling, cancelled
    case recoverableError = "recoverable_error"
    case unavailable
    case insufficientEvidence = "insufficient_evidence"
}

public enum InvestigationRole: String, Codable, Sendable { case user, assistant, system }

public struct InvestigationTurn: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let role: InvestigationRole
    public let structuredPayload: ConsultationInput
    public let createdAt: Date

    public init(id: PseudonymousReference, role: InvestigationRole, structuredPayload: ConsultationInput, createdAt: Date) {
        self.id = id
        self.role = role
        self.structuredPayload = structuredPayload
        self.createdAt = createdAt
    }
}

public struct InvestigationToolRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let toolType: ConsultationTool
    public let arguments: [ToolArgument]
    public let userApprovalRequired: Bool
    public let revision: Int
    public let expiresAt: Date

    public init(id: PseudonymousReference, toolType: ConsultationTool, arguments: [ToolArgument], userApprovalRequired: Bool, revision: Int, expiresAt: Date) {
        self.id = id
        self.toolType = toolType
        self.arguments = arguments
        self.userApprovalRequired = userApprovalRequired
        self.revision = revision
        self.expiresAt = expiresAt
    }
}

public struct InvestigationToolResult: Codable, Equatable, Sendable {
    public let requestID: PseudonymousReference
    public let status: ToolResultStatus
    public let evidenceRefs: [PseudonymousReference]
    public let errorCode: ConsultationErrorCode?

    public init(requestID: PseudonymousReference, status: ToolResultStatus, evidenceRefs: [PseudonymousReference] = [], errorCode: ConsultationErrorCode? = nil) {
        self.requestID = requestID
        self.status = status
        self.evidenceRefs = evidenceRefs
        self.errorCode = errorCode
    }
}

public struct InvestigationRemoteTurn: Codable, Equatable, Sendable {
    public let requestID: PseudonymousReference
    public let transportSessionID: PseudonymousReference
    public let turnID: PseudonymousReference
    public let revision: Int

    public init(requestID: PseudonymousReference, transportSessionID: PseudonymousReference, turnID: PseudonymousReference, revision: Int) {
        self.requestID = requestID
        self.transportSessionID = transportSessionID
        self.turnID = turnID
        self.revision = revision
    }
}

public struct InvestigationRecommendation: Codable, Equatable, Sendable {
    public let assessment: ConsultationAssessment
    public let actions: [ActionProposal]

    public init(assessment: ConsultationAssessment, actions: [ActionProposal] = []) {
        self.assessment = assessment
        self.actions = actions
    }
}

public struct InvestigationSession: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let intent: ConsultationIntent
    public internal(set) var state: InvestigationState
    public internal(set) var contextSnapshotVersion: Int
    public internal(set) var consentSnapshot: ConsentReceipt
    public internal(set) var answers: [QuestionAnswer]
    public internal(set) var evidenceRefs: [PseudonymousReference]
    public internal(set) var recommendedActionIDs: [PseudonymousReference]
    public let createdAt: Date
    public internal(set) var updatedAt: Date
    public internal(set) var turns: [InvestigationTurn]
    public internal(set) var pendingToolRequest: InvestigationToolRequest?
    public internal(set) var pendingRemoteTurn: InvestigationRemoteTurn?
    public internal(set) var recommendation: InvestigationRecommendation?
    var resumeState: InvestigationState?
    var pendingQuestion: ConsultationQuestion?

    public init(id: PseudonymousReference, intent: ConsultationIntent, contextSnapshotVersion: Int, consentSnapshot: ConsentReceipt, createdAt: Date) throws {
        guard contextSnapshotVersion > 0 else { throw ContractError.invalid("Sessão exige revisão inicial válida.") }
        self.id = id
        self.intent = intent
        self.state = .idle
        self.contextSnapshotVersion = contextSnapshotVersion
        self.consentSnapshot = consentSnapshot
        self.answers = []
        self.evidenceRefs = []
        self.recommendedActionIDs = []
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.turns = []
        self.pendingToolRequest = nil
        self.pendingRemoteTurn = nil
        self.recommendation = nil
        self.pendingQuestion = nil
    }
}

public enum InvestigationEvent: Sendable {
    case start
    case contextCollected(revision: Int, consent: ConsentReceipt, requiresConsent: Bool)
    case grantConsent(ConsentReceipt)
    case revokeConsent(ConsentReceipt)
    case denyConsent
    case beginPlanning
    case beginRemoteTurn(ConsultationPayload)
    case receiveRemoteResponse(ConsultationResponse, for: ConsultationPayload)
    case ask(ConsultationQuestion)
    case answer(QuestionAnswer, turnID: PseudonymousReference)
    case proposeTest(ToolProposal)
    case approveTest(proposalID: PseudonymousReference)
    case denyTest(proposalID: PseudonymousReference)
    case testFinished(InvestigationToolResult)
    case beginGenerating
    case showRecommendation(InvestigationRecommendation)
    case acceptAction(ActionProposal)
    case actionFeedback(ActionFeedbackPayload)
    case requestRetest
    case complete
    case pause
    case resume
    case cancel
    case cancellationFinished
    case recoverableFailure
    case retry
    case markUnavailable
    case markInsufficientEvidence
}

/// Reducer síncrono. A camada de UI chama `apply` somente em resposta a um
/// gesto, uma coleta local ou uma resposta contratual já validada.
public struct ConsultationCoordinator: Sendable {
    public private(set) var session: InvestigationSession

    public init(session: InvestigationSession) { self.session = session }

    public mutating func apply(_ event: InvestigationEvent, at now: Date) throws {
        switch event {
        case .start:
            try transition(from: [.idle], to: .collectingContext, at: now)
        case let .contextCollected(revision, consent, requiresConsent):
            guard session.state == .collectingContext, revision >= session.contextSnapshotVersion else { throw invalidTransition() }
            session.contextSnapshotVersion = revision
            session.consentSnapshot = consent
            try transition(to: requiresConsent || consent.state != .granted || !consent.scope.permitsQuestion ? .awaitingConsent : .planning, at: now)
        case let .grantConsent(consent):
            guard session.state == .awaitingConsent, consent.state == .granted, consent.scope.permitsQuestion else { throw invalidTransition() }
            session.consentSnapshot = consent
            try transition(to: .planning, at: now)
        case let .revokeConsent(consent):
            guard session.state != .idle, session.state != .completed, session.state != .cancelled, consent.state == .revoked else { throw invalidTransition() }
            session.consentSnapshot = consent
            session.pendingToolRequest = nil
            session.pendingRemoteTurn = nil
            session.pendingQuestion = nil
            try transition(to: .awaitingConsent, at: now)
        case .denyConsent:
            try transition(from: [.awaitingConsent], to: .insufficientEvidence, at: now)
        case .beginPlanning:
            try transition(from: [.collectingContext, .awaitingUserAnswer, .actionPending, .awaitingRetest, .recoverableError], to: .planning, at: now)
        case let .beginRemoteTurn(payload):
            guard session.state == .planning, session.pendingRemoteTurn == nil,
                  payload.localSessionID == session.id,
                  payload.contextSnapshot.intent == session.intent,
                  payload.expectedRevision == session.contextSnapshotVersion else { throw invalidTransition() }
            try payload.validate(at: now)
            session.pendingRemoteTurn = InvestigationRemoteTurn(requestID: payload.requestID, transportSessionID: payload.transportSessionID, turnID: payload.turnID, revision: payload.expectedRevision)
            try transition(to: .generatingResult, at: now)
        case let .receiveRemoteResponse(response, payload):
            guard session.state == .generatingResult,
                  let pending = session.pendingRemoteTurn,
                  payload.localSessionID == session.id,
                  payload.requestID == pending.requestID,
                  payload.transportSessionID == pending.transportSessionID,
                  payload.turnID == pending.turnID,
                  payload.expectedRevision == pending.revision,
                  pending.requestID == response.requestID,
                  pending.transportSessionID == response.transportSessionID,
                  pending.turnID == response.turnID,
                  pending.revision == response.revision else { throw invalidTransition() }
            try response.validate(for: payload, at: now)
            session.pendingRemoteTurn = nil
            switch response.outcome {
            case .error(let error):
                if error.recoverable {
                    session.resumeState = .planning
                    try transition(to: .recoverableError, at: now)
                } else {
                    try transition(to: .unavailable, at: now)
                }
            case .turn(let turn):
                guard turn.intent == session.intent else { throw invalidTransition() }
                switch (turn.disposition, turn.next) {
                case (.awaitingAnswer, .question(let question)):
                    session.pendingQuestion = question
                    try transition(to: .awaitingUserAnswer, at: now)
                case (.awaitingApproval, .toolProposal(let proposal)):
                    guard proposal.tool == .runExistingTest, proposal.revision == session.contextSnapshotVersion, proposal.expiresAt > now else { throw invalidTransition() }
                    session.pendingToolRequest = InvestigationToolRequest(id: proposal.id, toolType: proposal.tool, arguments: proposal.arguments, userApprovalRequired: true, revision: proposal.revision, expiresAt: proposal.expiresAt)
                    try transition(to: .awaitingTestPermission, at: now)
                case (_, .none), (_, .actionProposal):
                    guard let assessment = turn.assessment else { throw invalidTransition() }
                    let actions: [ActionProposal]
                    if case .actionProposal(let action) = turn.next { actions = [action] } else { actions = [] }
                    session.recommendation = InvestigationRecommendation(assessment: assessment, actions: actions)
                    session.recommendedActionIDs = actions.map(\.id)
                    try transition(to: turn.disposition == .unavailable ? .unavailable : .showingResult, at: now)
                default:
                    throw invalidTransition()
                }
            }
        case let .ask(question):
            guard session.state == .planning else { throw invalidTransition() }
            guard question.nextState == .awaitingAnswer else { throw ContractError.invalid("Pergunta com próximo estado inválido.") }
            session.pendingQuestion = question
            try transition(to: .awaitingUserAnswer, at: now)
        case let .answer(answer, turnID):
            guard session.state == .awaitingUserAnswer, let question = session.pendingQuestion, question.id == answer.questionID else { throw invalidTransition() }
            try answer.validate()
            if let optionID = answer.optionID, !question.options.contains(where: { $0.id == optionID }) { throw ContractError.invalid("Opção não pertence à pergunta ativa.") }
            if answer.text != nil, !question.allowFreeText { throw ContractError.invalid("Pergunta não aceita texto livre.") }
            guard !session.answers.contains(where: { $0.questionID == answer.questionID }) else { throw ContractError.invalid("Resposta repetida para a mesma pergunta.") }
            session.answers.append(answer)
            session.pendingQuestion = nil
            session.turns.append(InvestigationTurn(id: turnID, role: .user, structuredPayload: .answer(answer), createdAt: now))
            try transition(to: .collectingContext, at: now)
        case let .proposeTest(proposal):
            guard session.state == .planning, session.consentSnapshot.state == .granted, session.consentSnapshot.scope.permitsContext,
                  proposal.revision == session.contextSnapshotVersion, proposal.expiresAt > now,
                  proposal.tool == .runExistingTest else { throw invalidTransition() }
            guard session.pendingToolRequest == nil else { throw ContractError.invalid("Já existe uma proposta de teste ativa.") }
            session.pendingToolRequest = InvestigationToolRequest(id: proposal.id, toolType: proposal.tool, arguments: proposal.arguments, userApprovalRequired: true, revision: proposal.revision, expiresAt: proposal.expiresAt)
            try transition(to: .awaitingTestPermission, at: now)
        case let .approveTest(proposalID):
            guard session.state == .awaitingTestPermission,
                  let request = session.pendingToolRequest,
                  request.id == proposalID,
                  request.revision == session.contextSnapshotVersion,
                  request.expiresAt > now else { throw invalidTransition() }
            try transition(to: .executingTest, at: now)
        case let .denyTest(proposalID):
            guard session.state == .awaitingTestPermission, session.pendingToolRequest?.id == proposalID else { throw invalidTransition() }
            session.pendingToolRequest = nil
            try transition(to: .collectingContext, at: now)
        case let .testFinished(result):
            guard session.state == .executingTest, session.pendingToolRequest?.id == result.requestID else { throw invalidTransition() }
            guard !Set(result.evidenceRefs).isEmpty || result.status != .completed else { throw ContractError.invalid("Teste concluído sem evidência explícita.") }
            session.evidenceRefs = Array(Set(session.evidenceRefs + result.evidenceRefs)).sorted { $0.value < $1.value }
            session.pendingToolRequest = nil
            try transition(to: .generatingResult, at: now)
        case .beginGenerating:
            try transition(from: [.planning], to: .generatingResult, at: now)
        case let .showRecommendation(recommendation):
            guard session.state == .generatingResult else { throw invalidTransition() }
            guard Set(recommendation.assessment.evidenceRefs).isSubset(of: Set(session.evidenceRefs)) else { throw ContractError.invalid("Recomendação referencia evidência ausente na sessão.") }
            session.recommendation = recommendation
            session.recommendedActionIDs = recommendation.actions.map(\.id)
            try transition(to: .showingResult, at: now)
        case let .acceptAction(action):
            guard session.state == .showingResult, session.recommendedActionIDs.contains(action.id) else { throw invalidTransition() }
            try transition(to: .actionPending, at: now)
        case let .actionFeedback(feedback):
            guard session.state == .actionPending, session.recommendedActionIDs.contains(feedback.actionID) else { throw invalidTransition() }
            try transition(to: .showingResult, at: now)
        case .requestRetest:
            try transition(from: [.showingResult, .actionPending], to: .awaitingRetest, at: now)
        case .complete:
            try transition(from: [.showingResult, .actionPending, .awaitingRetest, .insufficientEvidence, .unavailable], to: .completed, at: now)
        case .pause:
            guard session.state != .idle, session.state != .completed, session.state != .cancelled, session.state != .executingTest else { throw invalidTransition() }
            session.resumeState = session.state
            try transition(to: .paused, at: now)
        case .resume:
            guard session.state == .paused, let resumeState = session.resumeState, resumeState != .executingTest else { throw invalidTransition() }
            session.resumeState = nil
            try transition(to: resumeState, at: now)
        case .cancel:
            guard session.state != .idle, session.state != .completed, session.state != .cancelled, session.state != .cancelling else { throw invalidTransition() }
            try transition(to: .cancelling, at: now)
        case .cancellationFinished:
            guard session.state == .cancelling else { throw invalidTransition() }
            session.pendingToolRequest = nil
            session.pendingRemoteTurn = nil
            session.pendingQuestion = nil
            try transition(to: .cancelled, at: now)
        case .recoverableFailure:
            guard session.state != .idle, session.state != .completed, session.state != .cancelled else { throw invalidTransition() }
            if session.state == .executingTest {
                session.pendingToolRequest = nil
                session.resumeState = .collectingContext
            } else {
                session.pendingRemoteTurn = nil
                session.resumeState = session.state
            }
            try transition(to: .recoverableError, at: now)
        case .retry:
            guard session.state == .recoverableError, let resumeState = session.resumeState, resumeState != .executingTest else { throw invalidTransition() }
            session.resumeState = nil
            try transition(to: resumeState, at: now)
        case .markUnavailable:
            try transition(from: [.planning, .generatingResult], to: .unavailable, at: now)
        case .markInsufficientEvidence:
            try transition(from: [.planning, .generatingResult], to: .insufficientEvidence, at: now)
        }
    }

    private func invalidTransition() -> ContractError { .invalid("Transição da sessão não autorizada.") }

    private mutating func transition(from states: Set<InvestigationState>, to state: InvestigationState, at now: Date) throws {
        guard states.contains(session.state) else { throw invalidTransition() }
        try transition(to: state, at: now)
    }

    private mutating func transition(to state: InvestigationState, at now: Date) throws {
        guard now >= session.updatedAt else { throw ContractError.invalid("Tempo da sessão não pode retroceder.") }
        session.state = state
        session.updatedAt = now
    }
}
