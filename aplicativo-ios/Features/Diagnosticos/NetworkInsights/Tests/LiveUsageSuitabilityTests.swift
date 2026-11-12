import XCTest
import NetworkCore
@testable import NetworkInsights

final class LiveUsageSuitabilityTests: XCTestCase {
    private let evaluator = LiveUsageSuitabilityEvaluator()

    func testGamingIsAdequateWithLowLatencyAndLowJitter() {
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: 18,
            jitterMs: 4,
            packetLossPercent: 0,
            sampleCount: 5
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: nil)
        let gaming = report.verdict(for: .onlineGaming)

        XCTAssertEqual(gaming?.level, .adequate)
        XCTAssertEqual(gaming?.confidence, .liveTelemetry)
        XCTAssertNil(gaming?.limitingMetric)
        XCTAssertNil(gaming?.reason)
    }

    func testGamingIsLimitedWhenLatencyExceedsThreshold() {
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: 120, // > 50ms
            jitterMs: 5,
            packetLossPercent: 0,
            sampleCount: 5
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: nil)
        let gaming = report.verdict(for: .onlineGaming)

        XCTAssertEqual(gaming?.level, .limited)
        XCTAssertEqual(gaming?.confidence, .liveTelemetry)
        XCTAssertEqual(gaming?.limitingMetric, .latencyMs)
        XCTAssertEqual(gaming?.reason, .latencyTooHigh)
    }

    func testGamingIsLimitedWhenJitterExceedsThreshold() {
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: 30,
            jitterMs: 45, // > 30ms
            packetLossPercent: 0,
            sampleCount: 5
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: nil)
        let gaming = report.verdict(for: .onlineGaming)

        XCTAssertEqual(gaming?.level, .limited)
        XCTAssertEqual(gaming?.confidence, .liveTelemetry)
        XCTAssertEqual(gaming?.limitingMetric, .jitterMs)
        XCTAssertEqual(gaming?.reason, .jitterTooHigh)
    }

    func testVideoCallIsLimitedWhenConstrainedModeActive() {
        let telemetry = LiveNetworkTelemetrySnapshot(
            isConstrained: true,
            latencyMs: 20,
            jitterMs: 2,
            packetLossPercent: 0,
            sampleCount: 5
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: nil)
        let video = report.verdict(for: .videoCall)

        XCTAssertEqual(video?.level, .limited)
        XCTAssertEqual(video?.reason, .constrainedModeActive)
    }

    func testVideoCallIsNotAssessedWhenUploadBaselineIsMissing() {
        // AGENTS.md §6/§8: Não atestar aptidão de vídeo sem saber a capacidade de upload
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: 25,
            jitterMs: 5,
            packetLossPercent: 0,
            sampleCount: 5
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: nil)
        let video = report.verdict(for: .videoCall)

        XCTAssertEqual(video?.level, .notAssessed)
        XCTAssertEqual(video?.confidence, .insufficientData)
        XCTAssertEqual(video?.limitingMetric, .uploadMbps)
        XCTAssertEqual(video?.reason, .missingThroughputMeasurement)
    }

    func testVideoCallIsAdequateWhenUploadBaselineIsPresent() {
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: 25,
            jitterMs: 5,
            packetLossPercent: 0,
            sampleCount: 5
        )
        let baseline = ThroughputBaseline(uploadMbps: 10, sampleCount: 1)

        let report = evaluator.evaluate(telemetry: telemetry, baseline: baseline)
        let video = report.verdict(for: .videoCall)

        XCTAssertEqual(video?.level, .adequate)
        XCTAssertEqual(video?.confidence, .historicalBaselineInferred)
    }

    func testGamingIsNotAssessedWhenSamplesAreFewerThanThree() {
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: 20,
            jitterMs: nil, // RFC 3550 requer >= 3 amostras
            packetLossPercent: 0,
            sampleCount: 2
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: nil)
        let gaming = report.verdict(for: .onlineGaming)

        XCTAssertEqual(gaming?.level, .notAssessed)
        XCTAssertEqual(gaming?.confidence, .insufficientData)
        XCTAssertEqual(gaming?.limitingMetric, .jitterMs)
    }

    func testStreaming4KIsNotAssessedWhenNoThroughputBaselineExists() {
        // AGENTS.md §6/§8/§9: Nunca inventar velocidade em produção!
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: 15,
            jitterMs: 2,
            packetLossPercent: 0,
            sampleCount: 5
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: nil)
        let streaming4K = report.verdict(for: .streaming4K)

        XCTAssertEqual(streaming4K?.level, .notAssessed)
        XCTAssertEqual(streaming4K?.confidence, .insufficientData)
        XCTAssertEqual(streaming4K?.limitingMetric, .downloadMbps)
        XCTAssertEqual(streaming4K?.reason, .missingThroughputMeasurement)
    }

    func testStreaming4KIsAdequateWhenRecentBaselineIsSufficient() {
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: 20,
            jitterMs: 3,
            packetLossPercent: 0,
            sampleCount: 5
        )
        let baseline = ThroughputBaseline(
            downloadMbps: 150,
            uploadMbps: 50,
            lastMeasuredAt: Date().addingTimeInterval(-3600),
            sampleCount: 3
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: baseline)
        let streaming4K = report.verdict(for: .streaming4K)

        XCTAssertEqual(streaming4K?.level, .adequate)
        XCTAssertEqual(streaming4K?.confidence, .historicalBaselineInferred)
        XCTAssertNil(streaming4K?.limitingMetric)
    }

    func testStreaming4KIsLimitedWhenRecentBaselineIsBelowThreshold() {
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: 20,
            jitterMs: 3,
            packetLossPercent: 0,
            sampleCount: 5
        )
        let baseline = ThroughputBaseline(
            downloadMbps: 12, // < 25 Mbps
            uploadMbps: 5,
            sampleCount: 1
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: baseline)
        let streaming4K = report.verdict(for: .streaming4K)

        XCTAssertEqual(streaming4K?.level, .limited)
        XCTAssertEqual(streaming4K?.confidence, .historicalBaselineInferred)
        XCTAssertEqual(streaming4K?.limitingMetric, .downloadMbps)
        XCTAssertEqual(streaming4K?.reason, .throughputBelowMinimum)
    }

    func testMissingLatencyYieldsNotAssessedWithInsufficientData() {
        let telemetry = LiveNetworkTelemetrySnapshot(
            latencyMs: nil,
            sampleCount: 0
        )

        let report = evaluator.evaluate(telemetry: telemetry, baseline: nil)
        let gaming = report.verdict(for: .onlineGaming)
        let video = report.verdict(for: .videoCall)

        XCTAssertEqual(gaming?.level, .notAssessed)
        XCTAssertEqual(gaming?.confidence, .insufficientData)
        XCTAssertEqual(video?.level, .notAssessed)
        XCTAssertEqual(video?.confidence, .insufficientData)
    }
}
