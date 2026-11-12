import XCTest
import LinkaEntitlements
import NetworkAssist
import NetworkCore
import NetworkInsights
@testable import LinkaModules

final class NetworkStabilityPatternsTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Análise local determinística (issue #125, itens 1-3)

    func testAnalyzeGroupsByNetworkAndReportsFactualNarrative() throws {
        var measurements: [NetworkMeasurement] = []
        for day in 1...6 {
            measurements.append(
                measurement(day: day, hour: 8, jitter: 10, connectionKind: .wifi, networkIdentifier: "Casa")
            )
        }
        for day in 1...4 {
            measurements.append(
                measurement(day: day, hour: 21, jitter: 100, connectionKind: .wifi, networkIdentifier: "Casa")
            )
        }
        // Rede diferente, sem amostra suficiente — não deve aparecer no relatório.
        measurements.append(
            measurement(day: 1, hour: 9, jitter: 10, connectionKind: .cellular, networkIdentifier: "Vivo")
        )

        let analyzer = BasicNetworkStabilityPatternAnalyzer(
            groupConfiguration: .init(minimumSampleCount: 5),
            calendar: utcCalendar
        )

        let reports = try analyzer.analyze(measurements)

        XCTAssertEqual(reports.count, 1)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report.connectionKind, .wifi)
        XCTAssertEqual(report.networkIdentifier, "Casa")
        XCTAssertEqual(report.summary.measurementCount, 10)

        guard case .factual(let text) = report.narrative(for: .jitterMs) else {
            return XCTFail("Esperava narrativa factual para jitter")
        }
        XCTAssertEqual(text, "Sua rede Wi-Fi Casa sofre picos de instabilidade (jitter alto) todos os dias entre 20h e 22h.")

        // Métricas nunca medidas neste histórico (só jitter foi capturado)
        // continuam explícitas, nunca omitidas nem promovidas a "sem
        // padrão" — não há amostra nenhuma para latência/perda de pacote,
        // então o estado correto é "histórico insuficiente" com 0 dias.
        XCTAssertEqual(
            report.narrative(for: .latencyMs),
            .insufficientHistory(distinctDayCount: 0, requiredDistinctDayCount: 5)
        )
        XCTAssertEqual(
            report.narrative(for: .packetLossPercent),
            .insufficientHistory(distinctDayCount: 0, requiredDistinctDayCount: 5)
        )
    }

    func testAnalyzeReportsNoPatternDetectedWhenMetricIsMeasuredButFlat() throws {
        var measurements: [NetworkMeasurement] = []
        for day in 1...6 {
            for hour in [8, 21] {
                measurements.append(
                    measurement(
                        day: day,
                        hour: hour,
                        jitter: 10,
                        latency: 20,
                        packetLoss: 0,
                        connectionKind: .wifi,
                        networkIdentifier: "Casa"
                    )
                )
            }
        }

        let analyzer = BasicNetworkStabilityPatternAnalyzer(
            groupConfiguration: .init(minimumSampleCount: 5),
            calendar: utcCalendar
        )
        let reports = try analyzer.analyze(measurements)
        let report = try XCTUnwrap(reports.first)

        XCTAssertEqual(report.narrative(for: .jitterMs), .noPatternDetected)
        XCTAssertEqual(report.narrative(for: .latencyMs), .noPatternDetected)
        XCTAssertEqual(report.narrative(for: .packetLossPercent), .noPatternDetected)
    }

    func testAnalyzeReturnsExplicitInsufficientHistoryBelowMinimumDays() throws {
        let measurements = [
            measurement(day: 1, hour: 20, jitter: 80, connectionKind: .wifi, networkIdentifier: "Casa"),
            measurement(day: 1, hour: 21, jitter: 90, connectionKind: .wifi, networkIdentifier: "Casa"),
            measurement(day: 2, hour: 20, jitter: 85, connectionKind: .wifi, networkIdentifier: "Casa")
        ]

        let analyzer = BasicNetworkStabilityPatternAnalyzer(
            groupConfiguration: .init(minimumSampleCount: 3),
            calendar: utcCalendar
        )

        let reports = try analyzer.analyze(measurements)
        let report = try XCTUnwrap(reports.first)

        guard case .insufficientHistory(let distinctDayCount, let required) = report.narrative(for: .jitterMs) else {
            return XCTFail("Esperava insufficientHistory, obteve \(String(describing: report.narrative(for: .jitterMs)))")
        }
        XCTAssertEqual(distinctDayCount, 2)
        XCTAssertEqual(required, 5)
    }

    func testAnalyzeReturnsNoReportsWhenNoGroupIsEligible() throws {
        let measurements = [
            measurement(day: 1, hour: 8, jitter: 10, connectionKind: .wifi, networkIdentifier: "Casa")
        ]

        let analyzer = BasicNetworkStabilityPatternAnalyzer(groupConfiguration: .init(minimumSampleCount: 5))
        let reports = try analyzer.analyze(measurements)

        XCTAssertTrue(reports.isEmpty)
    }

    // MARK: - Gate de entitlement (issue #125, item 4)

    func testFreeTierIsBlockedFromStabilityPatterns() {
        let analyzer = EntitlementGatedNetworkStabilityPatternAnalyzer(
            wrapping: BasicNetworkStabilityPatternAnalyzer(),
            snapshot: .free
        )

        XCTAssertThrowsError(try analyzer.analyze(sampleHistory())) { error in
            XCTAssertEqual(error as? NetworkInsightsError, .notEntitled)
        }
    }

    func testPlusTierIsGrantedStabilityPatterns() throws {
        let analyzer = EntitlementGatedNetworkStabilityPatternAnalyzer(
            wrapping: BasicNetworkStabilityPatternAnalyzer(
                groupConfiguration: .init(minimumSampleCount: 5),
                calendar: utcCalendar
            ),
            snapshot: .plus(status: .active, source: .subscription)
        )

        let reports = try analyzer.analyze(sampleHistory())
        XCTAssertFalse(reports.isEmpty)
    }

    func testInactivePlusSubscriptionIsBlocked() {
        let analyzer = EntitlementGatedNetworkStabilityPatternAnalyzer(
            wrapping: BasicNetworkStabilityPatternAnalyzer(),
            snapshot: .plus(status: .inactive, source: .subscription)
        )

        XCTAssertThrowsError(try analyzer.analyze(sampleHistory())) { error in
            XCTAssertEqual(error as? NetworkInsightsError, .notEntitled)
        }
    }

    // MARK: - Auxiliares

    private func sampleHistory() -> [NetworkMeasurement] {
        var measurements: [NetworkMeasurement] = []
        for day in 1...6 {
            measurements.append(
                measurement(day: day, hour: 8, jitter: 10, connectionKind: .wifi, networkIdentifier: "Casa")
            )
        }
        for day in 1...4 {
            measurements.append(
                measurement(day: day, hour: 21, jitter: 100, connectionKind: .wifi, networkIdentifier: "Casa")
            )
        }
        return measurements
    }

    private func measurement(
        day: Int,
        hour: Int,
        jitter: Double,
        latency: Double? = nil,
        packetLoss: Double? = nil,
        connectionKind: NetworkConnectionKind,
        networkIdentifier: String
    ) -> NetworkMeasurement {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = day
        components.hour = hour
        let measuredAt = utcCalendar.date(from: components)!

        return NetworkMeasurement(
            measuredAt: measuredAt,
            outcome: .partial,
            latencyMs: latency,
            jitterMs: jitter,
            packetLossPercent: packetLoss,
            connectionKind: connectionKind,
            networkIdentifier: networkIdentifier
        )
    }
}
