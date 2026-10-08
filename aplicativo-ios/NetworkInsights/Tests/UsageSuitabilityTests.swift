import XCTest
import NetworkCore
@testable import NetworkInsights

final class UsageSuitabilityTests: XCTestCase {
    private let evaluator = UsageSuitabilityEvaluator()

    // MARK: - Métricas completas e boas

    func testAllUsageCasesAreAdequateWhenEveryMetricIsWellWithinThresholds() {
        let measurement = measurement(
            download: 120,
            upload: 20,
            latency: 20,
            jitter: 5,
            packetLoss: 0,
            loadedLatency: 20
        )

        let report = evaluator.evaluate(measurement)

        for usageCase in UsageCase.allCases {
            let verdict = report.verdict(for: usageCase)
            XCTAssertEqual(verdict?.level, .adequate, "\(usageCase) deveria ser adequate")
            XCTAssertNil(verdict?.limitingMetric, "\(usageCase) não deveria ter métrica limitante quando adequate")
        }
    }

    func testZeroPacketLossCountsAsMeasuredNotMissing() {
        // packetLossPercent == 0 é um valor medido (ótimo), não ausência —
        // não deve rebaixar o veredito como `nil` rebaixaria.
        let measurement = measurement(
            download: 120,
            upload: 20,
            latency: 20,
            jitter: 5,
            packetLoss: 0
        )

        let report = evaluator.evaluate(measurement)

        XCTAssertEqual(report.verdict(for: .onlineGaming)?.level, .adequate)
        XCTAssertEqual(report.verdict(for: .videoCall)?.level, .adequate)
        XCTAssertEqual(report.verdict(for: .streaming4K)?.level, .adequate)
    }

    // MARK: - Métricas completas e ruins

    func testAllUsageCasesAreLimitedWhenMetricsFailThresholds() {
        let measurement = measurement(
            download: 1,
            upload: 0.5,
            latency: 400,
            jitter: 200,
            packetLoss: 50,
            loadedLatency: 400
        )

        let report = evaluator.evaluate(measurement)

        XCTAssertEqual(report.verdict(for: .videoCall)?.level, .limited)
        XCTAssertEqual(report.verdict(for: .videoCall)?.limitingMetric, .uploadMbps)

        XCTAssertEqual(report.verdict(for: .streamingHD)?.level, .limited)
        XCTAssertEqual(report.verdict(for: .streamingHD)?.limitingMetric, .downloadMbps)

        XCTAssertEqual(report.verdict(for: .streaming4K)?.level, .limited)
        XCTAssertEqual(report.verdict(for: .streaming4K)?.limitingMetric, .downloadMbps)

        XCTAssertEqual(report.verdict(for: .onlineGaming)?.level, .limited)
        XCTAssertEqual(report.verdict(for: .onlineGaming)?.limitingMetric, .loadedLatencyMs)
    }

    func testVideoCallFlagsLatencyWhenOnlyLatencyFailsThreshold() {
        let measurement = measurement(download: 120, upload: 20, latency: 300, jitter: 5, packetLoss: 0)

        let verdict = evaluator.evaluate(measurement).verdict(for: .videoCall)

        XCTAssertEqual(verdict?.level, .limited)
        XCTAssertEqual(verdict?.limitingMetric, .latencyMs)
    }

    func testOnlineGamingFlagsJitterWhenOnlyJitterFailsThreshold() {
        let measurement = measurement(download: 120, upload: 20, latency: 20, jitter: 80, packetLoss: 0)

        let verdict = evaluator.evaluate(measurement).verdict(for: .onlineGaming)

        XCTAssertEqual(verdict?.level, .limited)
        XCTAssertEqual(verdict?.limitingMetric, .jitterMs)
    }

    func testExcessivePacketLossLimitsCasesThatConsiderIt() {
        let measurement = measurement(download: 120, upload: 20, latency: 20, jitter: 5, packetLoss: 10)

        let report = evaluator.evaluate(measurement)

        XCTAssertEqual(report.verdict(for: .onlineGaming)?.level, .limited)
        XCTAssertEqual(report.verdict(for: .onlineGaming)?.limitingMetric, .packetLossPercent)

        XCTAssertEqual(report.verdict(for: .videoCall)?.level, .limited)
        XCTAssertEqual(report.verdict(for: .videoCall)?.limitingMetric, .packetLossPercent)

        XCTAssertEqual(report.verdict(for: .streaming4K)?.level, .limited)
        XCTAssertEqual(report.verdict(for: .streaming4K)?.limitingMetric, .packetLossPercent)

        // streamingHD não considera perda de pacotes — permanece adequate.
        XCTAssertEqual(report.verdict(for: .streamingHD)?.level, .adequate)
    }

