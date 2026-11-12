import XCTest
@testable import NetworkSpatial

final class WalkSessionTests: XCTestCase {

    // MARK: - Roteamento Espacial da Caminhada (Nearest Neighbor Manhattan)

    func testBuildWalkRouteStartsAtRouterRoom() {
        let roomA = Room(name: "Quarto 1", gridX: 3, gridY: 0, hasRouter: false)
        let roomRouter = Room(name: "Sala Roteador", gridX: 1, gridY: 1, hasRouter: true)
        let roomC = Room(name: "Cozinha", gridX: 0, gridY: 0, hasRouter: false)

        let route = SpatialLayoutEngine.buildWalkRoute(rooms: [roomA, roomRouter, roomC])

        XCTAssertEqual(route.count, 3)
        XCTAssertEqual(route.first?.id, roomRouter.id, "A caminhada deve iniciar obrigatoriamente no cômodo que possui o roteador.")
    }

    func testBuildWalkRouteSequencesByManhattanProximity() {
        let router = Room(name: "Sala", gridX: 0, gridY: 0, hasRouter: true)
        let nearRoom = Room(name: "Corredor", gridX: 1, gridY: 0, hasRouter: false) // dist 1
        let midRoom = Room(name: "Quarto", gridX: 2, gridY: 1, hasRouter: false) // dist 2 de Corredor
        let farRoom = Room(name: "Varanda", gridX: 4, gridY: 4, hasRouter: false)

        let route = SpatialLayoutEngine.buildWalkRoute(rooms: [farRoom, router, midRoom, nearRoom])

        XCTAssertEqual(route.count, 4)
        XCTAssertEqual(route[0].name, "Sala")
        XCTAssertEqual(route[1].name, "Corredor")
        XCTAssertEqual(route[2].name, "Quarto")
        XCTAssertEqual(route[3].name, "Varanda")
    }

    func testBuildWalkRouteHandlesEmptyAndSingleRoom() {
        let emptyRoute = SpatialLayoutEngine.buildWalkRoute(rooms: [])
        XCTAssertTrue(emptyRoute.isEmpty)

        let single = Room(name: "Studio", gridX: 0, gridY: 0, hasRouter: true)
        let singleRoute = SpatialLayoutEngine.buildWalkRoute(rooms: [single])
        XCTAssertEqual(singleRoute.count, 1)
        XCTAssertEqual(singleRoute.first?.name, "Studio")
    }

    // MARK: - Máquina de Estados do WalkSessionViewModel

    @MainActor
    func testWalkSessionViewModelInitialState() {
        let r1 = Room(name: "Sala", gridX: 0, gridY: 0, hasRouter: true)
        let r2 = Room(name: "Quarto", gridX: 1, gridY: 1)
        let dataStore = DataStore(inMemory: true)

        let vm = WalkSessionViewModel(rooms: [r1, r2], mode: .regular, dataStore: dataStore)

        if case .intro(let count) = vm.state {
            XCTAssertEqual(count, 2)
        } else {
            XCTFail("Estado inicial deveria ser .intro com 2 cômodos")
        }
    }

    @MainActor
    func testWalkSessionViewModelStartWalkGuidesToFirstRoom() {
        let r1 = Room(name: "Sala", gridX: 0, gridY: 0, hasRouter: true)
        let r2 = Room(name: "Quarto", gridX: 1, gridY: 1)
        let dataStore = DataStore(inMemory: true)

        let vm = WalkSessionViewModel(rooms: [r1, r2], mode: .regular, dataStore: dataStore)
        vm.startWalk()

        if case .guidingToRoom(let room, let step, let total) = vm.state {
            XCTAssertEqual(room.name, "Sala")
            XCTAssertEqual(step, 1)
            XCTAssertEqual(total, 2)
        } else {
            XCTFail("Após startWalk, o estado deveria ser .guidingToRoom para o primeiro cômodo")
        }
    }

    @MainActor
    func testWalkSessionViewModelSkipRoom() {
        let r1 = Room(name: "Sala", gridX: 0, gridY: 0, hasRouter: true)
        let r2 = Room(name: "Quarto", gridX: 1, gridY: 1)
        let dataStore = DataStore(inMemory: true)

        let vm = WalkSessionViewModel(rooms: [r1, r2], mode: .regular, dataStore: dataStore)
        vm.startWalk()
        vm.skipCurrentRoom()

        XCTAssertTrue(vm.session.skippedRoomIds.contains(r1.id))

        if case .guidingToRoom(let room, let step, let total) = vm.state {
            XCTAssertEqual(room.name, "Quarto")
            XCTAssertEqual(step, 2)
            XCTAssertEqual(total, 2)
        } else {
            XCTFail("Após pular a Sala, deveria guiar para o Quarto")
        }
    }

