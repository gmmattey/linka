import XCTest
import NetworkAssist
import NetworkCore
@testable import LinkaApp

@MainActor
final class AssistViewModelTests: XCTestCase {
    func test_directConversationReleasesComposerAfterResponse() async {
        let viewModel = AssistConversationViewModel(service: FinishedConversationService())
        viewModel.draft = "Minha conexão está lenta."

        viewModel.send(measurement: nil)
        for _ in 0..<20 where viewModel.isSending { await Task.yield() }

        XCTAssertFalse(viewModel.isSending)
        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(viewModel.messages.last?.content, "Vamos continuar.")

        viewModel.draft = "E agora?"
        viewModel.send(measurement: nil)
        for _ in 0..<20 where viewModel.isSending { await Task.yield() }
        XCTAssertFalse(viewModel.isSending)
        XCTAssertEqual(viewModel.messages.filter { $0.role == .user }.count, 2)
    }

    func test_makeContext_usesOnlyTheCurrentMeasurementAsEvidence() {
        let current = measurement(id: UUID())
        let recent = [measurement(id: UUID()), measurement(id: UUID())]

        let context = AssistViewModel.makeContext(
            currentMeasurement: current,
            recentMeasurements: recent
        )

        XCTAssertEqual(context.question, LinkaCopy.value("assist.defaultQuestion"))
        XCTAssertEqual(context.currentMeasurement.id, current.id)
        XCTAssertTrue(context.recentMeasurements.isEmpty)
        XCTAssertNil(context.usageContext)
        XCTAssertEqual(
            context.evidence.map(\.id),
            [
                NetworkAssistRequest.currentMeasurementEvidenceID(current.id)
            ]
        )
    }

    func test_makeContext_doesNotInferUsageContextOrUseHistory() {
        let current = measurement(id: UUID())
        let recent = (0..<25).map { _ in measurement(id: UUID()) }

        let context = AssistViewModel.makeContext(
            currentMeasurement: current,
            recentMeasurements: recent,
            usageContext: nil
        )

        XCTAssertTrue(context.recentMeasurements.isEmpty)
        XCTAssertNil(context.usageContext)
    }

    func test_makeContext_propagatesObjectiveAndSubcategory() {
        let current = measurement(id: UUID())

        let context = AssistViewModel.makeContext(
            currentMeasurement: current,
            recentMeasurements: [],
            objective: "JOGOS_COM_LAG",
            subcategory: "PING_ALTO"
        )

        XCTAssertEqual(context.objective, "JOGOS_COM_LAG")
        XCTAssertEqual(context.subcategory, "PING_ALTO")
        XCTAssertNil(context.reportedProblem)
    }

    func test_makeContext_propagatesEffectiveLanguageTagToTheAssistRequest() {
        let context = AssistViewModel.makeContext(
            currentMeasurement: measurement(id: UUID()),
            recentMeasurements: [],
            locale: "es-419"
        )

        XCTAssertEqual(context.locale, "es-419")
    }

    /// "Pular" a etapa 1 ou a etapa 2 (`AssistProblemSelectionView`) deve
    /// produzir o mesmo contrato observacional de sempre: sem
    /// objective/subcategory/reportedProblem, sem quebrar o fluxo.
    func test_makeContext_withoutGuidedSelection_hasNoObjectiveSubcategoryOrReportedProblem() {
        let current = measurement(id: UUID())

        let context = AssistViewModel.makeContext(
            currentMeasurement: current,
            recentMeasurements: []
        )

        XCTAssertNil(context.objective)
        XCTAssertNil(context.subcategory)
        XCTAssertNil(context.reportedProblem)
    }

    /// "Outro problema": objective/subcategory ficam nil, só o texto livre
    /// (aparado) vai para o contexto.
    func test_makeContext_propagatesTrimmedReportedProblem_withoutObjectiveOrSubcategory() {
        let current = measurement(id: UUID())

        let context = AssistViewModel.makeContext(
            currentMeasurement: current,
            recentMeasurements: [],
            reportedProblem: "  Minha internet cai só quando chove.  "
        )

        XCTAssertNil(context.objective)
        XCTAssertNil(context.subcategory)
        XCTAssertEqual(context.reportedProblem, "Minha internet cai só quando chove.")
    }

