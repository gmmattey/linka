import XCTest
@testable import NetworkOptimization
import NetworkCore

final class NetworkOptimizationTests: XCTestCase {
    func testBuildsDeterministicLoadOpportunity() {
        let measurement = sample(latency: 20, loaded: 150)
        let plan = OptimizationPlanBuilder().build(baseline: measurement, history: [])
        XCTAssertEqual(plan.opportunities.first?.kind, .responsivenessUnderLoad)
        XCTAssertEqual(plan.opportunities.first?.action, .reduceConcurrentUse)
    }

    func testInconclusiveEnvelopeCannotCreateLoadOpportunity() {
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 20,
            latencyMs: 20,
            loadedLatencyMs: 250,
            loadedLatencyUploadMs: 300,
            loadResponsiveness: LoadResponsivenessEvidence(
                environmentIdentifier: "cloudflare-speedtest-v1",
                integrity: .baselineInconclusive,
                baseline: nil,
                download: nil,
                upload: nil
            )
        )

        XCTAssertFalse(OptimizationPlanBuilder().build(baseline: measurement, history: []).opportunities.contains { $0.kind == .responsivenessUnderLoad })
    }

    func testDoesNotInventHistoryWithoutConfirmedIdentity() {
        let measurement = sample(latency: 80, loaded: nil, ssid: nil)
        let history = (0..<4).map { _ in sample(latency: 20, loaded: nil, ssid: nil) }
        XCTAssertTrue(OptimizationPlanBuilder().build(baseline: measurement, history: history).opportunities.isEmpty)
    }

    func testLimitsPlanToThreeOpportunities() {
        let measurement = sample(latency: 100, loaded: 240, jitter: 30, loss: 5)
        let history = (0..<3).map { _ in sample(latency: 20, loaded: nil) }
        XCTAssertEqual(OptimizationPlanBuilder().build(baseline: measurement, history: history).opportunities.count, 3)
    }

    /// Não existe roteador para "reiniciar" ou "se aproximar" numa conexão
    /// celular — a ação sugerida precisa continuar sendo necessária e
    /// possível para o tipo de rede da medição (issue de padronização de
    /// regras de Optimization/Assist).
    func testCellularInstabilityNeverSuggestsRouterAction() {
        let measurement = sample(latency: 100, loaded: nil, jitter: 30, loss: 5, connectionKind: .cellular)
        let plan = OptimizationPlanBuilder().build(baseline: measurement, history: [])
        let unstable = plan.opportunities.first { $0.kind == .unstableConnection }
        XCTAssertEqual(unstable?.action, .reduceConcurrentUse)
    }

    /// "Se aproximar do roteador" só faz sentido pra sinal sem fio — não há
    /// como "se aproximar" de um cabo Ethernet já conectado.
    func testEthernetInstabilityDoesNotSuggestMovingCloserToRouter() {
        let measurement = sample(latency: 100, loaded: nil, jitter: 30, loss: 5, connectionKind: .ethernet)
        let plan = OptimizationPlanBuilder().build(baseline: measurement, history: [])
        let unstable = plan.opportunities.first { $0.kind == .unstableConnection }
        XCTAssertEqual(unstable?.action, .reduceConcurrentUse)
    }

    /// `restartRouter` continua válida para Ethernet (também passa por um
    /// roteador doméstico), mas não para celular (não existe roteador
    /// nenhum entre o aparelho e a operadora).
    func testBelowUsualQualityActionRespectsConnectionKind() {
        let ethernetHistory = (0..<3).map { _ in sample(latency: 20, loaded: nil, connectionKind: .ethernet) }
        let ethernetBaseline = sample(latency: 100, loaded: nil, connectionKind: .ethernet)
        let ethernetPlan = OptimizationPlanBuilder().build(baseline: ethernetBaseline, history: ethernetHistory)
        XCTAssertEqual(
            ethernetPlan.opportunities.first { $0.kind == .belowUsualQuality }?.action,
            .restartRouter
        )

        let cellularHistory = (0..<3).map { _ in sample(latency: 20, loaded: nil, connectionKind: .cellular) }
        let cellularBaseline = sample(latency: 100, loaded: nil, connectionKind: .cellular)
        let cellularPlan = OptimizationPlanBuilder().build(baseline: cellularBaseline, history: cellularHistory)
        XCTAssertEqual(
            cellularPlan.opportunities.first { $0.kind == .belowUsualQuality }?.action,
            .reduceConcurrentUse
        )
    }

    func testBaselineRequiresAtLeastThreeEligibleMeasurements() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let builder = baselineBuilder()
        let measurements = [
            baselineSample(measuredAt: now.addingTimeInterval(-1)),
            baselineSample(measuredAt: now.addingTimeInterval(-2))
        ]

        XCTAssertNil(builder.build(profileIdentity: "casa", measurements: measurements, referenceDate: now))
    }

    func testBaselineOnlyUsesExplicitEnvironmentAssignments() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let room = "room-id"
        let otherRoom = "other-room-id"
        let first = baselineSample(measuredAt: now.addingTimeInterval(-1))
        let second = baselineSample(measuredAt: now.addingTimeInterval(-2))
        let third = baselineSample(measuredAt: now.addingTimeInterval(-3))
        let unassigned = baselineSample(measuredAt: now.addingTimeInterval(-4))
        let other = baselineSample(measuredAt: now.addingTimeInterval(-5))
        let assignments = [first.id: room, second.id: room, third.id: room, other.id: otherRoom]
        let builder = NetworkBaselineBuilder { assignments[$0.id] }
        let baseline = try XCTUnwrap(builder.build(profileIdentity: room, measurements: [first, second, third, unassigned, other], referenceDate: now))
        XCTAssertEqual(Set(baseline.measurementIDs), Set([first.id, second.id, third.id]))
    }

    func testBaselineExcludesMeasurementsOutsideThirtyDayWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let builder = baselineBuilder()
        let measurements = [
            baselineSample(measuredAt: now.addingTimeInterval(-1)),
            baselineSample(measuredAt: now.addingTimeInterval(-2)),
            baselineSample(measuredAt: now.addingTimeInterval(-3)),
            baselineSample(measuredAt: now.addingTimeInterval(-(30 * 24 * 60 * 60) - 1))
        ]

        let baseline = builder.build(profileIdentity: "casa", measurements: measurements, referenceDate: now)
        XCTAssertEqual(baseline?.sampleCount, 3)
        XCTAssertEqual(baseline?.measurementIDs.count, 3)
    }

    func testBaselineRejectsDifferentIdentityAndIncompleteOrNonWiFiMeasurements() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let builder = baselineBuilder()
        let measurements = [
            baselineSample(measuredAt: now.addingTimeInterval(-1)),
            baselineSample(measuredAt: now.addingTimeInterval(-2), ssid: "Trabalho"),
            baselineSample(measuredAt: now.addingTimeInterval(-3), outcome: .partial),
            baselineSample(measuredAt: now.addingTimeInterval(-4), connectionKind: .cellular)
        ]

        XCTAssertNil(builder.build(profileIdentity: "casa", measurements: measurements, referenceDate: now))
    }

    func testBaselineUsesMedianForAllMetrics() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let builder = baselineBuilder()
        let measurements = [
            baselineSample(measuredAt: now.addingTimeInterval(-1), download: 30, upload: 3, latency: 30, jitter: 3, loss: 3),
            baselineSample(measuredAt: now.addingTimeInterval(-2), download: 10, upload: 1, latency: 10, jitter: 1, loss: 1),
            baselineSample(measuredAt: now.addingTimeInterval(-3), download: 20, upload: 2, latency: 20, jitter: 2, loss: 2)
        ]

        let baseline = try XCTUnwrap(builder.build(profileIdentity: "casa", measurements: measurements, referenceDate: now))
        XCTAssertEqual(baseline.downloadMbps, 20)
        XCTAssertEqual(baseline.uploadMbps, 2)
        XCTAssertEqual(baseline.latencyMs, 20)
        XCTAssertEqual(baseline.jitterMs, 2)
        XCTAssertEqual(baseline.packetLossPercent, 2)
    }

    func testBaselinePreservesMissingMetricsInsteadOfSynthesizingZero() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let builder = baselineBuilder()
        let measurements = [
            baselineSample(measuredAt: now.addingTimeInterval(-1), download: 10, upload: nil, latency: nil, jitter: nil, loss: nil),
            baselineSample(measuredAt: now.addingTimeInterval(-2), download: 20, upload: nil, latency: nil, jitter: nil, loss: nil),
            baselineSample(measuredAt: now.addingTimeInterval(-3), download: 30, upload: nil, latency: nil, jitter: nil, loss: nil)
        ]

        let baseline = try XCTUnwrap(builder.build(profileIdentity: "casa", measurements: measurements, referenceDate: now))
        XCTAssertEqual(baseline.downloadMbps, 20)
        XCTAssertNil(baseline.uploadMbps)
        XCTAssertNil(baseline.latencyMs)
        XCTAssertNil(baseline.jitterMs)
        XCTAssertNil(baseline.packetLossPercent)
    }

    func testBaselineComparisonReportsImprovedWorsenedAndStableMetrics() throws {
        let baseline = profileBaseline(download: 100, upload: 10, latency: 100, jitter: 10, loss: 3)
        let current = baselineSample(
            measuredAt: Date(),
            download: 110,
            upload: 9,
            latency: 97,
            jitter: 5,
            loss: 3
        )

        let result = baselineComparator().compare(current: current, against: baseline)
        guard case .compared(let comparison) = result else {
            return XCTFail("A medição deveria ser compatível com a baseline")
        }

        XCTAssertEqual(comparison.comparison(for: .downloadMbps)?.direction, .improved)
        XCTAssertEqual(comparison.comparison(for: .uploadMbps)?.direction, .worsened)
        XCTAssertEqual(comparison.comparison(for: .latencyMs)?.direction, .stable)
        XCTAssertEqual(comparison.comparison(for: .jitterMs)?.direction, .improved)
        XCTAssertEqual(comparison.comparison(for: .packetLossPercent)?.direction, .stable)
    }

    func testBaselineComparisonMarksMissingMetricUnavailable() throws {
        let baseline = profileBaseline(download: 100, upload: nil, latency: nil, jitter: 10, loss: nil)
        let current = baselineSample(
            measuredAt: Date(),
            download: nil,
            upload: 5,
            latency: 20,
            jitter: nil,
            loss: 1
        )

        let result = baselineComparator().compare(current: current, against: baseline)
        guard case .compared(let comparison) = result else {
            return XCTFail("A identidade continua compatível")
        }

        XCTAssertEqual(
            comparison.metrics.map(\.direction),
            [.unavailable, .unavailable, .unavailable, .unavailable, .unavailable]
        )
    }

    func testBaselineComparisonRejectsIncompatibleCurrentMeasurement() {
        let baseline = profileBaseline()
        let differentNetwork = baselineSample(measuredAt: Date(), ssid: "Trabalho")
        let partial = baselineSample(measuredAt: Date(), outcome: .partial)

        XCTAssertEqual(baselineComparator().compare(current: differentNetwork, against: baseline), .incompatible)
        XCTAssertEqual(baselineComparator().compare(current: partial, against: baseline), .incompatible)
    }

    private func sample(
        latency: Double,
        loaded: Double?,
        jitter: Double? = nil,
        loss: Double? = nil,
        ssid: String? = "Casa",
        connectionKind: NetworkConnectionKind = .wifi
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 100,
            latencyMs: latency,
            jitterMs: jitter,
            packetLossPercent: loss,
            loadedLatencyMs: loaded,
            connectionKind: connectionKind,
            wifiContext: connectionKind == .wifi ? WiFiNetworkContext(ssid: ssid) : nil,
            networkIdentifier: connectionKind == .wifi ? nil : "Operadora"
        )
    }

    private func baselineBuilder() -> NetworkBaselineBuilder {
        NetworkBaselineBuilder { measurement in
            measurement.wifiContext?.ssid?.lowercased()
        }
    }

    private func baselineComparator() -> NetworkBaselineComparator {
        NetworkBaselineComparator { measurement in
            measurement.wifiContext?.ssid?.lowercased()
        }
    }

    private func profileBaseline(
        download: Double? = 100,
        upload: Double? = 10,
        latency: Double? = 20,
        jitter: Double? = 2,
        loss: Double? = 0
    ) -> NetworkBaseline {
        NetworkBaseline(
            profileIdentity: "casa",
            sampleCount: 3,
            measuredFrom: Date(timeIntervalSince1970: 1),
            measuredUntil: Date(timeIntervalSince1970: 2),
            measurementIDs: [UUID(), UUID(), UUID()],
            downloadMbps: download,
            uploadMbps: upload,
            latencyMs: latency,
            jitterMs: jitter,
            packetLossPercent: loss
        )
    }

    private func baselineSample(
        measuredAt: Date,
        ssid: String = "Casa",
        outcome: MeasurementOutcome = .complete,
        connectionKind: NetworkConnectionKind = .wifi,
        download: Double? = 100,
        upload: Double? = 10,
        latency: Double? = 20,
        jitter: Double? = 2,
        loss: Double? = 0
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            measuredAt: measuredAt,
            outcome: outcome,
            downloadMbps: download,
            uploadMbps: upload,
            latencyMs: latency,
            jitterMs: jitter,
            packetLossPercent: loss,
            connectionKind: connectionKind,
            wifiContext: connectionKind == .wifi ? WiFiNetworkContext(ssid: ssid) : nil
        )
    }
}
