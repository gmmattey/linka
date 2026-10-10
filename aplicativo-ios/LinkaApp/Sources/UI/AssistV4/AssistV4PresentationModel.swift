#if os(iOS)
import Foundation
import Combine
import AssistConsultation

@MainActor
final class AssistV4PresentationModel: ObservableObject {
    enum State: Equatable {
        case home
        case guided(intent: ConsultationIntent, question: ConsultationQuestion)
        case unavailableOpenQuestion(String)
        case limitation(String)
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

    func start(_ intent: ConsultationIntent) {
        guard intent != .openQuestion, let question = GuidedJourney.firstQuestion(for: intent) else { return }
        do {
            var coordinator = try localCoordinator(for: intent)
            try coordinator.apply(.start, at: Date())
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
        do {
            var coordinator = try localCoordinator(for: .openQuestion)
            try coordinator.apply(.start, at: Date())
            try coordinator.apply(.recordLocalMessage(text, turnID: reference(prefix: "local-turn")), at: Date())
            try coordinator.apply(.markUnavailable, at: Date())
            self.coordinator = coordinator
            turns = [Turn(role: .user, text: text)]
            state = .unavailableOpenQuestion(text)
        } catch {
            state = .limitation("A pergunta continua no rascunho. Nenhum dado foi enviado.")
        }
    }

    func continueGuided() {
        guard case let .guided(_, question) = state,
              let id = selectedOptionID,
              let option = question.options.first(where: { $0.id == id }),
              var coordinator else { return }
        do {
            try coordinator.apply(.answer(QuestionAnswer(questionID: question.id, optionID: option.id), turnID: reference(prefix: "local-turn")), at: Date())
            try coordinator.apply(.markInsufficientEvidence, at: Date())
            self.coordinator = coordinator
            turns.append(Turn(role: .user, text: option.text))
            selectedOptionID = nil
            state = .limitation("Esta etapa local registrou sua escolha, mas ainda não executa testes nem envia dados. A continuação integrada depende do motor V4 autorizado.")
        } catch {
            state = .limitation("Não foi possível registrar esta escolha localmente. Nenhum dado foi enviado.")
        }
    }

    func returnHome() {
        selectedOptionID = nil
        state = .home
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

    private func reference(prefix: String) -> PseudonymousReference {
        try! PseudonymousReference("\(prefix)-\(UUID().uuidString.lowercased())")
    }
}
#endif