    // MARK: - Métrica ausente rebaixa o veredito (nunca assume valor)

    func testMissingDownloadMakesDownloadDependentCasesNotAssessed() {
        let measurement = measurement(download: nil, upload: 20, latency: 20, jitter: 5, packetLoss: 0)

        let report = evaluator.evaluate(measurement)

        XCTAssertEqual(report.verdict(for: .streamingHD)?.level, .notAssessed)
        XCTAssertEqual(report.verdict(for: .streamingHD)?.limitingMetric, .downloadMbps)
        XCTAssertEqual(report.verdict(for: .streaming4K)?.level, .notAssessed)
        XCTAssertEqual(report.verdict(for: .streaming4K)?.limitingMetric, .downloadMbps)

        // Casos que não dependem de download continuam avaliáveis.
        XCTAssertEqual(report.verdict(for: .videoCall)?.level, .adequate)
        XCTAssertEqual(report.verdict(for: .onlineGaming)?.level, .adequate)
    }

    func testMissingPacketLossDowngradesToLimitedInsteadOfAdequate() {
        // packetLossPercent == nil (não medido) é diferente de 0 (medido,
        // sem perda) — ausência nunca promove `.adequate` silenciosamente.
        let measurement = measurement(download: 120, upload: 20, latency: 20, jitter: 5, packetLoss: nil)

        let report = evaluator.evaluate(measurement)

        XCTAssertEqual(report.verdict(for: .onlineGaming)?.level, .notAssessed)
        XCTAssertEqual(report.verdict(for: .onlineGaming)?.limitingMetric, .packetLossPercent)

        XCTAssertEqual(report.verdict(for: .videoCall)?.level, .notAssessed)
        XCTAssertEqual(report.verdict(for: .videoCall)?.limitingMetric, .packetLossPercent)

        XCTAssertEqual(report.verdict(for: .streaming4K)?.level, .limited)
        XCTAssertEqual(report.verdict(for: .streaming4K)?.limitingMetric, .packetLossPercent)

        // streamingHD não depende de perda de pacotes — segue adequate.
        XCTAssertEqual(report.verdict(for: .streamingHD)?.level, .adequate)
    }

    func testMissingJitterMakesOnlineGamingNotAssessedEvenWithGoodLatency() {
        let measurement = measurement(download: 120, upload: 20, latency: 20, jitter: nil, packetLoss: 0)

        let verdict = evaluator.evaluate(measurement).verdict(for: .onlineGaming)

        XCTAssertEqual(verdict?.level, .notAssessed)
        XCTAssertEqual(verdict?.limitingMetric, .jitterMs)
    }

    func testOnlineGamingFallsBackToLatencyMsWhenLoadedLatencyIsMissing() {
        let measurement = measurement(
            download: 120,
            upload: 20,
            latency: 20,
            jitter: 5,
            packetLoss: 0,
            loadedLatency: nil
        )

        let verdict = evaluator.evaluate(measurement).verdict(for: .onlineGaming)

        XCTAssertEqual(verdict?.level, .adequate)
    }

    func testOnlineGamingUsesLoadedLatencyOverLatencyWhenBothPresent() {
        // Ping isolado está ótimo, mas a conexão sob carga (loadedLatencyMs)
        // não sustenta jogo online — o veredito deve refletir a métrica sob
        // carga, mais representativa, e não o ping isolado.
        let measurement = measurement(
            download: 120,
            upload: 20,
            latency: 10,
            jitter: 5,
            packetLoss: 0,
            loadedLatency: 300
        )

        let verdict = evaluator.evaluate(measurement).verdict(for: .onlineGaming)

        XCTAssertEqual(verdict?.level, .limited)
        XCTAssertEqual(verdict?.limitingMetric, .loadedLatencyMs)
    }

    // MARK: - Limites de threshold

