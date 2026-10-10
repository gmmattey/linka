#if os(iOS)
import Foundation
import Combine
import AssistConsultation

/// Fronteira de apresentação para a consulta remota. A implementação padrão
/// falha fechada; a composição de transporte continua fora desta tela.
enum AssistV4OpenQuestionSubmission: Equatable {
    case response(ConsultationResponse)
    case disabled
    case offline
    case recoverableFailure(String)
}

@MainActor
final class AssistV4PresentationModel: ObservableObject {
    struct LocalOrientation: Equatable {
        let title: String
        let reason: String
        let nextAction: String
        let supportingConditions: [String]
        let declaredAnswers: [String]
        let actionProgress: LocalActionProgress
    }

    enum State: Equatable {
        case home
        case planDeclaration
        case guided(intent: ConsultationIntent, question: ConsultationQuestion)
        case awaitingConsent(question: String)
        case submittingOpenQuestion
        case remoteUnavailable(String)
        case remoteRecoverableError(String)
        case remoteResult(ConsultationAssessment)
        case unavailableOpenQuestion(String, canResumeGuidance: Bool)
        case limitation(String)
        case localOrientation(LocalOrientation)
        case cancelled
    }

    struct Turn: Equatable, Identifiable {
        enum Role: Equatable { case user, assist }
        let id = UUID()
        let role: Role
        let text: String
    }

    @Published var draft = ""
    @Published private(set) var state: State = .home
    @Published private(set) var turns: [Turn] = []
    @Published var selectedOptionID: PseudonymousReference?
    @Published var declaredPlanName = ""
    @Published var declaredPlanPrice = ""
    private var coordinator: ConsultationCoordinator?
    private var slowConnectionAnswers = SlowConnectionAnswers()
    private var planValueAnswers = PlanValueAnswers()
    private var guidedAnswers: [String] = []
    private var suspendedLocalFlow: SuspendedLocalFlow?
    private let submitOpenQuestionRemote: @Sendable (ConsultationPayload) async -> AssistV4OpenQuestionSubmission
    private var pendingRemotePayload: ConsultationPayload?

    private enum SuspendedLocalFlow {
        case guided(intent: ConsultationIntent, question: ConsultationQuestion)
        case planDeclaration
        case localOrientation(LocalOrientation)
    }

    init(
        submitOpenQuestionRemote: @escaping @Sendable (ConsultationPayload) async -> AssistV4OpenQuestionSubmission = { _ in .disabled }
    ) {
        self.submitOpenQuestionRemote = submitOpenQuestionRemote
    }

    func start(_ intent: ConsultationIntent) {
        guard intent != .openQuestion else { return }
        if intent == .slowConnection { slowConnectionAnswers = SlowConnectionAnswers() }
        if intent == .planValue {
            planValueAnswers = PlanValueAnswers()
            clearPlanDeclaration()
        }
        guidedAnswers = []
        suspendedLocalFlow = nil
        do {
            var coordinator = try localCoordinator(for: intent)
            try coordinator.apply(.start, at: Date())
            if intent == .planValue {
                self.coordinator = coordinator
                turns = []
                selectedOptionID = nil
                state = .planDeclaration
                return
            }
            guard let question = firstQuestion(for: intent) else {
                state = .limitation("A investigação local não encontrou uma próxima pergunta. Nenhum dado foi enviado.")
                return
            }
            try coordinator.apply(.askLocal(question), at: Date())
            self.coordinator = coordinator
            turns = []
            selectedOptionID = nil
            state = .guided(intent: intent, question: question)
        } catch {
            state = .limitation("A investigação local não pôde ser iniciada. Nenhum dado foi enviado.")
        }
    }

