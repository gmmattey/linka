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
