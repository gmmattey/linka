import XCTest
@testable import NetworkSpatial

final class NetworkResilienceTests: XCTestCase {

    func testGatewayDiscoveryReturnsValidIPv4() {
        let service = GatewayDiscoveryService.shared
        if let ip = service.discoverGatewayIP() {
            XCTAssertFalse(ip.isEmpty, "Gateway IP não deve ser vazio quando descoberto")

            let parts = ip.split(separator: ".")
            XCTAssertEqual(parts.count, 4, "Gateway deve ser um endereço IPv4 com 4 octetos")
            for part in parts {
                guard let intVal = Int(part) else {
                    XCTFail("Octeto \(part) não é um número inteiro válido")
                    return
                }
                XCTAssertTrue((0...255).contains(intVal), "Octeto \(intVal) fora do intervalo 0-255")
            }
        } else {
            XCTAssertEqual(service.discoverGatewayIPDisplayString(), "Não identificado", "Quando nil, deve retornar string descritiva")
        }
    }

    func testDarwinRoutingTableParsing() {
        let service = GatewayDiscoveryService.shared
        let routingGateway = service.getGatewayFromRoutingTable()
        // No macOS rodando os testes, uma rota padrão válida é esperada quando conectado à internet
        if let gw = routingGateway {
            let parts = gw.split(separator: ".")
            XCTAssertEqual(parts.count, 4, "Gateway de roteamento deve ser IPv4")
        }
    }

    func testWiFiDiagnosticEngineSimulatedMeasurementCompletesDeterministically() {
        let engine = WiFiDiagnosticEngine()
        let roomId = UUID()

        let excellent = engine.createSimulatedMeasurement(roomId: roomId, rating: .excellent)
        XCTAssertEqual(excellent.rating, .excellent)
        XCTAssertEqual(excellent.cause, .allGood)
        XCTAssertGreaterThan(excellent.score, 80)

        let poor = engine.createSimulatedMeasurement(roomId: roomId, rating: .poor)
        XCTAssertEqual(poor.rating, .poor)
        XCTAssertEqual(poor.cause, .bothDegraded)
        XCTAssertLessThan(poor.score, 60)
    }

    func testDiagnosticErrorDescriptionsAreInformative() {
        let notConnected = DiagnosticError.notConnectedToWiFi
        XCTAssertTrue(notConnected.localizedDescription.contains("não está conectado"), "Descrição clara de erro de Wi-Fi")

        let aborted = DiagnosticError.measurementAborted
        XCTAssertTrue(aborted.localizedDescription.contains("interrompida"), "Descrição clara de medição abortada")

        let unreachable = DiagnosticError.gatewayUnreachable
        XCTAssertTrue(unreachable.localizedDescription.contains("roteador local"), "Descrição clara de gateway inacessível")
    }

    @MainActor
    func testDataStoreActiveComparisonBaselineLifecycle() {
        let dataStore = DataStore(inMemory: true)

        let testRooms = [
            Room(id: UUID(), name: "Quarto Teste", icon: "bed.double", gridX: 0, gridY: 0)
        ]

        dataStore.saveActiveComparisonBaseline(testRooms)
        let loaded = dataStore.fetchActiveComparisonBaseline()
        XCTAssertNotNil(loaded, "Baseline deve ser recuperado com sucesso")
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.first?.name, "Quarto Teste")

        dataStore.clearActiveComparisonBaseline()
        let cleared = dataStore.fetchActiveComparisonBaseline()
        XCTAssertNil(cleared, "Baseline deve ser nulo após limpeza")
    }

    func testMeasurementCancellationAbortsCleanly() async {
        let engine = WiFiDiagnosticEngine()
        let roomId = UUID()

        let task = Task {
            try await engine.performMeasurement(for: roomId, isRouterRoom: false)
        }

        // Cancela a medição em andamento
        task.cancel()

        do {
            _ = try await task.value
        } catch let error as DiagnosticError {
            XCTAssertTrue(error == .measurementAborted || error == .notConnectedToWiFi, "Erro esperado de cancelamento ou não conectado")
        } catch {
            XCTAssertTrue(error is CancellationError, "Erro padrão de cancelamento esperado")
        }
    }

    @MainActor
    func testHomeViewModelCancelsMeasurementWhenWiFiDrops() async {
        let dataStore = DataStore(inMemory: true)
        let monitor = NetworkMonitorService()
        let vm = HomeViewModel(dataStore: dataStore, networkMonitor: monitor)

        vm.isMeasuring = true
        XCTAssertTrue(vm.isMeasuring)

        // Simula queda de conexão Wi-Fi via publisher
        monitor.simulateWiFiStatusChange(isWiFi: false)

        // Aguarda yield para processar o sink Combine no MainActor
        await Task.yield()

        XCTAssertFalse(vm.isMeasuring, "isMeasuring deve ser cancelado automaticamente pelo sink reativo")
        XCTAssertEqual(vm.errorMessage, DiagnosticError.measurementAborted.localizedDescription)
    }

    @MainActor
    func testWalkSessionViewModelHandlesCancellationGracefully() {
        let room = Room(id: UUID(), name: "Quarto Fundo", icon: "bed.double")
        let dataStore = DataStore(inMemory: true)
        var finishedCalled = false
        let vm = WalkSessionViewModel(rooms: [room], dataStore: dataStore, onFinished: {
            finishedCalled = true
        })

        vm.startWalk()
        if case .guidingToRoom(let r, _, _) = vm.state {
            XCTAssertEqual(r.name, "Quarto Fundo")
        } else {
            XCTFail("Deveria iniciar guiando para o quarto")
        }

        vm.confirmAtLocation()
        XCTAssertTrue(vm.isMeasuring)

        // Cancela a sessão em andamento
        vm.cancelSession()
        XCTAssertFalse(vm.isMeasuring)
        XCTAssertTrue(finishedCalled)
    }

    func testQualityClassifierWithUnreachableGateway() {
        let unreachableMetrics = NetworkMetrics(
            gatewayIP: "Não identificado",
            gatewayLatencyMs: 0.0,
            gatewayJitterMs: 0.0,
            gatewayPacketLossPercent: 100.0,
            wanLatencyMs: 0.0,
            wanPacketLossPercent: 100.0,
            downloadThroughputMbps: nil
        )

        let result = QualityClassifier.classify(metrics: unreachableMetrics, isWiFiActive: true)
        XCTAssertEqual(result.rating, .poor)
        XCTAssertEqual(result.cause, .bothDegraded)
        XCTAssertTrue(result.explanation.contains("roteador local"))
    }
}

