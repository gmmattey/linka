import XCTest
import NetworkCore
@testable import NetworkInsights

final class NetworkInsightsTests: XCTestCase {
    private let day = 86_400.0

    func testComparisonRespectsMetricSemantics() throws {
        let baseline = complete(download: 100, upload: 50, latency: 20)
        let current = complete(download: 120, upload: 40, latency: 30)
        let comparison = try BasicNetworkInsightsAnalyzer().compare(
            current: current,
            against: baseline
        )

        XCTAssertEqual(comparison.comparison(for: .downloadMbps)?.direction, .improved)
        XCTAssertEqual(comparison.comparison(for: .uploadMbps)?.direction, .worsened)
        XCTAssertEqual(comparison.comparison(for: .latencyMs)?.direction, .worsened)
        XCTAssertEqual(
            comparison.comparison(for: .downloadMbps)?.percentDelta ?? 0,
            20,
            accuracy: 0.001
        )
    }

    func testSmallChangeIsStableWithinConfiguredThreshold() throws {
        let analyzer = BasicNetworkInsightsAnalyzer(
            configuration: .init(stableChangeThresholdPercent: 5)
        )
        let baseline = complete(download: 100, upload: 50, latency: 20)
        let current = complete(download: 103, upload: 50, latency: 20)

        let comparison = try analyzer.compare(current: current, against: baseline)
        XCTAssertEqual(comparison.comparison(for: .downloadMbps)?.direction, .stable)
    }

    func testMissingMetricIsUnavailableInsteadOfZero() throws {
        let baseline = NetworkMeasurement(outcome: .partial, latencyMs: 20)
        let current = NetworkMeasurement(outcome: .partial, latencyMs: 18)
        let comparison = try BasicNetworkInsightsAnalyzer().compare(
            current: current,
            against: baseline
        )

        XCTAssertEqual(comparison.comparison(for: .downloadMbps)?.direction, .unavailable)
        XCTAssertNil(comparison.comparison(for: .downloadMbps)?.currentValue)
        XCTAssertEqual(comparison.comparison(for: .latencyMs)?.direction, .improved)
    }

    func testSummaryCalculatesDescriptiveStatistics() throws {
        let measurements = [
            complete(download: 100, measuredAt: Date(timeIntervalSince1970: 0)),
            complete(download: 200, measuredAt: Date(timeIntervalSince1970: day)),
            complete(download: 300, measuredAt: Date(timeIntervalSince1970: day * 2))
        ]

        let summary = try BasicNetworkInsightsAnalyzer().summarize(measurements)
        let stats = try XCTUnwrap(summary.statistics(for: .downloadMbps))

        XCTAssertEqual(stats.sampleCount, 3)
        XCTAssertEqual(stats.minimum, 100)
        XCTAssertEqual(stats.maximum, 300)
        XCTAssertEqual(stats.average ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(stats.median, 200)
        XCTAssertEqual(stats.standardDeviation ?? 0, 81.649658, accuracy: 0.001)
        XCTAssertEqual(stats.relativeVariationPercent ?? 0, 40.824829, accuracy: 0.001)
    }

    func testTrendUsesTimeSeriesInsteadOfArrayOrder() throws {
        let measurements = [
            complete(download: 120, measuredAt: Date(timeIntervalSince1970: day * 2)),
            complete(download: 100, measuredAt: Date(timeIntervalSince1970: 0)),
            complete(download: 110, measuredAt: Date(timeIntervalSince1970: day))
        ]

        let summary = try BasicNetworkInsightsAnalyzer().summarize(measurements)
        let trend = try XCTUnwrap(summary.trend(for: .downloadMbps))

        XCTAssertEqual(trend.direction, .rising)
        XCTAssertEqual(trend.slopePerDay ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(trend.fittedChangePercent ?? 0, 20, accuracy: 0.001)
    }

    func testTrendRequiresMinimumSamples() throws {
        let measurements = [
            complete(download: 100, measuredAt: Date(timeIntervalSince1970: 0)),
            complete(download: 120, measuredAt: Date(timeIntervalSince1970: day))
        ]

        let summary = try BasicNetworkInsightsAnalyzer().summarize(measurements)
        XCTAssertEqual(summary.trend(for: .downloadMbps)?.direction, .insufficientData)
    }

    func testPeriodComparisonUsesMetricAverages() throws {
        let baseline = [
            complete(download: 100, latency: 20),
            complete(download: 100, latency: 20)
        ]
        let current = [
            complete(download: 120, latency: 15),
            complete(download: 120, latency: 15)
        ]

        let comparison = try BasicNetworkInsightsAnalyzer().comparePeriods(
            current: current,
            baseline: baseline
        )

        XCTAssertEqual(comparison.comparison(for: .downloadMbps)?.direction, .improved)
        XCTAssertEqual(comparison.comparison(for: .latencyMs)?.direction, .improved)
        XCTAssertEqual(
            comparison.comparison(for: .downloadMbps)?.percentDelta ?? 0,
            20,
            accuracy: 0.001
        )
    }

    /// Issue #128: `loadedLatencyUploadMs` vira `NetworkMetric` de primeira
    /// classe, então precisa se comportar como qualquer outra métrica já
    /// coberta por `testComparisonRespectsMetricSemantics` — mesma
    /// semântica `lowerIsBetter`, mesmo cálculo de `percentDelta` via
    /// `MetricComparator`.
    func testLoadedLatencyUploadComparisonRespectsMetricSemantics() throws {
        let baseline = NetworkMeasurement(outcome: .partial, loadedLatencyUploadMs: 20)
        let current = NetworkMeasurement(outcome: .partial, loadedLatencyUploadMs: 30)

        let comparison = try BasicNetworkInsightsAnalyzer().compare(
            current: current,
            against: baseline
        )

        let metricComparison = try XCTUnwrap(comparison.comparison(for: .loadedLatencyUploadMs))
        XCTAssertEqual(metricComparison.direction, .worsened)
        XCTAssertEqual(metricComparison.percentDelta ?? 0, 50, accuracy: 0.001)
    }

    func testInvalidMeasurementFailsExplicitly() {
        let invalid = NetworkMeasurement(outcome: .complete, downloadMbps: 100)

        XCTAssertThrowsError(try BasicNetworkInsightsAnalyzer().summarize([invalid])) { error in
            XCTAssertEqual(error as? NetworkInsightsError, .invalidMeasurement(invalid.id))
        }
    }

    private func complete(
        download: Double = 100,
        upload: Double = 50,
        latency: Double = 20,
        measuredAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            measuredAt: measuredAt,
            outcome: .complete,
            downloadMbps: download,
            uploadMbps: upload,
            latencyMs: latency
        )
    }
}
