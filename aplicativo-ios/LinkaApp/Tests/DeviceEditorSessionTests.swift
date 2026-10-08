import XCTest
import NetworkInventory
import NetworkProfiles
@testable import LinkaApp

private actor DeferredDeviceLookup: DeviceSpecEnrichmentService {
    private var pending: [CheckedContinuation<DeviceSpecificationSnapshot, Error>] = []
    private(set) var calls = 0
    func enrich(identity: DeviceIdentity) async throws -> DeviceSpecificationSnapshot {
        calls += 1
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func resolve(_ result: DeviceSpecificationSnapshot) { pending.removeFirst().resume(returning: result) }
}
private actor DeferredDeviceOCR: DeviceLabelOCRService {
    private var pending: [CheckedContinuation<[DeviceLabelCandidate], Error>] = []
    private(set) var calls = 0
    func candidates(from imageData: Data) async throws -> [DeviceLabelCandidate] {
        calls += 1
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func resolve(_ identities: [DeviceIdentity]) { pending.removeFirst().resume(returning: identities.map { .init(identity: $0) }) }
}
@MainActor
final class DeviceEditorSessionTests: XCTestCase {
    private let identity = DeviceIdentity(brand: "TP-Link", model: "Archer C6")
    private func settle() async { for _ in 0..<100 { await Task.yield() } }
    private func awaitLookup(_ service: DeferredDeviceLookup, count: Int = 1) async {
        for _ in 0..<1000 { if await service.calls >= count { return }; await Task.yield() }
        XCTFail("Lookup did not start")
    }
    private func awaitOCR(_ service: DeferredDeviceOCR) async {
        for _ in 0..<1000 { if await service.calls > 0 { return }; await Task.yield() }
        XCTFail("OCR did not start")
    }
    func testEditedIdentityRejectsLateResearchWithoutViewCallback() async {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup)
        session.research(); await awaitLookup(lookup)
        session.draft.identity.model = "Different"
        await lookup.resolve(.init(identity: identity, status: .partial)); await settle()
        XCTAssertNil(session.proposal); XCTAssertFalse(session.researching)
        XCTAssertNil(session.draft.specifications)
    }
    func testCancelledResearchRejectsResponseFromServiceIgnoringCancellation() async {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup)
        session.research(); await awaitLookup(lookup); session.cancel()
        await lookup.resolve(.init(identity: identity, status: .partial)); await settle()
        XCTAssertNil(session.proposal); XCTAssertNil(session.message)
    }
    func testDeletedOrDismissedSessionCannotRestartFromLatePhotoImport() async {
        let lookup = DeferredDeviceLookup(); let ocr = DeferredDeviceOCR()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup, ocr: ocr)
        session.research(); await awaitLookup(lookup); session.deactivate()
        session.recognize(Data([1])); session.research()
        await lookup.resolve(.init(identity: identity, status: .partial)); await settle()
        let ocrCalls = await ocr.calls; let lookupCalls = await lookup.calls
        XCTAssertEqual(ocrCalls, 0); XCTAssertEqual(lookupCalls, 1)
        XCTAssertNil(session.proposal); XCTAssertFalse(session.isActive)
    }
    func testOCRLateResultCannotOverwriteEditedIdentity() async {
        let ocr = DeferredDeviceOCR()
        let session = DeviceEditorSession(device: .init(identity: identity), ocr: ocr)
        session.recognize(Data([1])); await awaitOCR(ocr)
        session.draft.identity.model = "Manual model"
        await ocr.resolve([identity]); await settle()
        XCTAssertTrue(session.candidates.isEmpty); XCTAssertEqual(session.draft.identity.model, "Manual model")
    }
    func testNewResearchWinsWhenOldResponseArrivesFirst() async {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup)
        session.research(); await awaitLookup(lookup)
        session.research(); await awaitLookup(lookup, count: 2)
        await lookup.resolve(.init(identity: identity, status: .notFound)); await settle()
        XCTAssertTrue(session.researching); XCTAssertNil(session.message)
        await lookup.resolve(.init(identity: identity, status: .partial)); await settle()
        XCTAssertEqual(session.proposal?.identity, identity); XCTAssertFalse(session.researching)
    }
    func testInjectedInvalidProposalStillRejected() async {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup)
        session.research(); await awaitLookup(lookup)
        await lookup.resolve(.init(identity: .init(model: "Wrong"), status: .partial)); await settle()
        XCTAssertNil(session.proposal); XCTAssertNotNil(session.message)
    }
    func testDraftLengthValidationPreservesTextAndAllowsBoundary() {
        let session = DeviceEditorSession(device: .init(identity: identity))
        session.draft.nickname = String(repeating: "a", count: 200)
        session.draft.installation.locationLabel = String(repeating: "b", count: 200)
        XCTAssertTrue(session.canSave)
        session.draft.nickname! += "x"
        XCTAssertFalse(session.canSave)
        XCTAssertNotNil(session.draftValidationMessage)
        XCTAssertEqual(session.draft.nickname?.count, 201)
        session.draft.nickname = nil
        session.draft.installation.locationLabel! += "x"
        XCTAssertFalse(session.canSave)
        XCTAssertEqual(session.draft.installation.locationLabel?.count, 201)
        session.draft.installation.locationLabel = nil
        XCTAssertTrue(session.canSave)
    }
    func testUnavailableAndNotFoundHaveDifferentMessages() async {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup)
        session.research(); await awaitLookup(lookup)
        await lookup.resolve(.init(identity: identity, status: .unavailable)); await settle()
        XCTAssertEqual(session.message, LinkaCopy.value("inventory.research.unavailable"))
        XCTAssertNil(session.proposal)
        session.research(); await awaitLookup(lookup, count: 2)
        await lookup.resolve(.init(identity: identity, status: .notFound)); await settle()
        XCTAssertEqual(session.message, LinkaCopy.value("inventory.research.empty"))
        XCTAssertNil(session.proposal)
    }
    func testRetryClearsPartialRemovalWithoutRequiringMeasurement() async {
        let coordinator = OptimizationProfileCoordinator(repository: PartialRemovalProfiles())
        let environment = NetworkEnvironment(name: "Sala")!
        let removed = await coordinator.remove(environment)
        XCTAssertFalse(removed)
        XCTAssertTrue(coordinator.partialRemoval)
        await coordinator.retryStoreAccess()
        XCTAssertFalse(coordinator.partialRemoval)
        XCTAssertFalse(coordinator.hasStoreError)
    }

}

private actor PartialRemovalProfiles: NetworkProfileRepository {
    func environments() async throws -> [NetworkEnvironment] { [] }
    func environment(id: UUID) async throws -> NetworkEnvironment? { nil }
    func create(_ environment: NetworkEnvironment) async throws {}
    func rename(id: UUID, to name: String, updatedAt: Date) async throws {}
    func remove(id: UUID) async throws { throw NetworkInventoryError.partialEnvironmentRemoval }
    func assignment(for measurementID: UUID) async throws -> EnvironmentMeasurementAssignment? { nil }
    func assignments(for environmentID: UUID) async throws -> [EnvironmentMeasurementAssignment] { [] }
    func assign(measurementID: UUID, to environmentID: UUID, assignedAt: Date) async throws {}
    func createAndAssign(_ environment: NetworkEnvironment, measurementID: UUID, assignedAt: Date) async throws {}
}
