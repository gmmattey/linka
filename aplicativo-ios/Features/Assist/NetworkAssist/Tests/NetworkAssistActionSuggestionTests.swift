import XCTest
import NetworkCore
@testable import NetworkAssist

final class NetworkAssistActionSuggestionTests: XCTestCase {
    private func measurement(
        outcome: MeasurementOutcome = .complete,
        connectionKind: NetworkConnectionKind? = nil,
        wifiBandGHz: Double? = nil,
        loadedLatencyMs: Double? = nil
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            outcome: outcome,
            downloadMbps: outcome == .complete ? 200 : nil,
            uploadMbps: outcome == .complete ? 50 : nil,
            latencyMs: outcome == .complete ? 15 : nil,
            loadedLatencyMs: loadedLatencyMs,
            connectionKind: connectionKind,
            wifiBandGHz: wifiBandGHz
        )
    }

    // MARK: - Sem resultado / inconclusivo nunca sugere nada

    func testNilResultSuggestsNothing() {
        XCTAssertNil(NetworkAssistActionEngine.suggest(for: nil))
    }

    func testInconclusiveDispositionSuggestsNothing() {
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(failureSignal: nil, recentMeasurements: [])
        )
        XCTAssertEqual(result.disposition, .inconclusive)
        XCTAssertNil(NetworkAssistActionEngine.suggest(for: result))
    }

    func testInconclusiveConnectionLostWithoutHistorySuggestsNothing() {
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .download),
                recentMeasurements: []
            )
        )
        XCTAssertEqual(result.disposition, .inconclusive)
        XCTAssertNil(NetworkAssistActionEngine.suggest(for: result))
    }

    // MARK: - Offline não produz orientação causal

    func testOfflineDoesNotSuggestWifiGuidanceWithoutEvidence() {
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(failureSignal: .offline, recentMeasurements: [])
        )
        XCTAssertEqual(result.disposition, .inconclusive)

        let suggestion = NetworkAssistActionEngine.suggest(for: result)
        XCTAssertNil(suggestion)
    }

    func testOfflineWithWifiHistoryStillDoesNotSuggestSettings() {
        let history = [measurement(connectionKind: .wifi), measurement(connectionKind: .wifi)]
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(failureSignal: .offline, recentMeasurements: history)
        )

        let suggestion = NetworkAssistActionEngine.suggest(for: result)
        XCTAssertNil(suggestion)
    }

    // MARK: - Local: connectionLost com Wi-Fi evidenciado abre Ajustes

    func testConnectionLostWithWifiEvidenceSuggestsOpenAppSettings() {
        let history = [
            measurement(outcome: .partial, connectionKind: .wifi),
            measurement(outcome: .complete, connectionKind: .wifi, loadedLatencyMs: 40)
        ]
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .download),
                recentMeasurements: history
            )
        )
        XCTAssertEqual(result.disposition, .localSignalLikely)

        let suggestion = NetworkAssistActionEngine.suggest(for: result)
        XCTAssertEqual(suggestion, .openAppSettings)
    }

    // MARK: - Local: connectionLost sem connectionKind evidenciado não fabrica sugestão

    func testConnectionLostWithoutConnectionKindEvidenceSuggestsNothing() {
        let history = [
            measurement(outcome: .partial, connectionKind: nil),
            measurement(outcome: .complete, connectionKind: nil)
        ]
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .ping),
                recentMeasurements: history
            )
        )
        XCTAssertEqual(result.disposition, .localSignalLikely)
        XCTAssertTrue(result.missingSignals.contains(.connectionKind))

        XCTAssertNil(NetworkAssistActionEngine.suggest(for: result))
    }

    func testConnectionLostWithCellularEvidenceNeverSuggestsOpenAppSettings() {
        let history = [
            measurement(outcome: .partial, connectionKind: .cellular),
            measurement(outcome: .complete, connectionKind: .cellular)
        ]
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .upload),
                recentMeasurements: history
            )
        )
        XCTAssertEqual(result.disposition, .localSignalLikely)

        XCTAssertNil(NetworkAssistActionEngine.suggest(for: result))
    }

    // MARK: - Externo: reteste só com histórico estável evidenciado

    func testExternalSignalWithStableHistorySuggestsRetry() {
        let history = [
            measurement(connectionKind: .wifi, wifiBandGHz: 5.0, loadedLatencyMs: 22),
            measurement(connectionKind: .wifi, wifiBandGHz: 5.0, loadedLatencyMs: 18),
            measurement(connectionKind: .wifi, wifiBandGHz: 5.0, loadedLatencyMs: 20)
        ]
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .upload),
                recentMeasurements: history
            )
        )
        XCTAssertEqual(result.disposition, .externalSignalLikely)

        let suggestion = NetworkAssistActionEngine.suggest(for: result)
        XCTAssertEqual(suggestion, .retryMeasurement)
    }

    // MARK: - Nunca mais de uma sugestão

    func testSuggestionIsNeverMoreThanOneCase() {
        let cases: [NetworkAssistInvestigationResult] = [
            NetworkAssistInvestigationEngine.investigate(
                NetworkAssistInvestigationInput(failureSignal: .offline, recentMeasurements: [])
            ),
            NetworkAssistInvestigationEngine.investigate(
                NetworkAssistInvestigationInput(
                    failureSignal: .connectionLost(phase: .download),
                    recentMeasurements: [
                        measurement(outcome: .partial, connectionKind: .wifi),
                        measurement(outcome: .complete, connectionKind: .wifi)
                    ]
                )
            ),
            NetworkAssistInvestigationEngine.investigate(
                NetworkAssistInvestigationInput(
                    failureSignal: .connectionLost(phase: .upload),
                    recentMeasurements: [
                        measurement(connectionKind: .wifi, loadedLatencyMs: 20),
                        measurement(connectionKind: .wifi, loadedLatencyMs: 22)
                    ]
                )
            )
        ]

        for result in cases {
            // Cada resultado só pode produzir `nil` ou exatamente 1 caso —
            // o próprio tipo de retorno (`NetworkAssistActionSuggestion?`,
            // não um array) já impede mais de uma sugestão por construção.
            _ = NetworkAssistActionEngine.suggest(for: result)
        }
    }

    // MARK: - Determinismo / sem I/O

    func testSuggestIsPureAndDeterministic() {
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .download),
                recentMeasurements: [
                    measurement(outcome: .partial, connectionKind: .wifi),
                    measurement(outcome: .complete, connectionKind: .wifi)
                ]
            )
        )

        let first = NetworkAssistActionEngine.suggest(for: result)
        let second = NetworkAssistActionEngine.suggest(for: result)

        XCTAssertEqual(first, second)
    }
}
