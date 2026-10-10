import XCTest
@testable import LinkaApp
import AssistConsultation

@MainActor
final class AssistV4PresentationModelTests: XCTestCase {
    func testOpenQuestionStaysLocalAndHonestWhenNoEngineIsAuthorized() {
        let model = AssistV4PresentationModel()
        model.draft = "Posso usar um roteador antigo como AP?"
        model.submitOpenQuestion()
        XCTAssertEqual(model.state, .unavailableOpenQuestion("Posso usar um roteador antigo como AP?"))
        XCTAssertEqual(model.draft, "Posso usar um roteador antigo como AP?")
        XCTAssertEqual(model.turns.count, 1)
        XCTAssertEqual(model.turns.first?.role, .user)
        XCTAssertEqual(model.turns.first?.text, "Posso usar um roteador antigo como AP?")
    }

    func testGuidedEntryShowsOneQuestionAndDoesNotSendAnything() {
        let model = AssistV4PresentationModel()
        model.start(.slowConnection)
        guard case let .guided(intent, question) = model.state else { return XCTFail("Expected guided question") }
        XCTAssertEqual(intent, .slowConnection)
        XCTAssertTrue(question.allowUnknown)
        model.selectedOptionID = question.options[0].id
        model.continueGuided()
        XCTAssertEqual(model.turns.count, 1)
        guard case let .guided(nextIntent, nextQuestion) = model.state else { return XCTFail("Expected the next local question") }
        XCTAssertEqual(nextIntent, .slowConnection)
        XCTAssertEqual(nextQuestion.text, "Acontece em tudo ou só em um app ou serviço?")

        model.selectedOptionID = nextQuestion.options[0].id
        model.continueGuided()
        XCTAssertEqual(model.turns.count, 2)
        guard case let .guidance(title, detail) = model.state else { return XCTFail("Expected a controlled local comparison") }
        XCTAssertEqual(title, "Próxima etapa sugerida")
        XCTAssertTrue(detail.contains("Medir o cenário de forma controlada"))
    }
}
