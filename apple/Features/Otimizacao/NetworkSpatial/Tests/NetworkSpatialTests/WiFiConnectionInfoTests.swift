import XCTest
import SwiftData
@testable import NetworkSpatial

@MainActor
final class WiFiConnectionInfoTests: XCTestCase {

    // MARK: - 1. Normalização de BSSID

    func testBSSIDNormalizerStandardCanonicalPreserved() {
        let input = "AA:BB:CC:DD:EE:FF"
        let normalized = WiFiBSSIDNormalizer.normalize(input)
        XCTAssertEqual(normalized, "AA:BB:CC:DD:EE:FF")
    }

    func testBSSIDNormalizerLowerCaseConvertedToUppercase() {
        let input = "aa:bb:cc:dd:ee:ff"
        let normalized = WiFiBSSIDNormalizer.normalize(input)
        XCTAssertEqual(normalized, "AA:BB:CC:DD:EE:FF")
    }

    func testBSSIDNormalizerHyphenSeparated() {
        let input = "12-34-56-78-9A-BC"
        let normalized = WiFiBSSIDNormalizer.normalize(input)
        XCTAssertEqual(normalized, "12:34:56:78:9A:BC")
    }

    func testBSSIDNormalizerSpaceSeparated() {
        let input = "12 34 56 78 9A BC"
        let normalized = WiFiBSSIDNormalizer.normalize(input)
        XCTAssertEqual(normalized, "12:34:56:78:9A:BC")
    }

    func testBSSIDNormalizerRawStringWithoutSeparators() {
        let input = "aabbccddeeff"
        let normalized = WiFiBSSIDNormalizer.normalize(input)
        XCTAssertEqual(normalized, "AA:BB:CC:DD:EE:FF")
    }

    func testBSSIDNormalizerMalformedInvalidCharactersReturnsNil() {
        let input = "AA:BB:CC:DD:EE:ZZ" // 'Z' não é hexadecimal
        XCTAssertNil(WiFiBSSIDNormalizer.normalize(input))
    }

    func testBSSIDNormalizerIncompleteOctetsReturnsNil() {
        let input = "AA:BB:CC:DD:EE" // Apenas 5 octetos
        XCTAssertNil(WiFiBSSIDNormalizer.normalize(input))
    }

    func testBSSIDNormalizerTooLongReturnsNil() {
        let input = "AA:BB:CC:DD:EE:FF:11"
        XCTAssertNil(WiFiBSSIDNormalizer.normalize(input))
    }

    func testBSSIDNormalizerAllZerosReturnsNil() {
        let input = "00:00:00:00:00:00"
        XCTAssertNil(WiFiBSSIDNormalizer.normalize(input))
    }

    func testBSSIDNormalizerEmptyOrWhitespaceReturnsNil() {
        XCTAssertNil(WiFiBSSIDNormalizer.normalize(""))
        XCTAssertNil(WiFiBSSIDNormalizer.normalize("   "))
        XCTAssertNil(WiFiBSSIDNormalizer.normalize(nil))
    }

    // MARK: - 2. Serviço de Informações Wi-Fi & Mocks

