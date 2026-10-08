import XCTest
import NetworkInventory
import NetworkProfiles
@testable import LinkaApp

private actor DeferredDeviceLookup: DeviceSpecResearchService {
    private var pending: [CheckedContinuation<DeviceResearchResult, Error>] = []
    private(set) var calls = 0
    func research(_ request: DeviceResearchQuery) async throws -> DeviceResearchResult {
        calls += 1
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func resolve(_ result: DeviceResearchResult) { pending.removeFirst().resume(returning: result) }
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
    private func result(status: DeviceResearchStatus = .available, query: String = "TP-Link Archer C6") -> DeviceResearchResult {
        let json = #"{"id":"s1","url":"https://example.com/manual","title":"Manual","retrievedAt":0}"#
        let source = try! JSONDecoder().decode(DeviceResearchSource.self, from: Data(json.utf8))
        return .init(query: query, status: status, reason: status == .notFound ? .noDocumentedData : status == .unavailable ? .providerFailure : nil,
                     identity: status == .available ? identity : nil,
                     attributes: status == .available ? [.init(key: "lanPorts", value: "4", evidenceIDs: ["s1"])] : [],
                     sources: status == .available ? [source] : [])
    }
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
        await lookup.resolve(result()); await settle()
        XCTAssertNil(session.proposal); XCTAssertFalse(session.researching)
        XCTAssertNil(session.draft.specifications)
    }
    func testCancelledResearchRejectsResponseFromServiceIgnoringCancellation() async {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup)
        session.research(); await awaitLookup(lookup); session.cancel()
        await lookup.resolve(result()); await settle()
        XCTAssertNil(session.proposal); XCTAssertNil(session.message)
    }
    func testDeletedOrDismissedSessionCannotRestartFromLatePhotoImport() async {
        let lookup = DeferredDeviceLookup(); let ocr = DeferredDeviceOCR()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup, ocr: ocr)
        session.research(); await awaitLookup(lookup); session.deactivate()
        session.recognize(Data([1])); session.research()
        await lookup.resolve(result()); await settle()
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
        await lookup.resolve(result(status: .notFound)); await settle()
        XCTAssertTrue(session.researching); XCTAssertNil(session.message)
        await lookup.resolve(result()); await settle()
        XCTAssertEqual(session.proposal?.identity, identity); XCTAssertFalse(session.researching)
    }
    func testInjectedInvalidProposalStillRejected() async {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup)
        session.research(); await awaitLookup(lookup)
        await lookup.resolve(result(query: "Wrong")); await settle()
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
        await lookup.resolve(result(status: .unavailable)); await settle()
        XCTAssertEqual(session.message, LinkaCopy.value("inventory.research.unavailable"))
        XCTAssertNil(session.proposal)
        session.research(); await awaitLookup(lookup, count: 2)
        await lookup.resolve(result(status: .notFound)); await settle()
        XCTAssertEqual(session.message, LinkaCopy.value("inventory.research.empty"))
        XCTAssertNil(session.proposal)
    }
    func testSingleFieldAcceptsNokiaWithoutRequiredTechnicalDetails() {
        let session = DeviceEditorSession(device: .init(kind: .other, identity: .init(model: "")))
        session.identification = "NOKIA G-1425-B"
        XCTAssertTrue(session.canResearch)
        XCTAssertTrue(session.canSave)
        XCTAssertEqual(session.preparedForSaving().identity.model, "NOKIA G-1425-B")
        XCTAssertNil(session.preparedForSaving().specifications)
    }
    func testSavingConfirmsProposalInOneStepWithoutMutatingDraft() async {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(identity: identity), enrichment: lookup)
        session.research(); await awaitLookup(lookup)
        await lookup.resolve(result()); await settle()
        XCTAssertNil(session.draft.specifications)
        XCTAssertEqual(session.preparedForSaving().specifications?.attributes.first?.key, "lanPorts")
        session.cancel()
        XCTAssertNil(session.draft.specifications)
    }
    func testQueryEditClearsProposalAndDoesNotDestroyOriginalRecord() async {
        let lookup = DeferredDeviceLookup()
        let original = RegisteredNetworkDevice(identity: identity, specifications: result().proposedSnapshot)
        let session = DeviceEditorSession(device: original, enrichment: lookup)
        session.identification = "NOKIA G-1425-B"
        XCTAssertNil(session.draft.specifications)
        XCTAssertNotNil(original.specifications)
        session.deactivate()
        XCTAssertEqual(original.specifications?.identity, identity)
    }
    func testConfirmingSameAmbiguousModelDoesNotRepeatLookupAndCanSaveWithoutSpecs() async throws {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(kind: .other, identity: .init(model: "NOKIA   G-1425-B")), enrichment: lookup)
        session.research(); await awaitLookup(lookup)
        let candidateJSON = #"[{"id":"same","label":"Nokia G-1425-B","identity":{"brand":"Nokia","model":"G-1425-B"},"evidenceIDs":["s1"]},{"id":"other","label":"Nokia G-1425G-B","identity":{"brand":"Nokia","model":"G-1425G-B"},"evidenceIDs":["s1"]}]"#
        let candidates = try JSONDecoder().decode([DeviceResearchCandidate].self, from: Data(candidateJSON.utf8))
        let ambiguous = DeviceResearchResult(query: "NOKIA   G-1425-B", status: .ambiguous, reason: .multipleMatches, candidates: candidates, sources: result().sources)
        await lookup.resolve(ambiguous); await settle()
        XCTAssertEqual(session.researchResult?.status, .ambiguous)
        session.selectResearchCandidate(candidates[0].identity)
        await settle()
        let calls = await lookup.calls
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(session.researching)
        XCTAssertEqual(session.draft.identity, candidates[0].identity)
        XCTAssertEqual(session.message, LinkaCopy.value("inventory.research.empty"))
        XCTAssertNil(session.proposal)
        XCTAssertNil(session.researchResult)
        XCTAssertTrue(session.canSave)
        XCTAssertTrue(session.canResearch)
        XCTAssertNil(session.preparedForSaving().specifications)
        // A later explicit search remains available.
        session.research(); await awaitLookup(lookup, count: 2)
        await lookup.resolve(.init(query: "Nokia G-1425-B", status: .notFound, reason: .noDocumentedData)); await settle()
        XCTAssertFalse(session.researching)
    }
    func testChoosingDifferentModelStartsResearchAfterExplicitSelection() async {
        let lookup = DeferredDeviceLookup()
        let session = DeviceEditorSession(device: .init(identity: .init(brand: "Nokia", model: "G-1425-B")), enrichment: lookup)
        session.selectResearchCandidate(.init(brand: "Nokia", model: "G-1425G-B"))
        await awaitLookup(lookup)
        XCTAssertTrue(session.researching)
        XCTAssertEqual(session.draft.identity.model, "G-1425G-B")
        await lookup.resolve(.init(query: "Nokia G-1425G-B", status: .notFound, reason: .noDocumentedData)); await settle()
    }
    func testSameModelWithNewRevisionOrRegionStartsClarifyingLookup() async {
        for candidate in [DeviceIdentity(brand: "Nokia", model: "G-1425-B", hardwareRevision: "V2"),
                          DeviceIdentity(brand: "Nokia", model: "G-1425-B", marketRegion: "BR")] {
            let lookup = DeferredDeviceLookup()
            let session = DeviceEditorSession(device: .init(identity: .init(brand: "Nokia", model: "G-1425-B")), enrichment: lookup)
            session.selectResearchCandidate(candidate)
            await awaitLookup(lookup)
            XCTAssertTrue(session.researching)
            XCTAssertEqual(session.draft.identity, candidate)
            let calls = await lookup.calls
            XCTAssertEqual(calls, 1)
            await lookup.resolve(.init(query: "Nokia G-1425-B", status: .notFound, reason: .noDocumentedData)); await settle()
        }
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
