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
    @Published private(set) var researchResult: DeviceResearchResult?
    @Published var message: String?
    private var queryTask: Task<Void, Never>?
    private var ocrTask: Task<Void, Never>?
    private var generation = UUID()
    private var ocrGeneration = UUID()
    private let enrichment: (any DeviceSpecResearchService)?
    private let ocr: any DeviceLabelOCRService
    private(set) var isActive = true
    init(device: RegisteredNetworkDevice, enrichment: (any DeviceSpecResearchService)? = nil, ocr: any DeviceLabelOCRService = VisionDeviceLabelOCR()) {
        draft = device; self.ocr = ocr
        self.enrichment = enrichment ?? Self.endpoint.map { HTTPDeviceSpecResearchService(endpoint: $0) }
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
        researching = false; recognizing = false; proposal = nil; researchResult = nil; candidates = []; message = nil
    }
    func recognize(_ data: Data) {
        guard isActive else { return }
        let identity = draft.identity; let deviceID = draft.id; let ocr = self.ocr
        ocrTask?.cancel()
        let token = UUID(); ocrGeneration = token
        recognizing = true; message = nil; candidates = []
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
    var draftValidationMessage: String? {
        if (draft.nickname?.count ?? 0) > 200 || (draft.installation.locationLabel?.count ?? 0) > 200 {
            return LinkaCopy.value("inventory.validation.textLength")
        }
        return nil
    }
    var identification: String {
        get { [draft.identity.brand, draft.identity.model].filter { !$0.isEmpty }.joined(separator: " ") }
        set { draft.identity = .init(model: newValue) }
    }
    var canResearch: Bool { researchQuery.isValid }
    var canSave: Bool { preparedForSaving().identity.isValid && draftValidationMessage == nil }
    private var researchQuery: DeviceResearchQuery {
        let identity = draft.identity.normalizedForResearch
        let context: DeviceResearchQuery.Context? = identity.hardwareRevision == nil && identity.marketRegion == nil ? nil : .init(hardwareRevision: identity.hardwareRevision, marketRegion: identity.marketRegion)
        return .init(query: identification, context: context)
    }
    /// Applying the proposal and saving are one user confirmation. Cancellation never touches storage.
    func preparedForSaving() -> RegisteredNetworkDevice {
        var value = draft
        if let proposal {
            value.identity = proposal.identity
            value.specifications = proposal
            if let kind = researchResult?.deviceKind { value.kind = kind }
        }
        return value
    }
    func selectCandidate(_ identity: DeviceIdentity) {
        draft.identity = identity
        candidates = []
    }

    /// Confirming the queried model is not a request to repeat the same unresolved search.
    func selectResearchCandidate(_ identity: DeviceIdentity) {
        func normalized(_ value: String) -> String {
            value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let candidateQuery = [identity.brand, identity.model].filter { !$0.isEmpty }.joined(separator: " ")
        let repeatsQuery = normalized(candidateQuery) == normalized(identification)
            && normalized(identity.hardwareRevision ?? "") == normalized(draft.identity.hardwareRevision ?? "")
            && normalized(identity.marketRegion ?? "") == normalized(draft.identity.marketRegion ?? "")
        selectCandidate(identity)
        if repeatsQuery {
            cancel()
            message = LinkaCopy.value("inventory.research.empty")
        } else {
            research()
        }
    }

    func research() {
        guard isActive, canResearch else { return }
        cancel()
        guard let enrichment else { message = LinkaCopy.value("inventory.research.unavailable"); return }
        let identity = draft.identity; let request = researchQuery; let deviceID = draft.id; let token = UUID(); generation = token
        researching = true; message = nil
        queryTask = Task { [weak self] in
            do {
                let result = try await enrichment.research(request)
                guard let self, !Task.isCancelled, self.isActive, self.generation == token, self.draft.id == deviceID, self.draft.identity == identity else { return }
                try result.validate(for: request)
                self.researching = false
                self.researchResult = result
                switch result.status {
                case .unavailable:
                    self.message = LinkaCopy.value(result.reason == .providerTimeout ? "inventory.research.timeout" : "inventory.research.unavailable")
                case .notFound: self.message = LinkaCopy.value("inventory.research.empty")
                case .ambiguous: self.message = LinkaCopy.value("inventory.research.ambiguous")
                case .available: self.proposal = result.proposedSnapshot
                }
            } catch {
                guard let self, !Task.isCancelled, self.isActive, self.generation == token, self.draft.id == deviceID, self.draft.identity == identity else { return }
                self.researching = false
                if (error as? URLError)?.code == .timedOut { self.message = LinkaCopy.value("inventory.research.timeout") }
                else if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost].contains(error.code) { self.message = LinkaCopy.value("inventory.research.offline") }
                else { self.message = LinkaCopy.value("inventory.research.failed") }
            }
        }
    }
    private static var endpoint: URL? { InventoryBuildConfiguration.lookupEndpoint }
}
