#if os(iOS)
import Foundation
import Combine
import AssistConsultation

@MainActor
final class AssistV4PresentationModel: ObservableObject {
    enum State: Equatable {
        case home
        case guided(intent: ConsultationIntent, question: ConsultationQuestion)
        case unavailableOpenQuestion(String, canResumeGuidance: Bool)
        case limitation(String)
        case guidance(title: String, detail: String)
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
    private var coordinator: ConsultationCoordinator?
    private var slowConnectionAnswers = SlowConnectionAnswers()
    private var suspendedGuidance: (intent: ConsultationIntent, question: ConsultationQuestion)?

    func start(_ intent: ConsultationIntent) {
        guard intent != .openQuestion else { return }
        if intent == .slowConnection { slowConnectionAnswers = SlowConnectionAnswers() }
        suspendedGuidance = nil
        do {
            var coordinator = try localCoordinator(for: intent)
            try coordinator.apply(.start, at: Date())
            if intent == .planValue {
                try coordinator.apply(.markInsufficientEvidence, at: Date())
                self.coordinator = coordinator
                turns = []
                selectedOptionID = nil
                state = .limitation(planLimitation())
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
        if case let .guided(intent, question) = state {
            // A pergunta livre não atravessa o contrato da pergunta guiada nem é
            // enviada. Guardamos somente a apresentação da escolha local para que
            // o usuário possa retornar sem reiniciar a investigação.
            suspendedGuidance = (intent, question)
            turns.append(Turn(role: .user, text: text))
            state = .unavailableOpenQuestion(text, canResumeGuidance: true)
            return
        }
        do {
            var coordinator = try localCoordinator(for: .openQuestion)
            try coordinator.apply(.start, at: Date())
            try coordinator.apply(.recordLocalMessage(text, turnID: reference(prefix: "local-turn")), at: Date())
            try coordinator.apply(.markUnavailable, at: Date())
            self.coordinator = coordinator
            turns.append(Turn(role: .user, text: text))
            state = .unavailableOpenQuestion(text, canResumeGuidance: false)
        } catch {
            state = .limitation("A pergunta continua no rascunho. Nenhum dado foi enviado.")
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
            selectedOptionID = nil
            if intent == .slowConnection {
                try continueSlowConnection(option: option, coordinator: &coordinator)
            } else if intent == .routerAdequacy {
                try continueRouterAdequacy(option: option, coordinator: &coordinator)
            } else if intent == .meshNeed {
                try continueMeshNeed(option: option, coordinator: &coordinator)
            } else {
                try coordinator.apply(.markInsufficientEvidence, at: Date())
                self.coordinator = coordinator
                state = .limitation("Esta etapa local registrou sua escolha, mas ainda não executa testes nem envia dados. A continuação integrada depende do motor V4 autorizado.")
            }
        } catch {
            state = .limitation("Não foi possível registrar esta escolha localmente. Nenhum dado foi enviado.")
        }
    }

    func returnHome() {
        suspendedGuidance = nil
        selectedOptionID = nil
        state = .home
    }

    func resumeGuidance() {
        guard let suspendedGuidance else { return }
        self.suspendedGuidance = nil
        state = .guided(intent: suspendedGuidance.intent, question: suspendedGuidance.question)
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
            state = .guidance(title: "Próxima etapa sugerida", detail: ([objective] + conditions).joined(separator: " "))
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

    private func planLimitation() -> String {
        guard case let .requiresDeclaredPlanData(limitations) = PlanValueLocalJourney.next(after: PlanValueAnswers()) else {
            return "Faltam dados declarados para avaliar o plano localmente."
        }
        return limitations.joined(separator: " ")
    }

    private func reference(prefix: String) -> PseudonymousReference {
        try! PseudonymousReference("\(prefix)-\(UUID().uuidString.lowercased())")
    }
}
#endif
