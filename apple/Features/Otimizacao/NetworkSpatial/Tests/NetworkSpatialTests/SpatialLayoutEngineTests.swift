import XCTest
@testable import NetworkSpatial

final class SpatialLayoutEngineTests: XCTestCase {

    func testDistanceCalculation() {
        let roomA = Room(name: "Sala", gridX: 0, gridY: 0)
        let roomB = Room(name: "Quarto", gridX: 2, gridY: 3)

        let dist = SpatialLayoutEngine.distance(from: roomA, to: roomB)
        XCTAssertEqual(dist, 5) // |0 - 2| + |0 - 3| = 5
    }

    func testHouseCoverageCalculation() {
        let measurementA = MeasurementResult(
            roomId: UUID(),
            rating: .excellent,
            score: 100,
            cause: .allGood,
            metrics: NetworkMetrics(),
            explanation: "",
            actionableRecommendation: ""
        )

        let measurementB = MeasurementResult(
            roomId: UUID(),
            rating: .good,
            score: 80,
            cause: .allGood,
            metrics: NetworkMetrics(),
            explanation: "",
            actionableRecommendation: ""
        )

        let roomA = Room(name: "Sala", lastMeasurement: measurementA)
        let roomB = Room(name: "Quarto", lastMeasurement: measurementB)
        let roomC = Room(name: "Cozinha", lastMeasurement: nil) // Não medido não entra na média dos medidos

        let coverage = SpatialLayoutEngine.calculateHouseCoverage(rooms: [roomA, roomB, roomC])
        XCTAssertEqual(coverage, 90) // (100 + 80) / 2 = 90
    }

    func testRecommendationsWithPoorRooms() {
        let measurementPoor = MeasurementResult(
            roomId: UUID(),
            rating: .poor,
            score: 25,
            cause: .localWiFiDegraded,
            metrics: NetworkMetrics(),
            explanation: "",
            actionableRecommendation: ""
        )

        let roomRouter = Room(name: "Sala", gridX: 0, gridY: 0, hasRouter: true)
        let roomDistant = Room(name: "Quarto 2", gridX: 3, gridY: 1, hasRouter: false, lastMeasurement: measurementPoor)

        let recs = SpatialLayoutEngine.generateRecommendations(rooms: [roomRouter, roomDistant])
        XCTAssertFalse(recs.isEmpty)
        XCTAssertTrue(recs.contains(where: { $0.contains("Quarto 2") || $0.contains("crítica") }))
    }
}
