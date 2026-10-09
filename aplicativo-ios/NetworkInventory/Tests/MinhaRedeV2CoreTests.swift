import XCTest
@testable import NetworkInventory
import NetworkProfiles
import NetworkCore

final class MinhaRedeV2CoreTests: XCTestCase {
    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("inventory.json")
    }

    // MARK: - 1. Guarda B1 (ResidentialPlanEligibility)

    func testResidentialPlanEligibilityCellularIsAlwaysIneligible() {
        let result = ResidentialPlanEligibility.evaluate(connectionKind: .cellular)
        XCTAssertFalse(result.isEligible)
        XCTAssertEqual(result.reason, .cellularConnection)
    }

    func testResidentialPlanEligibilityHotspotIsAlwaysIneligible() {
        let result = ResidentialPlanEligibility.evaluate(
            connectionKind: .wifi,
            isPersonalHotspot: true
        )
        XCTAssertFalse(result.isEligible)
        XCTAssertEqual(result.reason, .personalHotspot)
    }

    func testResidentialPlanEligibilityExpensiveIsAlwaysIneligible() {
        let result = ResidentialPlanEligibility.evaluate(
            connectionKind: .wifi,
            isExpensive: true
        )
        XCTAssertFalse(result.isEligible)
        XCTAssertEqual(result.reason, .expensiveNetwork)
    }

    func testResidentialPlanEligibilityMissingConnectionKindIsIneligible() {
        let result = ResidentialPlanEligibility.evaluate(connectionKind: nil)
        XCTAssertFalse(result.isEligible)
        XCTAssertEqual(result.reason, .missingConnectionKind)
    }

    func testResidentialPlanEligibilityUnsupportedConnectionKindIsIneligible() {
        let result = ResidentialPlanEligibility.evaluate(connectionKind: .other)
        XCTAssertFalse(result.isEligible)
        XCTAssertEqual(result.reason, .unsupportedConnectionKind)
    }

    func testResidentialPlanEligibilityWifiAndEthernetAreEligible() {
        let wifiResult = ResidentialPlanEligibility.evaluate(connectionKind: .wifi)
        XCTAssertTrue(wifiResult.isEligible)
        XCTAssertNil(wifiResult.reason)

        let ethResult = ResidentialPlanEligibility.evaluate(connectionKind: .ethernet)
        XCTAssertTrue(ethResult.isEligible)
        XCTAssertNil(ethResult.reason)
    }

    func testResidentialPlanEligibilityFromTelemetrySnapshot() {
        let cellularTelemetry = LiveNetworkTelemetrySnapshot(
            connectionKind: .cellular,
            isExpensive: false
        )
        XCTAssertEqual(
            ResidentialPlanEligibility.evaluate(telemetry: cellularTelemetry).reason,
            .cellularConnection
        )

        let expensiveWifi = LiveNetworkTelemetrySnapshot(
            connectionKind: .wifi,
            isExpensive: true
        )
        XCTAssertEqual(
            ResidentialPlanEligibility.evaluate(telemetry: expensiveWifi).reason,
            .expensiveNetwork
        )

        let cleanWifi = LiveNetworkTelemetrySnapshot(
            connectionKind: .wifi,
            isExpensive: false
        )
        XCTAssertTrue(ResidentialPlanEligibility.evaluate(telemetry: cleanWifi).isEligible)
    }

    func testResidentialPlanEligibilityFromMeasurement() {
        let wifiMeasurement = NetworkMeasurement(connectionKind: .wifi)
        let wifiResult = ResidentialPlanEligibility.evaluate(measurement: wifiMeasurement)
        XCTAssertTrue(wifiResult.isEligible)
        XCTAssertNil(wifiResult.reason)

        let cellularMeasurement = NetworkMeasurement(connectionKind: .cellular)
        let cellularResult = ResidentialPlanEligibility.evaluate(measurement: cellularMeasurement)
        XCTAssertFalse(cellularResult.isEligible)
        XCTAssertEqual(cellularResult.reason, .cellularConnection)
    }

    // MARK: - 2. Invariantes de NetworkServicePlan

    func testNetworkServicePlanValidation() {
        var plan = NetworkServicePlan(
            ispName: "Vivo Fibra",
            planName: "500 Mega",
            nominalDownloadMbps: 500.0,
            nominalUploadMbps: 250.0,
            technology: .fiber,
            monthlyCostCents: 12000,
            currencyCode: "BRL"
        )
        XCTAssertTrue(plan.isValid)

        // ISP vazio
        plan.ispName = "   "
        XCTAssertFalse(plan.isValid)
        plan.ispName = "Vivo Fibra"

        // Mbps não finitos ou <= 0
        plan.nominalDownloadMbps = 0
        XCTAssertFalse(plan.isValid)
        plan.nominalDownloadMbps = -10
        XCTAssertFalse(plan.isValid)
        plan.nominalDownloadMbps = Double.nan
        XCTAssertFalse(plan.isValid)
        plan.nominalDownloadMbps = Double.infinity
        XCTAssertFalse(plan.isValid)
        plan.nominalDownloadMbps = 500.0

        plan.nominalUploadMbps = -1
        XCTAssertFalse(plan.isValid)
        plan.nominalUploadMbps = 250.0

        // Custo com moeda inválida
        plan.currencyCode = "reais"
        XCTAssertFalse(plan.isValid)
        plan.currencyCode = "BR"
        XCTAssertFalse(plan.isValid)
        plan.currencyCode = "BRL"

        // Custo negativo
        plan.monthlyCostCents = -100
        XCTAssertFalse(plan.isValid)
        plan.monthlyCostCents = 12000

        // Custo sem moeda
        plan.currencyCode = nil
        XCTAssertFalse(plan.isValid)
        plan.currencyCode = "BRL"

        // Datas invertidas
        let now = Date()
        plan.effectiveFrom = now
        plan.effectiveTo = now.addingTimeInterval(-3600)
        XCTAssertFalse(plan.isValid)

        plan.effectiveTo = now.addingTimeInterval(3600)
        XCTAssertTrue(plan.isValid)

        // updatedAt anterior a createdAt
        plan.updatedAt = plan.createdAt.addingTimeInterval(-10)
        XCTAssertFalse(plan.isValid)
    }

    // MARK: - 3. Invariantes e Normalização de DeviceConnection

    func testDeviceConnectionValidationAndNormalization() {
        let devA = UUID()
        let devB = UUID()
        let devC = UUID()

        // Auto-conexão proibida
        let selfLoop = DeviceConnection(
            endpointADeviceID: devA,
            endpointBDeviceID: devA,
            medium: .ethernet
        )
        XCTAssertFalse(selfLoop.isValid)

        // SourceDeviceID estranho proibido
        let invalidSource = DeviceConnection(
            endpointADeviceID: devA,
            endpointBDeviceID: devB,
            medium: .ethernet,
            sourceDeviceID: devC
        )
        XCTAssertFalse(invalidSource.isValid)

        // Conexão válida
        let validConn = DeviceConnection(
            endpointADeviceID: devA,
            endpointBDeviceID: devB,
            medium: .wifi,
            sourceDeviceID: devA
        )
        XCTAssertTrue(validConn.isValid)

        // Normalização de chaves: A-B e B-A devem gerar mesma chave para mesmo meio
        let connAB = DeviceConnection(
            endpointADeviceID: devA,
            endpointBDeviceID: devB,
            medium: .wifi
        )
        let connBA = DeviceConnection(
            endpointADeviceID: devB,
            endpointBDeviceID: devA,
            medium: .wifi
        )
        XCTAssertEqual(connAB.normalizedLinkKey, connBA.normalizedLinkKey)

        // Meios distintos geram chaves distintas
        let connEthernet = DeviceConnection(
            endpointADeviceID: devA,
            endpointBDeviceID: devB,
            medium: .ethernet
        )
        XCTAssertNotEqual(connAB.normalizedLinkKey, connEthernet.normalizedLinkKey)
    }

    // MARK: - 4. HomeNetworkProfile Invariantes

    func testHomeNetworkProfileValidation() {
        var profile = HomeNetworkProfile(displayName: "Minha Casa")
        XCTAssertTrue(profile.isValid)

        profile.displayName = "   "
        XCTAssertFalse(profile.isValid)

        profile.displayName = "Casa com controle \u{0000}"
        XCTAssertFalse(profile.isValid)
    }

    // MARK: - 5. Migração de Schema V1 para V2 e Preservação

    func testFileRepositorySchemaV1MigrationToV2() async throws {
        let url = tempStoreURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let deviceID = UUID()
        let v1JSON = """
        {
            "schemaVersion": 1,
            "devices": [
                {
                    "id": "\(deviceID.uuidString)",
                    "kind": "router",
                    "identity": { "brand": "TP-Link", "model": "Archer AX50" },
                    "installation": { "role": "mainRouter", "mainRouterAnswer": "yes", "ownership": "userOwned", "fiberDirectConnected": "no" },
                    "revision": 1,
                    "createdAt": 0,
                    "updatedAt": 0
                }
            ]
        }
        """
        try Data(v1JSON.utf8).write(to: url)

        // 1. Carrega através do repositório
        let repo = FileNetworkInventoryRepository(fileURL: url)
        let loadedDevices = try await repo.devices()
        XCTAssertEqual(loadedDevices.count, 1)
        XCTAssertEqual(loadedDevices.first?.id, deviceID)

        // Verifica que antes de mutação, o arquivo físico ainda é V1
        let preMutationData = try Data(contentsOf: url)
        let preVersion = try JSONDecoder().decode(VersionHeaderCheck.self, from: preMutationData).schemaVersion
        XCTAssertEqual(preVersion, 1)

        // 2. Executa mutação (adiciona plano)
        let plan = NetworkServicePlan(
            ispName: "Claro",
            technology: .cable
        )
        _ = try await repo.savePlan(plan)

        // 3. Verifica que arquivo agora é Schema 2
        let postMutationData = try Data(contentsOf: url)
        let postVersion = try JSONDecoder().decode(VersionHeaderCheck.self, from: postMutationData).schemaVersion
        XCTAssertEqual(postVersion, 2)

        // 4. Instancia novo repositório e verifica que lê tudo perfeitamente
        let reloadedRepo = FileNetworkInventoryRepository(fileURL: url)
        let reloadedDevices = try await reloadedRepo.devices()
        let reloadedPlans = try await reloadedRepo.plans()
        XCTAssertEqual(reloadedDevices.count, 1)
        XCTAssertEqual(reloadedPlans.count, 1)
        XCTAssertEqual(reloadedPlans.first?.ispName, "Claro")
    }

    func testFileRepositoryUnsupportedSchemaPreservesFile() async throws {
        for version in [3, 99] {
            let url = tempStoreURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let rawData = Data("{\"schemaVersion\":\(version),\"devices\":[]}".utf8)
            try rawData.write(to: url)

            let repo = FileNetworkInventoryRepository(fileURL: url)
            do {
                _ = try await repo.devices()
                XCTFail("Deveria falhar para schema \(version)")
            } catch let error as NetworkInventoryError {
                XCTAssertEqual(error, .unsupportedSchema(version))
            }

            // Arquivo não pode ter sido alterado
            XCTAssertEqual(try Data(contentsOf: url), rawData)
        }
    }

    func testFileRepositoryCorruptedStorePreservesFile() async throws {
        let url = tempStoreURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corruptedData = Data("{\"schemaVersion\": 2, \"devices\": [\"invalid\"]}".utf8)
        try corruptedData.write(to: url)

        let repo = FileNetworkInventoryRepository(fileURL: url)
        do {
            _ = try await repo.devices()
            XCTFail("Deveria falhar com corruptedStore")
        } catch let error as NetworkInventoryError {
            XCTAssertEqual(error, .corruptedStore)
        }

        XCTAssertEqual(try Data(contentsOf: url), corruptedData)
    }

    // MARK: - 6. Topologia Mesh e Rejeição de Duplicatas

    func testTopologyMeshToleranceAndDisallowDuplicates() async throws {
        let url = tempStoreURL()
        let repo = FileNetworkInventoryRepository(fileURL: url)

        let devA = RegisteredNetworkDevice(identity: .init(model: "Node-A"))
        let devB = RegisteredNetworkDevice(identity: .init(model: "Node-B"))
        let devC = RegisteredNetworkDevice(identity: .init(model: "Node-C"))

        _ = try await repo.save(devA)
        _ = try await repo.save(devB)
        _ = try await repo.save(devC)

        // Conexão A-B Wi-Fi
        let connAB = DeviceConnection(
            endpointADeviceID: devA.id,
            endpointBDeviceID: devB.id,
            medium: .wifi
        )
        _ = try await repo.saveConnection(connAB)

        // Duplicata B-A com mesmo meio Wi-Fi deve falhar
        let connBAWifi = DeviceConnection(
            endpointADeviceID: devB.id,
            endpointBDeviceID: devA.id,
            medium: .wifi
        )
        do {
            _ = try await repo.saveConnection(connBAWifi)
            XCTFail("Deveria rejeitar conexão duplicada")
        } catch let error as NetworkInventoryError {
            XCTAssertEqual(error, .duplicateConnection)
        }

        // Conexão com mesmo par mas meio distinto (Ethernet) deve ser aceita
        let connABEth = DeviceConnection(
            endpointADeviceID: devA.id,
            endpointBDeviceID: devB.id,
            medium: .ethernet
        )
        _ = try await repo.saveConnection(connABEth)

        // Ciclo Mesh: B-C e C-A
        let connBC = DeviceConnection(
            endpointADeviceID: devB.id,
            endpointBDeviceID: devC.id,
            medium: .wifi
        )
        let connCA = DeviceConnection(
            endpointADeviceID: devC.id,
            endpointBDeviceID: devA.id,
            medium: .wifi
        )
        _ = try await repo.saveConnection(connBC)
        _ = try await repo.saveConnection(connCA)

        // Verifica que todas as conexões persistem e são recarregadas
        let reloadedRepo = FileNetworkInventoryRepository(fileURL: url)
        let allConns = try await reloadedRepo.connections()
        XCTAssertEqual(allConns.count, 4) // (A-B wifi, A-B eth, B-C wifi, C-A wifi)
    }

    func testSaveConnectionRejectsNonexistentEndpoints() async throws {
        let url = tempStoreURL()
        let repo = FileNetworkInventoryRepository(fileURL: url)

        let devA = RegisteredNetworkDevice(identity: .init(model: "Node-A"))
        _ = try await repo.save(devA)

        let nonexistentID1 = UUID()
        let nonexistentID2 = UUID()

        // 1. Ambos os endpoints inexistentes
        let connBothMissing = DeviceConnection(
            endpointADeviceID: nonexistentID1,
            endpointBDeviceID: nonexistentID2,
            medium: .wifi
        )
        do {
            _ = try await repo.saveConnection(connBothMissing)
            XCTFail("Deveria rejeitar conexão com endpoints inexistentes")
        } catch let error as NetworkInventoryError {
            XCTAssertEqual(error, .invalidConnection)
        }

        // 2. Endpoint B inexistente
        let connBMissing = DeviceConnection(
            endpointADeviceID: devA.id,
            endpointBDeviceID: nonexistentID1,
            medium: .wifi
        )
        do {
            _ = try await repo.saveConnection(connBMissing)
            XCTFail("Deveria rejeitar conexão com endpoint B inexistente")
        } catch let error as NetworkInventoryError {
            XCTAssertEqual(error, .invalidConnection)
        }

        // 3. Endpoint A inexistente
        let connAMissing = DeviceConnection(
            endpointADeviceID: nonexistentID1,
            endpointBDeviceID: devA.id,
            medium: .wifi
        )
        do {
            _ = try await repo.saveConnection(connAMissing)
            XCTFail("Deveria rejeitar conexão com endpoint A inexistente")
        } catch let error as NetworkInventoryError {
            XCTAssertEqual(error, .invalidConnection)
        }
    }

    // MARK: - 7. Cascata Atômica na Remoção de Dispositivo

    func testAtomicCascadeRemovalOfDeviceCleansConnections() async throws {
        let profileURL = tempStoreURL()
        let inventoryURL = tempStoreURL()

        let profiles = FileNetworkProfileRepository(fileURL: profileURL)
        let inventory = FileNetworkInventoryRepository(fileURL: inventoryURL)
        let household = HouseholdRepository(profiles: profiles, inventory: inventory)

        let devA = try await household.saveDevice(.init(identity: .init(model: "Router-A")))
        let devB = try await household.saveDevice(.init(identity: .init(model: "Satellite-B")))
        let devC = try await household.saveDevice(.init(identity: .init(model: "Satellite-C")))

        _ = try await household.saveConnection(.init(
            endpointADeviceID: devA.id,
            endpointBDeviceID: devB.id,
            medium: .wifi
        ))
        _ = try await household.saveConnection(.init(
            endpointADeviceID: devB.id,
            endpointBDeviceID: devC.id,
            medium: .wifi
        ))

        let initialCount = try await household.connections().count
        XCTAssertEqual(initialCount, 2)

        // Remove devB: deve remover automaticamente as conexões A-B e B-C
        try await household.removeDevice(id: devB.id, expectedRevision: devB.revision)

        let remainingConns = try await household.connections()
        XCTAssertEqual(remainingConns.count, 0)

        let reloadedHousehold = HouseholdRepository(
            profiles: FileNetworkProfileRepository(fileURL: profileURL),
            inventory: FileNetworkInventoryRepository(fileURL: inventoryURL)
        )
        let reloadedCount = try await reloadedHousehold.connections().count
        XCTAssertEqual(reloadedCount, 0)
    }

    // MARK: - 8. Remoção de Plano Desassocia Perfil Doméstico

    func testPlanRemovalUnlinksActivePlanFromProfile() async throws {
        let profileURL = tempStoreURL()
        let inventoryURL = tempStoreURL()

        let household = HouseholdRepository(
            profiles: FileNetworkProfileRepository(fileURL: profileURL),
            inventory: FileNetworkInventoryRepository(fileURL: inventoryURL)
        )

        let plan = try await household.savePlan(.init(
            ispName: "Operadora Teste",
            technology: .fiber
        ))

        let profile = try await household.saveHomeProfile(.init(
            displayName: "Casa",
            activePlanID: plan.id
        ))
        XCTAssertEqual(profile.activePlanID, plan.id)

        // Remove plano
        try await household.removePlan(id: plan.id)

        let updatedProfile = try await household.homeProfile()
        XCTAssertNotNil(updatedProfile)
        XCTAssertNil(updatedProfile?.activePlanID)
    }

    // MARK: - 9. Invariantes de Associação em Perfil Doméstico

    func testSaveHomeProfileRejectsNonexistentActivePlan() async throws {
        let url = tempStoreURL()
        let repo = FileNetworkInventoryRepository(fileURL: url)

        let unknownPlanID = UUID()
        let profile = HomeNetworkProfile(
            displayName: "Casa Sem Plano Válido",
            activePlanID: unknownPlanID
        )

        do {
            _ = try await repo.saveHomeProfile(profile)
            XCTFail("Deveria rejeitar perfil doméstico com plano ativo inexistente")
        } catch let error as NetworkInventoryError {
            XCTAssertEqual(error, .invalidProfile)
        }

        // Verifica também através do HouseholdRepository
        let profileURL = tempStoreURL()
        let household = HouseholdRepository(
            profiles: FileNetworkProfileRepository(fileURL: profileURL),
            inventory: repo
        )
        do {
            _ = try await household.saveHomeProfile(profile)
            XCTFail("Deveria rejeitar perfil doméstico com plano ativo inexistente via HouseholdRepository")
        } catch let error as NetworkInventoryError {
            XCTAssertEqual(error, .invalidProfile)
        }
    }
}

private struct VersionHeaderCheck: Decodable {
    let schemaVersion: Int
}
