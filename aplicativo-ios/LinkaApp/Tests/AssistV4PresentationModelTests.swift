import XCTest
@testable import LinkaApp
import AssistConsultation

@MainActor
final class AssistV4PresentationModelTests: XCTestCase {
    private func choose(_ text: String, on model: AssistV4PresentationModel) {
        guard case let .guided(_, question) = model.state,
              let option = question.options.first(where: { $0.text == text }) else {
            return XCTFail("Expected local option: \(text)")
        }
        model.selectedOptionID = option.id
        model.continueGuided()
    }

    private func reachSlowConnectionOrientation(on model: AssistV4PresentationModel) {
        model.start(.slowConnection)
        choose("Em um cômodo", on: model)
        choose("Em tudo", on: model)
        choose("Em certos horários", on: model)
        choose("Wi-Fi", on: model)
    }

    func testOpenQuestionRequiresConsentAndCanStayLocal() {
        let model = AssistV4PresentationModel()
        model.draft = "Posso usar um roteador antigo como AP?"
        model.submitOpenQuestion()
        XCTAssertEqual(model.state, .awaitingConsent(question: "Posso usar um roteador antigo como AP?"))
        XCTAssertTrue(model.turns.isEmpty)
        model.declineOpenQuestionConsent()
        XCTAssertEqual(model.state, .unavailableOpenQuestion("Posso usar um roteador antigo como AP?", canResumeGuidance: false))
        XCTAssertEqual(model.draft, "Posso usar um roteador antigo como AP?")
        XCTAssertTrue(model.turns.isEmpty)
    }

    func testQuestionOnlyConsentUsesNoContextAndFailsClosedWhenDisabled() async {
        let model = AssistV4PresentationModel()
        model.draft = "Posso usar um roteador antigo como AP?"
        model.submitOpenQuestion()
        model.sendOpenQuestionOnly()

        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(model.state, .remoteUnavailable("A consulta protegida ainda não está habilitada. Sua pergunta não foi enviada."))
        XCTAssertEqual(model.turns.map(\.text), ["Posso usar um roteador antigo como AP?"])
    }

    func testRecoverableRemoteFailureKeepsTheSameQuestionForRetry() async {
        let model = AssistV4PresentationModel(submitOpenQuestionRemote: { _ in
            .recoverableFailure("A rede caiu durante a consulta.")
        })
        model.draft = "Posso usar um roteador antigo como AP?"
        model.submitOpenQuestion()
        model.sendOpenQuestionOnly()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(model.state, .remoteRecoverableError("A rede caiu durante a consulta."))

        model.retryOpenQuestion()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(model.state, .remoteRecoverableError("A rede caiu durante a consulta."))
        XCTAssertEqual(model.turns.map(\.text), ["Posso usar um roteador antigo como AP?"])
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
        guard case let .guided(_, timingQuestion) = model.state else { return XCTFail("Expected timing question") }
        XCTAssertEqual(timingQuestion.text, "Quando a lentidão acontece mais?")
        model.selectedOptionID = timingQuestion.options.first(where: { $0.text == "O tempo todo" })?.id
        model.continueGuided()
        guard case let .guided(_, accessQuestion) = model.state else { return XCTFail("Expected access question") }
        XCTAssertEqual(accessQuestion.text, "Como este aparelho está conectado agora?")
        model.selectedOptionID = accessQuestion.options.first(where: { $0.text == "Wi-Fi" })?.id
        model.continueGuided()
        guard case let .localOrientation(orientation) = model.state else { return XCTFail("Expected a controlled local comparison") }
        XCTAssertEqual(orientation.title, "Próxima etapa sugerida")
        XCTAssertTrue(orientation.reason.contains("comparação controlada"))
        XCTAssertEqual(orientation.declaredAnswers, ["Na casa inteira", "Em tudo", "O tempo todo", "Wi-Fi"])
        XCTAssertTrue(orientation.nextAction.contains("Wi-Fi"))
        XCTAssertEqual(orientation.actionProgress.status, .pending)

        model.completeSuggestedAction()
        guard case let .localOrientation(completedOrientation) = model.state else { return XCTFail("Expected local orientation after action confirmation") }
        XCTAssertEqual(completedOrientation.actionProgress.status, .completed)
        XCTAssertNotNil(completedOrientation.actionProgress.confirmedAt)
        XCTAssertNil(completedOrientation.actionProgress.evidenceRef)
    }

    func testBackgroundPauseRequiresAnExplicitResumeAndPreservesTheGuidedChoice() {
        let model = AssistV4PresentationModel()
        model.start(.slowConnection)
        guard case let .guided(intent, question) = model.state else { return XCTFail("Expected guided question") }
        model.selectedOptionID = question.options[1].id

        model.pauseForBackground()

        XCTAssertEqual(model.state, .paused)
        XCTAssertEqual(model.selectedOptionID, question.options[1].id)
        model.continueGuided()
        XCTAssertEqual(model.state, .paused)

        model.resumePausedInvestigation()

        XCTAssertEqual(model.state, .guided(intent: intent, question: question))
        XCTAssertEqual(model.selectedOptionID, question.options[1].id)
        XCTAssertTrue(model.turns.isEmpty)
    }

