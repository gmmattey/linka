import XCTest
import NetworkCore
@testable import NetworkInsights

final class ConnectionPathTests: XCTestCase {
    private let evaluator = ConnectionPathEvaluator()

    // MARK: - Saudável

    func testAllStagesNormalWhenEverythingIsWellWithinThresholds() {
        let measurement = wifiMeasurement(
            download: 200, upload: 50, latency: 15, jitter: 5, packetLoss: 0,
            loadedLatency: 20, dnsResolutionMs: 20, rssi: -50
        )

        let report = evaluator.evaluate(measurement)

        for verdict in report.stages {
            XCTAssertEqual(verdict.status, .normal, "\(verdict.stage) deveria ser normal")
        }
        XCTAssertEqual(report.category, .healthy)
        XCTAssertNil(report.highlightedStage)
    }

    // MARK: - Device sempre normal

    func testDeviceIsAlwaysNormal() {
        let measurement = wifiMeasurement(download: 1, upload: 1, latency: 500, jitter: 500, packetLoss: 100, rssi: -90)
        let verdict = evaluator.evaluate(measurement).verdict(for: .device)
        XCTAssertEqual(verdict?.status, .normal)
    }

    // MARK: - Wi-Fi

    func testWiFiAndRouterAreAbsentWhenNotOnWiFi() {
        let measurement = NetworkMeasurement(outcome: .complete, downloadMbps: 100, uploadMbps: 20, latencyMs: 15, connectionKind: .cellular)
        let report = evaluator.evaluate(measurement)
        XCTAssertNil(report.verdict(for: .wifi))
        XCTAssertNil(report.verdict(for: .router))
    }