    @MainActor
    func testWalkSessionViewModelFinishEarlyComputesSummary() {
        let r1 = Room(name: "Sala", gridX: 0, gridY: 0, hasRouter: true)
        let r2 = Room(name: "Quarto", gridX: 1, gridY: 1)
        let dataStore = DataStore(inMemory: true)

        let vm = WalkSessionViewModel(rooms: [r1, r2], mode: .regular, dataStore: dataStore)
        vm.startWalk()

        // Simula uma medição salva no primeiro cômodo
        let measurement = MeasurementResult(
            roomId: r1.id,
            rating: .excellent,
            score: 95,
            cause: .allGood,
            metrics: NetworkMetrics(
                gatewayLatencyMs: 4,
                gatewayJitterMs: 1,
                gatewayPacketLossPercent: 0,
                wanLatencyMs: 18,
                wanPacketLossPercent: 0,
                bssid: "AA:BB:CC:DD:EE:01"
            ),
            explanation: "Wi-Fi excelente",
            actionableRecommendation: "Tudo ótimo"
        )
        vm.session.completedMeasurements[r1.id] = measurement
        vm.session.detectedBSSIDs.insert("AA:BB:CC:DD:EE:01")

        // Usuário decide encerrar mais cedo antes de medir o Quarto
        vm.finishEarly()

        if case .sessionSummary(let summary) = vm.state {
            XCTAssertEqual(summary.measuredRoomsCount, 1)
            XCTAssertEqual(summary.totalRoomsCount, 2)
            XCTAssertEqual(summary.excellentCount, 1)
            XCTAssertEqual(summary.detectedAccessPointsCount, 1)
        } else {
            XCTFail("Após finishEarly, deveria ir para .sessionSummary")
        }
    }

    @MainActor
    func testWalkSessionViewModelCancelSession() {
        let r1 = Room(name: "Sala", gridX: 0, gridY: 0, hasRouter: true)
        let dataStore = DataStore(inMemory: true)
        var finishedCalled = false

        let vm = WalkSessionViewModel(
            rooms: [r1],
            mode: .regular,
            dataStore: dataStore,
            onFinished: {
                finishedCalled = true
            }
        )

        vm.cancelSession()
        XCTAssertTrue(finishedCalled)
    }

    @MainActor
    func testComparisonWalkSessionProducesDelta() {
        let r1 = Room(name: "Sala", gridX: 0, gridY: 0, hasRouter: true)
        let dataStore = DataStore(inMemory: true)

        // Prepara baseline prévia no DataStore
        var baselineRoom = r1
        baselineRoom.lastMeasurement = MeasurementResult(
            roomId: r1.id,
            rating: .fair,
            score: 50,
            cause: .localWiFiDegraded,
            metrics: NetworkMetrics(gatewayLatencyMs: 45),
            explanation: "Regular",
            actionableRecommendation: ""
        )
        dataStore.saveActiveComparisonBaseline([baselineRoom])

        let vm = WalkSessionViewModel(rooms: [r1], mode: .comparison, dataStore: dataStore)
        vm.startWalk()

        // Simula nova medição excelente após mudança física
        let improvedMeasurement = MeasurementResult(
            roomId: r1.id,
            rating: .excellent,
            score: 95,
            cause: .allGood,
            metrics: NetworkMetrics(gatewayLatencyMs: 4),
            explanation: "Excelente",
            actionableRecommendation: ""
        )
        vm.session.completedMeasurements[r1.id] = improvedMeasurement

        vm.continueWalk() // Sendo o último cômodo, completa a sessão

        if case .sessionSummary(let summary) = vm.state {
            XCTAssertEqual(summary.mode, .comparison)
            XCTAssertEqual(summary.baselineCoverageScore, 50)
            XCTAssertEqual(summary.houseCoverageScore, 95)
            XCTAssertEqual(summary.deltaScore, 45) // +45% de melhoria
        } else {
            XCTFail("Deveria apresentar resumo com comparativo Antes × Depois")
        }
    }
}
