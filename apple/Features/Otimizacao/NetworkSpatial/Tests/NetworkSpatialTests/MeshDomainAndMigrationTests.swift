import XCTest
@testable import NetworkSpatial

@MainActor
final class MeshDomainAndMigrationTests: XCTestCase {
    func testAccessPointTypeProperties() {
        XCTAssertFalse(AccessPointType.none.isAccessPoint)
        XCTAssertTrue(AccessPointType.mainRouter.isAccessPoint)
        XCTAssertTrue(AccessPointType.meshSatellite.isAccessPoint)
        XCTAssertTrue(AccessPointType.repeater.isAccessPoint)

        XCTAssertEqual(AccessPointType.mainRouter.systemImage, "router.fill")
        XCTAssertEqual(AccessPointType.meshSatellite.systemImage, "point.3.connected.trianglepath.dotted")
        XCTAssertEqual(AccessPointType.repeater.systemImage, "antenna.radiowaves.left.and.right")
    }

    func testAccessPointNodeCreation() {
        let roomId = UUID()
        let ap = AccessPointNode(
            name: "Nó Mesh Sala",
            type: .meshSatellite,
            backhaulType: .ethernet,
            roomId: roomId,
            bssid: "aa:bb:cc:dd:ee:ff"
        )

        XCTAssertEqual(ap.name, "Nó Mesh Sala")
        XCTAssertEqual(ap.type, .meshSatellite)
        XCTAssertEqual(ap.backhaulType, .ethernet)
        XCTAssertEqual(ap.roomId, roomId)
        XCTAssertEqual(ap.bssid, "aa:bb:cc:dd:ee:ff")
    }

    func testRoomWithMeshAccessPoint() {
        let ap = AccessPointNode(
            name: "Satélite Quarto",
            type: .meshSatellite,
            roomId: UUID()
        )

        let room = Room(
            name: "Quarto",
            accessPoint: ap,
            floorAreaSqMeters: 18.5,
            isLiDARCaptured: true
        )

        XCTAssertEqual(room.accessPoint?.name, "Satélite Quarto")
        XCTAssertEqual(room.floorAreaSqMeters, 18.5)
        XCTAssertTrue(room.isLiDARCaptured)
    }

    func testNetworkMetricsWithMeshFields() {
        let metrics = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 4.2,
            gatewayJitterMs: 1.1,
            gatewayPacketLossPercent: 0,
            wanLatencyMs: 22.0,
            wanPacketLossPercent: 0,
            downloadThroughputMbps: 350.0,
            connectedNodeName: "Nó Sala",
            bssid: "00:11:22:33:44:55",
            backhaulLatencyMs: 1.8
        )

        XCTAssertEqual(metrics.connectedNodeName, "Nó Sala")
        XCTAssertEqual(metrics.bssid, "00:11:22:33:44:55")
        XCTAssertEqual(metrics.backhaulLatencyMs, 1.8)
    }

    func testDataStorePersistsMeshRoomsAndMeasurements() {
        let dataStore = DataStore(inMemory: true)
        let house = dataStore.fetchOrCreateDefaultHouse()

        let roomId = UUID()
        let ap = AccessPointNode(
            name: "Satélite Mesh Escritório",
            type: .meshSatellite,
            backhaulType: .ethernet,
            roomId: roomId
        )

        let meshRoom = Room(
            id: roomId,
            name: "Escritório Novo",
            icon: "laptopcomputer",
            gridX: 2,
            gridY: 2,
            hasRouter: false,
            accessPoint: ap,
            floorAreaSqMeters: 15.2,
            isLiDARCaptured: true
        )

        dataStore.saveRooms([meshRoom], for: house.id)

        let updatedHouse = dataStore.fetchOrCreateDefaultHouse()
        guard let retrievedRoom = updatedHouse.rooms.first(where: { $0.id == roomId }) else {
            XCTFail("Cômodo com nó mesh não encontrado após salvar")
            return
        }

        XCTAssertEqual(retrievedRoom.name, "Escritório Novo")
        XCTAssertEqual(retrievedRoom.accessPoint?.type, .meshSatellite)
        XCTAssertEqual(retrievedRoom.accessPoint?.backhaulType, .ethernet)
        XCTAssertEqual(retrievedRoom.accessPoint?.name, "Satélite Mesh Escritório")
        XCTAssertEqual(retrievedRoom.floorAreaSqMeters, 15.2)
        XCTAssertTrue(retrievedRoom.isLiDARCaptured)

        let measurement = MeasurementResult(
            roomId: roomId,
            rating: .excellent,
            score: 95,
            cause: .allGood,
            metrics: NetworkMetrics(
                gatewayIP: "192.168.1.1",
                connectedNodeName: "Satélite Mesh Escritório",
                bssid: "12:34:56:78:90:ab",
                backhaulLatencyMs: 2.1
            ),
            explanation: "Sinal excelente via cabo Ethernet.",
            actionableRecommendation: "Tudo perfeito."
        )

        dataStore.saveMeasurement(measurement, for: roomId)

        let houseWithMeasurement = dataStore.fetchOrCreateDefaultHouse()
        let roomWithMeasurement = houseWithMeasurement.rooms.first(where: { $0.id == roomId })
        XCTAssertNotNil(roomWithMeasurement?.lastMeasurement)
        XCTAssertEqual(roomWithMeasurement?.lastMeasurement?.metrics.connectedNodeName, "Satélite Mesh Escritório")
        XCTAssertEqual(roomWithMeasurement?.lastMeasurement?.metrics.bssid, "12:34:56:78:90:ab")
        XCTAssertEqual(roomWithMeasurement?.lastMeasurement?.metrics.backhaulLatencyMs, 2.1)
    }
}
