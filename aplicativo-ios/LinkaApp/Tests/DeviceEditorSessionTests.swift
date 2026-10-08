import XCTest
import NetworkInventory
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
}
