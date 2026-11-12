import XCTest
import NetworkCore
@testable import NetworkAssist

final class NetworkAssistTests: XCTestCase {
    private func completeMeasurement(
        id: UUID = UUID(),
        download: Double = 500,
        upload: Double = 100,
        latency: Double = 12
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            id: id,
            outcome: .complete,
            downloadMbps: download,
            uploadMbps: upload,
            latencyMs: latency
        )
    }

    func testUnconfiguredTransportFailsClosed() async {
        let service = NetworkAssistService(transport: UnconfiguredNetworkAssistTransport())
        let context = NetworkAssistContext(
            question: "Esse resultado está bom?",
            currentMeasurement: completeMeasurement()
        )

        do {
            _ = try await service.answer(context)
            XCTFail("Expected notConfigured")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServiceInjectsRestrictivePolicyAndAcceptsGroundedAnswer() async throws {
        let measurement = completeMeasurement()
        let transport = RecordingTransport { request in
            XCTAssertTrue(request.policy.observationalOnly)
            XCTAssertFalse(request.policy.mayInferRootCause)
            XCTAssertFalse(request.policy.mayRecommendRepair)
            XCTAssertTrue(request.policy.mustGroundInProvidedData)
            XCTAssertTrue(request.policy.handoffWhenDiagnosisIsRequired)

            return NetworkAssistResponse(
                text: "A medição mostra 500 Mbps de download e 12 ms de latência.",
                disposition: .answered,
                evidenceIDs: [NetworkAssistRequest.currentMeasurementEvidenceID(measurement.id)]
            )
        }
        let service = NetworkAssistService(transport: transport)

        let response = try await service.answer(
            NetworkAssistContext(
                question: "  Como foi esse teste?  ",
                currentMeasurement: measurement
            )
        )

        XCTAssertEqual(response.disposition, .answered)
        XCTAssertFalse(response.text.isEmpty)
    }

    func testServiceForwardsOnlyUserProvidedUsageContext() async throws {
        let measurement = completeMeasurement()
        let transport = RecordingTransport { request in
            XCTAssertEqual(request.usageContext, "chamada de vídeo")
            return NetworkAssistResponse(
                text: "A medição foi interpretada.",
                disposition: .answered,
                evidenceIDs: [NetworkAssistRequest.currentMeasurementEvidenceID(measurement.id)]
            )
        }
        let service = NetworkAssistService(transport: transport)

        _ = try await service.answer(
            NetworkAssistContext(
                question: "Como foi?",
                currentMeasurement: measurement,
                usageContext: "chamada de vídeo"
            )
        )
    }

    func testInvalidMeasurementNeverReachesTransport() async {
        let invalid = NetworkMeasurement(outcome: .complete, downloadMbps: 100)
        let service = NetworkAssistService(transport: FailingIfCalledTransport())

        do {
            _ = try await service.answer(
                NetworkAssistContext(question: "Como foi?", currentMeasurement: invalid)
            )
            XCTFail("Expected invalidMeasurement")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .invalidMeasurement(invalid.id))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyAndOversizedQuestionsAreRejected() async {
        let measurement = completeMeasurement()
        let service = NetworkAssistService(
            transport: FailingIfCalledTransport(),
            configuration: .init(maximumQuestionLength: 10)
        )

        do {
            _ = try await service.answer(
                NetworkAssistContext(question: "   ", currentMeasurement: measurement)
            )
            XCTFail("Expected emptyQuestion")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .emptyQuestion)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await service.answer(
                NetworkAssistContext(question: "01234567890", currentMeasurement: measurement)
            )
            XCTFail("Expected questionTooLong")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .questionTooLong(maximum: 10))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// "Outro problema" com texto dentro do limite (200) é aceito e chega
    /// aparado (trim) ao transporte — sem `objective`/`subcategory`.
    func testReportedProblemWithinLimitReachesTransportTrimmed() async throws {
        let measurement = completeMeasurement()
        let transport = RecordingTransport { request in
            XCTAssertEqual(request.reportedProblem, "Minha internet cai só quando chove.")
            XCTAssertNil(request.objective)
            XCTAssertNil(request.subcategory)
            return NetworkAssistResponse(
                text: "A medição foi interpretada.",
                disposition: .answered,
                evidenceIDs: [NetworkAssistRequest.currentMeasurementEvidenceID(measurement.id)]
            )
        }
        let service = NetworkAssistService(transport: transport)

        _ = try await service.answer(
            NetworkAssistContext(
                question: "Como foi?",
                currentMeasurement: measurement,
                reportedProblem: "  Minha internet cai só quando chove.  "
            )
        )
    }

    /// Texto acima de 200 caracteres é rejeitado pelo service, mesmo que o
    /// client já devesse ter truncado antes — o server-side (aqui, o
    /// `NetworkAssistService` local) não confia cegamente no chamador.
    func testReportedProblemOverLimitIsRejected() async {
        let measurement = completeMeasurement()
        let service = NetworkAssistService(transport: FailingIfCalledTransport())
        let oversized = String(repeating: "a", count: 201)

        do {
            _ = try await service.answer(
                NetworkAssistContext(
                    question: "Como foi?",
                    currentMeasurement: measurement,
                    reportedProblem: oversized
                )
            )
            XCTFail("Expected reportedProblemTooLong")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .reportedProblemTooLong(maximum: 200))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Exatamente 200 caracteres é o limite aceito (borda inclusiva).
    func testReportedProblemAtExactLimitIsAccepted() async throws {
        let measurement = completeMeasurement()
        let exactly200 = String(repeating: "a", count: 200)
        let transport = RecordingTransport { request in
            XCTAssertEqual(request.reportedProblem?.count, 200)
            return NetworkAssistResponse(
                text: "A medição foi interpretada.",
                disposition: .answered,
                evidenceIDs: [NetworkAssistRequest.currentMeasurementEvidenceID(measurement.id)]
            )
        }
        let service = NetworkAssistService(transport: transport)

        _ = try await service.answer(
            NetworkAssistContext(
                question: "Como foi?",
                currentMeasurement: measurement,
                reportedProblem: exactly200
            )
        )
    }

    func testEvidenceCannotReferenceUnknownMeasurement() async {
        let measurement = completeMeasurement()
        let evidence = NetworkAssistEvidence(
            id: "trend-download",
            kind: .trend,
            metricKey: "downloadMbps",
            direction: "falling",
            sourceMeasurementIDs: [UUID()]
        )
        let service = NetworkAssistService(transport: FailingIfCalledTransport())

        do {
            _ = try await service.answer(
                NetworkAssistContext(
                    question: "Meu download mudou?",
                    currentMeasurement: measurement,
                    evidence: [evidence]
                )
            )
            XCTFail("Expected unknownEvidenceSource")
        } catch let error as NetworkAssistError {
            guard case .unknownEvidenceSource = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderCannotInventEvidenceReference() async {
        let measurement = completeMeasurement()
        let transport = RecordingTransport { _ in
            NetworkAssistResponse(
                text: "Resposta",
                disposition: .answered,
                evidenceIDs: ["inventado"]
            )
        }
        let service = NetworkAssistService(transport: transport)

        do {
            _ = try await service.answer(
                NetworkAssistContext(question: "Como foi?", currentMeasurement: measurement)
            )
            XCTFail("Expected unknownResponseEvidenceID")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .unknownResponseEvidenceID("inventado"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAnsweredResponseMustCiteEvidence() async {
        let measurement = completeMeasurement()
        let transport = RecordingTransport { _ in
            NetworkAssistResponse(text: "Resposta", disposition: .answered)
        }
        let service = NetworkAssistService(transport: transport)

        do {
            _ = try await service.answer(
                NetworkAssistContext(question: "Como foi?", currentMeasurement: measurement)
            )
            XCTFail("Expected answeredWithoutEvidence")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .answeredWithoutEvidence)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequiresDiagnosisCanReturnWithoutEvidenceReference() async throws {
        let transport = RecordingTransport { _ in
            NetworkAssistResponse(
                text: "Essa pergunta exige investigação além das medições disponíveis.",
                disposition: .requiresDiagnosis
            )
        }
        let service = NetworkAssistService(transport: transport)

        let response = try await service.answer(
            NetworkAssistContext(
                question: "Por que meu Wi-Fi está caindo?",
                currentMeasurement: completeMeasurement()
            )
        )

        XCTAssertEqual(response.disposition, .requiresDiagnosis)
    }

    // MARK: - streamAnswer (issue #69)

    func testStreamAnswerBridgesNonStreamingTransportToASingleCompletedEvent() async throws {
        let measurement = completeMeasurement()
        let transport = RecordingTransport { _ in
            NetworkAssistResponse(
                text: "  A medição mostra 500 Mbps.  ",
                disposition: .answered,
                evidenceIDs: [NetworkAssistRequest.currentMeasurementEvidenceID(measurement.id)]
            )
        }
        let service = NetworkAssistService(transport: transport)

        var events: [NetworkAssistStreamEvent] = []
        for try await event in service.streamAnswer(
            NetworkAssistContext(question: "Como foi?", currentMeasurement: measurement)
        ) {
            events.append(event)
        }

        // Sem `.progress`/`.textDelta` fabricados — um único `.completed`,
        // com o mesmo texto normalizado (trim) que `answer(_:)` produz.
        XCTAssertEqual(events.count, 1)
        guard case .completed(let response) = events[0] else {
            return XCTFail("Expected a single .completed event, got \(events)")
        }
        XCTAssertEqual(response.text, "A medição mostra 500 Mbps.")
        XCTAssertEqual(response.disposition, .answered)
    }

    func testStreamAnswerValidatesInputBeforeAnyEvent() async {
        let invalid = NetworkMeasurement(outcome: .complete, downloadMbps: 100)
        let service = NetworkAssistService(transport: FailingIfCalledTransport())

        do {
            for try await _ in service.streamAnswer(
                NetworkAssistContext(question: "Como foi?", currentMeasurement: invalid)
            ) {
                XCTFail("No event expected when input validation fails")
            }
            XCTFail("Expected invalidMeasurement")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .invalidMeasurement(invalid.id))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamAnswerForwardsRealStreamingTransportEventsInOrder() async throws {
        let measurement = completeMeasurement()
        let transport = RecordingStreamingTransport { request in
            [
                .progress(.readingMeasurement),
                .progress(.comparingHistory),
                .textDelta("A medição "),
                .textDelta("mostra 500 Mbps."),
                .completed(NetworkAssistResponse(
                    text: "A medição mostra 500 Mbps.",
                    disposition: .answered,
                    evidenceIDs: [NetworkAssistRequest.currentMeasurementEvidenceID(request.currentMeasurement.id)]
                ))
            ]
        }
        let service = NetworkAssistService(transport: transport)

        var events: [NetworkAssistStreamEvent] = []
        for try await event in service.streamAnswer(
            NetworkAssistContext(question: "Como foi?", currentMeasurement: measurement)
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [
            .progress(.readingMeasurement),
            .progress(.comparingHistory),
            .textDelta("A medição "),
            .textDelta("mostra 500 Mbps."),
            .completed(NetworkAssistResponse(
                text: "A medição mostra 500 Mbps.",
                disposition: .answered,
                evidenceIDs: [NetworkAssistRequest.currentMeasurementEvidenceID(measurement.id)]
            ))
        ])
    }

    func testStreamAnswerValidatesFinalResponseEvenForStreamingTransport() async {
        // Mesma política de evidência de `answer(_:)` vale para o caminho
        // streaming: `.answered` sem evidência falha, mesmo depois de já
        // ter emitido `.progress`/`.textDelta` com sucesso.
        let measurement = completeMeasurement()
        let transport = RecordingStreamingTransport { _ in
            [
                .textDelta("Resposta"),
                .completed(NetworkAssistResponse(text: "Resposta", disposition: .answered))
            ]
        }
        let service = NetworkAssistService(transport: transport)

        var sawTextDelta = false
        do {
            for try await event in service.streamAnswer(
                NetworkAssistContext(question: "Como foi?", currentMeasurement: measurement)
            ) {
                if case .textDelta = event {
                    sawTextDelta = true
                }
            }
            XCTFail("Expected answeredWithoutEvidence")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .answeredWithoutEvidence)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(sawTextDelta, "O .textDelta deveria ter sido observado antes da validação final falhar")
    }

    func testStreamAnswerCancellationPropagatesToTransport() async throws {
        let cancelledExpectation = expectation(description: "transport observed cooperative cancellation")
        let transport = CancellationAwareStreamingTransport(cancelledExpectation: cancelledExpectation)
        let service = NetworkAssistService(transport: transport)
        let measurement = completeMeasurement()

        let consumer = Task {
            for try await _ in service.streamAnswer(
                NetworkAssistContext(question: "Como foi?", currentMeasurement: measurement)
            ) {
                XCTFail("No event expected before cancellation")
            }
        }

        // Deixa o stream iniciar e o transport entrar no laço de espera
        // antes de cancelar.
        try await Task.sleep(nanoseconds: 100_000_000)
        consumer.cancel()

        await fulfillment(of: [cancelledExpectation], timeout: 2.0)
    }
}

private struct RecordingTransport: NetworkAssistTransport {
    let handler: @Sendable (NetworkAssistRequest) throws -> NetworkAssistResponse

    init(handler: @escaping @Sendable (NetworkAssistRequest) throws -> NetworkAssistResponse) {
        self.handler = handler
    }

    func answer(_ request: NetworkAssistRequest) async throws -> NetworkAssistResponse {
        try handler(request)
    }
}

private struct FailingIfCalledTransport: NetworkAssistTransport {
    func answer(_ request: NetworkAssistRequest) async throws -> NetworkAssistResponse {
        XCTFail("Transport should not have been called")
        throw NetworkAssistError.notConfigured
    }
}

/// Transport de streaming de teste (issue #69) — devolve uma sequência
/// fixa de eventos síncronos, simulando um transporte real que sabe
/// emitir `.progress`/`.textDelta` além de `.completed`.
private struct RecordingStreamingTransport: NetworkAssistStreamingTransport {
    let handler: @Sendable (NetworkAssistRequest) -> [NetworkAssistStreamEvent]

    init(handler: @escaping @Sendable (NetworkAssistRequest) -> [NetworkAssistStreamEvent]) {
        self.handler = handler
    }

    func answer(_ request: NetworkAssistRequest) async throws -> NetworkAssistResponse {
        XCTFail("answer(_:) should not be called when the streaming path is exercised")
        throw NetworkAssistError.notConfigured
    }

    func streamAnswer(_ request: NetworkAssistRequest) -> AsyncThrowingStream<NetworkAssistStreamEvent, Error> {
        let events = handler(request)
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

/// Transport de streaming que só termina quando cancelado — usado para
/// provar que cancelar a `Task` que consome `NetworkAssistService.streamAnswer`
/// propaga cancelamento cooperativo até o transporte (issue #69).
private final class CancellationAwareStreamingTransport: NetworkAssistStreamingTransport, @unchecked Sendable {
    let cancelledExpectation: XCTestExpectation

    init(cancelledExpectation: XCTestExpectation) {
        self.cancelledExpectation = cancelledExpectation
    }

    func answer(_ request: NetworkAssistRequest) async throws -> NetworkAssistResponse {
        XCTFail("answer(_:) should not be called when the streaming path is exercised")
        throw NetworkAssistError.notConfigured
    }

    func streamAnswer(_ request: NetworkAssistRequest) -> AsyncThrowingStream<NetworkAssistStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withTaskCancellationHandler {
                        while !Task.isCancelled {
                            try await Task.sleep(nanoseconds: 10_000_000)
                        }
                        throw CancellationError()
                    } onCancel: { [cancelledExpectation] in
                        cancelledExpectation.fulfill()
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
