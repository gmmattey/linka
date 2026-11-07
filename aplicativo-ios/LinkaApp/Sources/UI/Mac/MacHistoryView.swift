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

/// Histórico no padrão Mac: tabela com colunas ordenáveis, seleção múltipla e
/// painel de detalhes à direita. Excluir pede confirmação.
struct MacHistoryView: View {
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @ObservedObject private var center = MacCommandCenter.shared
    @AppStorage(MacWindowPreferences.inspectorKey) private var inspectorVisible = true

    let onMeasureAgain: () -> Void

    @State private var measurements: [NetworkMeasurement] = []
    @State private var selection: Set<UUID> = []
    @State private var sortOrder: [KeyPathComparator<NetworkMeasurement>] = [KeyPathComparator(\.sortDate, order: .reverse)]
    @State private var filter: MacHistoryFilter = .all
    @State private var search = ""
    @State private var pendingDeletion: [NetworkMeasurement] = []
    @State private var showShare = false
    @State private var isLoading = true

    private var visible: [NetworkMeasurement] {
        let base = measurements.filter { filter.matches($0) }
        let searched = search.trimmingCharacters(in: .whitespaces).isEmpty ? base : base.filter {
            MacMeasurementFormat.networkName($0).localizedCaseInsensitiveContains(search)
        }
        return searched.sorted(using: sortOrder)
    }

    private var selected: [NetworkMeasurement] {
        measurements.filter { selection.contains($0.id) }
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
            if !selected.isEmpty { pendingDeletion = selected }
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
            VStack(spacing: 10) {
                Image(systemName: "chart.bar").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                Text(LinkaCopy.value("Nenhuma medição ainda")).font(.title3.weight(.semibold))
                Text(LinkaCopy.value("Faça um teste para começar o seu histórico."))
                    .foregroundStyle(.secondary)
                Button(LinkaCopy.value("Iniciar teste"), action: onMeasureAgain)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.brandAccentWarm)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Picker("", selection: $filter) {
                        Text(LinkaCopy.value("Todas")).tag(MacHistoryFilter.all)
                        Text("Wi-Fi").tag(MacHistoryFilter.wifi)
                        Text(LinkaCopy.value("Cabo")).tag(MacHistoryFilter.cable)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)

                if visible.count > 1 {
                    trendChart
                        .frame(height: 130)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }
                table
            }
        }
    }

    private var trendChart: some View {
        Chart {
            ForEach(visible.sorted { $0.measuredAt < $1.measuredAt }) { m in
                if let down = m.downloadMbps {
                    LineMark(x: .value("Data", m.measuredAt), y: .value("Mbps", down), series: .value("Série", "Download"))
                        .foregroundStyle(Color.chartDownloadSeries)
                        .interpolationMethod(.monotone)
                }
                if let up = m.uploadMbps {
                    LineMark(x: .value("Data", m.measuredAt), y: .value("Mbps", up), series: .value("Série", "Upload"))
                        .foregroundStyle(Color.chartUploadSeries.opacity(0.55))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYAxisLabel("Mbps", position: .top, alignment: .leading)
        .accessibilityLabel(LinkaCopy.value("Tendência de velocidade"))
    }

    private var table: some View {
        Table(visible, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(LinkaCopy.value("Data"), value: \.sortDate) { m in
                Text(m.measuredAt, format: .dateTime.day().month(.abbreviated).hour().minute())
            }
            .width(min: 100, ideal: 120)
            TableColumn(LinkaCopy.value("Rede"), value: \.sortNetwork) { m in
                Text(MacMeasurementFormat.networkName(m)).lineLimit(1)
            }
            .width(min: 70, ideal: 100)
            TableColumn("Download", value: \.sortDownload) { m in
                Text("\(MacMeasurementFormat.mbps(m.downloadMbps)) Mbps").monospacedDigit()
            }
            .width(min: 82, ideal: 96)
            TableColumn("Upload", value: \.sortUpload) { m in
                Text("\(MacMeasurementFormat.mbps(m.uploadMbps)) Mbps").monospacedDigit()
            }
            .width(min: 82, ideal: 96)
            TableColumn("Ping", value: \.sortPing) { m in
                Text(MacMeasurementFormat.ms(m.latencyMs)).monospacedDigit()
            }
            .width(min: 52, ideal: 64)
            TableColumn("Jitter", value: \.sortJitter) { m in
                Text(MacMeasurementFormat.ms(m.jitterMs)).monospacedDigit()
            }
            .width(min: 52, ideal: 64)
            TableColumn(LinkaCopy.value("Qualidade")) { m in
                if let quality = MacMeasurementFormat.quality(m) {
                    MacStatusTag(label: quality.label, color: quality.color)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 74, ideal: 84)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            let items = measurements.filter { ids.contains($0.id) }
            if items.count == 1 {
                Button(LinkaCopy.value("Compartilhar…")) { selection = ids; showShare = true }
                Button(LinkaCopy.value("Medir novamente"), action: onMeasureAgain)
                Divider()
            }
            if !items.isEmpty {
                Button(LinkaCopy.value("Excluir…"), role: .destructive) { pendingDeletion = items }
            }
        }
    }

    // MARK: Inspetor

    private var inspector: some View {
        MacInspectorPanel {
            if selected.count == 1, let m = selected.first {
                MacInspectorSection(LinkaCopy.value("Medição selecionada")) {
                    Text(m.measuredAt, format: .dateTime.day().month(.wide).hour().minute())
                        .font(.headline)
                    Text(MacMeasurementFormat.networkName(m))
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                    MacInspectorRow(label: "Download", value: "\(MacMeasurementFormat.mbps(m.downloadMbps)) Mbps")
                    MacInspectorRow(label: "Upload", value: "\(MacMeasurementFormat.mbps(m.uploadMbps)) Mbps")
                    MacInspectorRow(label: "Ping", value: MacMeasurementFormat.ms(m.latencyMs))
                    MacInspectorRow(label: "Jitter", value: MacMeasurementFormat.ms(m.jitterMs))
                    if let loss = m.packetLossPercent {
                        MacInspectorRow(label: LinkaCopy.value("Perda de pacotes"), value: String(format: "%.1f %%", loss))
                    }
                    if let dns = m.dnsResolutionMs {
                        MacInspectorRow(label: LinkaCopy.value("Resolução de DNS"), value: MacMeasurementFormat.ms(dns))
                    }
                    if let band = m.wifiContext?.bandGHz {
                        MacInspectorRow(label: LinkaCopy.value("network.wifiBand"), value: String(format: "%g GHz", band))
                    }
                }
                MacInspectorSection {
                    MacInspectorAction(title: LinkaCopy.value("Compartilhar…")) { showShare = true }
                    Divider()
                    MacInspectorAction(title: LinkaCopy.value("Medir novamente"), shortcut: "⌘R", action: onMeasureAgain)
                    Divider()
                    MacInspectorAction(title: LinkaCopy.value("Excluir…"), role: .destructive, shortcut: "⌘⌫") {
                        pendingDeletion = [m]
                    }
                }
            } else if selected.count > 1 {
                MacInspectorSection(LinkaCopy.value("Seleção")) {
                    Text(String(format: LinkaCopy.value("%d medições selecionadas"), selected.count)).font(.headline)
                }
                MacInspectorSection {
                    MacInspectorAction(title: LinkaCopy.value("Excluir…"), role: .destructive, shortcut: "⌘⌫") {
                        pendingDeletion = selected
                    }
                }
            } else {
                MacInspectorSection(LinkaCopy.value("Medição selecionada")) {
                    Text(LinkaCopy.value("Selecione uma medição para ver os detalhes."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
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
