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

    func start(_ intent: ConsultationIntent) {
        guard intent != .openQuestion, let question = GuidedJourney.firstQuestion(for: intent) else { return }
        selectedOptionID = nil
        state = .guided(intent: intent, question: question)
    }

    func submitOpenQuestion() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state = .unavailableOpenQuestion(text)
    }

    func continueGuided() {
        guard case let .guided(_, question) = state,
              let id = selectedOptionID,
              let option = question.options.first(where: { $0.id == id }) else { return }
        turns.append(Turn(role: .user, text: option.text))
        selectedOptionID = nil
        state = .limitation("Esta etapa local registrou sua escolha, mas ainda não executa testes nem envia dados. A continuação integrada depende do motor V4 autorizado.")
    }

    func returnHome() {
        selectedOptionID = nil
        state = .home
    }
}
#endif