    func testVideoCallThresholdsAreInclusiveAtTheBoundary() {
        let atBoundary = measurement(download: 120, upload: 3, latency: 150, jitter: 5, packetLoss: 2)
        XCTAssertEqual(evaluator.evaluate(atBoundary).verdict(for: .videoCall)?.level, .adequate)

        let justBelowUpload = measurement(download: 120, upload: 2.99, latency: 150, jitter: 5, packetLoss: 2)
        XCTAssertEqual(evaluator.evaluate(justBelowUpload).verdict(for: .videoCall)?.level, .limited)

        let justAboveLatency = measurement(download: 120, upload: 3, latency: 150.01, jitter: 5, packetLoss: 2)
        XCTAssertEqual(evaluator.evaluate(justAboveLatency).verdict(for: .videoCall)?.level, .limited)

        let justAbovePacketLoss = measurement(download: 120, upload: 3, latency: 150, jitter: 5, packetLoss: 2.01)
        XCTAssertEqual(evaluator.evaluate(justAbovePacketLoss).verdict(for: .videoCall)?.level, .limited)
    }

    func testStreamingHDThresholdIsInclusiveAtTheBoundary() {
        let atBoundary = measurement(download: 5, upload: 20, latency: 20, jitter: 5, packetLoss: 0)
        XCTAssertEqual(evaluator.evaluate(atBoundary).verdict(for: .streamingHD)?.level, .adequate)

        let justBelow = measurement(download: 4.99, upload: 20, latency: 20, jitter: 5, packetLoss: 0)
        XCTAssertEqual(evaluator.evaluate(justBelow).verdict(for: .streamingHD)?.level, .limited)
    }

    func testStreaming4KThresholdIsExclusiveAtTheBoundary() {
        // A nota de produto pede "> 25", diferente do "≥" usado nos demais
        // limiares — exatamente 25 Mbps não é suficiente para 4K.
        let atBoundary = measurement(download: 25, upload: 20, latency: 20, jitter: 5, packetLoss: 0)
        XCTAssertEqual(evaluator.evaluate(atBoundary).verdict(for: .streaming4K)?.level, .limited)
        XCTAssertEqual(evaluator.evaluate(atBoundary).verdict(for: .streaming4K)?.limitingMetric, .downloadMbps)

        let justAbove = measurement(download: 25.01, upload: 20, latency: 20, jitter: 5, packetLoss: 0)
        XCTAssertEqual(evaluator.evaluate(justAbove).verdict(for: .streaming4K)?.level, .adequate)
    }

    func testOnlineGamingThresholdsAreInclusiveAtTheBoundary() {
        let atBoundary = measurement(download: 120, upload: 20, latency: 50, jitter: 30, packetLoss: 1, loadedLatency: 50)
        XCTAssertEqual(evaluator.evaluate(atBoundary).verdict(for: .onlineGaming)?.level, .adequate)

        let justAboveLatency = measurement(download: 120, upload: 20, latency: 50.01, jitter: 30, packetLoss: 1, loadedLatency: 50.01)
        XCTAssertEqual(evaluator.evaluate(justAboveLatency).verdict(for: .onlineGaming)?.level, .limited)

        let justAboveJitter = measurement(download: 120, upload: 20, latency: 50, jitter: 30.01, packetLoss: 1, loadedLatency: 50)
        XCTAssertEqual(evaluator.evaluate(justAboveJitter).verdict(for: .onlineGaming)?.level, .limited)

        let justAbovePacketLoss = measurement(download: 120, upload: 20, latency: 50, jitter: 30, packetLoss: 1.01, loadedLatency: 50)
        XCTAssertEqual(evaluator.evaluate(justAbovePacketLoss).verdict(for: .onlineGaming)?.level, .limited)
    }

    // MARK: - workUpload

    func testWorkUploadFlagsUploadWhenOnlyUploadFailsThreshold() {
        let measurement = measurement(download: 120, upload: 4, latency: 20, jitter: 5, packetLoss: 0)

        let verdict = evaluator.evaluate(measurement).verdict(for: .workUpload)

        XCTAssertEqual(verdict?.level, .limited)
        XCTAssertEqual(verdict?.limitingMetric, .uploadMbps)
    }

    func testWorkUploadFlagsJitterWhenOnlyJitterFailsThreshold() {
        let measurement = measurement(download: 120, upload: 20, latency: 20, jitter: 41, packetLoss: 0)

        let verdict = evaluator.evaluate(measurement).verdict(for: .workUpload)

        XCTAssertEqual(verdict?.level, .limited)
        XCTAssertEqual(verdict?.limitingMetric, .jitterMs)
    }

