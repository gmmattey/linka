import XCTest
import NetworkInventory
import NetworkProfiles
@testable import LinkaApp

@MainActor
final class LinkaInventoryStoreV2Tests: XCTestCase {
    private var tempDir: URL!
    private var repository: HouseholdRepository!
    private var store: LinkaInventoryStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("linka-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let profilesRepo = FileNetworkProfileRepository(fileURL: tempDir.appendingPathComponent("profiles.json"))
        let inventoryRepo = FileNetworkInventoryRepository(fileURL: tempDir.appendingPathComponent("inventory.json"))
        repository = HouseholdRepository(profiles: profilesRepo, inventory: inventoryRepo)
        store = LinkaInventoryStore(repository: repository)
        await store.reload()
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Plans

    func testSavePlanAndSetAsActivePlan() async {
        let plan = NetworkServicePlan(
            ispName: "Claro Fibra",
            planName: "500 Mega",
            nominalDownloadMbps: 500,
            nominalUploadMbps: 250,
            technology: .fiber,
            monthlyCostCents: 9990,
            currencyCode: "BRL"
        )

        let success = await store.savePlan(plan, makeActive: true)
        XCTAssertTrue(success)
        XCTAssertEqual(store.plans.count, 1)
        XCTAssertNotNil(store.activePlan)
        XCTAssertEqual(store.activePlan?.ispName, "Claro Fibra")
        XCTAssertEqual(store.activePlan?.nominalDownloadMbps, 500)
        XCTAssertEqual(store.homeProfile?.activePlanID, plan.id)
    }

    func testReplacePlanClosesPreviousPlanAndActivatesNew() async {
        let planA = NetworkServicePlan(
            ispName: "Oi Fibra",
            nominalDownloadMbps: 400,
            nominalUploadMbps: 200,
            technology: .fiber
        )
        let savedA = await store.savePlan(planA, makeActive: true)
        XCTAssertTrue(savedA)
        XCTAssertEqual(store.activePlan?.id, planA.id)

        let planB = NetworkServicePlan(
            ispName: "Vivo Fibra",
            nominalDownloadMbps: 600,
            nominalUploadMbps: 300,
            technology: .fiber
        )
        let replaceSuccess = await store.replacePlan(current: planA, with: planB)
        XCTAssertTrue(replaceSuccess)
        XCTAssertEqual(store.plans.count, 2)
        XCTAssertEqual(store.activePlan?.id, planB.id)

        let previous = store.plans.first(where: { $0.id == planA.id })
        XCTAssertNotNil(previous?.effectiveTo)
        XCTAssertNotNil(store.activePlan?.effectiveFrom)
    }

    func testDeletePlanClearsActivePlanFromProfile() async {
        let plan = NetworkServicePlan(
            ispName: "Local Net",
            nominalDownloadMbps: 100,
            nominalUploadMbps: 50,
            technology: .fixedWireless
        )
        _ = await store.savePlan(plan, makeActive: true)
        XCTAssertEqual(store.activePlan?.id, plan.id)

        let deleted = await store.deletePlan(id: plan.id)
        XCTAssertTrue(deleted)
        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertNil(store.activePlan)
        XCTAssertNil(store.homeProfile?.activePlanID)
    }

    // MARK: - Connections

    func testSaveAndQueryDeviceConnections() async {
        let dev1 = RegisteredNetworkDevice(identity: .init(brand: "TP-Link", model: "Archer C6"))
        let dev2 = RegisteredNetworkDevice(identity: .init(brand: "Intelbras", model: "Twibi Fast"))
        let saved1 = await store.save(dev1)
        let saved2 = await store.save(dev2)
        XCTAssertTrue(saved1)
        XCTAssertTrue(saved2)

        let connection = DeviceConnection(
            endpointADeviceID: dev1.id,
            endpointBDeviceID: dev2.id,
            medium: .ethernet,
            sourceDeviceID: dev1.id
        )

        let savedConn = await store.saveConnection(connection)
        XCTAssertTrue(savedConn)
        XCTAssertEqual(store.connections.count, 1)

        let dev1Conns = store.connections(for: dev1.id)
        XCTAssertEqual(dev1Conns.count, 1)
        XCTAssertEqual(dev1Conns.first?.sourceDeviceID, dev1.id)

        let dev2Conns = store.connections(for: dev2.id)
        XCTAssertEqual(dev2Conns.count, 1)

        let deleted = await store.deleteConnection(id: connection.id)
        XCTAssertTrue(deleted)
        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertTrue(store.connections(for: dev1.id).isEmpty)
    }

    func testDuplicateConnectionReturnsError() async {
        let dev1 = RegisteredNetworkDevice(identity: .init(brand: "A", model: "M1"))
        let dev2 = RegisteredNetworkDevice(identity: .init(brand: "B", model: "M2"))
        _ = await store.save(dev1)
        _ = await store.save(dev2)

        let conn1 = DeviceConnection(
            endpointADeviceID: dev1.id,
            endpointBDeviceID: dev2.id,
            medium: .wifi
        )
        let conn2 = DeviceConnection(
            endpointADeviceID: dev2.id,
            endpointBDeviceID: dev1.id,
            medium: .wifi
        )

        let saved1 = await store.saveConnection(conn1)
        XCTAssertTrue(saved1)

        let saved2 = await store.saveConnection(conn2)
        XCTAssertFalse(saved2)
        XCTAssertNotNil(store.error)
    }

    // MARK: - Environments & Consolidated Helpers

    func testDeviceLinkedToEnvironmentReload() async throws {
        guard let env = NetworkEnvironment(name: "Sala") else {
            XCTFail("Failed to initialize NetworkEnvironment")
            return
        }
        try await repository.create(env)
        await store.reload()
        XCTAssertEqual(store.environments.count, 1)
        XCTAssertEqual(store.environments.first?.name, "Sala")

        var dev = RegisteredNetworkDevice(identity: .init(brand: "TP-Link", model: "Archer AX50"))
        dev.installation.environmentID = env.id
        let saved = await store.save(dev)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.devices.first?.installation.environmentID, env.id)

        let matchingEnv = store.environments.first(where: { $0.id == store.devices.first?.installation.environmentID })
        XCTAssertEqual(matchingEnv?.name, "Sala")
    }

    func testConnectionDirectionEndpointOrdering() async {
        let devA = RegisteredNetworkDevice(identity: .init(brand: "Modem", model: "FiberGateway"))
        let devB = RegisteredNetworkDevice(identity: .init(brand: "Mesh", model: "Deco X20"))
        _ = await store.save(devA)
        _ = await store.save(devB)

        // Internet flowing from A to B
        let connAtoB = DeviceConnection(
            endpointADeviceID: devA.id,
            endpointBDeviceID: devB.id,
            medium: .ethernet,
            sourceDeviceID: devA.id
        )
        let savedAtoB = await store.saveConnection(connAtoB)
        XCTAssertTrue(savedAtoB)

        let retrieved = store.connections.first
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.sourceDeviceID, devA.id)

        // If source is B, origin device should be B
        let connBtoA = DeviceConnection(
            endpointADeviceID: devA.id,
            endpointBDeviceID: devB.id,
            medium: .wifi,
            sourceDeviceID: devB.id
        )
        let savedBtoA = await store.saveConnection(connBtoA)
        XCTAssertTrue(savedBtoA)
        XCTAssertEqual(store.connections.count, 2)

        let retrievedBtoA = store.connections.first(where: { $0.id == connBtoA.id })
        XCTAssertEqual(retrievedBtoA?.sourceDeviceID, devB.id)
    }
}
