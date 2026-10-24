import XCTest
@testable import NetworkSpatial

final class BeforeAfterComparisonTests: XCTestCase {

    func testBeforeAfterComparisonDelta() {
        let roomId = UUID()

        let beforeMeasurement = MeasurementResult(
            roomId: roomId,
            rating: .poor,
            score: 38,
            cause: .localWiFiDegraded,
            metrics: NetworkMetrics(gatewayLatencyMs: 95),
            explanation: "",
            actionableRecommendation: ""
        )

        let afterMeasurement = MeasurementResult(
            roomId: roomId,
            rating: .good,
            score: 82,
            cause: .allGood,
            metrics: NetworkMetrics(gatewayLatencyMs: 20),
            explanation: "",
            actionableRecommendation: ""
        )

        let beforeRoom = Room(id: roomId, name: "Quarto", lastMeasurement: beforeMeasurement)
        let afterRoom = Room(id: roomId, name: "Quarto", lastMeasurement: afterMeasurement)

        let comparison = SpatialLayoutEngine.generateComparison(
            title: "Teste de Otimização",
            baselineRooms: [beforeRoom],
            afterRooms: [afterRoom]
        )

        XCTAssertEqual(comparison.baselineCoveragePercent, 38)
        XCTAssertEqual(comparison.afterCoveragePercent, 82)
        XCTAssertEqual(comparison.deltaCoveragePercent, 44) // +44%
        XCTAssertEqual(comparison.roomComparisons.count, 1)

        let roomComp = comparison.roomComparisons[0]
        XCTAssertEqual(roomComp.beforeScore, 38)
        XCTAssertEqual(roomComp.afterScore, 82)
        XCTAssertEqual(roomComp.deltaScore, 44)
        XCTAssertEqual(roomComp.beforeRating, .poor)
        XCTAssertEqual(roomComp.afterRating, .good)
    }
}
