import XCTest
@testable import NetworkSpatial

final class MeshTopologyProberTests: XCTestCase {

    func testEthernetBackhaulReturnsDeterministicExcellentQuality() async {
        let prober = MeshTopologyProber(customProbeHandler: { _ in
            LatencyProbeResult(
                meanLatencyMs: 1.5,
                jitterMs: 0.2,
                packetLossPercent: 0.0,
                samples: [1.5]
            )
        })
        let ap = AccessPointNode(
            name: "Satélite Escritório",
            type: .meshSatellite,
            backhaulType: .ethernet,
            roomId: UUID()
        )

        let diagnostic = await prober.probeBackhaulQuality(node: ap, gatewayIP: "192.168.1.1")

        XCTAssertEqual(diagnostic.nodeName, "Satélite Escritório")
        XCTAssertEqual(diagnostic.backhaulType, .ethernet)
        XCTAssertEqual(diagnostic.linkQuality, .excellent)
        XCTAssertNil(diagnostic.nodeLatencyMs, "Salto interno deve ser nil pois não é mensurável pelo iOS")
        XCTAssertLessThanOrEqual(diagnostic.gatewayLatencyMs, 3.0)
        XCTAssertNil(diagnostic.recommendation)
    }

    func testWiFiBackhaulWithOptimalLatencyReturnsExcellent() async {
        let simulatedProber = MeshTopologyProber(customProbeHandler: { _ in
            LatencyProbeResult(
                meanLatencyMs: 12.0,
                jitterMs: 1.5,
                packetLossPercent: 0.0,
                samples: [11.8, 12.2, 12.0]
            )
        })

        let ap = AccessPointNode(
            name: "Satélite Sala",
            type: .meshSatellite,
            backhaulType: .wifi,
            roomId: UUID()
        )

        let diagnostic = await simulatedProber.probeBackhaulQuality(node: ap, gatewayIP: "192.168.1.1")

        XCTAssertEqual(diagnostic.linkQuality, .excellent)
        XCTAssertEqual(diagnostic.gatewayLatencyMs, 12.0)
        XCTAssertNil(diagnostic.recommendation)
    }

    func testWiFiBackhaulWithHighLatencyTriggersFairAndRepositionRecommendation() async {
        let simulatedProber = MeshTopologyProber(customProbeHandler: { _ in
            LatencyProbeResult(
                meanLatencyMs: 42.0, // > 30ms
                jitterMs: 5.0,
                packetLossPercent: 0.0,
                samples: [40.0, 44.0]
            )
        })

        let ap = AccessPointNode(
            name: "Satélite Quarto",
            type: .meshSatellite,
            backhaulType: .wifi,
            roomId: UUID()
        )

        let diagnostic = await simulatedProber.probeBackhaulQuality(node: ap, gatewayIP: "192.168.1.1")

        XCTAssertEqual(diagnostic.linkQuality, .fair)
        XCTAssertNotNil(diagnostic.recommendation)
        XCTAssertTrue(diagnostic.recommendation?.contains("Aproxime o satélite mesh 1 cômodo") == true)
    }

    func testWiFiBackhaulWithCriticalLossTriggersPoorAndRepositionRecommendation() async {
        let simulatedProber = MeshTopologyProber(customProbeHandler: { _ in
            LatencyProbeResult(
                meanLatencyMs: 65.0, // > 60ms
                jitterMs: 12.0,
                packetLossPercent: 6.5, // > 5%
                samples: [60.0, 70.0]
            )
        })

        let ap = AccessPointNode(
            name: "Satélite Varanda",
            type: .meshSatellite,
            backhaulType: .wifi,
            roomId: UUID()
        )

        let diagnostic = await simulatedProber.probeBackhaulQuality(node: ap, gatewayIP: "192.168.1.1")

        XCTAssertEqual(diagnostic.linkQuality, .poor)
        XCTAssertNotNil(diagnostic.recommendation)
        XCTAssertTrue(diagnostic.recommendation?.contains("Aproxime o satélite mesh 1 cômodo") == true)
    }

    func testRepeaterWiFiBackhaulEmitsRepeaterSpecificRecommendation() async {
        let simulatedProber = MeshTopologyProber(customProbeHandler: { _ in
            LatencyProbeResult(
                meanLatencyMs: 38.0,
                jitterMs: 4.0,
                packetLossPercent: 2.5,
                samples: [38.0]
            )
        })

        let ap = AccessPointNode(
            name: "Repetidor Corredor",
            type: .repeater,
            backhaulType: .wifi,
            roomId: UUID()
        )

        let diagnostic = await simulatedProber.probeBackhaulQuality(node: ap, gatewayIP: "192.168.1.1")

        XCTAssertEqual(diagnostic.linkQuality, .fair)
        XCTAssertNotNil(diagnostic.recommendation)
        XCTAssertTrue(diagnostic.recommendation?.contains("repetidor") == true)
    }

    func testMainRouterProbeReturnsGatewayMetrics() async {
        let simulatedProber = MeshTopologyProber(customProbeHandler: { _ in
            LatencyProbeResult(
                meanLatencyMs: 4.5,
                jitterMs: 0.8,
                packetLossPercent: 0.0,
                samples: [4.5]
            )
        })

        let ap = AccessPointNode(
            name: "Roteador Principal",
            type: .mainRouter,
            backhaulType: .ethernet,
            roomId: UUID()
        )

        let diagnostic = await simulatedProber.probeBackhaulQuality(node: ap, gatewayIP: "192.168.1.1")

        XCTAssertEqual(diagnostic.linkQuality, .excellent)
        XCTAssertEqual(diagnostic.nodeType, .mainRouter)
    }
}
