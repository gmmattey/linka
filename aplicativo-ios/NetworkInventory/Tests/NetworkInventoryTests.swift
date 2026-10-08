import XCTest
@testable import NetworkInventory
import NetworkProfiles
final class NetworkInventoryTests: XCTestCase {
    func path() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("inventory.json") }
    func testRestartConflictAndDeletedRecordCannotBeRecreatedByStaleSave() async throws {
        let url = path(); let repo = FileNetworkInventoryRepository(fileURL: url)
        let first = try await repo.save(.init(identity: .init(model: "C6")))
        let restored = try await FileNetworkInventoryRepository(fileURL: url).devices()
        XCTAssertEqual(restored, [first])
        var edit = first; edit.nickname = "Sala"
        let second = try await repo.save(edit, expectedRevision: first.revision)
        do { _ = try await repo.save(edit, expectedRevision: first.revision); XCTFail() } catch { XCTAssertEqual(error as? NetworkInventoryError, .conflict) }
        try await repo.remove(id: first.id, expectedRevision: second.revision)
        do { _ = try await repo.save(edit, expectedRevision: first.revision); XCTFail() } catch { XCTAssertEqual(error as? NetworkInventoryError, .notFound) }
    }
    func testCorruptionAndUnknownVersionArePreserved() async throws {
        for bytes in [Data("broken".utf8), Data("{\"schemaVersion\":99,\"devices\":[]}".utf8)] {
            let url = path(); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try bytes.write(to: url)
            do { _ = try await FileNetworkInventoryRepository(fileURL: url).save(.init(identity: .init(model: "C6"))); XCTFail() } catch {}
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
    func testEnvironmentDeletionPreservesLabelAndDoesNotAllowStaleLink() async throws {
        let profiles = FileNetworkProfileRepository(fileURL: path()); let inventory = FileNetworkInventoryRepository(fileURL: path())
        let home = HouseholdRepository(profiles: profiles, inventory: inventory)
        let environment = NetworkEnvironment(name: "Sala")!
        try await home.create(environment)
        let value = try await home.saveDevice(.init(identity: .init(model: "C6"), installation: .init(environmentID: environment.id)))
        try await home.rename(id: environment.id, to: "Escritório", updatedAt: Date())
        try await home.remove(id: environment.id)
        let saved = try await home.device(id: value.id)
        XCTAssertNil(saved?.installation.environmentID); XCTAssertEqual(saved?.installation.locationLabel, "Escritório")
        do { _ = try await home.saveDevice(value, expectedRevision: value.revision); XCTFail() } catch {}
    }
    func testConcurrentSaveAndDeleteNeverLeaveOrphan() async throws {
        for _ in 0..<20 {
            let profiles = FileNetworkProfileRepository(fileURL: path()); let inventory = FileNetworkInventoryRepository(fileURL: path())
            let home = HouseholdRepository(profiles: profiles, inventory: inventory)
            let environment = NetworkEnvironment(name: "Sala")!; try await home.create(environment)
            let value = RegisteredNetworkDevice(identity: .init(model: "C6"), installation: .init(environmentID: environment.id))
            async let save: Void = { _ = try? await home.saveDevice(value) }()
            async let remove: Void = { try? await home.remove(id: environment.id) }()
            _ = await (save, remove)
            let values = try await home.devices(); XCTAssertTrue(values.allSatisfy { $0.installation.environmentID == nil })
        }
    }
    func testEvidenceVariantAndTypedValues() throws {
        let identity = DeviceIdentity(brand: "TP-Link", model: "C6", hardwareRevision: "V3")
        let source = SpecificationSource(id: "s1", url: URL(string: "https://www.tp-link.com/spec")!, title: "Ficha", matchedIdentity: identity)
        var snapshot = DeviceSpecificationSnapshot(identity: identity, status: .partial, attributes: [.init(key: "supportsMesh", value: "true", evidenceIDs: ["s1"])], sources: [source])
        XCTAssertNoThrow(try snapshot.validate(for: identity))
        snapshot.attributes[0].value = "probably"; XCTAssertThrowsError(try snapshot.validate(for: identity))
        snapshot.attributes[0].value = "true"; snapshot.sources[0].matchedIdentity.hardwareRevision = "V2"
        XCTAssertThrowsError(try snapshot.validate(for: identity))
        snapshot.sources[0] = source; snapshot.attributes[0].evidenceIDs = []
        XCTAssertThrowsError(try snapshot.validate(for: identity))
    }
    func testCancelledEnrichmentDoesNotDispatch() async throws {
        let service = HTTPDeviceSpecEnrichmentService(endpoint: URL(string: "https://example.invalid/lookup")!)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.enrich(identity: .init(model: "C6"))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail("Expected cancellation") }
    }
    func testOrphanRecoveryAfterRestartRetainsManualLabel() async throws {
        let url = path(); let id = UUID()
        _ = try await FileNetworkInventoryRepository(fileURL: url).save(.init(identity: .init(model: "C6"), installation: .init(environmentID: id, locationLabel: "Sala")))
        let home = HouseholdRepository(profiles: FileNetworkProfileRepository(fileURL: path()), inventory: FileNetworkInventoryRepository(fileURL: url))
        let values = try await home.devices()
        XCTAssertNil(values.first?.installation.environmentID)
        XCTAssertEqual(values.first?.installation.locationLabel, "Sala")
        let persisted = try await FileNetworkInventoryRepository(fileURL: url).devices()
        XCTAssertNil(persisted.first?.installation.environmentID)
    }
    func testStructuredCapabilitiesRejectInvalidUnitsAndUnknownValues() throws {
        let identity = DeviceIdentity(model: "C6")
        let source = SpecificationSource(id: "s", url: URL(string: "https://example.com/spec")!, title: "Spec", matchedIdentity: identity)
        var snapshot = DeviceSpecificationSnapshot(identity: identity, status: .partial, attributes: [.init(key: "radioCapabilities", value: #"[{"bandGHz":5,"maxChannelWidthMHz":80,"maxPhyRateMbps":867,"spatialStreams":2}]"#, evidenceIDs: ["s"])], sources: [source])
        XCTAssertNoThrow(try snapshot.validate(for: identity))
        snapshot.attributes[0].value = #"[{"bandGHz":5,"spatialStreams":true}]"#
        XCTAssertThrowsError(try snapshot.validate(for: identity))
        snapshot.attributes[0].value = #"[{"bandGHz":5}]"#
        XCTAssertThrowsError(try snapshot.validate(for: identity))
        snapshot.attributes[0] = .init(key: "ethernetPorts", value: #"[{"role":"wan","portCount":1,"speedMbps":1000}]"#, evidenceIDs: ["s"])
        XCTAssertNoThrow(try snapshot.validate(for: identity))
        snapshot.attributes[0].value = #"[{"role":"wan","portCount":1,"speedMbps":0}]"#
        XCTAssertThrowsError(try snapshot.validate(for: identity))
    }
    func testMeshAndFirmwareRejectFreeText() throws {
        let identity = DeviceIdentity(model: "C6")
        let source = SpecificationSource(id: "s", url: URL(string: "https://example.com/spec")!, title: "Spec", matchedIdentity: identity)
        var snapshot = DeviceSpecificationSnapshot(identity: identity, status: .partial, attributes: [.init(key: "meshTechnology", value: "easyMesh", evidenceIDs: ["s"])], sources: [source])
        XCTAssertNoThrow(try snapshot.validate(for: identity))
        snapshot.attributes[0].value = "probably supports all mesh"
        XCTAssertThrowsError(try snapshot.validate(for: identity))
        snapshot.attributes[0] = .init(key: "firmwareSupportStatus", value: "supported", evidenceIDs: ["s"])
        XCTAssertNoThrow(try snapshot.validate(for: identity))
        snapshot.attributes[0].value = "Visit a suspicious link"
        XCTAssertThrowsError(try snapshot.validate(for: identity))
    }
    func testMainRouterNoAndUnknownStayDistinctAndLegacyDecodes() async throws {
        let repo = FileNetworkInventoryRepository(fileURL: path())
        let no = try await repo.save(.init(identity: .init(model: "C6"), installation: .init(mainRouterAnswer: .no)))
        XCTAssertEqual(no.installation.mainRouterAnswer, .no)
        let legacy = Data(#"{"role":"unknown","ownership":"unknown","fiberDirectConnected":"unknown"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(DeviceInstallation.self, from: legacy).mainRouterAnswer, .unknown)
        var bad = no; bad.installation.mainRouterAnswer = .yes
        do { _ = try await repo.save(bad, expectedRevision: no.revision); XCTFail() } catch { XCTAssertEqual(error as? NetworkInventoryError, .invalidDevice) }
    }
    func testOCRReturnsAllDistinctModelsWithoutGuessingRevision() {
        let values = DeviceLabelParser.candidates(from: ["TP-Link", "Model: C6", "Model: C7", "Model: C6", "Ver: V3"])
        XCTAssertEqual(values.map { $0.identity.model }, ["C6", "C7"])
        XCTAssertTrue(values.allSatisfy { $0.identity.hardwareRevision == nil })
    }
    func testPartialEnvironmentRemovalPreservesLabelAndReportsPartialFailure() async throws {
        let url = path(); let profiles = FileNetworkProfileRepository(fileURL: url)
        let home = HouseholdRepository(profiles: profiles, inventory: FileNetworkInventoryRepository(fileURL: path()))
        let environment = NetworkEnvironment(name: "Sala")!; try await home.create(environment)
        _ = try await home.saveDevice(.init(identity: .init(model: "C6"), installation: .init(environmentID: environment.id)))
        try FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        do { try await home.remove(id: environment.id); XCTFail() } catch { XCTAssertEqual(error as? NetworkInventoryError, .partialEnvironmentRemoval) }
        let devices = try await home.devices(); let remaining = try await home.environment(id: environment.id)
        XCTAssertNil(devices.first?.installation.environmentID)
        XCTAssertEqual(devices.first?.installation.locationLabel, "Sala"); XCTAssertNotNil(remaining)
    }
    func testDiskFailureDoesNotPublishUnpersistedDevice() async throws {
        let directory = path(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("store.json")
        let repo = FileNetworkInventoryRepository(fileURL: url)
        let first = try await repo.save(.init(identity: .init(model: "C6")))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        var edit = first; edit.nickname = "Unsaved"
        do { _ = try await repo.save(edit, expectedRevision: first.revision); XCTFail() } catch { XCTAssertEqual(error as? NetworkInventoryError, .persistenceFailed) }
        let retained = try await repo.device(id: first.id)
        XCTAssertEqual(retained, first)
    }
    func testMergedOCRCredentialsNeverBecomeModel() {
        for line in ["Model: Archer C6 WPS PIN : 12345670", "Model: AX3000 Wi-Fi Key: segredo", "Modelo: AX3000 Senha : segredo", "Model: AX3000 S / N : ABC", "Model: AX3000 SSID casa", "Model: AX3000 PSK segredo", "Model: AX3000 passphrase segredo"] {
            XCTAssertTrue(DeviceLabelParser.candidates(from: [line]).isEmpty, line)
        }
    }
    func testOCRDoesNotReturnSecretsOrInventUnlabelledModel() {
        XCTAssertTrue(DeviceLabelParser.candidates(from: ["Senha: abc", "C6", "SSID: casa"]).isEmpty)
        let values = DeviceLabelParser.candidates(from: ["TP-Link", "Model: Archer C6", "Ver: V3", "Password: secret"])
        XCTAssertEqual(values.first?.identity, .init(brand: "TP-Link", model: "Archer C6", hardwareRevision: "V3"))
    }
}