    func testWorkUploadFlagsLatencyWhenOnlyLatencyFailsThreshold() {
        let measurement = measurement(download: 120, upload: 20, latency: 201, jitter: 5, packetLoss: 0)

        let verdict = evaluator.evaluate(measurement).verdict(for: .workUpload)

        XCTAssertEqual(verdict?.level, .limited)
        XCTAssertEqual(verdict?.limitingMetric, .latencyMs)
    }

    func testWorkUploadFlagsPacketLossWhenOnlyPacketLossFailsThreshold() {
        let measurement = measurement(download: 120, upload: 20, latency: 20, jitter: 5, packetLoss: 3)

        let verdict = evaluator.evaluate(measurement).verdict(for: .workUpload)

        XCTAssertEqual(verdict?.level, .limited)
        XCTAssertEqual(verdict?.limitingMetric, .packetLossPercent)
    }

    func testWorkUploadIsNotAssessedWhenUploadIsMissing() {
        let measurement = measurement(download: 120, upload: nil, latency: 20, jitter: 5, packetLoss: 0)

        let verdict = evaluator.evaluate(measurement).verdict(for: .workUpload)

        XCTAssertEqual(verdict?.level, .notAssessed)
        XCTAssertEqual(verdict?.limitingMetric, .uploadMbps)
    }

    func testWorkUploadIsNotAssessedWhenJitterIsMissingEvenWithGoodUpload() {
        let measurement = measurement(download: 120, upload: 20, latency: 20, jitter: nil, packetLoss: 0)

        let verdict = evaluator.evaluate(measurement).verdict(for: .workUpload)

        XCTAssertEqual(verdict?.level, .notAssessed)
        XCTAssertEqual(verdict?.limitingMetric, .jitterMs)
    }

    func testWorkUploadThresholdsAreInclusiveAtTheBoundary() {
        let atBoundary = measurement(download: 120, upload: 5, latency: 200, jitter: 40, packetLoss: 2)
        XCTAssertEqual(evaluator.evaluate(atBoundary).verdict(for: .workUpload)?.level, .adequate)

        let justBelowUpload = measurement(download: 120, upload: 4.99, latency: 200, jitter: 40, packetLoss: 2)
        XCTAssertEqual(evaluator.evaluate(justBelowUpload).verdict(for: .workUpload)?.level, .limited)

        let justAboveJitter = measurement(download: 120, upload: 5, latency: 200, jitter: 40.01, packetLoss: 2)
        XCTAssertEqual(evaluator.evaluate(justAboveJitter).verdict(for: .workUpload)?.level, .limited)

        let justAboveLatency = measurement(download: 120, upload: 5, latency: 200.01, jitter: 40, packetLoss: 2)
        XCTAssertEqual(evaluator.evaluate(justAboveLatency).verdict(for: .workUpload)?.level, .limited)

        let justAbovePacketLoss = measurement(download: 120, upload: 5, latency: 200, jitter: 40, packetLoss: 2.01)
        XCTAssertEqual(evaluator.evaluate(justAbovePacketLoss).verdict(for: .workUpload)?.level, .limited)
    }

    // MARK: - Helper

    private func measurement(
        download: Double? = 100,
        upload: Double? = 50,
        latency: Double? = 20,
        jitter: Double? = 5,
        packetLoss: Double? = 0,
        loadedLatency: Double? = nil
    ) -> NetworkMeasurement {
        let formalLoadedLatency = loadedLatency ?? latency
        let probes = packetLoss.map { loss in
            PacketProbeEvidence(
                environmentIdentifier: "test",
                attemptCount: 10_000,
                successCount: 10_000 - Int((loss * 100).rounded()),
                failureCount: Int((loss * 100).rounded()),
                timeoutCount: 0,
                longestFailureStreak: 0,
                expandedAfterInitialWindow: false,
                completed: true
            )
        }
        let reference = RegionalGameReference(
            catalogVersion: "test",
            regionIdentifier: "test-region",
            p50LatencyMs: latency,
            jitterMs: jitter,
            attemptCount: 6,
            validResponseCount: 6,
            timeoutCount: 0,
            packetLossPercent: 0,
            status: .measured
        )
        return NetworkMeasurement(
            outcome: .complete,
            downloadMbps: download,
            uploadMbps: upload,
            latencyMs: latency,
            jitterMs: jitter,
            packetLossPercent: packetLoss,
            packetProbeEvidence: probes,
            regionalGameReference: reference,
            loadedLatencyMs: formalLoadedLatency,
            loadedLatencyUploadMs: formalLoadedLatency
        )
    }
}