    func testMockServiceSuccessfulFetch() async {
        let mockService = MockWiFiConnectionInfoService(
            mockSSID: "MinhaCasa",
            mockBSSID: "aa:bb:cc:10:01:01"
        )

        let info = await mockService.fetchCurrentConnectionInfo()
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.ssid, "MinhaCasa")
        XCTAssertEqual(info?.bssid, "AA:BB:CC:10:01:01")
    }

    func testMockServiceUnauthorizedOrUnavailableReturnsNil() async {
        let mockService = MockWiFiConnectionInfoService(shouldReturnNil: true)
        let info = await mockService.fetchCurrentConnectionInfo()
        XCTAssertNil(info)
    }

    func testMockServiceAuthorizationRequest() async {
        let mockService = MockWiFiConnectionInfoService()
        XCTAssertFalse(mockService.authorizationRequested)

        await mockService.requestAuthorizationIfNeeded()
        XCTAssertTrue(mockService.authorizationRequested)
    }

    // MARK: - 3. Rastreamento de APs e Detecção de Handoff

    func testDeterministicAPNamingAndReusing() {
        let tracker = AccessPointTracker()

        let m1 = MeasurementResult(
            roomId: UUID(),
            rating: .excellent,
            score: 95,
            cause: .allGood,
            metrics: NetworkMetrics(gatewayIP: "192.168.1.1", bssid: "aa:bb:cc:10:01:01", ssid: "MinhaCasa"),
            explanation: "",
            actionableRecommendation: ""
        )

        let m2 = MeasurementResult(
            roomId: UUID(),
            rating: .good,
            score: 80,
            cause: .allGood,
            metrics: NetworkMetrics(gatewayIP: "192.168.1.1", bssid: "aa:bb:cc:20:01:01", ssid: "MinhaCasa"),
            explanation: "",
            actionableRecommendation: ""
        )

        // Primeira medição: cria AP 1
        let (ap1, handoff1) = tracker.registerMeasurement(result: m1, roomName: "Sala")
        XCTAssertEqual(ap1?.label, "AP 1")
        XCTAssertNil(handoff1)

        // Segunda medição: cria AP 2 e detecta handoff de AP 1 para AP 2
        let (ap2, handoff2) = tracker.registerMeasurement(result: m2, roomName: "Quarto")
        XCTAssertEqual(ap2?.label, "AP 2")
        XCTAssertNotNil(handoff2)
        XCTAssertEqual(handoff2?.fromAPName, "AP 1")
        XCTAssertEqual(handoff2?.toAPName, "AP 2")

        // Terceira medição no mesmo BSSID do AP 1: reutiliza AP 1 sem criar AP 3
        let (ap3, handoff3) = tracker.registerMeasurement(result: m1, roomName: "Sala")
        XCTAssertEqual(ap3?.label, "AP 1")
        XCTAssertEqual(tracker.detectedAccessPoints.count, 2)
        XCTAssertEqual(handoff3?.fromAPName, "AP 2")
        XCTAssertEqual(handoff3?.toAPName, "AP 1")
    }

    func testSameBSSIDNoHandoff() {
        let tracker = AccessPointTracker()

        let m1 = MeasurementResult(
            roomId: UUID(),
            rating: .excellent,
            score: 95,
            cause: .allGood,
            metrics: NetworkMetrics(gatewayIP: "192.168.1.1", bssid: "AA:BB:CC:10:01:01", ssid: "MinhaCasa"),
            explanation: "",
            actionableRecommendation: ""
        )

        let m2 = MeasurementResult(
            roomId: UUID(),
            rating: .good,
            score: 85,
            cause: .allGood,
            metrics: NetworkMetrics(gatewayIP: "192.168.1.1", bssid: "AA:BB:CC:10:01:01", ssid: "MinhaCasa"),
            explanation: "",
            actionableRecommendation: ""
        )

        tracker.registerMeasurement(result: m1, roomName: "Sala")
        let (_, handoff) = tracker.registerMeasurement(result: m2, roomName: "Cozinha")

        XCTAssertNil(handoff, "Duas medições no mesmo BSSID não devem gerar evento de handoff")
    }

    func testDifferentSSIDDoesNotTriggerHandoff() {
        let tracker = AccessPointTracker()

        let m1 = MeasurementResult(
            roomId: UUID(),
            rating: .excellent,
            score: 95,
            cause: .allGood,
            metrics: NetworkMetrics(gatewayIP: "192.168.1.1", bssid: "AA:BB:CC:10:01:01", ssid: "MinhaCasa"),
            explanation: "",
            actionableRecommendation: ""
        )

        let m2 = MeasurementResult(
            roomId: UUID(),
            rating: .good,
            score: 80,
            cause: .allGood,
            metrics: NetworkMetrics(gatewayIP: "192.168.1.1", bssid: "AA:BB:CC:20:01:01", ssid: "VizinhoGuest"),
            explanation: "",
            actionableRecommendation: ""
        )

        tracker.registerMeasurement(result: m1, roomName: "Sala")
        let (_, handoff) = tracker.registerMeasurement(result: m2, roomName: "Varanda")

        XCTAssertNil(handoff, "Troca de SSID para rede diferente não deve ser classificada como roaming residencial")
    }

    func testNilBSSIDHandledGracefully() {
        let tracker = AccessPointTracker()

        let mNil = MeasurementResult(
            roomId: UUID(),
            rating: .fair,
            score: 50,
            cause: .localWiFiDegraded,
            metrics: NetworkMetrics(gatewayIP: "192.168.1.1", bssid: nil, ssid: nil),
            explanation: "",
            actionableRecommendation: ""
        )

        let (ap, handoff) = tracker.registerMeasurement(result: mNil, roomName: "Garagem")
        XCTAssertNil(ap)
        XCTAssertNil(handoff)
        XCTAssertTrue(tracker.detectedAccessPoints.isEmpty)
    }

    // MARK: - 4. Persistência no SwiftData

    func testSwiftDataPersistenceWithSSIDAndBSSID() throws {
        let dataStore = DataStore(inMemory: true)
        let house = dataStore.fetchOrCreateDefaultHouse()
        guard let firstRoom = house.rooms.first else {
            XCTFail("Casa deve possuir cômodos")
            return
        }

        let testBSSID = "11:22:33:44:55:66"
        let testSSID = "CasaDoLuiz"

        let result = MeasurementResult(
            roomId: firstRoom.id,
            rating: .excellent,
            score: 98,
            cause: .allGood,
            metrics: NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 3.5,
                gatewayJitterMs: 1.0,
                gatewayPacketLossPercent: 0.0,
                wanLatencyMs: 15.0,
                wanPacketLossPercent: 0.0,
                downloadThroughputMbps: 300.0,
                bssid: testBSSID,
                ssid: testSSID
            ),
            explanation: "Teste de persistência",
            actionableRecommendation: "Tudo certo"
        )

        dataStore.saveMeasurement(result, for: firstRoom.id)

        let reloadedHouse = dataStore.fetchOrCreateDefaultHouse()
        let reloadedRoom = reloadedHouse.rooms.first(where: { $0.id == firstRoom.id })
        let savedMeasurement = reloadedRoom?.lastMeasurement

        XCTAssertNotNil(savedMeasurement)
        XCTAssertEqual(savedMeasurement?.metrics.bssid, testBSSID)
        XCTAssertEqual(savedMeasurement?.metrics.ssid, testSSID)
    }

    func testLegacyMeasurementEntityCompatibilityWithoutSSID() {
        let entity = MeasurementEntity(
            ratingRaw: "Ótimo",
            score: 95,
            causeRaw: "Wi-Fi e Internet Excelentes",
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 4.0,
            gatewayJitterMs: 1.0,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 20.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 200.0,
            explanation: "Legado",
            actionableRecommendation: "Ok"
        )

        XCTAssertNil(entity.ssid)
        XCTAssertNil(entity.bssid)
    }

    // MARK: - 5. Integração com WiFiDiagnosticEngine

    func testDiagnosticEngineWithMockConnectionInfo() async throws {
        let mockInfoService = MockWiFiConnectionInfoService(
            mockSSID: "RedeMeshCasa",
            mockBSSID: "AA:BB:CC:99:88:77"
        )

        let engine = WiFiDiagnosticEngine(
            connectionInfoService: mockInfoService
        )

        let simulated = engine.createSimulatedMeasurement(
            roomId: UUID(),
            rating: .good,
            isRouterRoom: true,
            bssid: "AA:BB:CC:99:88:77",
            ssid: "RedeMeshCasa"
        )

        XCTAssertEqual(simulated.metrics.ssid, "RedeMeshCasa")
        XCTAssertEqual(simulated.metrics.bssid, "AA:BB:CC:99:88:77")
        XCTAssertEqual(simulated.rating, .good)
    }

    func testDiagnosticEngineWithoutConnectionInfoDoesNotBreak() async throws {
        let mockInfoService = MockWiFiConnectionInfoService(shouldReturnNil: true)

        let engine = WiFiDiagnosticEngine(
            connectionInfoService: mockInfoService
        )

        let simulated = engine.createSimulatedMeasurement(
            roomId: UUID(),
            rating: .fair,
            isRouterRoom: false
        )

        XCTAssertNil(simulated.metrics.ssid)
        XCTAssertNil(simulated.metrics.bssid)
        XCTAssertEqual(simulated.rating, .fair)
    }
}