    func testDeferringSuggestedActionDoesNotCreateRetestEvidence() {
        let model = AssistV4PresentationModel()
        reachSlowConnectionOrientation(on: model)

        model.deferSuggestedAction()

        guard case let .localOrientation(orientation) = model.state else { return XCTFail("Expected local orientation") }
        XCTAssertEqual(orientation.actionProgress.status, .ignored)
        XCTAssertNotNil(orientation.actionProgress.confirmedAt)
        XCTAssertNil(orientation.actionProgress.evidenceRef)
    }

    func testEligibleMeasurementIsAttachedOnlyToTheCurrentLocalOrientation() {
        let model = AssistV4PresentationModel()
        reachSlowConnectionOrientation(on: model)
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)

        model.recordSuggestedMeasurement(
            .init(
                measuredAt: measuredAt,
                downloadMbps: 123.4,
                uploadMbps: 45.6,
                latencyMs: 12.0,
                connectionKind: "wifi"
            )
        )

        guard case let .localOrientation(orientation) = model.state else {
            return XCTFail("Expected local orientation with a measurement")
        }
        XCTAssertEqual(orientation.actionProgress.status, .completed)
        XCTAssertNotNil(orientation.actionProgress.evidenceRef)
        XCTAssertEqual(orientation.measurement?.measuredAt, measuredAt)
        XCTAssertEqual(orientation.measurement?.downloadMbps, 123.4)
        XCTAssertEqual(orientation.measurement?.connectionKind, "wifi")
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

    func testOpenQuestionAfterOrientationCanReturnToTheLocalResult() {
        let model = AssistV4PresentationModel()
        reachSlowConnectionOrientation(on: model)
        guard case let .localOrientation(orientation) = model.state else { return XCTFail("Expected local orientation") }

        model.draft = "E se eu usar outro roteador?"
        model.submitOpenQuestion()
        XCTAssertEqual(model.state, .unavailableOpenQuestion("E se eu usar outro roteador?", canResumeGuidance: true))

        model.resumeGuidance()
        XCTAssertEqual(model.state, .localOrientation(orientation))
    }

    func testSlowConnectionResultCanRevisitTheLastGuidedAnswerLocally() {
        let model = AssistV4PresentationModel()
        reachSlowConnectionOrientation(on: model)

        model.reviseSlowConnectionAnswers()
        guard case let .guided(intent, revisedQuestion) = model.state else { return XCTFail("Expected the revised local question") }
        XCTAssertEqual(intent, .slowConnection)
        XCTAssertEqual(revisedQuestion.text, "Como este aparelho está conectado agora?")
        XCTAssertEqual(model.selectedOptionID, revisedQuestion.options.first(where: { $0.text == "Wi-Fi" })?.id)
        XCTAssertEqual(model.turns.map(\.text), ["Em um cômodo", "Em tudo", "Em certos horários"])

        model.selectedOptionID = revisedQuestion.options.first(where: { $0.text == "Cabo de rede" })?.id
        model.continueGuided()
        guard case let .localOrientation(orientation) = model.state else { return XCTFail("Expected rebuilt local orientation") }
        XCTAssertTrue(orientation.nextAction.contains("cabo"))
    }

    func testGuidedBackRebuildsTheSlowConnectionQuestionWithoutReusingTheAnswer() {
        let model = AssistV4PresentationModel()
        model.start(.slowConnection)
        guard case let .guided(_, locationQuestion) = model.state else { return XCTFail("Expected location question") }
        model.selectedOptionID = locationQuestion.options.first(where: { $0.text == "Em um cômodo" })?.id
        model.continueGuided()
        guard case .guided = model.state else { return XCTFail("Expected usage question") }

        model.goBackFromGuidedQuestion()
        guard case let .guided(intent, rebuiltQuestion) = model.state else { return XCTFail("Expected rebuilt location question") }
        XCTAssertEqual(intent, .slowConnection)
        XCTAssertEqual(rebuiltQuestion.text, "Onde a conexão está lenta?")
        XCTAssertEqual(model.selectedOptionID, rebuiltQuestion.options.first(where: { $0.text == "Em um cômodo" })?.id)
        XCTAssertTrue(model.turns.isEmpty)

        model.continueGuided()
        guard case let .guided(_, nextQuestion) = model.state else { return XCTFail("Expected usage question after rebuilding") }
        XCTAssertEqual(nextQuestion.text, "Acontece em tudo ou só em um app ou serviço?")
    }

    func testCancelDiscardsTheEphemeralLocalInvestigation() {
        let model = AssistV4PresentationModel()
        model.start(.slowConnection)
        guard case let .guided(_, question) = model.state else { return XCTFail("Expected local question") }
        model.selectedOptionID = question.options.first?.id
        model.continueGuided()
        XCTAssertFalse(model.turns.isEmpty)

        model.cancelLocalInvestigation()
        XCTAssertEqual(model.state, .cancelled)
        XCTAssertTrue(model.turns.isEmpty)
        XCTAssertNil(model.selectedOptionID)
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
