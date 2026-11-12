import XCTest
@testable import NetworkSpatial

final class QualityClassifierTests: XCTestCase {

    func testExcellentClassification() {
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 6.0,
            gatewayJitterMs: 1.5,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 18.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 200.0,
            gatewayMedianMs: 6.0,
            gatewayP95Ms: 12.0,
            gatewayLossEvents: 0,
            gatewayTotalProbes: 20,
            gatewayLossInterpretation: .stable,
            wanMedianMs: 18.0,
            wanP95Ms: 25.0,
            wanJitterMs: 2.0,
            wanLossInterpretation: .stable
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .excellent)
        XCTAssertGreaterThanOrEqual(result.score, 90)
        XCTAssertEqual(result.cause, .allGood)
    }

    func testGoodClassification() {
        // Mediana ≤ 20ms, p95 ≤ 40ms, Jitter ≤ 5ms, sem perda confirmada
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 16.0,
            gatewayJitterMs: 4.0,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 35.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 120.0,
            gatewayMedianMs: 16.0,
            gatewayP95Ms: 30.0,
            gatewayLossEvents: 0,
            gatewayTotalProbes: 20,
            gatewayLossInterpretation: .stable,
            wanMedianMs: 35.0,
            wanP95Ms: 50.0,
            wanJitterMs: 5.0,
            wanLossInterpretation: .stable
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .good)
        XCTAssertGreaterThanOrEqual(result.score, 75)
        XCTAssertLessThanOrEqual(result.score, 89)
    }

    func testFairClassificationDueToLatency() {
        // Mediana entre 21 e 40ms ou Jitter entre 6 e 15ms
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 28.0,
            gatewayJitterMs: 8.0,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 45.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 60.0,
            gatewayMedianMs: 28.0,
            gatewayP95Ms: 55.0,
            gatewayLossEvents: 0,
            gatewayTotalProbes: 20,
            gatewayLossInterpretation: .stable
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .fair)
        XCTAssertGreaterThanOrEqual(result.score, 45)
        XCTAssertLessThanOrEqual(result.score, 74)
        XCTAssertEqual(result.cause, .localWiFiDegraded)
    }

    func testFairClassificationDueToIsolatedLossEvent() {
        // REGRA DE OURO DO LUIZ: 1 perda isolada em 40 NÃO destrói o teste para "Ruim", classifica como Regular/Oscilação eventual
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 6.0,
            gatewayJitterMs: 2.0,
            gatewayPacketLossPercent: 2.5, // 1 perda em 40 = 2.5%
            wanLatencyMs: 20.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 150.0,
            gatewayMedianMs: 6.0,
            gatewayP95Ms: 14.0,
            gatewayLossEvents: 1,
            gatewayTotalProbes: 40,
            gatewayConsecutiveLoss: 1,
            gatewayLossInterpretation: .isolatedEvent,
            wanMedianMs: 20.0,
            wanP95Ms: 28.0,
            wanJitterMs: 2.5,
            wanLossInterpretation: .stable
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .fair, "Uma perda isolada em 40 probes deve ser classificada como Regular, nunca como Ruim")
        XCTAssertGreaterThanOrEqual(result.score, 45)
        XCTAssertLessThanOrEqual(result.score, 74)
    }

    func testPoorClassificationDueToConfirmedLoss() {
        // 2+ perdas confirmadas em 40 probes -> Ruim
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 8.0,
            gatewayJitterMs: 2.5,
            gatewayPacketLossPercent: 5.0, // 2 perdas em 40
            wanLatencyMs: 25.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 30.0,
            gatewayMedianMs: 8.0,
            gatewayP95Ms: 18.0,
            gatewayLossEvents: 2,
            gatewayTotalProbes: 40,
            gatewayConsecutiveLoss: 1,
            gatewayLossInterpretation: .confirmedLoss
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .poor, "2+ perdas confirmadas devem ser classificadas como Ruim")
        XCTAssertLessThanOrEqual(result.score, 44)
    }

    func testPoorClassificationDueToConsecutiveLoss() {
        // Perdas consecutivas -> Instabilidade forte -> Ruim
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 12.0,
            gatewayJitterMs: 3.0,
            gatewayPacketLossPercent: 5.0,
            wanLatencyMs: 25.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 30.0,
            gatewayMedianMs: 12.0,
            gatewayP95Ms: 22.0,
            gatewayLossEvents: 2,
            gatewayTotalProbes: 40,
            gatewayConsecutiveLoss: 2,
            gatewayLossInterpretation: .consecutiveLoss
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .poor)
    }

    func testPoorClassificationDueToLatency() {
        // Mediana > 40ms -> Ruim
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 55.0,
            gatewayJitterMs: 12.0,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 65.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 15.0,
            gatewayMedianMs: 55.0,
            gatewayP95Ms: 75.0,
            gatewayLossEvents: 0,
            gatewayTotalProbes: 20,
            gatewayLossInterpretation: .stable
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .poor)
        XCTAssertLessThanOrEqual(result.score, 44)
    }

    func testPoorClassificationDueToP95Spike() {
        // Mediana normal (15ms), mas p95 > 80ms (pico de bufferbloat/interferência) -> Ruim
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 15.0,
            gatewayJitterMs: 4.0,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 35.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 50.0,
            gatewayMedianMs: 15.0,
            gatewayP95Ms: 95.0,
            gatewayLossEvents: 0,
            gatewayTotalProbes: 20,
            gatewayLossInterpretation: .stable
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .poor, "Spike com p95 > 80ms na LAN deve classificar como Ruim")
    }

    func testIsolationGoodWiFiBadISP() {
        // LAN excelente (3ms, 0% loss), mas WAN degradada (150ms > 120ms)
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 3.0,
            gatewayJitterMs: 1.0,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 150.0,
            wanPacketLossPercent: 4.0,
            downloadThroughputMbps: 10.0,
            gatewayMedianMs: 3.0,
            gatewayP95Ms: 6.0,
            gatewayLossEvents: 0,
            gatewayTotalProbes: 20,
            gatewayLossInterpretation: .stable,
            wanMedianMs: 150.0,
            wanP95Ms: 210.0,
            wanJitterMs: 35.0,
            wanLossInterpretation: .confirmedLoss
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .excellent)
        XCTAssertEqual(result.cause, .ispDegraded)
        XCTAssertTrue(result.explanation.contains("operadora"))
    }

    func testIsolationBothDegraded() {
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 65.0,
            gatewayJitterMs: 18.0,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 160.0,
            wanPacketLossPercent: 10.0,
            downloadThroughputMbps: 5.0,
            gatewayMedianMs: 65.0,
            gatewayP95Ms: 95.0,
            gatewayLossInterpretation: .stable,
            wanMedianMs: 160.0,
            wanP95Ms: 250.0,
            wanJitterMs: 40.0,
            wanLossInterpretation: .confirmedLoss
        )

        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .poor)
        XCTAssertEqual(result.cause, .bothDegraded)
    }

    func testIsolationOfflineWhenWiFiDisabled() {
        let metrics = NetworkMetrics()
        let result = QualityClassifier.classify(metrics: metrics, isWiFiActive: false)
        XCTAssertEqual(result.rating, .unmeasured)
        XCTAssertEqual(result.cause, .offline)
    }

    // MARK: - Testes dos Métodos Estatísticos (Mediana e p95)

    func testPercentileCalculations() {
        let values: [Double] = [3.0, 3.2, 3.5, 4.0, 4.1, 4.2, 4.5, 5.0, 6.0, 75.0]
        let median = GatewayLatencyProber.calculateMedian(values)
        // 10 elementos -> média dos índices 4 e 5: (4.1 + 4.2) / 2 = 4.15
        XCTAssertEqual(median, 4.15, accuracy: 0.01)

        let p95 = GatewayLatencyProber.calculateP95(values)
        // 10 * 0.95 = 9.5 -> ceil = 10 -> index 9 = 75.0
        XCTAssertEqual(p95, 75.0)

        // Com 20 elementos estáveis
        let stableValues = Array(repeating: 5.0, count: 20)
        XCTAssertEqual(GatewayLatencyProber.calculateMedian(stableValues), 5.0)
        XCTAssertEqual(GatewayLatencyProber.calculateP95(stableValues), 5.0)
    }
}