    /// Texto vazio (só espaço) vira `nil`, igual a `usageContext`.
    func test_makeContext_blankReportedProblem_becomesNil() {
        let current = measurement(id: UUID())

        let context = AssistViewModel.makeContext(
            currentMeasurement: current,
            recentMeasurements: [],
            reportedProblem: "   "
        )

        XCTAssertNil(context.reportedProblem)
    }

    func test_load_insufficientEvidence_becomesExplicitError() async {
        let provider = StubAssistProvider(
            response: NetworkAssistResponse(
                text: "Não há dados suficientes.",
                disposition: .insufficientEvidence
            )
        )
        let viewModel = AssistViewModel(assistProvider: provider)

        await viewModel.load(
            currentMeasurement: measurement(id: UUID()),
            failureSignal: nil
        )

        XCTAssertEqual(
            viewModel.state,
            .error(LinkaCopy.value("assist.insufficient"))
        )
    }

    func test_load_fallback_keepsRecommendationAndSteps() async {
        let recommendation = NetworkAssistRecommendation(
            title: "Repita a medição",
            description: "Faça outro teste para confirmar o resultado.",
            steps: ["Aproxime-se do roteador.", "Repita a medição."]
        )
        let current = measurement(id: UUID())
        let provider = StubAssistProvider(
            response: NetworkAssistResponse(
                text: "A resposta chegou sem o bloco visual estruturado.",
                disposition: .answered,
                evidenceIDs: [NetworkAssistRequest.currentMeasurementEvidenceID(current.id)],
                recommendation: recommendation
            )
        )
        let viewModel = AssistViewModel(assistProvider: provider)

        await viewModel.load(currentMeasurement: current, failureSignal: nil)

        guard case .success(let data) = viewModel.state else {
            return XCTFail("A resposta respondida deveria produzir sucesso")
        }
        XCTAssertEqual(data.recommendation?.steps, recommendation.steps)
    }

    func test_load_success_propagatesAiAttribution() async {
        let current = measurement(id: UUID())
        let provider = StubAssistProvider(
            response: NetworkAssistResponse(
                text: "Conexão estável",
                disposition: .answered,
                evidenceIDs: [NetworkAssistRequest.currentMeasurementEvidenceID(current.id)],
                headerStatus: "✓ TUDO CERTO",
                title: "Tudo certo com o Wi-Fi",
                summary: "Sua conexão está operando dentro dos parâmetros normais.",
                aiAttribution: "ChatGPT – Luna"
            )
        )
        let viewModel = AssistViewModel(assistProvider: provider)

        await viewModel.load(currentMeasurement: current, failureSignal: nil)

        guard case .success(let data) = viewModel.state else {
            return XCTFail("A resposta respondida deveria produzir sucesso")
        }
        XCTAssertEqual(data.aiAttribution, "ChatGPT – Luna")
    }

    private func measurement(id: UUID) -> NetworkMeasurement {
        NetworkMeasurement(
            id: id,
            outcome: .complete,
            downloadMbps: 120,
            uploadMbps: 30,
            latencyMs: 18
        )
    }
}

private struct StubAssistProvider: NetworkAssistProviding {
    let response: NetworkAssistResponse

    func answer(_ context: NetworkAssistContext) async throws -> NetworkAssistResponse {
        response
    }

    func streamAnswer(_ context: NetworkAssistContext) -> AsyncThrowingStream<NetworkAssistStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.completed(response))
            continuation.finish()
        }
    }
}

private struct FinishedConversationService: AssistConversationServing {
    func stream(
        message: String,
        history: [AssistConversationMessage],
        measurement: NetworkMeasurement?,
        locale: String,
        onDelta: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        await onDelta("Vamos continuar.")
    }
}
