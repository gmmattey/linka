#if os(macOS)
import SwiftUI
import Charts
import NetworkCore
import MeasurementHistory
import LinkaEntitlements
import LinkaModules

extension NetworkMeasurement {
    var sortDate: Date { measuredAt }
    var sortDownload: Double { downloadMbps ?? -1 }
    var sortUpload: Double { uploadMbps ?? -1 }
    var sortPing: Double { latencyMs ?? .greatestFiniteMagnitude }
    var sortJitter: Double { jitterMs ?? .greatestFiniteMagnitude }
    var sortNetwork: String { MacMeasurementFormat.networkName(self) }
}

private enum MacHistoryFilter: Hashable {
    case all, wifi, cable

    func matches(_ m: NetworkMeasurement) -> Bool {
        switch self {
        case .all: return true
        case .wifi: return m.connectionKind == .wifi
        case .cable: return m.connectionKind == .ethernet
        }
    }
}

/// Histórico no padrão Mac: resumo em cartões, gráfico de tendência, tabela
/// com colunas ordenáveis e painel de detalhes. Excluir pede confirmação.
struct MacHistoryView: View {
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @ObservedObject private var center = MacCommandCenter.shared
    @AppStorage(MacWindowPreferences.inspectorKey) private var inspectorVisible = true
    @AppStorage(MacSettingsKeys.confirmDelete) private var confirmDelete = true

    let onMeasureAgain: () -> Void

    @State private var measurements: [NetworkMeasurement] = []
    @State private var selection: Set<UUID> = []
    @State private var sortOrder: [KeyPathComparator<NetworkMeasurement>] = [KeyPathComparator(\.sortDate, order: .reverse)]
    @State private var filter: MacHistoryFilter = .all
    @State private var search = ""
    @State private var pendingDeletion: [NetworkMeasurement] = []
    @State private var showShare = false
    @State private var isLoading = true

    private var filtered: [NetworkMeasurement] {
        let base = measurements.filter { filter.matches($0) }
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        return base.filter { MacMeasurementFormat.networkName($0).localizedCaseInsensitiveContains(search) }
    }

    private var visible: [NetworkMeasurement] { filtered.sorted(using: sortOrder) }

    private var selected: [NetworkMeasurement] {
        measurements.filter { selection.contains($0.id) }
    }

    private var peakDownload: Double {
        max(visible.compactMap(\.downloadMbps).max() ?? 1, 1)
    }

