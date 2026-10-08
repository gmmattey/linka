import Foundation
import Combine
import NetworkInventory

/// Owns only an editable draft. Neither OCR nor a late network response writes storage.
@MainActor
final class DeviceEditorSession: ObservableObject {
    @Published var draft: RegisteredNetworkDevice {
        didSet {
            if oldValue.id != draft.id || oldValue.identity != draft.identity { identityChanged() }
        }
    }
    @Published private(set) var researching = false
    @Published private(set) var recognizing = false
    @Published var proposal: DeviceSpecificationSnapshot?
    @Published var candidates: [DeviceIdentity] = []
    @Published var message: String?
    private var queryTask: Task<Void, Never>?
    private var ocrTask: Task<Void, Never>?
    private var generation = UUID()
    private var ocrGeneration = UUID()
    private let enrichment: (any DeviceSpecEnrichmentService)?
    private let ocr: any DeviceLabelOCRService
    private(set) var isActive = true
    init(device: RegisteredNetworkDevice, enrichment: (any DeviceSpecEnrichmentService)? = nil, ocr: any DeviceLabelOCRService = VisionDeviceLabelOCR()) {
        draft = device; self.ocr = ocr
        self.enrichment = enrichment ?? Self.endpoint.map { HTTPDeviceSpecEnrichmentService(endpoint: $0) }
    }
    /// Terminal lifecycle event (dismissal/deletion). Late photo imports cannot start another task.
    func deactivate() { isActive = false; cancel() }

    func identityChanged() {
        cancel()
        // A specification for a previous model must never follow an identity edit.
        if let saved = draft.specifications, !saved.identity.matches(draft.identity) { draft.specifications = nil }
    }
    func cancel() {
        generation = UUID(); ocrGeneration = UUID()
        queryTask?.cancel(); ocrTask?.cancel(); queryTask = nil; ocrTask = nil
        researching = false; recognizing = false; proposal = nil; candidates = []
    }
    func recognize(_ data: Data) {
        guard isActive else { return }
        let identity = draft.identity; let deviceID = draft.id; let ocr = self.ocr
        ocrTask?.cancel()
        let token = UUID(); ocrGeneration = token
        recognizing = true; message = nil
        ocrTask = Task { [weak self] in
            do {
                let found = try await ocr.candidates(from: data)
                guard let self, !Task.isCancelled, self.isActive, self.ocrGeneration == token, self.draft.id == deviceID, self.draft.identity == identity else { return }
                self.recognizing = false
                self.candidates = found.map(\.identity)
                if found.isEmpty { self.message = LinkaCopy.value("inventory.ocr.empty") }
            } catch {
                guard let self, !Task.isCancelled, self.isActive, self.ocrGeneration == token, self.draft.id == deviceID, self.draft.identity == identity else { return }
                self.recognizing = false; self.message = LinkaCopy.value("inventory.ocr.failed")
            }
        }
    }
    func research() {
        guard isActive, draft.identity.isValid else { return }
        cancel()
        guard let enrichment else { message = LinkaCopy.value("inventory.research.unavailable"); return }
        let identity = draft.identity; let deviceID = draft.id; let token = UUID(); generation = token
        researching = true; message = nil
        queryTask = Task { [weak self] in
            do {
                let result = try await enrichment.enrich(identity: identity)
                guard let self, !Task.isCancelled, self.isActive, self.generation == token, self.draft.id == deviceID, self.draft.identity == identity else { return }
                try result.validate(for: identity)
                self.researching = false
                if result.status == .unavailable || result.status == .notFound {
                    self.message = LinkaCopy.value("inventory.research.empty")
                } else { self.proposal = result }
            } catch {
                guard let self, !Task.isCancelled, self.isActive, self.generation == token, self.draft.id == deviceID, self.draft.identity == identity else { return }
                self.researching = false; self.message = LinkaCopy.value("inventory.research.failed")
            }
        }
    }
    private static var endpoint: URL? {
        // Internal builds only, no default host and no public activation via preferences.
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment["LINKA_DEVICE_SPEC_ENDPOINT"],
              let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
        #else
        return nil
        #endif
    }
}
