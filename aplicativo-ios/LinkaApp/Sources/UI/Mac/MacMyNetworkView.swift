#if os(macOS)
import SwiftUI
import NetworkInventory
import NetworkProfiles
import NetworkSpatial
import LinkaEntitlements
import LinkaModules

/// Minha Rede no padrão Mac: resumo em cartões, equipamentos em grade, plano de
/// internet com a entrega medida, cobertura da casa e acesso ao roteador.
/// Usa o mesmo cadastro local da versão de iPhone e iPad.
struct MacMyNetworkView: View {
    @StateObject private var store = LinkaInventoryStore()
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider

    @State private var editingDevice: RegisteredNetworkDevice?
    @State private var editingPlan = false
    @State private var managingEnvironments = false
    @State private var showPurchase = false
    @State private var spatialSummary: MyNetworkView.SpatialSummary?

    private let deviceColumns = [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if store.devices.isEmpty {
                    emptyHero
                } else {
                    summaryRow
                    equipmentSection
                    planSection
                    if MacFeatures.homeCoverage, #available(macOS 14.0, *) { homeSection }
                    environmentsSection
                }
                if MacFeatures.routerPanel { accessCard }
                footer
            }
            .padding(28)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addDevice) {
                    Label(LinkaCopy.value("inventory.devices.add"), systemImage: "plus")
                }
                .help(LinkaCopy.value("inventory.devices.add"))
            }
        }
        .overlay { if store.loading && store.devices.isEmpty { ProgressView() } }
        .task {
            await store.reload()
            if #available(macOS 14.0, *) { spatialSummary = SpatialCoverageBridge.shared.loadSummary() }
        }
        .onReceive(NotificationCenter.default.publisher(for: LinkaHousehold.didChange)) { _ in
            Task { await store.reload() }
        }
        .sheet(item: $editingDevice) { device in
            DeviceEditorView(device: device, store: store)
                .frame(minWidth: 580, idealWidth: 640, minHeight: 520, idealHeight: 650)
        }
        .onChange(of: editingPlan) { if $0 { MacAnalytics.shared.track(.myNetworkAction(action: "edit_plan")) } }
        .onChange(of: managingEnvironments) { if $0 { MacAnalytics.shared.track(.myNetworkAction(action: "manage_environments")) } }
        .sheet(isPresented: $editingPlan) {
            ServicePlanEditorView(plan: store.activePlan, store: store)
                .frame(minWidth: 520, idealWidth: 600, minHeight: 500)
        }
        .sheet(isPresented: $managingEnvironments) {
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
                        Button(LinkaCopy.value("common.close")) { managingEnvironments = false }
                    }
                }
            }
            .frame(minWidth: 520, idealWidth: 600, minHeight: 480)
        }
        .sheet(isPresented: $showPurchase) {
            PurchaseSheet(entryPoint: .optimization)
                .environmentObject(entitlements)
                .frame(minWidth: 500, idealWidth: 560, minHeight: 580)
        }
    }

    // MARK: Resumo

    private var summaryRow: some View {
        HStack(spacing: 16) {
            MacMetricTile(
                title: LinkaCopy.value("inventory.overview.equipment"),
                value: "\(store.devices.count)",
                unit: LinkaCopy.value(store.devices.count == 1 ? "equipamento" : "equipamentos"),
                systemImage: "wifi.router", tint: MacPalette.download, valueSize: 38)
            MacMetricTile(
                title: LinkaCopy.value("Internet contratada"),
                value: store.activePlan?.nominalDownloadMbps.map(formatSpeed) ?? "—",
                unit: "Mbps",
                systemImage: "arrow.down.circle.fill", tint: MacPalette.upload, valueSize: 38,
                caption: store.activePlan?.ispName)
            MacMetricTile(
                title: LinkaCopy.value("Ambientes"),
                value: "\(store.environments.count)",
                unit: LinkaCopy.value(store.environments.count == 1 ? "ambiente" : "ambientes"),
                systemImage: "house.fill", tint: MacPalette.ping, valueSize: 38)
        }
    }

    // MARK: Equipamentos

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(LinkaCopy.value("inventory.overview.equipment")).font(MacType.section)
                Spacer()
                Button(action: addDevice) {
                    Label(LinkaCopy.value("inventory.devices.add"), systemImage: "plus")
                }
                .controlSize(.large)
            }
            LazyVGrid(columns: deviceColumns, spacing: 16) {
                ForEach(store.devices) { device in
                    NavigationLink {
                        DeviceDetailView(deviceID: device.id, store: store)
                    } label: {
                        HStack(spacing: 14) {
                            MacIconBadge(systemImage: icon(for: device.kind), tint: MacPalette.download, size: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.inventoryTitle)
                                    .font(MacType.headline)
                                    .lineLimit(1)
                                Text(subtitle(for: device))
                                    .font(MacType.label)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .linkaMacCard()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if store.devices.count >= 2 {
                NavigationLink {
                    NetworkConnectionsListView(store: store)
                } label: {
                    HStack(spacing: 14) {
                        MacIconBadge(systemImage: "point.3.connected.trianglepath.dotted", tint: MacPalette.upload, size: 40)
                        Text(LinkaCopy.value("inventory.overview.connections")).font(MacType.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .linkaMacCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyHero: some View {
        VStack(spacing: 16) {
            MacIconBadge(systemImage: "wifi.router.fill", tint: MacPalette.download, size: 84)
            Text(LinkaCopy.value("Cadastre seus equipamentos")).font(MacType.title)
            Text(LinkaCopy.value("Roteador, modem, mesh ou repetidor ajudam a entender onde o sinal cai. Tudo fica só neste Mac."))
                .font(MacType.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button(action: addDevice) {
                Label(LinkaCopy.value("inventory.devices.add"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.brandAccentWarm)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .linkaMacCard(padding: 24)
    }

    // MARK: Internet da casa

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LinkaCopy.value("inventory.overview.internet")).font(MacType.section)
            if let plan = store.activePlan {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        MacIconBadge(systemImage: "network", tint: MacPalette.upload, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.ispName).font(MacType.headline)
                            Text([plan.planName, LinkaCopy.value("inventory.technology.\(plan.technology.rawValue)")]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(MacType.label).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let cents = plan.monthlyCostCents {
                            MacStatusTag(label: formatCost(cents), color: MacPalette.upload)
                        }
                        Button(LinkaCopy.value("inventory.plan.edit")) { editingPlan = true }
                            .controlSize(.large)
                    }
                    HStack(spacing: 16) {
                        if let dl = plan.nominalDownloadMbps {
                            planSpeed(title: "Download", value: dl, icon: "arrow.down.circle.fill", tint: MacPalette.download)
                        }
                        if let ul = plan.nominalUploadMbps {
                            planSpeed(title: "Upload", value: ul, icon: "arrow.up.circle.fill", tint: MacPalette.upload)
                        }
                    }
                    if let evaluation = store.planEvaluation { evaluationBlock(evaluation) }
                }
                .linkaMacCard(padding: 22)
            } else {
                HStack(spacing: 16) {
                    MacIconBadge(systemImage: "network", tint: MacPalette.upload, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LinkaCopy.value("inventory.plan.card.empty")).font(MacType.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(LinkaCopy.value("inventory.plan.cta.add")) { editingPlan = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(Color.brandAccentWarm)
                }
                .linkaMacCard(padding: 22)
            }
        }
    }

    private func planSpeed(title: String, value: Double, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            MacIconBadge(systemImage: icon, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MacType.label).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(formatSpeed(value)).font(MacType.metric(30)).monospacedDigit()
                    Text("Mbps").font(MacType.label).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func evaluationBlock(_ evaluation: ResidentialPlanAggregateEvaluation) -> some View {
        let info = evaluationInfo(evaluation)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                MacIconBadge(systemImage: info.icon, tint: info.tint, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title).font(MacType.headline)
                    Text(info.message).font(MacType.label).foregroundStyle(.secondary)
                }
            }
            if evaluation.eligibleMeasurementsCount > 0 {
                if let dl = evaluation.downloadAggregate {
                    deliveryBar(title: "Download", delivery: dl, tint: MacPalette.download)
                }
                if let ul = evaluation.uploadAggregate {
                    deliveryBar(title: "Upload", delivery: ul, tint: MacPalette.upload)
                }
                Text(String(format: LinkaCopy.value("inventory.evaluation.sampleCount"), evaluation.eligibleMeasurementsCount))
                    .font(MacType.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func deliveryBar(title: String, delivery: PlanMetricAggregateDelivery, tint: Color) -> some View {
        let fraction = min(max(delivery.averageDeliveredPercent / 100, 0), 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(MacType.bodyStrong)
                Spacer()
                Text("\(formatSpeed(delivery.averageMbps)) / \(formatSpeed(delivery.nominalMbps)) Mbps · \(Int(round(delivery.averageDeliveredPercent)))%")
                    .font(MacType.label).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { proxy in
                Capsule().fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: proxy.size.width * CGFloat(fraction))
                    }
            }
            .frame(height: 10)
        }
    }

    private struct EvaluationInfo { let icon: String; let tint: Color; let title: String; let message: String }

    private func evaluationInfo(_ evaluation: ResidentialPlanAggregateEvaluation) -> EvaluationInfo {
        if evaluation.eligibleMeasurementsCount == 0 ||
            (evaluation.downloadEvaluation.isNoData && evaluation.uploadEvaluation.isNoData) {
            return EvaluationInfo(icon: "network.badge.shield.half.filled", tint: .secondary,
                                  title: LinkaCopy.value("inventory.evaluation.noData.title"),
                                  message: LinkaCopy.value("inventory.evaluation.noData.message"))
        }
        let statuses = [evaluation.downloadAggregate?.status, evaluation.uploadAggregate?.status].compactMap { $0 }
        if statuses.contains(.belowPlan) {
            return EvaluationInfo(icon: "exclamationmark.triangle.fill", tint: .statusAttention,
                                  title: LinkaCopy.value("inventory.evaluation.below.title"),
                                  message: LinkaCopy.value("inventory.evaluation.below.message"))
        } else if statuses.contains(.partiallyMeeting) {
            return EvaluationInfo(icon: "exclamationmark.triangle.fill", tint: .statusAttention,
                                  title: LinkaCopy.value("inventory.evaluation.partiallyMeeting.title"),
                                  message: LinkaCopy.value("inventory.evaluation.partiallyMeeting.message"))
        } else if !statuses.isEmpty && statuses.allSatisfy({ $0 == .exceeding }) {
            return EvaluationInfo(icon: "checkmark.seal.fill", tint: .statusGood,
                                  title: LinkaCopy.value("inventory.evaluation.exceeding.title"),
                                  message: LinkaCopy.value("inventory.evaluation.exceeding.message"))
        }
        return EvaluationInfo(icon: "checkmark.seal.fill", tint: .statusGood,
                              title: LinkaCopy.value("inventory.evaluation.meeting.title"),
                              message: LinkaCopy.value("inventory.evaluation.meeting.message"))
    }

    // MARK: Casa e ambientes

    @available(macOS 14.0, *)
    private var homeSection: some View {
        let summary = spatialSummary ?? SpatialCoverageBridge.shared.loadSummary()
        let percent = Double(summary.totalCoveragePercent) / 100
        let tint: Color = summary.totalCoveragePercent >= 80 ? .statusGood : (summary.totalCoveragePercent >= 50 ? .statusAttention : .statusCritical)
        return VStack(alignment: .leading, spacing: 14) {
            Text(LinkaCopy.value("inventory.overview.home")).font(MacType.section)
            NavigationLink {
                HomeView(
                    dataStore: SpatialCoverageBridge.shared.dataStore,
                    wrapInNavigationStack: false,
                    title: LinkaCopy.value("inventory.spatial.title", defaultValue: "Cobertura Residencial")
                )
            } label: {
                HStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 9)
                        Circle().trim(from: 0, to: summary.measuredCount > 0 ? percent : 0)
                            .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(summary.measuredCount > 0 ? "\(summary.totalCoveragePercent)%" : "—")
                            .font(MacType.metric(20)).monospacedDigit()
                    }
                    .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.houseName).font(MacType.headline)
                        Text(summary.measuredCount > 0
                             ? String(format: LinkaCopy.value("inventory.spatial.measuredCount", defaultValue: "%d de %d cômodos medidos"), summary.measuredCount, summary.totalRoomsCount)
                             : String(format: LinkaCopy.value("inventory.spatial.unmeasured", defaultValue: "%d cômodos cadastrados · Toque para mapear"), summary.totalRoomsCount))
                            .font(MacType.label).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .linkaMacCard(padding: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var environmentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(LinkaCopy.value("Ambientes")).font(MacType.section)
                Spacer()
                Button(LinkaCopy.value("inventory.environments.manage")) { managingEnvironments = true }
                    .controlSize(.large)
            }
            if store.environments.isEmpty {
                Text(LinkaCopy.value("inventory.overview.context.none"))
                    .font(MacType.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .linkaMacCard()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 12) {
                    ForEach(store.environments) { environment in
                        HStack(spacing: 10) {
                            MacIconBadge(systemImage: "house.fill", tint: MacPalette.ping, size: 34)
                            Text(environment.name).font(MacType.bodyStrong).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .linkaMacCard(padding: 12)
                    }
                }
            }
        }
    }

    // MARK: Acesso e rodapé

    private var accessCard: some View {
        NavigationLink {
            MacRouterPanelView()
        } label: {
            HStack(spacing: 16) {
                MacIconBadge(systemImage: "wifi.router", tint: MacPalette.network, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LinkaCopy.value("settings.routerAccess")).font(MacType.headline)
                    Text(LinkaCopy.value("Abra o painel do roteador da rede atual."))
                        .font(MacType.label).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .linkaMacCard(padding: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LinkaCopy.value("inventory.local")).font(MacType.caption).foregroundStyle(.secondary)
            if let error = store.error {
                HStack {
                    Text(error).font(MacType.label).foregroundStyle(Color.statusCritical)
                    Button(LinkaCopy.value("common.tryAgain")) { Task { await store.reload() } }
                }
            }
        }
    }

    // MARK: Ações e formatação

    private func addDevice() {
        MacAnalytics.shared.track(.myNetworkAction(action: "add_device"))
        editingDevice = RegisteredNetworkDevice(kind: .other, identity: .init(model: ""))
    }

    private func icon(for kind: DeviceKind) -> String {
        switch kind {
        case .modem: return "cable.connector"
        case .router, .modemRouter: return "wifi.router.fill"
        case .ont: return "cable.connector.horizontal"
        case .meshNode: return "dot.radiowaves.left.and.right"
        case .extender: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        }
    }

    private func subtitle(for device: RegisteredNetworkDevice) -> String {
        let kind = LinkaCopy.value(device.kind == .ont ? "inventory.kind.fiberEquipment" : "inventory.kind.\(device.kind.rawValue)")
        if let environment = store.environments.first(where: { $0.id == device.installation.environmentID })?.name,
           !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(kind) · \(environment)"
        }
        if let location = device.installation.locationLabel,
           !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(kind) · \(location)"
        }
        return kind
    }

    private func formatSpeed(_ speed: Double) -> String {
        speed.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", speed) : String(format: "%.1f", speed)
    }

    private func formatCost(_ cents: Int) -> String {
        String(format: LinkaCopy.value("inventory.plan.monthCostDisplay"), String(format: "%.2f", Double(cents) / 100.0))
    }
}
#endif
