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
        XCTAssertTrue(model.turns.isEmpty)
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
        guard case .limitation = model.state else { return XCTFail("Expected local limitation") }
    }
}
