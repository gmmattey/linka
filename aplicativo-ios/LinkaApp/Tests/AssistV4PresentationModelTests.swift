import XCTest
@testable import LinkaApp
import AssistConsultation

@MainActor
final class AssistV4PresentationModelTests: XCTestCase {
    func testOpenQuestionStaysLocalAndHonestWhenNoEngineIsAuthorized() {
        let model = AssistV4PresentationModel()
        model.draft = "Posso usar um roteador antigo como AP?"
        model.submitOpenQuestion()
        XCTAssertEqual(model.state, .unavailableOpenQuestion("Posso usar um roteador antigo como AP?", canResumeGuidance: false))
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
        guard case let .localOrientation(orientation) = model.state else { return XCTFail("Expected a controlled local comparison") }
        XCTAssertEqual(orientation.title, "Próxima etapa sugerida")
        XCTAssertTrue(orientation.reason.contains("Medir o cenário de forma controlada"))
        XCTAssertEqual(orientation.declaredAnswers, ["Na casa inteira", "Em tudo"])
        XCTAssertEqual(orientation.nextAction, "Registre se a condição ocorre em vários aparelhos.")
    }

    func testOpenQuestionDuringGuidancePreservesTheLocalQuestionAndSelection() {
        let model = AssistV4PresentationModel()
        model.start(.slowConnection)
        guard case let .guided(intent, question) = model.state else { return XCTFail("Expected guided question") }
        model.selectedOptionID = question.options[1].id
        model.draft = "Isso acontece quando alguém faz videochamada?"

        model.submitOpenQuestion()
        XCTAssertEqual(model.state, .unavailableOpenQuestion("Isso acontece quando alguém faz videochamada?", canResumeGuidance: true))
        XCTAssertEqual(model.selectedOptionID, question.options[1].id)
        XCTAssertEqual(model.turns.last?.text, "Isso acontece quando alguém faz videochamada?")

        model.resumeGuidance()
        XCTAssertEqual(model.selectedOptionID, question.options[1].id)
        XCTAssertEqual(model.state, .guided(intent: intent, question: question))
    }

    func testRouterAndMeshStayInEvidenceLimitedLocalPaths() {
        let router = AssistV4PresentationModel()
        router.start(.routerAdequacy)
        guard case let .guided(_, routerQuestion) = router.state,
              let selectedEquipment = routerQuestion.options.first(where: { $0.text == "Selecionar um equipamento" }) else {
            return XCTFail("Expected equipment selection")
        }
        router.selectedOptionID = selectedEquipment.id
        router.continueGuided()
        guard case let .limitation(routerDetail) = router.state else { return XCTFail("Expected verified-evidence limitation") }
        XCTAssertTrue(routerDetail.contains("identidade, a revisão e a fonte"))

        let mesh = AssistV4PresentationModel()
        mesh.start(.meshNeed)
        guard case let .guided(_, meshQuestion) = mesh.state,
              let affectedArea = meshQuestion.options.first(where: { $0.text == "Em vários ambientes" }) else {
            return XCTFail("Expected affected-area selection")
        }
        mesh.selectedOptionID = affectedArea.id
        mesh.continueGuided()
        guard case let .limitation(meshDetail) = mesh.state else { return XCTFail("Expected coverage-evidence limitation") }
        XCTAssertTrue(meshDetail.contains("Sem evidência de cobertura"))
    }

    func testPlanValueDoesNotClaimOffersWithoutDeclaredData() {
        let model = AssistV4PresentationModel()
        model.start(.planValue)
        guard case let .limitation(detail) = model.state else { return XCTFail("Expected declared-plan limitation") }
        XCTAssertTrue(detail.contains("plano e o preço atuais precisam ser declarados"))
        XCTAssertTrue(model.turns.isEmpty)
    }
}
