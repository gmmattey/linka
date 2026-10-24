import XCTest
@testable import NetworkSpatial

final class RoomPlanModelConverterTests: XCTestCase {

    func testConvertCapturedRoomsToHouseRoomsPreservesCountAndAssignsGrid() {
        let captured = [
            CapturedRoomData(suggestedName: "Sala de Estar", areaSqMeters: 25.0, boundingWidthMeters: 5.0, boundingLengthMeters: 5.0),
            CapturedRoomData(suggestedName: "Cozinha", areaSqMeters: 12.5, boundingWidthMeters: 3.5, boundingLengthMeters: 3.5),
            CapturedRoomData(suggestedName: "Quarto Principal", areaSqMeters: 16.0, boundingWidthMeters: 4.0, boundingLengthMeters: 4.0),
            CapturedRoomData(suggestedName: "Banheiro", areaSqMeters: 4.5, boundingWidthMeters: 2.0, boundingLengthMeters: 2.25)
        ]

        let rooms = RoomPlanParser.convertCapturedRoomsToHouseRooms(capturedRooms: captured, defaultRouterRoomIndex: 0)

        XCTAssertEqual(rooms.count, 4)

        // Verificação de coordenadas de grid sem colisão
        XCTAssertEqual(rooms[0].gridX, 0)
        XCTAssertEqual(rooms[0].gridY, 0)
        XCTAssertEqual(rooms[1].gridX, 1)
        XCTAssertEqual(rooms[1].gridY, 0)
        XCTAssertEqual(rooms[2].gridX, 0)
        XCTAssertEqual(rooms[2].gridY, 1)
        XCTAssertEqual(rooms[3].gridX, 1)
        XCTAssertEqual(rooms[3].gridY, 1)

        // Verificação do roteador no índice 0
        XCTAssertTrue(rooms[0].hasRouter)
        XCTAssertEqual(rooms[0].accessPoint?.type, .mainRouter)
        XCTAssertEqual(rooms[0].accessPoint?.backhaulType, .ethernet)
        XCTAssertFalse(rooms[1].hasRouter)
        XCTAssertNil(rooms[1].accessPoint)

        // Verificação de metadados LiDAR
        for room in rooms {
            XCTAssertTrue(room.isLiDARCaptured)
            XCTAssertNotNil(room.floorAreaSqMeters)
        }

        // Verificação de ícones semânticos
        XCTAssertEqual(rooms[0].icon, "sofa")
        XCTAssertEqual(rooms[1].icon, "fork.knife")
        XCTAssertEqual(rooms[2].icon, "bed.double")
        XCTAssertEqual(rooms[3].icon, "bathtub")
    }

    func testAreaSanitizationPreventsAnomalies() {
        let captured = [
            CapturedRoomData(suggestedName: "Espaço Minúsculo", areaSqMeters: 0.1, boundingWidthMeters: 0.3, boundingLengthMeters: 0.3),
            CapturedRoomData(suggestedName: "Mansão Gigante", areaSqMeters: 800.0, boundingWidthMeters: 30.0, boundingLengthMeters: 26.6)
        ]

        let rooms = RoomPlanParser.convertCapturedRoomsToHouseRooms(capturedRooms: captured, defaultRouterRoomIndex: nil)

        XCTAssertEqual(rooms.count, 2)
        XCTAssertEqual(rooms[0].floorAreaSqMeters, 1.0)
        XCTAssertEqual(rooms[1].floorAreaSqMeters, 500.0)
        XCTAssertFalse(rooms[0].hasRouter)
        XCTAssertFalse(rooms[1].hasRouter)
    }
}
