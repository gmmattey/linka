import XCTest
import NetworkCore
@testable import NetworkAssist

final class NetworkAssistInvestigationTests: XCTestCase {
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

    // MARK: - Sem sinal de falha

    func testNoFailureSignalIsInconclusiveWithoutEvidence() {
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(failureSignal: nil, recentMeasurements: [measurement()])
        )

        XCTAssertEqual(result.disposition, .inconclusive)
        XCTAssertTrue(result.evidence.isEmpty)
        XCTAssertTrue(result.evidenceIDs.isEmpty)
        XCTAssertEqual(result.missingSignals, [.failureContext])
    }

    // MARK: - Offline é fato, não causa

    func testOfflineIsInconclusiveWithoutAnyHistory() {
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(failureSignal: .offline, recentMeasurements: [])
        )

        XCTAssertEqual(result.disposition, .inconclusive)
        XCTAssertFalse(result.evidenceIDs.isEmpty)
        XCTAssertEqual(Set(result.evidenceIDs), Set(result.evidence.map(\.id)))
        XCTAssertTrue(result.missingSignals.contains(.connectionKind))
        XCTAssertTrue(result.missingSignals.contains(.alternateNetworkSample))
    }

    func testOfflineStaysInconclusiveEvenWithWifiHistory() {
        let history = [measurement(connectionKind: .wifi), measurement(connectionKind: .wifi)]
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(failureSignal: .offline, recentMeasurements: history)
        )

        XCTAssertEqual(result.disposition, .inconclusive)
    }

    // MARK: - Acesso externo indisponível aparente (connectionLost)

    func testConnectionLostWithoutHistoryIsInconclusive() {
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .download),
                recentMeasurements: []
            )
        )

        XCTAssertEqual(result.disposition, .inconclusive)
        // O sinal de falha em si é conhecido, então ele é citado mesmo no
        // inconclusivo — só falta o histórico para diferenciar.
        XCTAssertFalse(result.evidenceIDs.isEmpty)
        XCTAssertTrue(result.missingSignals.contains(.recentMeasurementHistory))
        XCTAssertTrue(result.missingSignals.contains(.alternateNetworkSample))
    }

    func testConnectionLostWithStableHistoryLeansExternal() {
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
        XCTAssertFalse(result.evidenceIDs.isEmpty)
        XCTAssertEqual(Set(result.evidenceIDs), Set(result.evidence.map(\.id)))
        XCTAssertTrue(result.missingSignals.isEmpty)

        let connectionEvidence = result.evidence.first { $0.metricKey == "connectionKind" }
        XCTAssertEqual(connectionEvidence?.direction, "wifi")
        let latencyEvidence = result.evidence.first { $0.metricKey == "loadedLatencyMs" }
        XCTAssertNotNil(latencyEvidence?.value)
    }

    func testInconclusiveEnvelopeIsNotUsedAsAssistLoadedLatencyEvidence() {
        let history = (0..<3).map { _ in
            NetworkMeasurement(
                outcome: .complete,
                downloadMbps: 200,
                uploadMbps: 50,
                latencyMs: 15,
                loadedLatencyMs: 250,
                loadResponsiveness: LoadResponsivenessEvidence(
                    environmentIdentifier: "cloudflare-speedtest-v1",
                    integrity: .downloadInconclusive,
                    baseline: nil,
                    download: nil,
                    upload: nil
                ),
                connectionKind: .wifi,
                wifiBandGHz: 5
            )
        }
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(failureSignal: .connectionLost(phase: .download), recentMeasurements: history)
        )

        XCTAssertNil(result.evidence.first { $0.metricKey == "loadedLatencyMs" })
        XCTAssertTrue(result.missingSignals.contains(.loadedLatencyBaseline))
    }

    func testConnectionLostWithUnstableHistoryLeansLocal() {
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
        XCTAssertFalse(result.evidenceIDs.isEmpty)

        let historyEvidence = result.evidence.first { $0.metricKey == "recentOutcomeStability" }
        XCTAssertEqual(historyEvidence?.direction, "unstable")
    }

    // MARK: - Sinais ausentes limitam o que pode ser afirmado

    func testMissingConnectionKindAndLatencyAreFlagged() {
        let history = [measurement(), measurement()]
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .ping),
                recentMeasurements: history
            )
        )

        XCTAssertTrue(result.missingSignals.contains(.connectionKind))
        XCTAssertTrue(result.missingSignals.contains(.loadedLatencyBaseline))
        // Sem `connectionKind` resolvido, não faz sentido cobrar banda Wi-Fi.
        XCTAssertFalse(result.missingSignals.contains(.wifiBandGHz))
    }

    func testMissingWifiBandIsFlaggedOnlyWhenConnectionIsWifi() {
        let history = [
            measurement(connectionKind: .wifi, loadedLatencyMs: 20),
            measurement(connectionKind: .wifi, loadedLatencyMs: 22)
        ]
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .upload),
                recentMeasurements: history
            )
        )

        XCTAssertTrue(result.missingSignals.contains(.wifiBandGHz))
        XCTAssertFalse(result.missingSignals.contains(.connectionKind))
        XCTAssertFalse(result.missingSignals.contains(.loadedLatencyBaseline))
    }

    func testCellularHistoryNeverFlagsMissingWifiBand() {
        let history = [
            measurement(connectionKind: .cellular, loadedLatencyMs: 30),
            measurement(connectionKind: .cellular, loadedLatencyMs: 28)
        ]
        let result = NetworkAssistInvestigationEngine.investigate(
            NetworkAssistInvestigationInput(
                failureSignal: .connectionLost(phase: .download),
                recentMeasurements: history
            )
        )

        XCTAssertFalse(result.missingSignals.contains(.wifiBandGHz))
    }

    // MARK: - Determinismo / sem I/O

    func testInvestigateIsPureAndDeterministic() {
        let input = NetworkAssistInvestigationInput(
            failureSignal: .connectionLost(phase: .download),
            recentMeasurements: [measurement(connectionKind: .wifi, loadedLatencyMs: 20)]
        )

        let first = NetworkAssistInvestigationEngine.investigate(input)
        let second = NetworkAssistInvestigationEngine.investigate(input)

        XCTAssertEqual(first, second)
    }
}
