import XCTest
import NetworkCore
import MeasurementHistory
@testable import LinkaModules

final class LiveTelemetryCollectorTests: XCTestCase {
    func testSlidingWindowMedianCalculation() {
        var buffer = SlidingWindowTelemetryBuffer(maxCapacity: 5)
        buffer.append(sample: LiveProbeSample(rttMs: 20))
        buffer.append(sample: LiveProbeSample(rttMs: 10))
        buffer.append(sample: LiveProbeSample(rttMs: 30))

        // Sorted: 10, 20, 30 -> Median = 20
        XCTAssertEqual(buffer.medianLatencyMs, 20)

        buffer.append(sample: LiveProbeSample(rttMs: 40))
        // Sorted: 10, 20, 30, 40 -> Median = (20 + 30) / 2 = 25
        XCTAssertEqual(buffer.medianLatencyMs, 25)
    }

    func testSlidingWindowJitterRFC3550() {
        var buffer = SlidingWindowTelemetryBuffer(maxCapacity: 5)
        buffer.append(sample: LiveProbeSample(rttMs: 20))
        buffer.append(sample: LiveProbeSample(rttMs: 30))

        // Less than 3 samples: RFC 3550 requires at least 3 samples to calculate inter-packet jitter
        XCTAssertNil(buffer.jitterMs, "Ausência de amostras suficientes não deve virar zero")

        buffer.append(sample: LiveProbeSample(rttMs: 24))
        // Diffs: |30 - 20| = 10, |24 - 30| = 6. Jitter = (10 + 6) / 2 = 8.0
        XCTAssertEqual(buffer.jitterMs, 8.0)
    }

    func testSlidingWindowPacketLossPercentage() {
        var buffer = SlidingWindowTelemetryBuffer(maxCapacity: 5)
        buffer.append(sample: LiveProbeSample(rttMs: 20))
        buffer.append(sample: LiveProbeSample(rttMs: nil)) // Lost
        buffer.append(sample: LiveProbeSample(rttMs: 22))
        buffer.append(sample: LiveProbeSample(rttMs: nil)) // Lost

        // 2 lost out of 4 = 50%
        XCTAssertEqual(buffer.packetLossPercent, 50.0)
    }

    func testSlidingWindowCapacityLimit() {
        var buffer = SlidingWindowTelemetryBuffer(maxCapacity: 3)
        buffer.append(sample: LiveProbeSample(rttMs: 10))
        buffer.append(sample: LiveProbeSample(rttMs: 20))
        buffer.append(sample: LiveProbeSample(rttMs: 30))
        buffer.append(sample: LiveProbeSample(rttMs: 40))

        XCTAssertEqual(buffer.sampleCount, 3)
        // 10 should have been dropped: remaining 20, 30, 40
        XCTAssertEqual(buffer.medianLatencyMs, 30)
    }

    func testCollectorSnapshotGeneration() {
        let collector = LiveTelemetryCollector()
        collector.recordProbe(rttMs: 15)
        collector.recordProbe(rttMs: 20)
        collector.recordProbe(rttMs: 25)

        let snapshot = collector.snapshot(
            connectionKind: .wifi,
            interfaceLabel: "Home Wi-Fi",
            isExpensive: false,
            isConstrained: false,
            wifiLinkSpeedMbps: 866,
            wifiRssiDbm: -55
        )

        XCTAssertEqual(snapshot.connectionKind, .wifi)
        XCTAssertEqual(snapshot.interfaceLabel, "Home Wi-Fi")
        XCTAssertEqual(snapshot.latencyMs, 20)
        XCTAssertNotNil(snapshot.jitterMs)
        XCTAssertEqual(snapshot.packetLossPercent, 0)
        XCTAssertEqual(snapshot.wifiLinkSpeedMbps, 866)
        XCTAssertEqual(snapshot.wifiRssiDbm, -55)
    }

    func testThroughputBaselineOnlyUsesCompleteRecentMeasurementOnSameSSID() async throws {
        let repository = InMemoryMeasurementHistoryRepository()
        let matching = NetworkMeasurement(
            measuredAt: Date().addingTimeInterval(-60),
            outcome: .complete,
            downloadMbps: 320,
            uploadMbps: 45,
            latencyMs: 12,
            connectionKind: .wifi,
            wifiContext: WiFiNetworkContext(ssid: "Casa"),
            networkIdentifier: "Provider A"
        )
        let sameProviderDifferentSSID = NetworkMeasurement(
            measuredAt: Date().addingTimeInterval(-30),
            outcome: .complete,
            downloadMbps: 999,
            uploadMbps: 999,
            latencyMs: 12,
            connectionKind: .wifi,
            wifiContext: WiFiNetworkContext(ssid: "Vizinho"),
            networkIdentifier: "Provider A"
        )
        try await repository.save(matching)
        try await repository.save(sameProviderDifferentSSID)

        let baseline = await LiveTelemetryCollector.fetchThroughputBaseline(
            forWiFiSSID: "Casa",
            repository: repository
        )

        XCTAssertEqual(baseline?.downloadMbps, 320)
        XCTAssertEqual(baseline?.uploadMbps, 45)
        XCTAssertEqual(baseline?.networkIdentifier, "Casa")
    }

    func testThroughputBaselineRejectsExpiredAndPartialMeasurements() async throws {
        let repository = InMemoryMeasurementHistoryRepository()
        try await repository.save(NetworkMeasurement(
            measuredAt: Date().addingTimeInterval(-14_401),
            outcome: .complete,
            downloadMbps: 80,
            uploadMbps: 20,
            latencyMs: 12,
            connectionKind: .wifi,
            wifiContext: WiFiNetworkContext(ssid: "Casa")
        ))
        try await repository.save(NetworkMeasurement(
            measuredAt: Date().addingTimeInterval(-10),
            outcome: .partial,
            downloadMbps: 80,
            uploadMbps: 20,
            connectionKind: .wifi,
            wifiContext: WiFiNetworkContext(ssid: "Casa")
        ))
        let baseline = await LiveTelemetryCollector.fetchThroughputBaseline(
            forWiFiSSID: "Casa",
            repository: repository
        )

        XCTAssertNil(baseline)
    }
}