    func submitOpenQuestion() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch state {
        case let .guided(intent, question):
            // A pergunta livre não atravessa o contrato da pergunta guiada nem é
            // enviada. Guardamos somente a apresentação da escolha local para que
            // o usuário possa retornar sem reiniciar a investigação.
            suspendedLocalFlow = .guided(intent: intent, question: question)
            turns.append(Turn(role: .user, text: text))
            state = .unavailableOpenQuestion(text, canResumeGuidance: true)
            return
        case .planDeclaration:
            suspendedLocalFlow = .planDeclaration
            turns.append(Turn(role: .user, text: text))
            state = .unavailableOpenQuestion(text, canResumeGuidance: true)
            return
        case let .localOrientation(orientation):
            // Sem motor autorizado, a pergunta fica somente nesta apresentação.
            // Preservamos a orientação local em vez de reiniciar silenciosamente a
            // investigação que a pessoa acabara de concluir.
            suspendedLocalFlow = .localOrientation(orientation)
            turns.append(Turn(role: .user, text: text))
            state = .unavailableOpenQuestion(text, canResumeGuidance: true)
            return
        default:
            break
        }
        // A pergunta livre passa primeiro por uma escolha explícita. Não
        // criamos payload, sessão remota ou tráfego antes do consentimento.
        state = .awaitingConsent(question: text)
    }

    func sendOpenQuestionOnly() {
        guard case let .awaitingConsent(text) = state else { return }
        let now = Date()
        do {
            let refused = ConsentReceipt(
                ref: reference(prefix: "consultation-consent"),
                state: .refused,
                scope: .none,
                recordedAt: now
            )
            let session = try InvestigationSession(
                id: reference(prefix: "consultation-session"),
                intent: .openQuestion,
                contextSnapshotVersion: 1,
                consentSnapshot: refused,
                createdAt: now
            )
            var coordinator = ConsultationCoordinator(session: session)
            try coordinator.apply(.start, at: now)
            try coordinator.apply(.contextCollected(revision: 1, consent: refused, requiresConsent: true), at: now)

            let consent = ConsentReceipt(
                ref: reference(prefix: "consultation-consent"),
                state: .granted,
                scope: .question,
                recordedAt: now
            )
            try coordinator.apply(.grantConsent(consent), at: now)
            let snapshot = try ContextSnapshotAssembler.assemble(
                ContextSnapshotAssemblyRequest(
                    snapshotID: reference(prefix: "consultation-snapshot"),
                    revision: 1,
                    intent: .openQuestion,
                    consent: consent
                ),
                at: now
            )
            let payload = ConsultationPayload(
                requestID: reference(prefix: "consultation-request"),
                localSessionID: coordinator.session.id,
                transportSessionID: reference(prefix: "consultation-transport"),
                turnID: reference(prefix: "consultation-turn"),
                expectedRevision: snapshot.revision,
                // `Locale.current.identifier` can carry Unicode extensions
                // (for example, `pt_BR@rg=uszzzz`) that do not belong in the
                // wire contract. The contract accepts a language or
                // language-region tag only.
                locale: Locale.current.language.languageCode?.identifier ?? "pt",
                input: .userMessage(text),
                contextSnapshot: snapshot,
                consentReceiptRef: consent.ref
            )
            try coordinator.apply(.beginRemoteTurn(payload), at: now)
            self.coordinator = coordinator
            pendingRemotePayload = payload
            turns.append(Turn(role: .user, text: text))
            state = .submittingOpenQuestion
            submit(payload)
        } catch {
            state = .limitation("A pergunta continua no rascunho. Nenhum dado foi enviado.")
        }
    }

    func declineOpenQuestionConsent() {
        guard case let .awaitingConsent(text) = state else { return }
        state = .unavailableOpenQuestion(text, canResumeGuidance: false)
    }

    func retryOpenQuestion() {
        guard case .remoteRecoverableError = state,
              let payload = pendingRemotePayload,
              var coordinator else { return }
        do {
            try coordinator.apply(.retry, at: Date())
            try coordinator.apply(.beginRemoteTurn(payload), at: Date())
            self.coordinator = coordinator
            state = .submittingOpenQuestion
            submit(payload)
        } catch {
            state = .remoteUnavailable("Não foi possível retomar a pergunta. Ela continua no rascunho neste aparelho.")
        }
    }

    private func submit(_ payload: ConsultationPayload) {
        let submitOpenQuestionRemote = submitOpenQuestionRemote
        Task { [weak self] in
            let outcome = await submitOpenQuestionRemote(payload)
            self?.receive(outcome, for: payload)
        }
    }

    private func receive(_ outcome: AssistV4OpenQuestionSubmission, for payload: ConsultationPayload) {
        guard pendingRemotePayload?.requestID == payload.requestID else { return }
        switch outcome {
        case .disabled:
            pendingRemotePayload = nil
            state = .remoteUnavailable("A consulta protegida ainda não está habilitada. Sua pergunta não foi enviada.")
        case .offline:
            recoverableRemoteFailure("Você está offline. A pergunta permanece no aparelho e pode ser reenviada.")
        case .recoverableFailure(let message):
            recoverableRemoteFailure(message)
        case .response(let response):
            guard var coordinator else {
                state = .remoteUnavailable("A resposta não pôde ser associada à sua sessão.")
                return
            }
            do {
                try coordinator.apply(.receiveRemoteResponse(response, for: payload), at: Date())
                self.coordinator = coordinator
                pendingRemotePayload = nil
                switch coordinator.session.state {
                case .showingResult:
                    guard let assessment = coordinator.session.recommendation?.assessment else {
                        throw ContractError.invalid("A resposta não trouxe uma conclusão verificável.")
                    }
                    state = .remoteResult(assessment)
                case .recoverableError:
                    state = .remoteRecoverableError("A consulta falhou temporariamente. Você pode tentar de novo.")
                case .unavailable:
                    state = .remoteUnavailable("A consulta não está disponível agora. Sua pergunta permanece no aparelho.")
                default:
                    state = .remoteUnavailable("A consulta pediu uma próxima etapa que ainda não está disponível nesta prova.")
                }
            } catch {
                state = .remoteUnavailable("A resposta recebida não passou na validação da consulta.")
            }
        }
    }

    private func recoverableRemoteFailure(_ message: String) {
        guard var coordinator else {
            state = .remoteUnavailable(message)
            return
        }
        do {
            try coordinator.apply(.recoverableFailure, at: Date())
            self.coordinator = coordinator
            state = .remoteRecoverableError(message)
        } catch {
            state = .remoteUnavailable(message)
        }
    }

    func continueGuided() {
        guard case let .guided(intent, question) = state,
              let id = selectedOptionID,
              let option = question.options.first(where: { $0.id == id }),
              var coordinator else { return }
        do {
            try coordinator.apply(.answer(QuestionAnswer(questionID: question.id, optionID: option.id), turnID: reference(prefix: "local-turn")), at: Date())
            turns.append(Turn(role: .user, text: option.text))
            guidedAnswers.append(option.text)
            selectedOptionID = nil
            if intent == .slowConnection {
                try continueSlowConnection(option: option, coordinator: &coordinator)
            } else if intent == .routerAdequacy {
                try continueRouterAdequacy(option: option, coordinator: &coordinator)
            } else if intent == .meshNeed {
                try continueMeshNeed(option: option, coordinator: &coordinator)
            } else if intent == .planValue {
                try continuePlanValue(option: option, coordinator: &coordinator)
            } else {
                try coordinator.apply(.markInsufficientEvidence, at: Date())
                self.coordinator = coordinator
                state = .limitation("Esta etapa local registrou sua escolha, mas ainda não executa testes nem envia dados. A continuação integrada depende do motor V4 autorizado.")
            }
        } catch {
            state = .limitation("Não foi possível registrar esta escolha localmente. Nenhum dado foi enviado.")
        }
    }

    func goBackFromGuidedQuestion() {
        guard case let .guided(intent, _) = state else { return }
        switch intent {
        case .slowConnection where slowConnectionAnswers.location != nil:
            restartSlowConnectionAtLocationQuestion()
        case .planValue where planValueAnswers.priority != nil:
            restartPlanValueAtPriorityQuestion()
        default:
            returnHome()
        }
    }

    func cancelLocalInvestigation() {
        guard var coordinator else {
            returnHome()
            return
        }
        do {
            try coordinator.apply(.cancel, at: Date())
            try coordinator.apply(.cancellationFinished, at: Date())
            self.coordinator = nil
            suspendedLocalFlow = nil
            slowConnectionAnswers = SlowConnectionAnswers()
            planValueAnswers = PlanValueAnswers()
            clearPlanDeclaration()
            selectedOptionID = nil
            turns = []
            guidedAnswers = []
            state = .cancelled
        } catch {
            state = .limitation("Não foi possível encerrar esta investigação local. Nenhum dado foi enviado.")
        }
    }

    func returnHome() {
        suspendedLocalFlow = nil
        selectedOptionID = nil
        clearPlanDeclaration()
        pendingRemotePayload = nil
        coordinator = nil
        state = .home
    }

    func resumeGuidance() {
        guard let suspendedLocalFlow else { return }
        self.suspendedLocalFlow = nil
        switch suspendedLocalFlow {
        case let .guided(intent, question):
            state = .guided(intent: intent, question: question)
        case .planDeclaration:
            state = .planDeclaration
        case let .localOrientation(orientation):
            state = .localOrientation(orientation)
        }
    }

    func continuePlanDeclaration() {
        guard !declaredPlanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !declaredPlanPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var coordinator else { return }
        do {
            planValueAnswers = PlanValueAnswers(hasDeclaredPlan: true, hasDeclaredPrice: true)
            guard case let .question(question) = PlanValueLocalJourney.next(after: planValueAnswers) else {
                throw ContractError.invalid("A declaração de plano não produziu a próxima pergunta esperada.")
            }
            try coordinator.apply(.askLocal(question), at: Date())
            self.coordinator = coordinator
            clearPlanDeclaration()
            selectedOptionID = nil
            state = .guided(intent: .planValue, question: question)
        } catch {
            state = .limitation("Não foi possível iniciar a avaliação local do plano. Nenhum dado foi enviado.")
        }
    }

    func completeSuggestedAction() {
        updateSuggestedAction(status: .completed)
    }

    func deferSuggestedAction() {
        updateSuggestedAction(status: .ignored)
    }

    func reviseSlowConnectionAnswers() {
        guard case .localOrientation = state,
              let location = slowConnectionAnswers.location,
              let usage = slowConnectionAnswers.usage else { return }
        do {
            var coordinator = try localCoordinator(for: .slowConnection)
            try coordinator.apply(.start, at: Date())

            let firstQuestion = try slowQuestion(after: SlowConnectionAnswers())
            try coordinator.apply(.askLocal(firstQuestion), at: Date())
            guard let locationOption = firstQuestion.options.first(where: { $0.text == slowLocationText(location) }) else {
                throw ContractError.invalid("Opção de local não encontrada ao revisar a investigação.")
            }
            try coordinator.apply(
                .answer(
                    QuestionAnswer(questionID: firstQuestion.id, optionID: locationOption.id),
                    turnID: reference(prefix: "local-turn")
                ),
                at: Date()
            )

            slowConnectionAnswers = try SlowConnectionLocalJourney.applying(locationOption, to: SlowConnectionAnswers())
            let usageQuestion = try slowQuestion(after: slowConnectionAnswers)
            try coordinator.apply(.askLocal(usageQuestion), at: Date())
            guard let usageOption = usageQuestion.options.first(where: { $0.text == slowUsageText(usage) }) else {
                throw ContractError.invalid("Opção de uso não encontrada ao revisar a investigação.")
            }

            self.coordinator = coordinator
            turns = [Turn(role: .user, text: locationOption.text)]
            guidedAnswers = [locationOption.text]
            selectedOptionID = usageOption.id
            state = .guided(intent: .slowConnection, question: usageQuestion)
        } catch {
            state = .limitation("Não foi possível revisar esta investigação local. Nenhum dado foi enviado.")
        }
    }

    private func localCoordinator(for intent: ConsultationIntent) throws -> ConsultationCoordinator {
        let now = Date()
        let consent = ConsentReceipt(
            ref: reference(prefix: "local-consent"),
            state: .refused,
            scope: .none,
            recordedAt: now
        )
        let session = try InvestigationSession(
            id: reference(prefix: "local-session"),
            intent: intent,
            contextSnapshotVersion: 1,
            consentSnapshot: consent,
            createdAt: now
        )
        return ConsultationCoordinator(session: session)
    }

    private func firstQuestion(for intent: ConsultationIntent) -> ConsultationQuestion? {
        switch intent {
        case .slowConnection:
            if case let .question(question) = SlowConnectionLocalJourney.next(after: slowConnectionAnswers) { return question }
        case .routerAdequacy:
            if case let .question(question) = RouterAdequacyLocalJourney.next(after: RouterAdequacyAnswers()) { return question }
        case .meshNeed:
            if case let .question(question) = MeshNeedLocalJourney.next(after: MeshNeedAnswers()) { return question }
        case .planValue, .openQuestion:
            break
        }
        return nil
    }

    private func slowQuestion(after answers: SlowConnectionAnswers) throws -> ConsultationQuestion {
        guard case let .question(question) = SlowConnectionLocalJourney.next(after: answers) else {
            throw ContractError.invalid("A investigação local não encontrou a pergunta esperada.")
        }
        return question
    }

    private func restartSlowConnectionAtLocationQuestion() {
        guard let previousLocation = slowConnectionAnswers.location else {
            returnHome()
            return
        }
        do {
            var coordinator = try localCoordinator(for: .slowConnection)
            try coordinator.apply(.start, at: Date())
            let question = try slowQuestion(after: SlowConnectionAnswers())
            try coordinator.apply(.askLocal(question), at: Date())
            guard let option = question.options.first(where: { $0.text == slowLocationText(previousLocation) }) else {
                throw ContractError.invalid("Opção de local não encontrada ao voltar na investigação.")
            }
            self.coordinator = coordinator
            slowConnectionAnswers = SlowConnectionAnswers()
            turns = []
            guidedAnswers = []
            selectedOptionID = option.id
            state = .guided(intent: .slowConnection, question: question)
        } catch {
            state = .limitation("Não foi possível voltar nesta investigação local. Nenhum dado foi enviado.")
        }
    }

    private func restartPlanValueAtPriorityQuestion() {
        guard let previousPriority = planValueAnswers.priority else {
            returnHome()
            return
        }
        do {
            var coordinator = try localCoordinator(for: .planValue)
            try coordinator.apply(.start, at: Date())
            let declared = PlanValueAnswers(hasDeclaredPlan: true, hasDeclaredPrice: true)
            guard case let .question(question) = PlanValueLocalJourney.next(after: declared) else {
                throw ContractError.invalid("A declaração de plano não produziu a pergunta de prioridade esperada.")
            }
            try coordinator.apply(.askLocal(question), at: Date())
            guard let option = question.options.first(where: { $0.text == planPriorityText(previousPriority) }) else {
                throw ContractError.invalid("Opção de prioridade não encontrada ao voltar na avaliação do plano.")
            }
            self.coordinator = coordinator
            planValueAnswers = declared
            turns = []
            guidedAnswers = []
            selectedOptionID = option.id
            state = .guided(intent: .planValue, question: question)
        } catch {
            state = .limitation("Não foi possível voltar nesta avaliação local do plano. Nenhum dado foi enviado.")
        }
    }

    private func slowLocationText(_ location: SlowConnectionLocation) -> String {
        switch location {
        case .home: "Na casa inteira"
        case .room: "Em um cômodo"
        case .device: "Em um aparelho"
        case .unknown: "Não sei"
        }
    }

    private func slowUsageText(_ usage: SlowConnectionUsage) -> String {
        switch usage {
        case .all: "Em tudo"
        case .service: "Só em um app ou serviço"
        case .unknown: "Não sei"
        }
    }

    private func planPriorityText(_ priority: PlanValuePriority) -> String {
        switch priority {
        case .economy: "Economia"
        case .stability: "Estabilidade"
        case .speed: "Velocidade"
        case .offers: "Entender ofertas"
        case .unknown: "Não sei"
        }
    }

    private func continueSlowConnection(option: QuestionOption, coordinator: inout ConsultationCoordinator) throws {
        slowConnectionAnswers = try SlowConnectionLocalJourney.applying(option, to: slowConnectionAnswers)
        switch SlowConnectionLocalJourney.next(after: slowConnectionAnswers) {
        case let .question(question):
            try coordinator.apply(.askLocal(question), at: Date())
            self.coordinator = coordinator
            state = .guided(intent: .slowConnection, question: question)
        case let .proposedComparison(objective, conditions):
            try coordinator.apply(.markInsufficientEvidence, at: Date())
            self.coordinator = coordinator
            state = .localOrientation(
                LocalOrientation(
                    title: "Próxima etapa sugerida",
                    reason: objective,
                    nextAction: conditions.first ?? "Reúna uma medição ou relato explícito antes de atribuir uma causa.",
                    supportingConditions: Array(conditions.dropFirst()),
                    declaredAnswers: guidedAnswers,
                    actionProgress: LocalActionProgress(
                        actionID: reference(prefix: "local-action"),
                        status: .pending
                    )
                )
            )
        case let .result(_, limitations):
            try coordinator.apply(.markInsufficientEvidence, at: Date())
            self.coordinator = coordinator
            state = .limitation(limitations.joined(separator: " "))
        }
    }

    private func continueRouterAdequacy(option: QuestionOption, coordinator: inout ConsultationCoordinator) throws {
        guard option.text == "Selecionar um equipamento" else {
            try coordinator.apply(.markInsufficientEvidence, at: Date())
            self.coordinator = coordinator
            state = .limitation("Selecione o equipamento e confirme sua identidade, revisão e fonte antes de avaliar capacidade.")
            return
        }
        switch RouterAdequacyLocalJourney.next(after: RouterAdequacyAnswers(equipmentSelected: true)) {
        case let .requiresVerifiedEvidence(limitations):
            try coordinator.apply(.markInsufficientEvidence, at: Date())
            self.coordinator = coordinator
            state = .limitation(limitations.joined(separator: " "))
        default:
            throw ContractError.invalid("Triagem local de roteador retornou uma etapa inesperada.")
        }
    }

    private func continueMeshNeed(option: QuestionOption, coordinator: inout ConsultationCoordinator) throws {
        let area: MeshAffectedArea
        switch option.text {
        case "Em um ambiente": area = .one
        case "Em vários ambientes": area = .many
        case "Na casa toda": area = .all
        case "Não sei": area = .unknown
        default: throw ContractError.invalid("Opção não pertence à triagem de cobertura.")
        }
        switch MeshNeedLocalJourney.next(after: MeshNeedAnswers(affectedArea: area)) {
        case let .requiresCoverageEvidence(limitations), let .result(_, limitations):
            try coordinator.apply(.markInsufficientEvidence, at: Date())
            self.coordinator = coordinator
            state = .limitation(limitations.joined(separator: " "))
        default:
            throw ContractError.invalid("Triagem local de cobertura retornou uma etapa inesperada.")
        }
    }

    private func continuePlanValue(option: QuestionOption, coordinator: inout ConsultationCoordinator) throws {
        if planValueAnswers.priority == nil {
            let priority: PlanValuePriority
            switch option.text {
            case "Economia": priority = .economy
            case "Estabilidade": priority = .stability
            case "Velocidade": priority = .speed
            case "Entender ofertas": priority = .offers
            case "Não sei": priority = .unknown
            default: throw ContractError.invalid("Opção não pertence à triagem de valor do plano.")
            }
            planValueAnswers = PlanValueAnswers(hasDeclaredPlan: true, hasDeclaredPrice: true, priority: priority)
            if priority == .unknown {
                try coordinator.apply(.markInsufficientEvidence, at: Date())
                self.coordinator = coordinator
                state = .limitation("Falta definir o que importa no plano antes de avaliar valor. Nenhuma oferta foi consultada.")
                return
            }
        } else if planValueAnswers.satisfaction == nil {
            let satisfaction: PlanSatisfaction
            switch option.text {
            case "Sim": satisfaction = .satisfied
            case "Não": satisfaction = .dissatisfied
            case "Não sei": satisfaction = .unknown
            default: throw ContractError.invalid("Opção não pertence à satisfação com o plano.")
            }
            planValueAnswers = PlanValueAnswers(
                hasDeclaredPlan: true,
                hasDeclaredPrice: true,
                priority: planValueAnswers.priority,
                satisfaction: satisfaction
            )
            if satisfaction == .unknown {
                try coordinator.apply(.markInsufficientEvidence, at: Date())
                self.coordinator = coordinator
                state = .limitation("Falta saber se o plano atende ao uso antes de avaliar valor. Nenhuma oferta foi consultada.")
                return
            }
        } else {
            throw ContractError.invalid("A triagem local de plano já coletou as respostas disponíveis.")
        }

        switch PlanValueLocalJourney.next(after: planValueAnswers) {
        case let .question(question):
            try coordinator.apply(.askLocal(question), at: Date())
            self.coordinator = coordinator
            state = .guided(intent: .planValue, question: question)
        case let .requiresComparableMeasurements(limitations), let .requiresDeclaredPlanData(limitations), let .result(_, limitations):
            try coordinator.apply(.markInsufficientEvidence, at: Date())
            self.coordinator = coordinator
            state = .limitation(limitations.joined(separator: " "))
        }
    }

    private func clearPlanDeclaration() {
        declaredPlanName = ""
        declaredPlanPrice = ""
    }

    private func updateSuggestedAction(status: LocalActionStatus) {
        guard case let .localOrientation(orientation) = state,
              orientation.actionProgress.status == .pending else { return }
        let progress = LocalActionProgress(
            actionID: orientation.actionProgress.actionID,
            status: status,
            confirmedAt: Date()
        )
        do {
            try ActionRetestLocalPolicy.validate(progress, at: Date())
            state = .localOrientation(
                LocalOrientation(
                    title: orientation.title,
                    reason: orientation.reason,
                    nextAction: orientation.nextAction,
                    supportingConditions: orientation.supportingConditions,
                    declaredAnswers: orientation.declaredAnswers,
                    actionProgress: progress
                )
            )
        } catch {
            state = .limitation("Não foi possível registrar a confirmação desta ação local. Nenhum dado foi enviado.")
        }
    }

    private func reference(prefix: String) -> PseudonymousReference {
        try! PseudonymousReference("\(prefix)-\(UUID().uuidString.lowercased())")
    }
}
#endif
