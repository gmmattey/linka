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
        XCTAssertEqual(orientation.actionProgress.status, .pending)

        model.completeSuggestedAction()
        guard case let .localOrientation(completedOrientation) = model.state else { return XCTFail("Expected local orientation after action confirmation") }
        XCTAssertEqual(completedOrientation.actionProgress.status, .completed)
        XCTAssertNotNil(completedOrientation.actionProgress.confirmedAt)
        XCTAssertNil(completedOrientation.actionProgress.evidenceRef)
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

    func testSlowConnectionResultCanRevisitTheLastGuidedAnswerLocally() {
        let model = AssistV4PresentationModel()
        model.start(.slowConnection)
        guard case let .guided(_, firstQuestion) = model.state else { return XCTFail("Expected first local question") }
        model.selectedOptionID = firstQuestion.options.first(where: { $0.text == "Em um cômodo" })?.id
        model.continueGuided()
        guard case let .guided(_, usageQuestion) = model.state else { return XCTFail("Expected usage question") }
        model.selectedOptionID = usageQuestion.options.first(where: { $0.text == "Em tudo" })?.id
        model.continueGuided()

        model.reviseSlowConnectionAnswers()
        guard case let .guided(intent, revisedQuestion) = model.state else { return XCTFail("Expected the revised local question") }
        XCTAssertEqual(intent, .slowConnection)
        XCTAssertEqual(revisedQuestion.text, "Acontece em tudo ou só em um app ou serviço?")
        XCTAssertEqual(model.selectedOptionID, revisedQuestion.options.first(where: { $0.text == "Em tudo" })?.id)
        XCTAssertEqual(model.turns.map(\.text), ["Em um cômodo"])

        model.selectedOptionID = revisedQuestion.options.first(where: { $0.text == "Só em um app ou serviço" })?.id
        model.continueGuided()
        guard case let .limitation(detail) = model.state else { return XCTFail("Expected local evidence limitation") }
        XCTAssertTrue(detail.contains("teste geral não comprova"))
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
        XCTAssertEqual(model.state, .planDeclaration)
        model.declaredPlanName = "Fibra 500"
        model.declaredPlanPrice = "99,90"
        model.continuePlanDeclaration()
        guard case let .guided(intent, question) = model.state else { return XCTFail("Expected declared-plan priority question") }
        XCTAssertEqual(intent, .planValue)
        XCTAssertEqual(question.text, "O que mais importa para você?")
        XCTAssertTrue(model.declaredPlanName.isEmpty)
        XCTAssertTrue(model.declaredPlanPrice.isEmpty)

        model.selectedOptionID = question.options.first(where: { $0.text == "Entender ofertas" })?.id
        model.continueGuided()
        guard case let .limitation(detail) = model.state else { return XCTFail("Expected commercial-data limitation") }
        XCTAssertTrue(detail.contains("nenhuma oferta é consultada"))
        XCTAssertFalse(model.turns.contains { $0.text.contains("Fibra 500") || $0.text.contains("99,90") })
    }

    func testPlanDeclarationSurvivesAnUnsentOpenQuestion() {
        let model = AssistV4PresentationModel()
        model.start(.planValue)
        model.declaredPlanName = "Fibra 500"
        model.declaredPlanPrice = "99,90"
        model.draft = "Existe alguma oferta mais barata?"
        model.submitOpenQuestion()
        XCTAssertEqual(model.state, .unavailableOpenQuestion("Existe alguma oferta mais barata?", canResumeGuidance: true))

        model.resumeGuidance()
        XCTAssertEqual(model.state, .planDeclaration)
        XCTAssertEqual(model.declaredPlanName, "Fibra 500")
        XCTAssertEqual(model.declaredPlanPrice, "99,90")
    }
}
