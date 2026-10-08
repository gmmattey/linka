import SwiftUI
import NetworkInventory
import NetworkProfiles
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import AVFoundation
#endif

struct MyNetworkView: View {
    @StateObject private var store = LinkaInventoryStore()
    @State private var editing: RegisteredNetworkDevice?
    var body: some View {
        List {
            if store.devices.isEmpty {
                Section {
                    Text(LinkaCopy.value("inventory.empty"))
                    Button(LinkaCopy.value("inventory.add")) { add() }
                        .accessibilityIdentifier("inventory.add")
                }
            } else {
                ForEach(store.devices) { device in
                    NavigationLink {
                        DeviceDetailView(deviceID: device.id, store: store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.inventoryTitle).font(.headline)
                            Text(LinkaCopy.value("inventory.kind.\(device.kind.rawValue)"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("inventory.device.\(device.id.uuidString)")
                }
            }
            Section { Text(LinkaCopy.value("inventory.local")).font(.footnote).foregroundStyle(.secondary) }
            if let error = store.error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button(LinkaCopy.value("common.tryAgain")) { Task { await store.reload() } }
                }
            }
        }
        .navigationTitle(LinkaCopy.value("inventory.title"))
        .toolbar {
            ToolbarItem {
                Button(action: add) { Label(LinkaCopy.value("inventory.add"), systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityIdentifier("inventory.toolbar.add")
            }
        }
        .overlay { if store.loading { ProgressView() } }
        .task { await store.reload() }
        .onReceive(NotificationCenter.default.publisher(for: LinkaHousehold.didChange)) { _ in Task { await store.reload() } }
        .sheet(item: $editing) { device in
            DeviceEditorView(device: device, store: store)
                #if os(macOS)
                .frame(minWidth: 580, idealWidth: 640, minHeight: 520, idealHeight: 650)
                #endif
        }

    }
    private func add() { editing = RegisteredNetworkDevice(identity: .init(model: "")) }
}

private struct DeviceDetailView: View {
    let deviceID: UUID
    @ObservedObject var store: LinkaInventoryStore
    @State private var editing: RegisteredNetworkDevice?
    @State private var deleting: RegisteredNetworkDevice?
    var body: some View {
        Group {
            if let device = store.devices.first(where: { $0.id == deviceID }) {
                Form {
                    Section(LinkaCopy.value("inventory.identity")) {
                        value("inventory.brand", device.identity.brand)
                        value("inventory.model", device.identity.model)
                        value("inventory.revision", device.identity.hardwareRevision ?? "")
                        value("inventory.region", device.identity.marketRegion ?? "")
                    }
                    Section(LinkaCopy.value("inventory.installation")) {
                        value("inventory.mainRouter", LinkaCopy.value("inventory.answer.\(device.installation.mainRouterAnswer.rawValue)"))
                        value("inventory.role", LinkaCopy.value("inventory.role.\(device.installation.role.rawValue)"))
                        value("inventory.fiber", LinkaCopy.value("inventory.answer.\(device.installation.fiberDirectConnected.rawValue)"))
                        value("inventory.ownership", LinkaCopy.value("inventory.ownership.\(device.installation.ownership.rawValue)"))
                        value("inventory.location", store.environments.first(where: { $0.id == device.installation.environmentID })?.name ?? device.installation.locationLabel ?? "")
                    }
                    if let error = store.error { Section { Text(error).foregroundStyle(.red) } }
                    if let snapshot = device.specifications { DeviceSpecificationSections(snapshot: snapshot) }
                    else { Section { Text(LinkaCopy.value("inventory.specs.empty")) } }
                    Section {
                        Button(LinkaCopy.value("inventory.edit")) { editing = device }
                        Button(LinkaCopy.value("inventory.delete"), role: .destructive) { deleting = device }
                    }
                }
                #if os(macOS)
                .formStyle(.grouped)
                #endif
                .navigationTitle(device.inventoryTitle)
            } else { Text(LinkaCopy.value("inventory.deleted")) }
        }
        .sheet(item: $editing) { device in
            DeviceEditorView(device: device, store: store)
                #if os(macOS)
                .frame(minWidth: 580, idealWidth: 640, minHeight: 520, idealHeight: 650)
                #endif
        }
        .alert(LinkaCopy.value("inventory.delete.title"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(LinkaCopy.value("inventory.delete"), role: .destructive) {
                if let device = deleting { Task { await store.delete(device) } }; deleting = nil
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) { deleting = nil }
        } message: { Text(LinkaCopy.value("inventory.delete.message")) }
    }
    private func value(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LinkaCopy.value(key)).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? LinkaCopy.value("inventory.unknown") : value)
        }
    }
}

struct DeviceSpecificationSections: View {
    let snapshot: DeviceSpecificationSnapshot
    var body: some View {
        Section(LinkaCopy.value("inventory.specs.title")) {
            Text(LinkaCopy.value("inventory.specs.disclaimer")).font(.footnote).foregroundStyle(.secondary)
            if snapshot.status == .partial { Text(LinkaCopy.value("inventory.specs.partial")).font(.subheadline) }
            ForEach(["wifiStandards", "bandsGHz", "lanPorts", "wanPorts", "wanMedia", "supportsMesh"].filter { key in !snapshot.attributes.contains(where: { $0.key == key }) }, id: \.self) { key in
                VStack(alignment: .leading) {
                    Text(LinkaCopy.value("inventory.spec.\(key)")).font(.caption).foregroundStyle(.secondary)
                    Text(LinkaCopy.value("inventory.unknown"))
                }
            }
            ForEach(Array(snapshot.attributes.enumerated()), id: \.offset) { _, attribute in
                VStack(alignment: .leading, spacing: 4) {
                    Text(LinkaCopy.value("inventory.spec.\(attribute.key)")).font(.caption).foregroundStyle(.secondary)
                    Text(SpecificationDisplay.value(attribute))
                    ForEach(snapshot.sources.filter { attribute.evidenceIDs.contains($0.id) }) { source in
                        Link(source.title, destination: source.url).font(.caption)
                    }
                }
            }
            Text(snapshot.checkedAt, style: .date).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DeviceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LinkaInventoryStore
    @StateObject private var session: DeviceEditorSession
    @State private var saving = false
    @State private var importing = false
    @State private var confirmingResearch = false
    @State private var reviewing = false
    @State private var confirmDiscard = false
    private let original: RegisteredNetworkDevice
    #if os(iOS)
    @State private var camera = false
    @State private var selectedPhoto: PhotosPickerItem?
    #endif
    init(device: RegisteredNetworkDevice, store: LinkaInventoryStore) {
        self.store = store; self.original = device; _session = StateObject(wrappedValue: DeviceEditorSession(device: device))
    }
    var body: some View {
        NavigationStack {
            Form {
                identitySection
                installationSection
                researchSection
                if let message = session.message { Section { Text(message).foregroundStyle(.secondary) } }
                if let error = store.error { Section { Text(error).foregroundStyle(.red) } }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(LinkaCopy.value(session.draft.revision == 0 ? "inventory.add" : "inventory.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LinkaCopy.value("common.cancel")) {
                        if session.draft != original { confirmDiscard = true }
                        else { session.deactivate(); dismiss() }
                    }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LinkaCopy.value("inventory.save")) {
                        saving = true; session.cancel()
                        Task { if await store.save(session.draft) { dismiss() }; saving = false }
                    }
                    .disabled(!session.draft.identity.isValid || saving)
                    .accessibilityIdentifier("inventory.save")
                }
            }
            .disabled(saving)
        }
        .onChange(of: session.draft.identity) { _ in session.identityChanged() }
        .onDisappear { session.deactivate() }
        .onChange(of: store.devices) { devices in
            if session.draft.revision > 0 && !devices.contains(where: { $0.id == session.draft.id }) { session.deactivate(); dismiss() }
        }
        .interactiveDismissDisabled(saving || session.draft != original)
        .alert(LinkaCopy.value("inventory.discard.title"), isPresented: $confirmDiscard) {
            Button(LinkaCopy.value("inventory.discard"), role: .destructive) { session.deactivate(); dismiss() }
            Button(LinkaCopy.value("inventory.keepEditing"), role: .cancel) {}
        } message: { Text(LinkaCopy.value("inventory.discard.message")) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 20_000_000 else { throw NetworkInventoryError.invalidDevice }
                    session.recognize(try Data(contentsOf: url))
                } catch { session.message = LinkaCopy.value("inventory.ocr.failed") }
            }
        }
        .confirmationDialog(LinkaCopy.value("inventory.research.title"), isPresented: $confirmingResearch, titleVisibility: .visible) {
            Button(LinkaCopy.value("inventory.research.action")) { session.research() }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
        } message: { Text(LinkaCopy.value("inventory.research.disclosure")) }
        .sheet(isPresented: $reviewing) {
            NavigationStack {
                Form {
                    if let proposal = session.proposal { DeviceSpecificationSections(snapshot: proposal) }
                }
                #if os(macOS)
                .formStyle(.grouped)
                #endif
                .navigationTitle(LinkaCopy.value("inventory.review"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(LinkaCopy.value("common.cancel")) { reviewing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LinkaCopy.value("inventory.apply")) {
                            if let proposal = session.proposal, proposal.identity.matches(session.draft.identity) {
                                session.draft.specifications = proposal
                            }
                            reviewing = false; session.proposal = nil
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 450)
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $camera) {
            DeviceLabelCamera { data in camera = false; if let data { session.recognize(data) } }
        }
        .task(id: selectedPhoto) {
                guard let item = selectedPhoto else { return }
                do {
                    if let data = try await item.loadTransferable(type: Data.self), !Task.isCancelled, session.isActive { session.recognize(data) }
                } catch { session.message = LinkaCopy.value("inventory.ocr.failed") }
                if !Task.isCancelled { selectedPhoto = nil }
        }
        #endif
    }
    private var identitySection: some View {
        Section(LinkaCopy.value("inventory.identity")) {
            Picker(LinkaCopy.value("inventory.kind"), selection: $session.draft.kind) {
                ForEach(DeviceKind.allCases, id: \.self) { Text(LinkaCopy.value("inventory.kind.\($0.rawValue)")).tag($0) }
            }
            TextField(LinkaCopy.value("inventory.brand"), text: $session.draft.identity.brand)
            TextField(LinkaCopy.value("inventory.model"), text: $session.draft.identity.model).accessibilityIdentifier("inventory.model")
            if !session.draft.identity.isValid { Text(LinkaCopy.value("inventory.model.required")).font(.caption).foregroundStyle(.secondary) }
            TextField(LinkaCopy.value("inventory.revision"), text: optional($session.draft.identity.hardwareRevision))
            TextField(LinkaCopy.value("inventory.region"), text: optional($session.draft.identity.marketRegion))
            TextField(LinkaCopy.value("inventory.nickname"), text: optional($session.draft.nickname))
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(LinkaCopy.value("inventory.camera")) {
                    Task {
                        let allowed: Bool
                        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { allowed = true }
                        else { allowed = await AVCaptureDevice.requestAccess(for: .video) }
                        guard session.isActive else { return }
                        if allowed { camera = true } else { session.message = LinkaCopy.value("inventory.camera.denied") }
                    }
                }
            }
            PhotosPicker(selection: $selectedPhoto, matching: .images) { Text(LinkaCopy.value("inventory.image")) }
            #else
            Button(LinkaCopy.value("inventory.image")) { importing = true }
            #endif
            if session.recognizing { ProgressView(LinkaCopy.value("inventory.ocr.progress")) }
            if !session.candidates.isEmpty {
                Text(LinkaCopy.value("inventory.ocr.confirm")).font(.footnote)
                ForEach(Array(session.candidates.enumerated()), id: \.offset) { _, candidate in
                    Button([candidate.brand, candidate.model, candidate.hardwareRevision ?? ""].filter { !$0.isEmpty }.joined(separator: " ")) {
                        session.draft.identity = candidate; session.candidates = []
                    }
                }
            }
        }
    }
    private var installationSection: some View {
        Section(LinkaCopy.value("inventory.installation")) {
            Picker(LinkaCopy.value("inventory.mainRouter"), selection: $session.draft.installation.mainRouterAnswer) {
                ForEach(DeclaredAnswer.allCases, id: \.self) { Text(LinkaCopy.value("inventory.answer.\($0.rawValue)")).tag($0) }
            }
            .onChange(of: session.draft.installation.mainRouterAnswer) { answer in
                if answer == .yes { session.draft.installation.role = .mainRouter }
                else if session.draft.installation.role == .mainRouter { session.draft.installation.role = .unknown }
            }
            Picker(LinkaCopy.value("inventory.role"), selection: $session.draft.installation.role) {
                ForEach(InstalledRole.allCases, id: \.self) { Text(LinkaCopy.value("inventory.role.\($0.rawValue)")).tag($0) }
            }
            .onChange(of: session.draft.installation.role) { role in
                if role == .mainRouter { session.draft.installation.mainRouterAnswer = .yes }
                else if session.draft.installation.mainRouterAnswer == .yes { session.draft.installation.mainRouterAnswer = .unknown }
            }
            Picker(LinkaCopy.value("inventory.fiber"), selection: $session.draft.installation.fiberDirectConnected) {
                ForEach(DeclaredAnswer.allCases, id: \.self) { Text(LinkaCopy.value("inventory.answer.\($0.rawValue)")).tag($0) }
            }
            Picker(LinkaCopy.value("inventory.ownership"), selection: $session.draft.installation.ownership) {
                ForEach(OwnershipSource.allCases, id: \.self) { Text(LinkaCopy.value("inventory.ownership.\($0.rawValue)")).tag($0) }
            }
            Picker(LinkaCopy.value("inventory.location"), selection: $session.draft.installation.environmentID) {
                Text(LinkaCopy.value("inventory.location.manual")).tag(nil as UUID?)
                ForEach(store.environments) { Text($0.name).tag(Optional($0.id)) }
            }
            if session.draft.installation.environmentID == nil {
                TextField(LinkaCopy.value("inventory.location.optional"), text: optional($session.draft.installation.locationLabel))
            }
        }
    }
    private var researchSection: some View {
        Section(LinkaCopy.value("inventory.specs.title")) {
            Button(LinkaCopy.value("inventory.research.action")) { confirmingResearch = true }
                .disabled(!session.draft.identity.isResearchable || session.researching)
            if !session.draft.identity.isResearchable { Text(LinkaCopy.value("inventory.research.required")).font(.caption).foregroundStyle(.secondary) }
            if session.researching {
                ProgressView(LinkaCopy.value("inventory.research.progress"))
                Button(LinkaCopy.value("common.cancel")) { session.cancel() }
            }
            if session.proposal != nil { Button(LinkaCopy.value("inventory.review")) { reviewing = true } }
            if session.draft.specifications != nil { Text(LinkaCopy.value("inventory.specs.saved")).font(.footnote) }
        }
    }
    private func optional(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

private extension RegisteredNetworkDevice {
    var inventoryTitle: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nickname }
        return [identity.brand, identity.model].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

#if os(iOS)
private struct DeviceLabelCamera: UIViewControllerRepresentable {
    let completion: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Data?) -> Void
        init(completion: @escaping (Data?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.85))
        }
    }
}
#endif
