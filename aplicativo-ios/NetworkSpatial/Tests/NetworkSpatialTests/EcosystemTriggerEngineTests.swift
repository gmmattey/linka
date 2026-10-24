import XCTest
@testable import NetworkSpatial

final class EcosystemTriggerEngineTests: XCTestCase {

    func testISPDegradedTriggersLinka() {
        let roomId = UUID()
        let room = Room(id: roomId, name: "Sala", icon: "sofa")
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.15.1",
            gatewayLatencyMs: 8.0,
            gatewayJitterMs: 1.2,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 160.0,
            wanPacketLossPercent: 4.5
        )
        let measurement = MeasurementResult(
            roomId: roomId,
            rating: .good,
            score: 82,
            cause: .ispDegraded,
            metrics: metrics,
            explanation: "Wi-Fi local excelente, lentidão na operadora.",
            actionableRecommendation: "Contate a operadora."
        )

        let target = EcosystemTriggerEngine.evaluateTrigger(for: measurement, room: room)

        XCTAssertEqual(target, .linka(gatewayIP: "192.168.15.1"))
        guard case .linka(let ip) = target else {
            XCTFail("Expected .linka")
            return
        }
        XCTAssertEqual(ip, "192.168.15.1")
        XCTAssertEqual(target?.appTitle, "Linka")
        XCTAssertEqual(target?.deepLinkURL.scheme, "linka")
        XCTAssertTrue(target?.deepLinkURL.absoluteString.contains("ip=192.168.15.1") == true)
        XCTAssertTrue(target?.appStoreURL.absoluteString.contains("linka") == true)
    }

    func testCriticalJitterTriggersLagCheckEvenInNonGamingRoom() {
        let roomId = UUID()
        let room = Room(id: roomId, name: "Cozinha", icon: "fork.knife")
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 18.0,
            gatewayJitterMs: 19.5, // > 15.0ms
            gatewayPacketLossPercent: 0.0
        )
        let measurement = MeasurementResult(
            roomId: roomId,
            rating: .fair,
            score: 65,
            cause: .allGood,
            metrics: metrics,
            explanation: "Jitter elevado.",
            actionableRecommendation: "Verifique tráfego."
        )

        let target = EcosystemTriggerEngine.evaluateTrigger(for: measurement, room: room)

        XCTAssertEqual(target, .lagcheck(isGamingRoom: false))
        XCTAssertEqual(target?.appTitle, "Lagcheck")
        XCTAssertEqual(target?.deepLinkURL.scheme, "lagcheck")
        XCTAssertTrue(target?.deepLinkURL.absoluteString.contains("quicktest") == true)
    }

    func testGamingRoomTriggersLagCheck() {
        let roomId = UUID()
        let room = Room(id: roomId, name: "Quarto Gamer", icon: "gamecontroller.fill")
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 6.0,
            gatewayJitterMs: 2.0,
            gatewayPacketLossPercent: 0.0
        )
        let measurement = MeasurementResult(
            roomId: roomId,
            rating: .excellent,
            score: 98,
            cause: .allGood,
            metrics: metrics,
            explanation: "Conexão perfeita.",
            actionableRecommendation: "Excelente."
        )

        let target = EcosystemTriggerEngine.evaluateTrigger(for: measurement, room: room)

        XCTAssertEqual(target, .lagcheck(isGamingRoom: true))
        XCTAssertEqual(target?.appTitle, "Lagcheck")
    }

    func testOfficeRoomByNameTriggersLagCheck() {
        let roomId = UUID()
        let room = Room(id: roomId, name: "Escritório Home Office", icon: "briefcase")
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 9.0,
            gatewayJitterMs: 2.5,
            gatewayPacketLossPercent: 0.0
        )
        let measurement = MeasurementResult(
            roomId: roomId,
            rating: .good,
            score: 85,
            cause: .allGood,
            metrics: metrics,
            explanation: "Bom.",
            actionableRecommendation: "Manter."
        )

        let target = EcosystemTriggerEngine.evaluateTrigger(for: measurement, room: room)

        XCTAssertEqual(target, .lagcheck(isGamingRoom: true))
    }

    func testLocalWiFiDegradedSuppressesEcosystemTriggers() {
        let roomId = UUID()
        let room = Room(id: roomId, name: "Quarto Gamer", icon: "gamecontroller.fill")
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 95.0,
            gatewayJitterMs: 28.0,
            gatewayPacketLossPercent: 8.0
        )
        let measurement = MeasurementResult(
            roomId: roomId,
            rating: .poor,
            score: 22,
            cause: .localWiFiDegraded,
            metrics: metrics,
            explanation: "Sinal Wi-Fi fraco.",
            actionableRecommendation: "Aproxime o roteador."
        )

        let target = EcosystemTriggerEngine.evaluateTrigger(for: measurement, room: room)

        XCTAssertNil(target, "Quando o Wi-Fi local está degradado, o app não deve sugerir outros apps")
    }

    func testOfflineNetworkSuppressesEcosystemTriggers() {
        let roomId = UUID()
        let room = Room(id: roomId, name: "Sala", icon: "sofa")
        let measurement = MeasurementResult(
            roomId: roomId,
            rating: .unmeasured,
            score: 0,
            cause: .offline,
            metrics: NetworkMetrics(),
            explanation: "Offline.",
            actionableRecommendation: "Conecte-se."
        )

        let target = EcosystemTriggerEngine.evaluateTrigger(for: measurement, room: room)

        XCTAssertNil(target)
    }
}
