import XCTest
@testable import NetworkSpatial

final class SpatialAndLiDARTests: XCTestCase {
    func testLiDARCapabilityDeterministic() {
        // No ambiente macOS CLI ou simulador, deve retornar false sem crashes
        XCTAssertFalse(LiDARCapability.isSupported)
    }

    func testMockRoomPlanScannerSuccess() async throws {
        let scanner = MockRoomPlanScanner()
        XCTAssertFalse(scanner.isScanning)

        try await scanner.startScan()
        XCTAssertTrue(scanner.isScanning)

        let rooms = try await scanner.stopScan()
        XCTAssertFalse(scanner.isScanning)
        XCTAssertEqual(rooms.count, 4)
        XCTAssertEqual(rooms.first?.suggestedName, "Sala de Estar")
        XCTAssertEqual(rooms.first?.areaSqMeters, 24.5)
    }

    func testMockRoomPlanScannerErrorHandling() async {
        let scanner = MockRoomPlanScanner(shouldThrowError: true)

        do {
            try await scanner.startScan()
            XCTFail("Deveria ter lançado erro")
        } catch let error as RoomPlanScanningError {
            XCTAssertEqual(error, .captureFailed("Erro simulado de inicialização de câmera."))
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }
}
