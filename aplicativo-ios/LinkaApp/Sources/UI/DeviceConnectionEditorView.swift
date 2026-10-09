import SwiftUI
import NetworkInventory

struct DeviceConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LinkaInventoryStore

    let connection: DeviceConnection?

    @State private var endpointADeviceID: UUID
    @State private var endpointBDeviceID: UUID
    @State private var medium: LinkMedium
    @State private var direction: DirectionChoice

    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var validationError: String?

    enum DirectionChoice: Hashable {
        case fromA
        case fromB
        case unspecified
    }

    init(
        connection: DeviceConnection? = nil,
        preselectedDeviceA: UUID? = nil,
        preselectedDeviceB: UUID? = nil,
        store: LinkaInventoryStore
    ) {
        self.connection = connection
        self.store = store

        let initialA = connection?.endpointADeviceID ?? preselectedDeviceA ?? store.devices.first?.id ?? UUID()
        let fallbackB = store.devices.first(where: { $0.id != initialA })?.id ?? initialA
        let initialB = connection?.endpointBDeviceID ?? preselectedDeviceB ?? fallbackB

        _endpointADeviceID = State(initialValue: initialA)
        _endpointBDeviceID = State(initialValue: initialB)
        _medium = State(initialValue: connection?.medium ?? .wifi)

        let initialDir: DirectionChoice
        if let sourceID = connection?.sourceDeviceID {
            if sourceID == initialA {
                initialDir = .fromA
            } else if sourceID == initialB {
                initialDir = .fromB
            } else {
                initialDir = .unspecified
            }
        } else {
            initialDir = .unspecified
        }
        _direction = State(initialValue: initialDir)
    }

    private var isNewConnection: Bool {
        connection == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                devicesSection

                mediumSection

                directionSection

                if let error = validationError ?? store.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if !isNewConnection {
                    Section {
                        Button(LinkaCopy.value("inventory.connection.delete"), role: .destructive) {
                            confirmDelete = true
                        }
                        .accessibilityIdentifier("inventory.connection.deleteButton")
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(LinkaCopy.value(isNewConnection ? "inventory.connection.add" : "inventory.connection.edit"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LinkaCopy.value("common.cancel")) {
                        if hasUnsavedChanges {
                            confirmDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(LinkaCopy.value("inventory.save")) {
                        saveConnection()
                    }
                    .disabled(!canSave || saving)
                    .accessibilityIdentifier("inventory.connection.saveButton")
                }
            }
            .interactiveDismissDisabled(saving || hasUnsavedChanges)
            .alert(LinkaCopy.value("inventory.discard.title"), isPresented: $confirmDiscard) {
                Button(LinkaCopy.value("inventory.discard"), role: .destructive) { dismiss() }
                Button(LinkaCopy.value("inventory.keepEditing"), role: .cancel) {}
            } message: {
                Text(LinkaCopy.value("inventory.discard.message"))
            }
            .alert(LinkaCopy.value("inventory.connection.delete.title"), isPresented: $confirmDelete) {
                Button(LinkaCopy.value("inventory.delete"), role: .destructive) {
                    deleteConnection()
                }
                Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
            } message: {
                Text(LinkaCopy.value("inventory.connection.delete.message"))
            }
        }
    }

    // MARK: - Sections

    private var devicesSection: some View {
        Section(LinkaCopy.value("inventory.connection.devicesHeader")) {
            Picker(LinkaCopy.value("inventory.connection.deviceA"), selection: $endpointADeviceID) {
                ForEach(store.devices) { device in
                    Text(device.inventoryTitle).tag(device.id)
                }
            }
            .accessibilityIdentifier("inventory.connection.deviceAPicker")

            Picker(LinkaCopy.value("inventory.connection.deviceB"), selection: $endpointBDeviceID) {
                ForEach(store.devices) { device in
                    Text(device.inventoryTitle).tag(device.id)
                }
            }
            .accessibilityIdentifier("inventory.connection.deviceBPicker")

            if endpointADeviceID == endpointBDeviceID {
                Text(LinkaCopy.value("inventory.connection.invalidError"))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var mediumSection: some View {
        Section(LinkaCopy.value("inventory.connection.medium")) {
            Picker(LinkaCopy.value("inventory.connection.medium"), selection: $medium) {
                ForEach(LinkMedium.allCases, id: \.self) { med in
                    Label(mediumLabel(med), systemImage: mediumIcon(med))
                        .tag(med)
                }
            }
            .accessibilityIdentifier("inventory.connection.mediumPicker")
        }
    }

    private var directionSection: some View {
        Section(LinkaCopy.value("inventory.connection.direction")) {
            Picker(LinkaCopy.value("inventory.connection.direction"), selection: $direction) {
                Text(nameForDirectionChoice(.fromA)).tag(DirectionChoice.fromA)
                Text(nameForDirectionChoice(.fromB)).tag(DirectionChoice.fromB)
                Text(LinkaCopy.value("inventory.connection.direction.unknown")).tag(DirectionChoice.unspecified)
            }
            #if os(iOS)
            .pickerStyle(.inline)
            #endif
            .accessibilityIdentifier("inventory.connection.directionPicker")
        }
    }

    // MARK: - Helpers

    private var canSave: Bool {
        endpointADeviceID != endpointBDeviceID
    }

    private var hasUnsavedChanges: Bool {
        if let original = connection {
            let originalDir: DirectionChoice
            if let src = original.sourceDeviceID {
                if src == original.endpointADeviceID { originalDir = .fromA }
                else if src == original.endpointBDeviceID { originalDir = .fromB }
                else { originalDir = .unspecified }
            } else {
                originalDir = .unspecified
            }
            return endpointADeviceID != original.endpointADeviceID ||
                endpointBDeviceID != original.endpointBDeviceID ||
                medium != original.medium ||
                direction != originalDir
        }
        return true
    }

    private func deviceTitle(for id: UUID) -> String {
        store.devices.first(where: { $0.id == id })?.inventoryTitle ?? LinkaCopy.value("inventory.unknown")
    }

    private func nameForDirectionChoice(_ choice: DirectionChoice) -> String {
        switch choice {
        case .fromA:
            let name = deviceTitle(for: endpointADeviceID)
            return String(format: LinkaCopy.value("inventory.connection.direction.fromA"), name)
        case .fromB:
            let name = deviceTitle(for: endpointBDeviceID)
            return String(format: LinkaCopy.value("inventory.connection.direction.fromB"), name)
        case .unspecified:
            return LinkaCopy.value("inventory.connection.direction.unknown")
        }
    }

    private func mediumLabel(_ medium: LinkMedium) -> String {
        LinkaCopy.value("inventory.medium.\(medium.rawValue)")
    }

    private func mediumIcon(_ medium: LinkMedium) -> String {
        switch medium {
        case .ethernet:
            return "cable.connector"
        case .wifi:
            return "wifi"
        case .fiber:
            return "point.3.connected.trianglepath.dotted"
        case .other:
            return "ellipsis.circle"
        case .unknown:
            return "questionmark.circle"
        }
    }

    // MARK: - Actions

    private func saveConnection() {
        guard canSave, !saving else { return }
        saving = true
        validationError = nil

        let sourceID: UUID?
        switch direction {
        case .fromA:
            sourceID = endpointADeviceID
        case .fromB:
            sourceID = endpointBDeviceID
        case .unspecified:
            sourceID = nil
        }

        let targetConnection = DeviceConnection(
            id: connection?.id ?? UUID(),
            endpointADeviceID: endpointADeviceID,
            endpointBDeviceID: endpointBDeviceID,
            medium: medium,
            sourceDeviceID: sourceID,
            declaredByUser: true,
            createdAt: connection?.createdAt ?? Date(),
            updatedAt: Date()
        )

        guard targetConnection.isValid else {
            validationError = LinkaCopy.value("inventory.connection.invalidError")
            saving = false
            return
        }

        Task {
            let success = await store.saveConnection(targetConnection)
            saving = false
            if success {
                dismiss()
            }
        }
    }

    private func deleteConnection() {
        guard let existing = connection, !saving else { return }
        saving = true
        Task {
            let success = await store.deleteConnection(id: existing.id)
            saving = false
            if success {
                dismiss()
            }
        }
    }
}