    func testWiFiIsUnavailableWithoutAdvancedDiagnostics() {
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: 5, packetLoss: 0, rssi: nil)
        XCTAssertEqual(evaluator.evaluate(measurement).verdict(for: .wifi)?.status, .unavailable)
    }

    func testWiFiFlagsLikelyProblemOnWeakSignal() {
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: 5, packetLoss: 0, rssi: -85)
        let verdict = evaluator.evaluate(measurement).verdict(for: .wifi)
        XCTAssertEqual(verdict?.status, .likelyProblem)
        XCTAssertEqual(verdict?.limitingFact, .wifiSignal)
    }

    func testWiFiFlagsAttentionOnBorderlineSignal() {
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: 5, packetLoss: 0, rssi: -72)
        XCTAssertEqual(evaluator.evaluate(measurement).verdict(for: .wifi)?.status, .attention)
    }

    // MARK: - Roteador

    func testRouterIsUnavailableWithoutJitterOrLoadedLatency() {
        let measurement = NetworkMeasurement(outcome: .complete, downloadMbps: 100, uploadMbps: 20, latencyMs: 15, connectionKind: .wifi)
        XCTAssertEqual(evaluator.evaluate(measurement).verdict(for: .router)?.status, .unavailable)
    }

    func testRouterFlagsLikelyProblemOnHighJitter() {
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: 70, packetLoss: 0, rssi: -50)
        let verdict = evaluator.evaluate(measurement).verdict(for: .router)
        XCTAssertEqual(verdict?.status, .likelyProblem)
        XCTAssertEqual(verdict?.limitingFact, .routerJitter)
    }

    func testRouterFlagsLikelyProblemOnLoadedLatencyDelta() {
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: 5, packetLoss: 0, loadedLatency: 200, rssi: -50)
        let verdict = evaluator.evaluate(measurement).verdict(for: .router)
        XCTAssertEqual(verdict?.status, .likelyProblem)
        XCTAssertEqual(verdict?.limitingFact, .routerLoadedLatency)
    }

    // MARK: - Operadora

    func testCarrierIsUnavailableWithoutLatency() {
        let measurement = NetworkMeasurement(outcome: .partial, downloadMbps: 100, connectionKind: .wifi)
        XCTAssertEqual(evaluator.evaluate(measurement).verdict(for: .carrier)?.status, .unavailable)
    }

    func testCarrierFlagsLikelyProblemOnHighLatency() {
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 200, jitter: 5, packetLoss: 0, rssi: -50)
        let verdict = evaluator.evaluate(measurement).verdict(for: .carrier)
        XCTAssertEqual(verdict?.status, .likelyProblem)
        XCTAssertEqual(verdict?.limitingFact, .carrierLatency)
    }

    func testCarrierFlagsLikelyProblemOnPacketLoss() {
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: 5, packetLoss: 8, rssi: -50)
        let verdict = evaluator.evaluate(measurement).verdict(for: .carrier)
        XCTAssertEqual(verdict?.status, .likelyProblem)
        XCTAssertEqual(verdict?.limitingFact, .carrierPacketLoss)
    }

    // MARK: - Internet

    func testInternetIsUnavailableWithoutDownload() {
        let measurement = NetworkMeasurement(outcome: .partial, latencyMs: 15, connectionKind: .wifi)
        XCTAssertEqual(evaluator.evaluate(measurement).verdict(for: .internet)?.status, .unavailable)
    }

    func testInternetFlagsLikelyProblemOnLowDownload() {
        let measurement = wifiMeasurement(download: 1, upload: 20, latency: 15, jitter: 5, packetLoss: 0, rssi: -50)
        let verdict = evaluator.evaluate(measurement).verdict(for: .internet)
        XCTAssertEqual(verdict?.status, .likelyProblem)
        XCTAssertEqual(verdict?.limitingFact, .internetDownload)
    }

    func testInternetFlagsLikelyProblemOnSlowDNS() {
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: 5, packetLoss: 0, dnsResolutionMs: 500, rssi: -50)
        let verdict = evaluator.evaluate(measurement).verdict(for: .internet)
        XCTAssertEqual(verdict?.status, .likelyProblem)
        XCTAssertEqual(verdict?.limitingFact, .internetDns)
    }

    // MARK: - Categoria e destaque

    func testSingleProblemStageHighlightsItsOwnCategory() {
        // Só o Wi-Fi ruim, resto saudável — categoria wifi, destaque wifi.
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: 5, packetLoss: 0, loadedLatency: 20, dnsResolutionMs: 20, rssi: -85)
        let report = evaluator.evaluate(measurement)
        XCTAssertEqual(report.category, .wifi)
        XCTAssertEqual(report.highlightedStage, .wifi)
    }

    func testCarrierProblemHighlightsCarrierCategory() {
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 200, jitter: 5, packetLoss: 0, loadedLatency: 210, dnsResolutionMs: 20, rssi: -50)
        let report = evaluator.evaluate(measurement)
        XCTAssertEqual(report.category, .carrier)
        XCTAssertEqual(report.highlightedStage, .carrier)
    }

    func testTiedProblemsAcrossDifferentCategoriesAreInconclusive() {
        // Wi-Fi ruim (likelyProblem) E download muito baixo (likelyProblem)
        // — mesma severidade, categorias diferentes (wifi vs external).
        let measurement = wifiMeasurement(download: 1, upload: 20, latency: 15, jitter: 5, packetLoss: 0, rssi: -85)
        let report = evaluator.evaluate(measurement)
        XCTAssertEqual(report.category, .inconclusive)
        XCTAssertNil(report.highlightedStage)
    }

    func testWiFiAndRouterBothAttentionStayInWiFiCategoryHighlightingWiFi() {
        // Wi-Fi e roteador no mesmo balde de categoria (.wifi) — destaca a
        // etapa mais a montante (Wi-Fi antes de roteador).
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: 40, packetLoss: 0, rssi: -72)
        let report = evaluator.evaluate(measurement)
        XCTAssertEqual(report.category, .wifi)
        XCTAssertEqual(report.highlightedStage, .wifi)
    }

    func testUnavailableStagesNeverCountAsProblemsForCategory() {
        // Sem diagnóstico Wi-Fi avançado (wifi/router unavailable), resto
        // saudável — continua healthy, não inconclusive nem problemático.
        let measurement = wifiMeasurement(download: 100, upload: 20, latency: 15, jitter: nil, packetLoss: 0, dnsResolutionMs: 20, rssi: nil)
        let report = evaluator.evaluate(measurement)
        XCTAssertEqual(report.category, .healthy)
        XCTAssertNil(report.highlightedStage)
    }

    // MARK: - Helper

    private func wifiMeasurement(
        download: Double? = 100,
        upload: Double? = 20,
        latency: Double? = 15,
        jitter: Double? = 5,
        packetLoss: Double? = 0,
        loadedLatency: Double? = nil,
        dnsResolutionMs: Double? = nil,
        rssi: Double?
    ) -> NetworkMeasurement {
        let diagnostics: AdvancedWiFiDiagnostics? = rssi.map {
            AdvancedWiFiDiagnostics(capturedAt: Date(), rssiDbm: $0)
        }
        return NetworkMeasurement(
            outcome: .complete,
            downloadMbps: download,
            uploadMbps: upload,
            latencyMs: latency,
            jitterMs: jitter,
            packetLossPercent: packetLoss,
            loadedLatencyMs: loadedLatency,
            dnsResolutionMs: dnsResolutionMs,
            connectionKind: .wifi,
            advancedWiFiDiagnostics: diagnostics
        )
    }
}
