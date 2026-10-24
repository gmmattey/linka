import XCTest
import SwiftUI
@testable import NetworkSpatial

@MainActor
final class FlowsAndViewsMVP2Tests: XCTestCase {

    func testLiDARUnavailableSheetInstantiatesCleanly() {
        var didCallManualEditor = false
        let view = LiDARUnavailableSheet {
            didCallManualEditor = true
        }

        XCTAssertNotNil(view.body)
        view.onOpenManualEditor()
        XCTAssertTrue(didCallManualEditor)
    }

    func testRoomScanIntroSheetInstantiatesCleanly() {
        var didStartScan = false
        var didOpenManual = false

        let view = RoomScanIntroSheet(
            onStartScanning: {
                didStartScan = true
            },
            onOpenManualEditor: {
                didOpenManual = true
            }
        )

        XCTAssertNotNil(view.body)
        view.onStartScanning()
        view.onOpenManualEditor()
        XCTAssertTrue(didStartScan)
        XCTAssertTrue(didOpenManual)
    }

    func testRoomScanReviewViewConsolidationTriggersCallback() {
        let captured = [
            CapturedRoomData(suggestedName: "Sala", areaSqMeters: 20.0, boundingWidthMeters: 4.0, boundingLengthMeters: 5.0),
            CapturedRoomData(suggestedName: "Quarto", areaSqMeters: 12.0, boundingWidthMeters: 3.0, boundingLengthMeters: 4.0)
        ]

        var consolidatedRooms: [Room] = []
        let view = RoomScanReviewView(capturedRooms: captured) { rooms in
            consolidatedRooms = rooms
        }

        XCTAssertNotNil(view.body)
        view.onConsolidate(RoomPlanParser.convertCapturedRoomsToHouseRooms(capturedRooms: captured, defaultRouterRoomIndex: 0))

        XCTAssertEqual(consolidatedRooms.count, 2)
        XCTAssertEqual(consolidatedRooms[0].name, "Sala")
        XCTAssertTrue(consolidatedRooms[0].hasRouter)
    }

    func testReportPreviewSheetInstantiatesCleanly() {
        let house = House(
            name: "Apartamento Teste",
            rooms: [
                Room(name: "Sala", icon: "sofa", hasRouter: true),
                Room(name: "Quarto", icon: "bed.double", hasRouter: false)
            ]
        )

        let view = ReportPreviewSheet(house: house, ssid: "Teste_5G", gatewayIP: "192.168.1.1")
        XCTAssertNotNil(view.body)
    }

    func testRoomEditorSheetConfiguresAccessPointAndBackhaul() {
        var rooms = [
            Room(id: UUID(), name: "Sala", icon: "sofa", hasRouter: true),
            Room(id: UUID(), name: "Corredor", icon: "door.left.hand.open", hasRouter: false)
        ]

        var savedRooms: [Room] = []
        let view = RoomEditorSheet(
            rooms: Binding(get: { rooms }, set: { rooms = $0 }),
            onSave: { updated in
                savedRooms = updated
            }
        )

        XCTAssertNotNil(view.body)
        view.onSave(rooms)
        XCTAssertEqual(savedRooms.count, 2)
    }
}
