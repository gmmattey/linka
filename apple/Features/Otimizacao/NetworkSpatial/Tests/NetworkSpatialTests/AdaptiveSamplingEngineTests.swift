import XCTest
@testable import NetworkSpatial

final class AdaptiveSamplingEngineTests: XCTestCase {

    // MARK: - Validação Matemática dos Percentis (Mediana e p95)

    func testMedianOddAndEvenSamples() {
        // Ímpar: 5 amostras
        let oddSamples: [Double] = [2.0, 4.0, 6.0, 8.0, 10.0]
        XCTAssertEqual(GatewayLatencyProber.calculateMedian(oddSamples), 6.0)

        // Par: 6 amostras
        let evenSamples: [Double] = [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]
        XCTAssertEqual(GatewayLatencyProber.calculateMedian(evenSamples), 7.0) // (6 + 8) / 2

        // Amostra única
        let singleSample: [Double] = [5.5]
        XCTAssertEqual(GatewayLatencyProber.calculateMedian(singleSample), 5.5)

        // Lista vazia
        let empty: [Double] = []
        XCTAssertEqual(GatewayLatencyProber.calculateMedian(empty), 999.0)
    }

    func testP95CalculationsAcrossDistributions() {
        // 20 amostras ordenadas de 1 a 20
        let samples20: [Double] = (1...20).map { Double($0) }
        // 20 * 0.95 = 19 -> index 18 (19º elemento) = 19.0
        XCTAssertEqual(GatewayLatencyProber.calculateP95(samples20), 19.0)

        // 40 amostras (janela completa de confirmação adaptativa)
        let samples40: [Double] = (1...40).map { Double($0) }
        // 40 * 0.95 = 38 -> index 37 (38º elemento) = 38.0
        XCTAssertEqual(GatewayLatencyProber.calculateP95(samples40), 38.0)

        // Distribuição com spike único em 10 amostras (1 elemento = 10% > 5%, portanto p95 captura o spike)
        var spikeDistribution10 = Array(repeating: 4.0, count: 9)
        spikeDistribution10.append(92.0)
        spikeDistribution10.sort()
        XCTAssertEqual(GatewayLatencyProber.calculateMedian(spikeDistribution10), 4.0)
        XCTAssertEqual(GatewayLatencyProber.calculateP95(spikeDistribution10), 92.0)

        // Em 20 amostras, 2 spikes representam 10% (excedendo os 95% estáveis)
        var spikeDistribution20 = Array(repeating: 4.0, count: 18)
        spikeDistribution20.append(contentsOf: [85.0, 92.0])
        spikeDistribution20.sort()
        XCTAssertEqual(GatewayLatencyProber.calculateMedian(spikeDistribution20), 4.0)
        XCTAssertEqual(GatewayLatencyProber.calculateP95(spikeDistribution20), 85.0)
    }

    // MARK: - Validação do Motor em Duas Etapas (RFC 7680)

    func testLatencyProbeResultCreationWithAdaptiveFields() {
        let result = LatencyProbeResult(
            medianLatencyMs: 5.2,
            p95LatencyMs: 11.4,
            meanLatencyMs: 6.8,
            jitterMs: 1.8,
            packetLossPercent: 2.5,
            samples: Array(repeating: 5.2, count: 39),
            lostCount: 1,
            totalProbes: 40,
            consecutiveLossCount: 1,
            lossInterpretation: .isolatedEvent,
            didRunAdaptiveConfirmation: true
        )

        XCTAssertEqual(result.medianLatencyMs, 5.2)
        XCTAssertEqual(result.p95LatencyMs, 11.4)
        XCTAssertEqual(result.jitterMs, 1.8)
        XCTAssertEqual(result.lostCount, 1)
        XCTAssertEqual(result.totalProbes, 40)
        XCTAssertEqual(result.lossInterpretation, .isolatedEvent)
        XCTAssertTrue(result.didRunAdaptiveConfirmation)
        XCTAssertFalse(result.lossInterpretation.isDegraded, "Evento isolado não deve ser considerado degradação confirmada")
    }

    func testWANProbeResultCreationWithJitterAndPercentiles() {
        let wanResult = WANProbeResult(
            wanMedianLatencyMs: 24.5,
            wanP95LatencyMs: 38.0,
            wanMeanLatencyMs: 26.1,
            wanJitterMs: 4.2,
            wanPacketLossPercent: 0.0,
            wanLostCount: 0,
            wanTotalProbes: 8,
            wanLossInterpretation: .stable,
            didRunAdaptiveConfirmation: false
        )

        XCTAssertEqual(wanResult.wanLatencyMs, 24.5, "Acesso de compatibilidade deve retornar a mediana")
        XCTAssertEqual(wanResult.wanMedianLatencyMs, 24.5)
        XCTAssertEqual(wanResult.wanP95LatencyMs, 38.0)
        XCTAssertEqual(wanResult.wanJitterMs, 4.2)
        XCTAssertEqual(wanResult.wanLossInterpretation, .stable)
    }

    // MARK: - Matriz de Decisão do Luiz: Evento Isolado vs Perda Confirmada

    func testSingleLossDoesNotPenalizeToPoor() {
        // 1 perda isolada em 40 probes
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 8.0,
            gatewayJitterMs: 2.2,
            gatewayPacketLossPercent: 2.5,
            wanLatencyMs: 22.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 180.0,
            gatewayMedianMs: 8.0,
            gatewayP95Ms: 16.0,
            gatewayLossEvents: 1,
            gatewayTotalProbes: 40,
            gatewayConsecutiveLoss: 1,
            gatewayLossInterpretation: .isolatedEvent,
            wanMedianMs: 22.0,
            wanP95Ms: 32.0,
            wanJitterMs: 3.0,
            wanLossInterpretation: .stable
        )

        let classification = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(classification.rating, .fair, "1 perda em 40 não pode derrubar para Ruim; deve ser Regular")
        XCTAssertGreaterThanOrEqual(classification.score, 45)
    }

    func testTwoLossesConfirmDegradationToPoor() {
        // 2 perdas em 40 probes
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 8.0,
            gatewayJitterMs: 2.2,
            gatewayPacketLossPercent: 5.0,
            wanLatencyMs: 22.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 180.0,
            gatewayMedianMs: 8.0,
            gatewayP95Ms: 16.0,
            gatewayLossEvents: 2,
            gatewayTotalProbes: 40,
            gatewayConsecutiveLoss: 1,
            gatewayLossInterpretation: .confirmedLoss,
            wanMedianMs: 22.0,
            wanP95Ms: 32.0,
            wanJitterMs: 3.0,
            wanLossInterpretation: .stable
        )

        let classification = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(classification.rating, .poor, "2 ou mais perdas em 40 probes confirmam perda real de RF")
        XCTAssertEqual(classification.cause, .localWiFiDegraded)
    }

    func testConsecutiveLossesTriggerSevereInstability() {
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 10.0,
            gatewayJitterMs: 3.0,
            gatewayPacketLossPercent: 5.0,
            wanLatencyMs: 22.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 180.0,
            gatewayMedianMs: 10.0,
            gatewayP95Ms: 20.0,
            gatewayLossEvents: 2,
            gatewayTotalProbes: 40,
            gatewayConsecutiveLoss: 2,
            gatewayLossInterpretation: .consecutiveLoss
        )

        let classification = QualityClassifier.classify(metrics: metrics, isWiFiActive: true)
        XCTAssertEqual(classification.rating, .poor)
        XCTAssertTrue(metrics.gatewayLossInterpretation?.isDegraded ?? false)
    }
}
