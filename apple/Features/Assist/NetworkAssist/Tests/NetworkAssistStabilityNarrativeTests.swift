import XCTest
import NetworkCore
@testable import NetworkAssist

final class NetworkAssistStabilityNarrativeTests: XCTestCase {
    // MARK: - Estados explícitos de ausência (issue #125, item 3)

    func testInsufficientHistoryIsExplicitNotAGenericSentence() {
        let outcome = NetworkAssistStabilityPatternOutcome.insufficientHistory(
            distinctDayCount: 2,
            requiredDistinctDayCount: 5
        )

        let narrative = NetworkAssistStabilityNarrativeGenerator.makeNarrative(from: outcome)

        XCTAssertEqual(narrative, .insufficientHistory(distinctDayCount: 2, requiredDistinctDayCount: 5))
    }

    func testNoPatternDetectedIsExplicitNotAnEmptyString() {
        let narrative = NetworkAssistStabilityNarrativeGenerator.makeNarrative(from: .noPatternDetected)

        XCTAssertEqual(narrative, .noPatternDetected)
    }

    // MARK: - Frase factual (issue #125, item 3)

    func testWifiJitterPatternMatchesProductOwnerExample() {
        let signal = NetworkAssistStabilityPatternSignal(
            network: NetworkAssistNetworkIdentitySignal(connectionKind: .wifi, networkIdentifier: "Casa"),
            metric: .jitterMs,
            startHour: 20,
            endHour: 22,
            distinctDayCount: 6
        )

        let narrative = NetworkAssistStabilityNarrativeGenerator.makeNarrative(from: .detected(signal))

        guard case .factual(let text) = narrative else {
            return XCTFail("Esperava uma frase factual, obteve \(narrative)")
        }
        XCTAssertEqual(
            text,
            "Sua rede Wi-Fi Casa sofre picos de instabilidade (jitter alto) todos os dias entre 20h e 22h."
        )
    }

    func testCellularNetworkUsesCarrierWording() {
        let signal = NetworkAssistStabilityPatternSignal(
            network: NetworkAssistNetworkIdentitySignal(connectionKind: .cellular, networkIdentifier: "Vivo"),
            metric: .latencyMs,
            startHour: 18,
            endHour: 19,
            distinctDayCount: 4
        )

        let narrative = NetworkAssistStabilityNarrativeGenerator.makeNarrative(from: .detected(signal))

        guard case .factual(let text) = narrative else {
            return XCTFail("Esperava uma frase factual, obteve \(narrative)")
        }
        XCTAssertTrue(text.hasPrefix("Sua operadora Vivo"))
        XCTAssertFalse(text.contains("Wi-Fi"))
    }

    func testPacketLossPhraseCitesOnlyMeasuredFacts() {
        let signal = NetworkAssistStabilityPatternSignal(
            network: NetworkAssistNetworkIdentitySignal(connectionKind: .wifi, networkIdentifier: "Escritório"),
            metric: .packetLossPercent,
            startHour: 12,
            endHour: 14,
            distinctDayCount: 5
        )

        let narrative = NetworkAssistStabilityNarrativeGenerator.makeNarrative(from: .detected(signal))

        guard case .factual(let text) = narrative else {
            return XCTFail("Esperava uma frase factual, obteve \(narrative)")
        }
        // Fatos medidos: nome da rede, métrica e janela de horário.
        XCTAssertTrue(text.contains("Escritório"))
        XCTAssertTrue(text.contains("12h"))
        XCTAssertTrue(text.contains("14h"))
        // Nunca causa raiz não medida (AGENTS.md §9 / issue #125 "Não vira").
        XCTAssertFalse(text.lowercased().contains("vizinho"))
        XCTAssertFalse(text.lowercased().contains("canal"))
        XCTAssertFalse(text.lowercased().contains("roteador"))
    }

    func testMidnightWrappingWindowIsLabeledAsZeroHour() {
        let signal = NetworkAssistStabilityPatternSignal(
            network: NetworkAssistNetworkIdentitySignal(connectionKind: .wifi, networkIdentifier: "Casa"),
            metric: .jitterMs,
            startHour: 22,
            endHour: 24,
            distinctDayCount: 3
        )

        let narrative = NetworkAssistStabilityNarrativeGenerator.makeNarrative(from: .detected(signal))

        guard case .factual(let text) = narrative else {
            return XCTFail("Esperava uma frase factual, obteve \(narrative)")
        }
        XCTAssertTrue(text.contains("22h e 0h"))
    }
}
