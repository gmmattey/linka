import SwiftUI
import NetworkInventory
import NetworkProfiles
import UniformTypeIdentifiers
import LinkaEntitlements
#if os(iOS)
import PhotosUI
import AVFoundation
#endif

struct MyNetworkView: View {
    @StateObject private var store = LinkaInventoryStore()
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @State private var editing: RegisteredNetworkDevice?
    @State private var editingPlan = false
    @State private var connectionSheet: ConnectionSheetTarget?
    @State private var managingEnvironments = false
    @State private var showPurchase = false

    private enum ConnectionSheetTarget: Identifiable {
        case add
        case edit(DeviceConnection)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let conn): return conn.id.uuidString
            }
        }
    }

    var body: some View {
        List {
            planSection

            if store.activePlan != nil {
                planPerformanceSection
            }

            devicesSection

            if store.devices.count >= 2 {
                connectionsSection
            }

            environmentsSection

            Section {
                Text(LinkaCopy.value("inventory.local")).font(.footnote).foregroundStyle(.secondary)
            }
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
                Button(action: add) { Label(LinkaCopy.value("inventory.devices.add"), systemImage: "plus") }
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
        .sheet(isPresented: $editingPlan) {
            ServicePlanEditorView(plan: store.activePlan, store: store)
                #if os(macOS)
                .frame(minWidth: 520, idealWidth: 600, minHeight: 500)
                #endif
        }
        .sheet(item: $connectionSheet) { target in
            switch target {
            case .add:
                DeviceConnectionEditorView(connection: nil, store: store)
                    #if os(macOS)
                    .frame(minWidth: 520, idealWidth: 600, minHeight: 480)
                    #endif
            case .edit(let conn):
                DeviceConnectionEditorView(connection: conn, store: store)
                    #if os(macOS)
                    .frame(minWidth: 520, idealWidth: 600, minHeight: 480)
                    #endif
            }
        }
        .sheet(isPresented: $managingEnvironments) {
            #if os(macOS)
            NavigationStack {
                NetworkProfilesManagementView(
                    isPlusActive: LinkaEntitlementPolicy.decision(for: .optimization, snapshot: entitlements.snapshot).isGranted,
                    onRequestPurchase: {
                        managingEnvironments = false
                        showPurchase = true
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(LinkaCopy.value("common.close")) {
                            managingEnvironments = false
                        }
                    }
                }
            }
            .frame(minWidth: 520, idealWidth: 600, minHeight: 480)
            #else
            NetworkProfilesManagementView(
                isPlusActive: LinkaEntitlementPolicy.decision(for: .optimization, snapshot: entitlements.snapshot).isGranted,
                onRequestPurchase: {
                    managingEnvironments = false
                    showPurchase = true
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(isPresented: $showPurchase) {
            PurchaseSheet(entryPoint: .optimization)
                .environmentObject(entitlements)
                #if os(macOS)
                .frame(minWidth: 500, idealWidth: 560, minHeight: 580)
                #endif
        }
    }

    private var planSection: some View {
        Section(LinkaCopy.value("inventory.section.plan")) {
            if let plan = store.activePlan {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.ispName)
                                .font(.headline)
                            if let name = plan.planName {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(LinkaCopy.value("inventory.plan.edit")) {
                            editingPlan = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("inventory.plan.editButton")
                    }

                    HStack(spacing: 16) {
                        if let dl = plan.nominalDownloadMbps {
                            Label(String(format: LinkaCopy.value("inventory.plan.downloadDisplay"), "\(formatSpeed(dl)) Mbps"), systemImage: "arrow.down.circle")
                                .font(.caption.weight(.medium))
                        }
                        if let ul = plan.nominalUploadMbps {
                            Label(String(format: LinkaCopy.value("inventory.plan.uploadDisplay"), "\(formatSpeed(ul)) Mbps"), systemImage: "arrow.up.circle")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .foregroundStyle(.secondary)

                    HStack {
                        Text(LinkaCopy.value("inventory.technology.\(plan.technology.rawValue)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let cents = plan.monthlyCostCents {
                            Spacer()
                            Text(formatCost(cents))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    editingPlan = true
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LinkaCopy.value("inventory.plan.card.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(LinkaCopy.value("inventory.plan.cta.add")) {
                        editingPlan = true
                    }
                    .accessibilityIdentifier("inventory.plan.add")
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var planPerformanceSection: some View {
        if let evaluation = store.planEvaluation {
            Section(LinkaCopy.value("inventory.evaluation.section")) {
                VStack(alignment: .leading, spacing: 12) {
                    let statusInfo = evaluationStatusInfo(evaluation)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: statusInfo.icon)
                            .font(.title2)
                            .foregroundStyle(statusInfo.iconColor)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusInfo.title)
                                .font(.headline)
                                .foregroundStyle(Color.textPrimary)

                            Text(statusInfo.message)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    if evaluation.eligibleMeasurementsCount > 0 {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            if let dl = evaluation.downloadAggregate {
                                HStack {
                                    Label(LinkaCopy.value("inventory.evaluation.download"), systemImage: "arrow.down.circle")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    Text(
                                        LinkaCopy.format(
                                            "inventory.evaluation.delivered",
                                            "\(formatSpeed(dl.averageMbps)) Mbps",
                                            "\(formatSpeed(dl.nominalMbps)) Mbps",
                                            "\(Int(round(dl.averageDeliveredPercent)))%"
                                        )
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                }
                            }

                            if let ul = evaluation.uploadAggregate {
                                HStack {
                                    Label(LinkaCopy.value("inventory.evaluation.upload"), systemImage: "arrow.up.circle")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    Text(
                                        LinkaCopy.format(
                                            "inventory.evaluation.delivered",
                                            "\(formatSpeed(ul.averageMbps)) Mbps",
                                            "\(formatSpeed(ul.nominalMbps)) Mbps",
                                            "\(Int(round(ul.averageDeliveredPercent)))%"
                                        )
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }

                        Text(String(format: LinkaCopy.value("inventory.evaluation.sampleCount"), evaluation.eligibleMeasurementsCount))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private struct EvaluationStatusInfo {
        let icon: String
        let iconColor: Color
        let title: String
        let message: String
    }

    private func evaluationStatusInfo(_ evaluation: ResidentialPlanAggregateEvaluation) -> EvaluationStatusInfo {
        if evaluation.eligibleMeasurementsCount == 0 ||
            (evaluation.downloadEvaluation.isNoData && evaluation.uploadEvaluation.isNoData) {
            return EvaluationStatusInfo(
                icon: "network.badge.shield.half.filled",
                iconColor: Color.textSecondary,
                title: LinkaCopy.value("inventory.evaluation.noData.title"),
                message: LinkaCopy.value("inventory.evaluation.noData.message")
            )
        }

        let dlStatus = evaluation.downloadAggregate?.status
        let ulStatus = evaluation.uploadAggregate?.status
        let statuses = [dlStatus, ulStatus].compactMap { $0 }

        if statuses.contains(.belowPlan) {
            return EvaluationStatusInfo(
                icon: "info.circle.fill",
                iconColor: Color.statusAttention,
                title: LinkaCopy.value("inventory.evaluation.below.title"),
                message: LinkaCopy.value("inventory.evaluation.below.message")
            )
        } else if statuses.contains(.partiallyMeeting) {
            return EvaluationStatusInfo(
                icon: "info.circle.fill",
                iconColor: Color.statusAttention,
                title: LinkaCopy.value("inventory.evaluation.partiallyMeeting.title"),
                message: LinkaCopy.value("inventory.evaluation.partiallyMeeting.message")
            )
        } else if !statuses.isEmpty && statuses.allSatisfy({ $0 == .exceeding }) {
            return EvaluationStatusInfo(
                icon: "checkmark.circle.fill",
                iconColor: Color.statusGood,
                title: LinkaCopy.value("inventory.evaluation.exceeding.title"),
                message: LinkaCopy.value("inventory.evaluation.exceeding.message")
            )
        } else {
            return EvaluationStatusInfo(
                icon: "checkmark.circle.fill",
                iconColor: Color.statusGood,
                title: LinkaCopy.value("inventory.evaluation.meeting.title"),
                message: LinkaCopy.value("inventory.evaluation.meeting.message")
            )
        }
    }

    private var devicesSection: some View {
        Section(LinkaCopy.value("inventory.section.devices")) {
            if store.devices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LinkaCopy.value("inventory.devices.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(LinkaCopy.value("inventory.devices.add")) {
                        add()
                    }
                    .accessibilityIdentifier("inventory.devices.add")
                }
                .padding(.vertical, 4)
            } else {
                ForEach(store.devices) { device in
                    NavigationLink {
                        DeviceDetailView(deviceID: device.id, store: store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.inventoryTitle).font(.headline)
                            Text(deviceSubtitle(device))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("inventory.device.\(device.id.uuidString)")
                }
                Button {
                    add()
                } label: {
                    Label(LinkaCopy.value("inventory.devices.add"), systemImage: "plus")
                }
                .accessibilityIdentifier("inventory.devices.addButton")
            }
        }
    }

    @ViewBuilder
    private var connectionsSection: some View {
        Section(LinkaCopy.value("inventory.section.connections")) {
            if store.connections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LinkaCopy.value("inventory.connections.guide.message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(LinkaCopy.value("inventory.connections.guide.cta")) {
                        connectionSheet = .add
                    }
                    .accessibilityIdentifier("inventory.connections.informCTA")
                }
                .padding(.vertical, 4)
            } else {
                ForEach(store.connections) { conn in
                    Button {
                        connectionSheet = .edit(conn)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: mediumIcon(conn.medium))
                                .font(.body)
                                .foregroundStyle(.tint)
                                .frame(width: 24)

                            Text(connectionLabel(conn))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("inventory.connection.row.\(conn.id.uuidString)")
                }

                Button {
                    connectionSheet = .add
                } label: {
                    Label(LinkaCopy.value("inventory.connection.addNew"), systemImage: "plus")
                }
                .accessibilityIdentifier("inventory.connection.addButton")
            }
        }
    }

    private var environmentsSection: some View {
        Section {
            if store.environments.isEmpty {
                Text(LinkaCopy.value("inventory.environments.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.environments) { env in
                    let count = store.devices.filter { $0.installation.environmentID == env.id }.count
                    HStack {
                        Label(env.name, systemImage: "mappin.and.ellipse")
                            .font(.body)
                        Spacer()
                        if count > 0 {
                            Text(String(format: LinkaCopy.value(count == 1 ? "inventory.environment.deviceCount.single" : "inventory.environment.deviceCount.multiple"), count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button {
                managingEnvironments = true
            } label: {
                Label(LinkaCopy.value("inventory.environments.manage"), systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("inventory.environments.manageButton")
        } header: {
            Text(LinkaCopy.value("inventory.section.environments"))
        } footer: {
            Text(LinkaCopy.value("inventory.environments.footer"))
        }
    }

    private func deviceSubtitle(_ device: RegisteredNetworkDevice) -> String {
        let kindText = LinkaCopy.value(device.kind == .ont ? "inventory.kind.fiberEquipment" : "inventory.kind.\(device.kind.rawValue)")
        if let envName = store.environments.first(where: { $0.id == device.installation.environmentID })?.name,
           !envName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(kindText) · \(envName)"
        } else if let loc = device.installation.locationLabel,
                  !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(kindText) · \(loc)"
        } else {
            return kindText
        }
    }

    private func connectionLabel(_ conn: DeviceConnection) -> String {
        let devA = store.devices.first(where: { $0.id == conn.endpointADeviceID })
        let devB = store.devices.first(where: { $0.id == conn.endpointBDeviceID })
        let titleA = devA?.inventoryTitle ?? LinkaCopy.value("inventory.unknown")
        let titleB = devB?.inventoryTitle ?? LinkaCopy.value("inventory.unknown")
        let medium = mediumDisplayName(conn.medium)

        if conn.sourceDeviceID == conn.endpointBDeviceID {
            return "\(titleB) → \(medium) → \(titleA)"
        } else if conn.sourceDeviceID == conn.endpointADeviceID {
            return "\(titleA) → \(medium) → \(titleB)"
        } else {
            return "\(titleA) — \(medium) — \(titleB)"
        }
    }

    private func mediumDisplayName(_ medium: LinkMedium) -> String {
        LinkaCopy.value("inventory.medium.short.\(medium.rawValue)")
    }

    private func mediumIcon(_ medium: LinkMedium) -> String {
        switch medium {
        case .ethernet: return "cable.connector"
        case .wifi: return "wifi"
        case .fiber: return "point.3.connected.trianglepath.dotted"
        case .other: return "ellipsis.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private func add() {
        editing = RegisteredNetworkDevice(kind: .other, identity: .init(model: ""))
    }

    private func formatSpeed(_ speed: Double) -> String {
        if speed.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", speed)
        }
        return String(format: "%.1f", speed)
    }

    private func formatCost(_ cents: Int) -> String {
        let value = Double(cents) / 100.0
        return String(format: LinkaCopy.value("inventory.plan.monthCostDisplay"), String(format: "%.2f", value))
    }
}

private struct DeviceDetailView: View {
    let deviceID: UUID
    @ObservedObject var store: LinkaInventoryStore
    @State private var editing: RegisteredNetworkDevice?
    @State private var deleting: RegisteredNetworkDevice?
    @State private var completing: RegisteredNetworkDevice?
    @State private var editingConnection: DeviceConnection?
    @State private var connectingWithDevice: RegisteredNetworkDevice?
    @State private var dismissedConnectionPrompt = false

    var body: some View {
        Group {
            if let device = store.devices.first(where: { $0.id == deviceID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(device.inventoryTitle).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                            if device.nickname != nil {
                                Text([device.identity.brand, device.identity.model].filter { !$0.isEmpty }.joined(separator: " "))
                                    .foregroundStyle(.secondary)
                            }
                            if device.kind != .other {
                                Text(LinkaCopy.value(device.kind == .ont ? "inventory.kind.fiberEquipment" : "inventory.kind.\(device.kind.rawValue)"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Button(LinkaCopy.value("inventory.completeDetails")) { completing = device }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                            .accessibilityIdentifier("inventory.completeDetails")
                        if hasInstallationDetails(device) {
                            DisclosureGroup(LinkaCopy.value("inventory.installation")) {
                                VStack(alignment: .leading, spacing: 12) {
                                    if device.installation.mainRouterAnswer != .unknown {
                                        value("inventory.mainRouter", LinkaCopy.value("inventory.answer.\(device.installation.mainRouterAnswer.rawValue)"))
                                    }
                                    if device.installation.role != .unknown {
                                        value("inventory.role", LinkaCopy.value("inventory.role.\(device.installation.role.rawValue)"))
                                    }
                                    if device.installation.fiberDirectConnected != .unknown {
                                        value("inventory.fiber", LinkaCopy.value("inventory.answer.\(device.installation.fiberDirectConnected.rawValue)"))
                                    }
                                    if device.installation.ownership != .unknown {
                                        value("inventory.ownership", LinkaCopy.value("inventory.ownership.\(device.installation.ownership.rawValue)"))
                                    }
                                    if let location = location(device), !location.isEmpty { value("inventory.location", location) }
                                }.padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        connectionsSection(device)
                        if let snapshot = device.specifications {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(LinkaCopy.value("inventory.specs.title")).font(.headline)
                                ForEach(SpecificationDisplay.summary(snapshot), id: \.self) { Text($0).font(.subheadline) }
                                DisclosureGroup(LinkaCopy.value("inventory.detailsAndSources")) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        if let revision = device.identity.hardwareRevision { value("inventory.revision", revision) }
                                        if let region = device.identity.marketRegion { value("inventory.region", region) }
                                        DeviceSpecificationContent(snapshot: snapshot)
                                    }.padding(.top, 12)
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg))
                        } else {
                            Text(LinkaCopy.value("inventory.specs.empty")).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let error = store.error { Text(error).foregroundStyle(.red) }
                        Button(LinkaCopy.value("inventory.edit")) { editing = device }.frame(minHeight: 44)
                        Button(LinkaCopy.value("inventory.delete"), role: .destructive) { deleting = device }.frame(minHeight: 44)
                    }
                    .padding(24).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
                }
                .background(Color.surfacePage)
                .navigationTitle(device.inventoryTitle)
            } else { Text(LinkaCopy.value("inventory.deleted")) }
        }
        .sheet(item: $editing) { device in
            DeviceEditorView(device: device, store: store)
                #if os(macOS)
                .frame(minWidth: 580, idealWidth: 640, minHeight: 520, idealHeight: 650)
                #endif
        }
        .sheet(item: $completing) { device in
            DeviceInstallationEditor(device: device, store: store)
                #if os(macOS)
                .frame(minWidth: 520, idealWidth: 600, minHeight: 500)
                #endif
        }
        .sheet(item: $editingConnection) { conn in
            DeviceConnectionEditorView(connection: conn, store: store)
                #if os(macOS)
                .frame(minWidth: 520, idealWidth: 600, minHeight: 480)
                #endif
        }
        .sheet(item: $connectingWithDevice) { target in
            DeviceConnectionEditorView(
                connection: nil,
                preselectedDeviceA: target.id,
                store: store
            )
            #if os(macOS)
            .frame(minWidth: 520, idealWidth: 600, minHeight: 480)
            #endif
        }
        .alert(LinkaCopy.value("inventory.delete.title"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(LinkaCopy.value("inventory.delete"), role: .destructive) {
                if let device = deleting { Task { await store.delete(device) } }; deleting = nil
            }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) { deleting = nil }
        } message: { Text(LinkaCopy.value("inventory.delete.message")) }
    }

    private func connectionsSection(_ device: RegisteredNetworkDevice) -> some View {
        let linkedConnections = store.connections(for: device.id)
        return VStack(alignment: .leading, spacing: 12) {
            Text(LinkaCopy.value("inventory.connection.section.title"))
                .font(.headline)

            if linkedConnections.isEmpty && store.devices.count >= 2 && !dismissedConnectionPrompt {
                connectionPromptCard(for: device)
            } else if linkedConnections.isEmpty {
                Text(LinkaCopy.value("inventory.connection.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linkedConnections) { conn in
                    connectionCard(conn, currentDevice: device)
                }
            }

            if store.devices.count >= 2 && (!linkedConnections.isEmpty || dismissedConnectionPrompt) {
                Button {
                    connectingWithDevice = device
                } label: {
                    Label(LinkaCopy.value("inventory.connection.add"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("inventory.connection.addButton")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg))
    }

    private func connectionPromptCard(for device: RegisteredNetworkDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LinkaCopy.value("inventory.connection.prompt.title"))
                        .font(.headline)
                    Text(LinkaCopy.value("inventory.connection.prompt.message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button(LinkaCopy.value("inventory.connection.prompt.connect")) {
                    connectingWithDevice = device
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("inventory.connection.prompt.connectButton")

                Button(LinkaCopy.value("inventory.connection.prompt.notNow")) {
                    dismissedConnectionPrompt = true
                }
                .buttonStyle(.bordered)

                Button(LinkaCopy.value("inventory.connection.prompt.dontKnow")) {
                    dismissedConnectionPrompt = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.footnote)
            }
            .padding(.top, 4)
        }
    }

    private func connectionCard(_ conn: DeviceConnection, currentDevice: RegisteredNetworkDevice) -> some View {
        let otherID = (conn.endpointADeviceID == currentDevice.id) ? conn.endpointBDeviceID : conn.endpointADeviceID
        let otherDevice = store.devices.first(where: { $0.id == otherID })
        let otherTitle = otherDevice?.inventoryTitle ?? LinkaCopy.value("inventory.unknown")

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: mediumIcon(conn.medium))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(otherTitle)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(LinkaCopy.value("inventory.medium.\(conn.medium.rawValue)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(directionLabel(conn, currentID: currentDevice.id, otherTitle: otherTitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(LinkaCopy.value("inventory.edit")) {
                editingConnection = conn
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("inventory.connection.edit.\(conn.id.uuidString)")
        }
        .padding(10)
        .background(Color.surfacePage, in: RoundedRectangle(cornerRadius: LinkaRadius.md))
    }

    private func mediumIcon(_ medium: LinkMedium) -> String {
        switch medium {
        case .ethernet: return "cable.connector"
        case .wifi: return "wifi"
        case .fiber: return "point.3.connected.trianglepath.dotted"
        case .other: return "ellipsis.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private func directionLabel(_ conn: DeviceConnection, currentID: UUID, otherTitle: String) -> String {
        guard let sourceID = conn.sourceDeviceID else {
            return LinkaCopy.value("inventory.connection.direction.unspecified")
        }
        if sourceID == currentID {
            return String(format: LinkaCopy.value("inventory.connection.direction.sendsTo"), otherTitle)
        } else {
            return String(format: LinkaCopy.value("inventory.connection.direction.receivesFrom"), otherTitle)
        }
    }

    private func location(_ device: RegisteredNetworkDevice) -> String? {
        store.environments.first(where: { $0.id == device.installation.environmentID })?.name ?? device.installation.locationLabel
    }
    private func hasInstallationDetails(_ device: RegisteredNetworkDevice) -> Bool {
        device.installation.mainRouterAnswer != .unknown || device.installation.role != .unknown ||
        device.installation.fiberDirectConnected != .unknown || device.installation.ownership != .unknown ||
        !(location(device) ?? "").isEmpty
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
        Section(LinkaCopy.value("inventory.specs.title")) { DeviceSpecificationContent(snapshot: snapshot) }
    }
}

private struct DeviceSpecificationContent: View {
    let snapshot: DeviceSpecificationSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LinkaCopy.value("inventory.specs.disclaimer")).font(.footnote).foregroundStyle(.secondary)
            ForEach(Array(snapshot.attributes.enumerated()), id: \.offset) { _, attribute in
                VStack(alignment: .leading, spacing: 4) {
                    Text(LinkaCopy.value("inventory.spec.\(attribute.key)")).font(.caption).foregroundStyle(.secondary)
                    Text(SpecificationDisplay.value(attribute))
                    ForEach(snapshot.sources.filter { attribute.evidenceIDs.contains($0.id) }) { source in
                        Link(source.title, destination: source.url).font(.caption)
                    }
                }
            }
            if snapshot.attributes.isEmpty {
                ForEach(snapshot.sources) { source in Link(source.title, destination: source.url).font(.caption) }
            }
            Text(snapshot.checkedAt, style: .date).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DeviceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var store: LinkaInventoryStore
    @StateObject private var session: DeviceEditorSession
    @State private var saving = false
    @State private var importing = false
    @State private var confirmDiscard = false
    @State private var showingPrivacy = false
    @FocusState private var identificationFocused: Bool
    private let original: RegisteredNetworkDevice
    #if os(iOS)
    @State private var camera = false
    @State private var selectedPhoto: PhotosPickerItem?
    #endif
    init(device: RegisteredNetworkDevice, store: LinkaInventoryStore) {
        self.store = store; self.original = device
        _session = StateObject(wrappedValue: DeviceEditorSession(device: device))
    }
    var body: some View {
        NavigationStack {
            // The scroll container and field keep the same identity throughout research.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identificationSection
                    researchSection
                    if let validation = session.draftValidationMessage {
                        Text(validation).foregroundStyle(.red)
                    }
                    if let error = store.error { Text(error).foregroundStyle(.red) }
                }
                .padding(24)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.surfacePage)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .navigationTitle(LinkaCopy.value(session.draft.revision == 0 ? "inventory.add" : "inventory.edit"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LinkaCopy.value("common.cancel")) {
                        if session.draft != original { confirmDiscard = true }
                        else { session.deactivate(); dismiss() }
                    }.disabled(saving)
                }
            }
            .disabled(saving)
        }
        .onDisappear { session.deactivate() }
        .onChange(of: store.devices) { devices in
            if session.draft.revision > 0 && !devices.contains(where: { $0.id == session.draft.id }) {
                session.deactivate(); dismiss()
            }
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
        .sheet(isPresented: $showingPrivacy) {
            NavigationStack {
                ScrollView { Text(LinkaCopy.value("inventory.privacy.details")).padding(24).frame(maxWidth: 560, alignment: .leading) }
                    .navigationTitle(LinkaCopy.value("inventory.privacy.title"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(LinkaCopy.value("common.close")) { showingPrivacy = false } } }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 300)
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $camera) {
            DeviceLabelCamera { data in camera = false; if let data { session.recognize(data) } }
        }
        .task(id: selectedPhoto) {
            guard let item = selectedPhoto else { return }
            let identity = session.draft.identity
            do {
                if let data = try await item.loadTransferable(type: Data.self), !Task.isCancelled, session.isActive, session.draft.identity == identity {
                    session.recognize(data)
                }
            } catch { session.message = LinkaCopy.value("inventory.ocr.failed") }
            if !Task.isCancelled { selectedPhoto = nil }
        }
        #endif
    }
    private var identificationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LinkaCopy.value("inventory.identify.title")).font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(LinkaCopy.value("inventory.identify.subtitle")).font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text(LinkaCopy.value("inventory.identify.label")).font(.subheadline.weight(.medium))
                TextField(LinkaCopy.value("inventory.identify.placeholder"), text: $session.identification)
                    .textFieldStyle(.roundedBorder)
                    .focused($identificationFocused)
                    .accessibilityLabel(LinkaCopy.value("inventory.identify.label"))
                    .accessibilityIdentifier("inventory.model")
                    .onSubmit { if session.canResearch && !session.researching { startResearch() } }
            }
            photoActionsLayout {
                #if os(iOS)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        identificationFocused = false
                        Task {
                            let allowed: Bool
                            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { allowed = true }
                            else { allowed = await AVCaptureDevice.requestAccess(for: .video) }
                            guard session.isActive else { return }
                            if allowed { camera = true }
                            else { session.message = LinkaCopy.value("inventory.camera.denied") }
                        }
                    } label: { Label(LinkaCopy.value("inventory.camera"), systemImage: "camera").fixedSize(horizontal: false, vertical: true) }
                        .frame(minHeight: 44)
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(LinkaCopy.value("inventory.image"), systemImage: "photo").fixedSize(horizontal: false, vertical: true)
                }.frame(minHeight: 44)
                #else
                Button { importing = true } label: { Label(LinkaCopy.value("inventory.image"), systemImage: "photo").fixedSize(horizontal: false, vertical: true) }
                    .frame(minHeight: 44)
                #endif
            }
            if session.recognizing { ProgressView(LinkaCopy.value("inventory.ocr.progress")) }
            if !session.candidates.isEmpty {
                Text(LinkaCopy.value("inventory.ocr.confirm")).font(.subheadline)
                ForEach(Array(session.candidates.enumerated()), id: \.offset) { _, candidate in
                    Button(identityLabel(candidate)) { session.selectCandidate(candidate) }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                }
            }
        }
    }
    private var photoActionsLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        }
        return AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }
    private var researchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if session.proposal == nil && session.draft.specifications == nil {
                    searchButton.buttonStyle(.borderedProminent)
                } else {
                    searchButton.buttonStyle(.borderless)
                }
            }
            if session.researching {
                ProgressView(LinkaCopy.value("inventory.research.progress"))
                    .accessibilityIdentifier("inventory.research.progress")
                Button(LinkaCopy.value("common.cancel")) { session.cancel() }
                    .frame(minHeight: 44).accessibilityIdentifier("inventory.research.cancel")
            }
            if let message = session.message {
                Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inventory.research.message")
            }
            if let result = session.researchResult, result.status == .ambiguous {
                ForEach(result.candidates) { candidate in
                    Button(identityLabel(candidate.identity)) {
                        identificationFocused = false
                        session.selectResearchCandidate(candidate.identity)
                    }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                }
            }
            if let snapshot = session.proposal ?? session.draft.specifications, !session.researching {
                confirmationCard(snapshot)
            } else if !session.researching {
                Button(action: save) {
                    Text(LinkaCopy.value(session.researchResult == nil && session.message == nil ? "inventory.saveWithoutResearch" : "inventory.saveWithoutSpecs"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!session.canSave || session.recognizing)
                .accessibilityIdentifier("inventory.saveWithoutResearch")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(LinkaCopy.value("inventory.research.disclosure")).font(.footnote).foregroundStyle(.secondary)
                Button(LinkaCopy.value("inventory.privacy.title")) { showingPrivacy = true }
                    .font(.footnote).frame(minHeight: 44)
            }
        }
    }
    private var searchButton: some View {
        Button(action: startResearch) {
            Text(LinkaCopy.value("inventory.research.action"))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(!session.canResearch || session.researching || session.recognizing)
        .accessibilityIdentifier("inventory.research")
    }
    private func confirmationCard(_ snapshot: DeviceSpecificationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LinkaCopy.value("inventory.confirm.title")).font(.headline)
                .accessibilityIdentifier("inventory.research.result")
                .accessibilityAddTraits(.isHeader)
            Text(identityLabel(snapshot.identity)).font(.title3.bold())
            if let kind = session.researchResult?.deviceKind {
                Text(LinkaCopy.value(kind == .ont ? "inventory.kind.fiberEquipment" : "inventory.kind.\(kind.rawValue)"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(SpecificationDisplay.summary(snapshot), id: \.self) { line in
                Text(line).font(.subheadline)
            }
            Button(action: save) {
                Text(LinkaCopy.value("inventory.save")).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent).disabled(!session.canSave)
            .accessibilityIdentifier("inventory.save")
            Button(LinkaCopy.value("inventory.correctIdentity")) {
                session.cancel(); identificationFocused = true
            }.frame(minHeight: 44)
            DisclosureGroup(LinkaCopy.value("inventory.detailsAndSources")) {
                DeviceSpecificationContent(snapshot: snapshot).padding(.top, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg))
    }
    private func identityLabel(_ identity: DeviceIdentity) -> String {
        [identity.brand, identity.model, identity.hardwareRevision ?? "", identity.marketRegion ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
    private func startResearch() {
        identificationFocused = false
        session.research()
    }
    private func save() {
        guard session.canSave, !saving else { return }
        let value = session.preparedForSaving()
        saving = true
        Task {
            if await store.save(value) { session.deactivate(); dismiss() }
            saving = false
        }
    }
}

/// Optional household details are edited only after the equipment has been saved.
private struct DeviceInstallationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LinkaInventoryStore
    @StateObject private var session: DeviceEditorSession
    @State private var saving = false
    @State private var confirmDiscard = false
    private let original: RegisteredNetworkDevice
    init(device: RegisteredNetworkDevice, store: LinkaInventoryStore) {
        self.store = store; original = device
        _session = StateObject(wrappedValue: DeviceEditorSession(device: device))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(LinkaCopy.value("inventory.completeDetails.subtitle")).foregroundStyle(.secondary)
                    TextField(LinkaCopy.value("inventory.nickname"), text: optional($session.draft.nickname))
                    Picker(LinkaCopy.value("inventory.kind"), selection: $session.draft.kind) {
                        ForEach(DeviceKind.allCases, id: \.self) { Text(LinkaCopy.value("inventory.kind.\($0.rawValue)")).tag($0) }
                    }
                }
                installationSection
                if let message = session.draftValidationMessage { Section { Text(message).foregroundStyle(.red) } }
                if let error = store.error { Section { Text(error).foregroundStyle(.red) } }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(LinkaCopy.value("inventory.completeDetails"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LinkaCopy.value("common.cancel")) {
                        if session.draft != original { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LinkaCopy.value("inventory.save")) {
                        saving = true
                        Task { if await store.save(session.draft) { dismiss() }; saving = false }
                    }.disabled(!session.canSave)
                }
            }
            .disabled(saving)
        }
        .interactiveDismissDisabled(saving || session.draft != original)
        .alert(LinkaCopy.value("inventory.discard.title"), isPresented: $confirmDiscard) {
            Button(LinkaCopy.value("inventory.discard"), role: .destructive) { dismiss() }
            Button(LinkaCopy.value("inventory.keepEditing"), role: .cancel) {}
        } message: { Text(LinkaCopy.value("inventory.discard.message")) }
        .onDisappear { session.deactivate() }
        .onChange(of: store.devices) { devices in
            if !devices.contains(where: { $0.id == session.draft.id }) { dismiss() }
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
    private func optional(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
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
