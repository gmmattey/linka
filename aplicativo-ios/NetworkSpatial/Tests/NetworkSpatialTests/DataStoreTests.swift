import XCTest
@testable import NetworkSpatial

@MainActor
final class DataStoreTests: XCTestCase {

    func testFetchOrCreateDefaultHouse() {
        let store = DataStore(inMemory: true)
        let house = store.fetchOrCreateDefaultHouse()

        XCTAssertFalse(house.rooms.isEmpty)
        XCTAssertEqual(house.name, "Minha Residência")
        XCTAssertTrue(house.rooms.contains(where: { $0.hasRouter }))
    }

    func testSaveAndRetrieveMeasurement() {
        let store = DataStore(inMemory: true)
        let house = store.fetchOrCreateDefaultHouse()
        guard let firstRoom = house.rooms.first else {
            XCTFail("Casa padrão sem cômodos")
            return
        }

        let measurement = MeasurementResult(
            roomId: firstRoom.id,
            rating: .excellent,
            score: 96,
            cause: .allGood,
            metrics: NetworkMetrics(gatewayIP: "192.168.1.1", gatewayLatencyMs: 4.5),
            explanation: "Tudo ótimo",
            actionableRecommendation: "Manter posição"
        )

        store.saveMeasurement(measurement, for: firstRoom.id)
        let updatedHouse = store.fetchOrCreateDefaultHouse()
        let updatedRoom = updatedHouse.rooms.first(where: { $0.id == firstRoom.id })

        XCTAssertNotNil(updatedRoom?.lastMeasurement)
        XCTAssertEqual(updatedRoom?.lastMeasurement?.score, 96)
        XCTAssertEqual(updatedRoom?.lastMeasurement?.rating, .excellent)
    }

    func testSaveAndFetchComparisonSession() {
        let store = DataStore(inMemory: true)

        let roomComp = RoomComparison(
            roomName: "Escritório",
            roomIcon: "laptopcomputer",
            beforeRating: .fair,
            beforeScore: 50,
            afterRating: .excellent,
            afterScore: 92
        )

        let comparison = BeforeAfterComparison(
            title: "Troca de Posição do Roteador",
            baselineCoveragePercent: 50,
            afterCoveragePercent: 92,
            roomComparisons: [roomComp]
        )

        store.saveComparison(comparison)
        let savedList = store.fetchComparisons()

        XCTAssertEqual(savedList.count, 1)
        XCTAssertEqual(savedList.first?.deltaCoveragePercent, 42)
        XCTAssertEqual(savedList.first?.roomComparisons.first?.roomName, "Escritório")
    }
}