    var body: some View {
        HStack(spacing: 0) {
            content
            if inspectorVisible {
                inspector
            }
        }
        .navigationSubtitle(String(format: LinkaCopy.value("%d medições"), measurements.count))
        .searchable(text: $search, placement: .toolbar, prompt: LinkaCopy.value("Buscar"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { MacMeasurementFormat.exportCSV(visible) } label: {
                    Label(LinkaCopy.value("Exportar CSV"), systemImage: "square.and.arrow.up")
                }
                .help(LinkaCopy.value("Exportar histórico em CSV"))
                .disabled(measurements.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { inspectorVisible.toggle() } label: {
                    Label(LinkaCopy.value("Inspetor"), systemImage: "sidebar.right")
                }
                .help(LinkaCopy.value(inspectorVisible ? "Ocultar inspetor" : "Mostrar inspetor"))
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .linkaHistoryDidChange)) { _ in
            Task { await load() }
        }
        .onChange(of: selection) { _ in updateCommandState() }
        .onChange(of: center.deleteRequest) { requested in
            guard requested else { return }
            center.deleteRequest = false
            if !selected.isEmpty { askToDelete(selected) }
        }
        .onChange(of: center.shareRequest) { requested in
            guard requested else { return }
            center.shareRequest = false
            if selected.count == 1 { showShare = true }
        }
        .onDisappear {
            center.canDelete = false
            center.canShare = false
        }
        .shareMeasurementSheet(isPresented: $showShare, measurement: selected.count == 1 ? selected.first : nil)
        .alert(
            LinkaCopy.value(pendingDeletion.count > 1 ? "Excluir estas medições?" : "history.delete.title"),
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
        ) {
            Button(LinkaCopy.value("common.delete"), role: .destructive) { delete(pendingDeletion) }
            Button(LinkaCopy.value("common.cancel"), role: .cancel) { pendingDeletion = [] }
        } message: {
            Text(LinkaCopy.value("history.delete.message"))
        }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if measurements.isEmpty {
            VStack(spacing: 14) {
                MacIconBadge(systemImage: "chart.bar.fill", tint: MacPalette.download, size: 72)
                Text(LinkaCopy.value("Nenhuma medição ainda")).font(MacType.title)
                Text(LinkaCopy.value("Faça um teste para começar o seu histórico."))
                    .font(MacType.body).foregroundStyle(.secondary)
                Button(LinkaCopy.value("Iniciar teste"), action: onMeasureAgain)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.brandAccentWarm)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("", selection: $filter) {
                        Text(LinkaCopy.value("Todas")).tag(MacHistoryFilter.all)
                        Text("Wi-Fi").tag(MacHistoryFilter.wifi)
                        Text(LinkaCopy.value("Cabo")).tag(MacHistoryFilter.cable)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.large)
                    .frame(width: 280)

                    overviewCard

                    table
                        .frame(height: CGFloat(visible.count) * 46 + 40)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.macCard).shadow(color: .black.opacity(0.22), radius: 22, y: 12))
                }
                .padding(24)
            }
        }
    }

    /// Um único cartão: números-chave do período e o gráfico de tendência.
    private var overviewCard: some View {
        let downloads = visible.compactMap(\.downloadMbps)
        let uploads = visible.compactMap(\.uploadMbps)
        let pings = visible.compactMap(\.latencyMs)
        let average: ([Double]) -> String = { $0.isEmpty ? "—" : MacMeasurementFormat.mbps($0.reduce(0, +) / Double($0.count)) }
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LinkaCopy.value("Tendência de velocidade")).font(MacType.section)
                    Text(String(format: LinkaCopy.value("%d medições"), visible.count))
                        .font(MacType.label).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                stat(LinkaCopy.value("Melhor download"), downloads.max().map { MacMeasurementFormat.mbps($0) } ?? "—", "Mbps", MacPalette.download)
                stat(LinkaCopy.value("Download médio"), average(downloads), "Mbps", MacPalette.download)
                stat(LinkaCopy.value("Upload médio"), average(uploads), "Mbps", MacPalette.upload)
                stat(LinkaCopy.value("Ping médio"), pings.isEmpty ? "—" : String(Int(round(pings.reduce(0, +) / Double(pings.count)))), "ms", MacPalette.ping)
            }
            if visible.count > 1 {
                trendChart
                HStack(spacing: 18) {
                    Spacer()
                    legendDot(MacPalette.download, "Download")
                    legendDot(MacPalette.upload, "Upload")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .linkaMacCard(padding: 24)
    }

    private func stat(_ title: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MacType.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(MacType.metric(26)).monospacedDigit().foregroundStyle(tint)
                Text(unit).font(MacType.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var trendChart: some View {
        Chart {
            ForEach(visible.sorted { $0.measuredAt < $1.measuredAt }) { m in
                if let down = m.downloadMbps {
                    AreaMark(x: .value("Data", m.measuredAt), y: .value("Mbps", down), series: .value("Série", "DownloadArea"))
                        .foregroundStyle(LinearGradient(colors: [MacPalette.download.opacity(0.30), MacPalette.download.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Data", m.measuredAt), y: .value("Mbps", down), series: .value("Série", "Download"))
                        .foregroundStyle(MacPalette.download)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Data", m.measuredAt), y: .value("Mbps", down))
                        .foregroundStyle(MacPalette.download)
                        .symbolSize(40)
                }
                if let up = m.uploadMbps {
                    LineMark(x: .value("Data", m.measuredAt), y: .value("Mbps", up), series: .value("Série", "Upload"))
                        .foregroundStyle(MacPalette.upload)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 5]))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel().font(MacType.caption)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(MacType.caption)
            }
        }
        .frame(height: 170)
        .accessibilityLabel(LinkaCopy.value("Tendência de velocidade"))
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(MacType.label).foregroundStyle(.secondary)
        }
    }

    private var table: some View {
        Table(visible, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(LinkaCopy.value("Data"), value: \.sortDate) { m in
                Text(m.measuredAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(MacType.body)
            }
            .width(min: 110, ideal: 130)
            TableColumn(LinkaCopy.value("Rede"), value: \.sortNetwork) { m in
                HStack(spacing: 8) {
                    Image(systemName: m.connectionKind == .ethernet ? "cable.connector" : "wifi")
                        .foregroundStyle(MacPalette.download)
                    Text(MacMeasurementFormat.networkName(m)).font(MacType.body).lineLimit(1)
                }
            }
            .width(min: 90, ideal: 120)
            TableColumn("Download", value: \.sortDownload) { m in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(MacMeasurementFormat.mbps(m.downloadMbps)) Mbps")
                        .font(MacType.bodyStrong).monospacedDigit()
                    Capsule().fill(MacPalette.download.opacity(0.85))
                        .frame(width: 70 * CGFloat((m.downloadMbps ?? 0) / peakDownload), height: 4)
                }
            }
            .width(min: 110, ideal: 130)
            TableColumn("Upload", value: \.sortUpload) { m in
                Text("\(MacMeasurementFormat.mbps(m.uploadMbps)) Mbps").font(MacType.body).monospacedDigit()
            }
            .width(min: 95, ideal: 110)
            TableColumn("Ping", value: \.sortPing) { m in
                Text(MacMeasurementFormat.ms(m.latencyMs)).font(MacType.body).monospacedDigit()
            }
            .width(min: 60, ideal: 70)
            TableColumn("Jitter", value: \.sortJitter) { m in
                Text(MacMeasurementFormat.ms(m.jitterMs)).font(MacType.body).monospacedDigit()
            }
            .width(min: 60, ideal: 70)
            TableColumn(LinkaCopy.value("Qualidade")) { m in
                if let quality = MacMeasurementFormat.quality(m) {
                    MacStatusTag(label: quality.label, color: quality.color)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .environment(\.defaultMinListRowHeight, 46)
        .contextMenu(forSelectionType: UUID.self) { ids in
            let items = measurements.filter { ids.contains($0.id) }
            if items.count == 1 {
                Button(LinkaCopy.value("Compartilhar…")) { selection = ids; showShare = true }
                Button(LinkaCopy.value("Medir novamente"), action: onMeasureAgain)
            }
            if !items.isEmpty {
                Button(LinkaCopy.value("Excluir…"), role: .destructive) { askToDelete(items) }
            }
        }
    }

    // MARK: Inspetor

    private var inspector: some View {
        MacInspectorPanel {
            if selected.count == 1, let m = selected.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.measuredAt, format: .dateTime.day().month(.wide).hour().minute())
                        .font(MacType.section)
                    Text(MacMeasurementFormat.networkName(m))
                        .font(MacType.body).foregroundStyle(.secondary)
                    if let quality = MacMeasurementFormat.quality(m) {
                        MacStatusTag(label: quality.label, color: quality.color).padding(.top, 6)
                    }
                }
                VStack(spacing: 12) {
                    inspectorMetric("Download", "\(MacMeasurementFormat.mbps(m.downloadMbps))", "Mbps", "arrow.down.circle.fill", MacPalette.download)
                    inspectorMetric("Upload", "\(MacMeasurementFormat.mbps(m.uploadMbps))", "Mbps", "arrow.up.circle.fill", MacPalette.upload)
                    inspectorMetric("Ping", m.latencyMs.map { String(Int(round($0))) } ?? "—", "ms", "timer", MacPalette.ping)
                }
                MacInspectorSection(LinkaCopy.value("Detalhes da medição")) {
                    MacInspectorRow(label: "Jitter", value: MacMeasurementFormat.ms(m.jitterMs))
                    if let loss = m.packetLossPercent {
                        MacInspectorRow(label: LinkaCopy.value("Perda de pacotes"), value: String(format: "%.1f %%", loss))
                    }
                    if let dns = m.dnsResolutionMs {
                        MacInspectorRow(label: LinkaCopy.value("Resolução de DNS"), value: MacMeasurementFormat.ms(dns))
                    }
                    if let loaded = m.loadedLatencyMs {
                        MacInspectorRow(label: LinkaCopy.value("Latência sob carga"), value: MacMeasurementFormat.ms(loaded))
                    }
                    if let band = m.wifiContext?.bandGHz {
                        MacInspectorRow(label: LinkaCopy.value("network.wifiBand"), value: String(format: "%g GHz", band))
                    }
                    if let rssi = m.wifiContext?.rssiDbm {
                        MacInspectorRow(label: LinkaCopy.value("Sinal"), value: "\(Int(rssi)) dBm")
                    }
                    if let link = m.wifiContext?.linkSpeedMbps {
                        MacInspectorRow(label: LinkaCopy.value("Velocidade do link"), value: "\(Int(link)) Mbps")
                    }
                }
                MacInspectorSection {
                    MacInspectorAction(title: LinkaCopy.value("Compartilhar…")) { showShare = true }
                    MacInspectorAction(title: LinkaCopy.value("Medir novamente"), shortcut: "⌘R", action: onMeasureAgain)
                    MacInspectorAction(title: LinkaCopy.value("Excluir…"), role: .destructive, shortcut: "⌘⌫") {
                        askToDelete([m])
                    }
                }
            } else if selected.count > 1 {
                MacInspectorSection(LinkaCopy.value("Seleção")) {
                    Text(String(format: LinkaCopy.value("%d medições selecionadas"), selected.count)).font(MacType.headline)
                }
                MacInspectorSection {
                    MacInspectorAction(title: LinkaCopy.value("Excluir…"), role: .destructive, shortcut: "⌘⌫") {
                        askToDelete(selected)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    MacIconBadge(systemImage: "cursorarrow.click", tint: MacPalette.download, size: 52)
                    Text(LinkaCopy.value("Selecione uma medição para ver os detalhes."))
                        .font(MacType.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
    }

    private func inspectorMetric(_ title: String, _ value: String, _ unit: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            MacIconBadge(systemImage: icon, tint: tint, size: 38)
            Text(title).font(MacType.body).foregroundStyle(.secondary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(MacType.metric(26)).monospacedDigit()
                Text(unit).font(MacType.label).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.macWell, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Dados

    private func load() async {
        let repo = LinkaMeasurementHistory.makeRepository(entitlements: entitlements)
        let all = (try? await repo.measurements(matching: MeasurementQuery(sortOrder: .newestFirst))) ?? []
        await MainActor.run {
            measurements = all
            selection = selection.filter { id in all.contains { $0.id == id } }
            isLoading = false
            updateCommandState()
        }
    }

    private func askToDelete(_ items: [NetworkMeasurement]) {
        if confirmDelete { pendingDeletion = items } else { delete(items) }
    }

    private func delete(_ items: [NetworkMeasurement]) {
        pendingDeletion = []
        Task { @MainActor in
            let repo = LinkaMeasurementHistory.makeRepository(entitlements: entitlements)
            for item in items { try? await repo.delete(id: item.id) }
            selection.subtract(items.map(\.id))
            await load()
            NotificationCenter.default.post(name: .linkaHistoryDidChange, object: nil)
        }
    }

    private func updateCommandState() {
        center.canDelete = !selected.isEmpty
        center.canShare = selected.count == 1
    }
}
#endif
