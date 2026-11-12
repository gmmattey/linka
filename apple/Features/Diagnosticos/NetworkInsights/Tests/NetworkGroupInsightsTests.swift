import XCTest
import NetworkCore
@testable import NetworkInsights

final class NetworkGroupInsightsTests: XCTestCase {
    func testWiFiGroupsUseSSIDInsteadOfProviderIdentifierWhenAvailable() {
        let measurements = [
            measurement(connectionKind: .wifi, networkIdentifier: "ISP A", wifiSSID: "Casa"),
            measurement(connectionKind: .wifi, networkIdentifier: "ISP B", wifiSSID: "Casa")
        ]

        let groups = NetworkGroupInsightsAnalyzer.group(measurements)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[NetworkGroupIdentity(connectionKind: .wifi, networkIdentifier: "Casa")]?.count, 2)
    }
    private let day = 86_400.0

    // MARK: - Agrupamento (issue #125, item 1)

    func testGroupsBySameConnectionKindAndNetworkIdentifier() {
        let measurements = [
            measurement(connectionKind: .wifi, networkIdentifier: "Casa"),
            measurement(connectionKind: .wifi, networkIdentifier: "Casa"),
            measurement(connectionKind: .wifi, networkIdentifier: "Trabalho")
        ]

        let groups = NetworkGroupInsightsAnalyzer.group(measurements)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[NetworkGroupIdentity(connectionKind: .wifi, networkIdentifier: "Casa")]?.count, 2)
        XCTAssertEqual(groups[NetworkGroupIdentity(connectionKind: .wifi, networkIdentifier: "Trabalho")]?.count, 1)
    }

    func testTreatsWifiAndCellularAsDistinctIdentitiesEvenWithSameIdentifier() {
        // Coincidência de nome entre SSID e operadora não deve virar o
        // mesmo grupo — são fisicamente redes diferentes.
        let measurements = [
            measurement(connectionKind: .wifi, networkIdentifier: "Vivo"),
            measurement(connectionKind: .cellular, networkIdentifier: "Vivo")
        ]

        let groups = NetworkGroupInsightsAnalyzer.group(measurements)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[NetworkGroupIdentity(connectionKind: .wifi, networkIdentifier: "Vivo")]?.count, 1)
        XCTAssertEqual(groups[NetworkGroupIdentity(connectionKind: .cellular, networkIdentifier: "Vivo")]?.count, 1)
    }

    func testExcludesMeasurementsMissingConnectionKindOrNetworkIdentifier() {
        let measurements = [
            measurement(connectionKind: nil, networkIdentifier: "Casa"),
            measurement(connectionKind: .wifi, networkIdentifier: nil),
            measurement(connectionKind: .wifi, networkIdentifier: "  "),
            measurement(connectionKind: .wifi, networkIdentifier: "Casa")
        ]

        let groups = NetworkGroupInsightsAnalyzer.group(measurements)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[NetworkGroupIdentity(connectionKind: .wifi, networkIdentifier: "Casa")]?.count, 1)
    }

    // MARK: - Elegibilidade por amostra mínima

    func testEligibleGroupsFiltersByMinimumSampleCount() {
        let measurements =
            (0..<2).map { _ in measurement(connectionKind: .wifi, networkIdentifier: "Pouco") } +
            (0..<5).map { _ in measurement(connectionKind: .wifi, networkIdentifier: "Bastante") }

        let eligible = NetworkGroupInsightsAnalyzer.eligibleGroups(measurements, minimumSampleCount: 5)

        XCTAssertEqual(eligible.count, 1)
        XCTAssertEqual(eligible.first?.identity.networkIdentifier, "Bastante")
    }

    func testEligibleGroupsIsSortedDeterministically() {
        let measurements =
            (0..<5).map { _ in measurement(connectionKind: .wifi, networkIdentifier: "Trabalho") } +
            (0..<5).map { _ in measurement(connectionKind: .wifi, networkIdentifier: "Casa") } +
            (0..<5).map { _ in measurement(connectionKind: .cellular, networkIdentifier: "Vivo") }

        let eligible = NetworkGroupInsightsAnalyzer.eligibleGroups(measurements, minimumSampleCount: 1)

        XCTAssertEqual(
            eligible.map { "\($0.identity.connectionKind.rawValue):\($0.identity.networkIdentifier)" },
            ["cellular:Vivo", "wifi:Casa", "wifi:Trabalho"]
        )
    }

    // MARK: - Reuso de BasicNetworkInsightsAnalyzer (issue #125, item 1)

    func testSummarizeByNetworkReusesBasicAnalyzerStatistics() throws {
        let measurements = [
            measurement(connectionKind: .wifi, networkIdentifier: "Casa", download: 100),
            measurement(connectionKind: .wifi, networkIdentifier: "Casa", download: 200),
            measurement(connectionKind: .wifi, networkIdentifier: "Casa", download: 300),
            measurement(connectionKind: .cellular, networkIdentifier: "Vivo", download: 10)
        ]

        let analyzer = NetworkGroupInsightsAnalyzer(configuration: .init(minimumSampleCount: 3))
        let summaries = try analyzer.summarizeByNetwork(measurements)

        XCTAssertEqual(summaries.count, 1)
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.identity, NetworkGroupIdentity(connectionKind: .wifi, networkIdentifier: "Casa"))
        XCTAssertEqual(summary.summary.statistics(for: .downloadMbps)?.average ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(summary.summary.measurementCount, 3)
    }

    func testSummarizeByNetworkOmitsGroupsBelowMinimumSampleCount() throws {
        let measurements = [
            measurement(connectionKind: .wifi, networkIdentifier: "Casa")
        ]

        let analyzer = NetworkGroupInsightsAnalyzer(configuration: .init(minimumSampleCount: 5))
        let summaries = try analyzer.summarizeByNetwork(measurements)

        XCTAssertTrue(summaries.isEmpty)
    }

    // MARK: - Auxiliar

    private func measurement(
        connectionKind: NetworkConnectionKind?,
        networkIdentifier: String?,
        wifiSSID: String? = nil,
        download: Double = 100,
        measuredAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            measuredAt: measuredAt,
            outcome: .complete,
            downloadMbps: download,
            uploadMbps: 50,
            latencyMs: 20,
            connectionKind: connectionKind,
            wifiContext: wifiSSID.map { WiFiNetworkContext(ssid: $0) },
            networkIdentifier: networkIdentifier
        )
    }
}
