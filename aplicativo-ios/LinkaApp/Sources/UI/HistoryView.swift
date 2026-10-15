import SwiftUI
import MapKit
import MeasurementHistory
import NetworkCore
import NetworkInsights
import LinkaEntitlements
import LinkaModules

enum HistoryDisplayMode {
    case list
    case map
}

private enum HistoryFilter: CaseIterable {
    case all, wifi, mobile
    var label: String { switch self { case .all: return LinkaCopy.value("history.filter.all"); case .wifi: return LinkaCopy.value("network.wifi"); case .mobile: return LinkaCopy.value("history.filter.mobile") } }
}

private enum HistorySort: CaseIterable, Hashable {
    case recent
    case fastest
    case slowest

    var label: String {
        switch self {
        case .recent: return LinkaCopy.value("history.sort.recent")
        case .fastest: return LinkaCopy.value("history.sort.fastest")
        case .slowest: return LinkaCopy.value("history.sort.slowest")
        }
    }
}

enum HistoryVisualizationState: Equatable {
    case empty
    case singleMeasurement
    case trend

    static func resolve(measurementCount: Int) -> Self {
        switch measurementCount {
        case ..<1: return .empty
        case 1: return .singleMeasurement
        default: return .trend
        }
    }
}

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @EnvironmentObject private var ads: LinkaAdsCoordinator
    var onSelectMeasurement: ((NetworkMeasurement) -> Void)? = nil

    @State private var measurements: [NetworkMeasurement] = []
    @State private var isLoading = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasPlus = false
    @State private var showPurchase = false
    @State private var purchaseEntryPoint: PurchaseEntryPoint = .historyInsights
    @State private var insightText: String?
    @State private var filter: HistoryFilter = .all
    @State private var sort: HistorySort = .recent
    #if os(macOS)
    @State private var selectedComparisonIDs: Set<UUID> = []
    @State private var showComparisonModal = false
    @State private var inspectedMeasurementID: UUID?
    @State private var searchQuery: String = ""
    #endif

    private var repository: any MeasurementHistoryRepository {
        LinkaMeasurementHistory.makeRepository(entitlements: entitlements)
    }

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        standardContent
        #endif
    }

    private var standardContent: some View {
        ZStack {
            LinkaScreenBackground(variant: .gradientOnly, showWaves: false)
                .ignoresSafeArea()
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        HStack {
                            Menu {
                                ForEach(availableFilters, id: \.self) { option in
                                    Button(option.label) { filter = option }
                                }
                            } label: {
                                Label(filter.label, systemImage: "line.3.horizontal.decrease.circle")
                            }
                            Spacer()
                            Menu {
                                ForEach(HistorySort.allCases, id: \.self) { option in
                                    Button {
                                        sort = option
                                    } label: {
                                        HStack {
                                            Text(option.label)
                                            if sort == option {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label(sort.label, systemImage: "arrow.up.arrow.down")
                            }
                        }
                        .font(.captionSmall)
                        .foregroundColor(.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    }

                    if hasPlus {
                        if let insightText = insightText {
                            Section(LinkaCopy.value("history.insights")) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.brandAccentWarm)
                                        .font(.bodyRegularStrong)
                                    Text(insightText)
                                        .font(.bodyRegular)
                                        .foregroundColor(.textPrimary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else if !filteredMeasurements.isEmpty {
                        Section(LinkaCopy.value("history.insights")) {
                            Button {
                                purchaseEntryPoint = .historyInsights
                                showPurchase = true
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.textSecondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LinkaCopy.value("history.plus.prompt"))
                                            .font(.bodyRegular)
                                            .foregroundColor(.textPrimary)
                                        LinkaPlusWordmarkView(height: 14)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.captionSmallStrong)
                                        .foregroundColor(.textSecondary.opacity(0.65))
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if historyVisualizationState == .trend {
                        Section {
                            HistoryWaveChartView(measurements: filteredMeasurements)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                        .listRowBackground(Color.clear)
                    }

                    if historyVisualizationState == .empty {
                        Section {
                            LinkaUnavailableState(
                                title: LinkaCopy.value("history.empty.title"),
                                message: LinkaCopy.value("history.empty.message"),
                                systemImage: "clock"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        // O anúncio fica no começo do conteúdo rolável, antes
                        // das medições. Só existe depois de o SDK entregar um
                        // native ad, portanto nunca cria um buraco na lista.
                        if showsHistoryAd {
                            historyAdRow
                        }

                        if historyVisualizationState == .singleMeasurement,
                           let measurement = filteredMeasurements.first {
                            Section {
                                Button { onSelectMeasurement?(measurement) } label: {
                                    HistorySingleMeasurementSummary(measurement: measurement)
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.clear)
                        }
                        if historyVisualizationState != .singleMeasurement {
                            Section("\(LinkaCopy.value("history.measurements")) (\(filteredMeasurements.count))") {
                                ForEach(filteredMeasurements, id: \.id) { measurement in
                                    Button {
                                        onSelectMeasurement?(measurement)
                                    } label: {
                                        AppleStyleHistoryRow(measurement: measurement)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(LinkaCopy.value("history.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showPurchase) {
            PurchaseSheet(entryPoint: purchaseEntryPoint) {
                loadData()
            }
            .environmentObject(entitlements)
        }
        .onAppear {
            loadData()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { prepareHistoryAdIfEligible() }
        }
        .onChange(of: entitlements.isEntitlementResolved) { resolved in
            guard resolved else { return }
            prepareHistoryAdIfEligible()
        }
    }

    #if os(macOS)
    /// O Histórico no Mac privilegia a leitura e a comparação intencional:
    /// primeiro a lista de fatos salvos; o gráfico é uma visão secundária
    /// da variação observada naquele recorte, nunca uma promessa de tendência.
    private var macOSContent: some View {
        ZStack(alignment: .bottom) {
            LinkaScreenBackground(variant: .gradientOnly, showWaves: false)
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        macHeader

                        if historyVisualizationState == .empty {
                            LinkaUnavailableState(
                                title: LinkaCopy.value("history.empty.title"),
                                message: LinkaCopy.value("history.empty.message"),
                                systemImage: "clock"
                            )
                            .frame(maxWidth: .infinity, minHeight: 280)
                        } else {
                            macFiltersRow

                            HStack(alignment: .top, spacing: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    macTableView
                                        .frame(minWidth: 420, maxWidth: .infinity)
                                    Text(LinkaCopy.value("mac.result.savedLocal"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.textSecondary)
                                        .padding(.horizontal, 4)
                                }

                                if let inspected = activeInspectedMeasurement {
                                    macDetailSidebar(for: inspected)
                                        .frame(width: 250)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, selectedComparisonIDs.isEmpty ? 32 : 80)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            if !selectedComparisonIDs.isEmpty {
                comparisonFloatingBar
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(LinkaCopy.value("history.title"))
        #if os(macOS)
        .sheet(isPresented: $showComparisonModal) {
            if let pair = comparisonMeasurements {
                MacHistoryComparisonSheet(first: pair.0, second: pair.1) {
                    onSelectMeasurement?(pair.1)
                }
            }
        }
        #endif
        .sheet(isPresented: $showPurchase) {
            PurchaseSheet(entryPoint: purchaseEntryPoint) { loadData() }
                .environmentObject(entitlements)
                .frame(minWidth: 620, minHeight: 620)
        }
        .task { loadData() }
    }

    private var macHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(LinkaCopy.value("history.title"))
                    .font(.largeTitle.weight(.bold))
                Text("Encontre padrões. Compare condições, não apenas velocidades.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(historySummary)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.macSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundColor(.textSecondary)
        }
    }

    private var historySummary: String {
        "\(filteredMeasurements.count) \(LinkaCopy.value("history.measurements").lowercased())"
    }

    private var macFiltersRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textSecondary)
                    .font(.system(size: 12))
                TextField(LinkaCopy.value("history.search.placeholder"), text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 180)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.4), lineWidth: 0.6)
            )

            Menu {
                ForEach(availableFilters, id: \.self) { option in
                    Button(option.label) { filter = option }
                }
            } label: {
                Label(filter.label, systemImage: "line.3.horizontal.decrease.circle")
            }
            .controlSize(.small)

            Menu {
                ForEach(HistorySort.allCases, id: \.self) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Label(sort.label, systemImage: "arrow.up.arrow.down")
            }
            .controlSize(.small)

            Spacer()

            Text("Marque duas para comparar")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
    }

    private var macTableView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 36)
                Text("Data e rede")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("↓ Mbps")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 75, alignment: .trailing)
                Text("↑ Mbps")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 75, alignment: .trailing)
                Text("ms")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 55, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.surfacePage)

            Divider()

            if filteredMeasurements.isEmpty {
                Text("Nenhuma medição corresponde à busca.")
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
                    .padding(32)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(filteredMeasurements, id: \.id) { m in
                    macTableRow(for: m)
                    if m.id != filteredMeasurements.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    private func macTableRow(for m: NetworkMeasurement) -> some View {
        let isInspected = (inspectedMeasurementID ?? filteredMeasurements.first?.id) == m.id
        let isSelected = selectedComparisonIDs.contains(m.id)

        return HStack(spacing: 0) {
            Button {
                toggleComparison(for: m.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .brandAccentWarm : .textSecondary)
            }
            .buttonStyle(.plain)
            .frame(width: 36, alignment: .center)
            .accessibilityIdentifier("mac.history.checkbox.\(m.id.uuidString)")

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.shortDateFormatter.string(from: m.measuredAt))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text((m.wifiContext?.ssid ?? m.networkIdentifier ?? "Rede") + " · " + (m.wifiContext?.bandDisplay ?? (m.connectionKind == .wifi ? "Wi-Fi" : "Cabo")))
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(m.downloadMbps.map { localizedNumber($0, fractionDigits: 1) } ?? "—")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.textPrimary)
                .frame(width: 75, alignment: .trailing)

            Text(m.uploadMbps.map { localizedNumber($0, fractionDigits: 1) } ?? "—")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.textSecondary)
                .frame(width: 75, alignment: .trailing)

            Text(m.latencyMs.map { "\(Int(round($0)))" } ?? "—")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor((m.latencyMs ?? 0) > 40 ? .statusAttention : .textPrimary)
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isInspected ? Color.brandAccentWarm.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            inspectedMeasurementID = m.id
        }
    }

    private func macDetailSidebar(for m: NetworkMeasurement) -> some View {
        let isGood = (m.latencyMs ?? 0) <= 40 && (m.packetLossPercent ?? 0) < 1.0

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Detalhe da medição")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }

            Text(Self.shortDateFormatter.string(from: m.measuredAt) + " · " + (m.wifiContext?.bandDisplay ?? (m.connectionKind == .wifi ? "Wi-Fi" : "Cabo")))
                .font(.system(size: 10))
                .foregroundColor(.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.downloadMbps.map { localizedNumber($0, fractionDigits: 1) } ?? "—")
                        .font(.system(size: 33, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("Mbps")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(isGood ? Color.statusGood : Color.statusAttention)
                    .frame(width: 6, height: 6)
                Text(isGood ? LinkaCopy.value("mac.result.good") : LinkaCopy.value("mac.result.attention"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isGood ? .statusGood : .statusAttention)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isGood ? Color.statusGood : Color.statusAttention).opacity(0.12), in: Capsule())

            Divider()

            VStack(spacing: 8) {
                sidebarPair(label: "Upload", value: m.uploadMbps.map { localizedNumber($0, fractionDigits: 1) + " Mbps" } ?? "—")
                sidebarPair(label: "Latência", value: m.latencyMs.map { "\(Int(round($0))) ms" } ?? "—")
                sidebarPair(label: "Jitter", value: m.jitterMs.map { localizedNumber($0, fractionDigits: 1) + " ms" } ?? "—")
                sidebarPair(label: "Perda", value: m.packetLossPercent.map { localizedNumber($0, fractionDigits: 1) + "%" } ?? "—")
            }

            if let note = m.networkIdentifier, !note.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ANOTAÇÃO")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.textSecondary)
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(.textPrimary)
                        .lineSpacing(2)
                }
                .padding(.top, 4)
            }

            Button {
                onSelectMeasurement?(m)
            } label: {
                HStack(spacing: 4) {
                    Text("Abrir resultado")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                }
                .foregroundColor(.brandAccentWarm)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(16)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    private func sidebarPair(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textPrimary)
        }
    }

    private var comparisonMeasurements: (NetworkMeasurement, NetworkMeasurement)? {
        let selected = measurements.filter { selectedComparisonIDs.contains($0.id) }
        guard selected.count == 2 else { return nil }
        return (selected[0], selected[1])
    }

    private var activeInspectedMeasurement: NetworkMeasurement? {
        if let id = inspectedMeasurementID, let m = measurements.first(where: { $0.id == id }) {
            return m
        }
        return filteredMeasurements.first
    }

    private func toggleComparison(for id: UUID) {
        if selectedComparisonIDs.contains(id) {
            selectedComparisonIDs.remove(id)
        } else if selectedComparisonIDs.count < 2 {
            selectedComparisonIDs.insert(id)
        }
    }

    private var comparisonFloatingBar: some View {
        HStack(spacing: 16) {
            Text(String(format: LinkaCopy.value("mac.history.compare.count"), selectedComparisonIDs.count))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            Button(LinkaCopy.value("mac.history.compare.clear")) {
                withAnimation { selectedComparisonIDs.removeAll() }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.75))
            .font(.system(size: 12))

            Button {
                showComparisonModal = true
            } label: {
                HStack(spacing: 4) {
                    Text(LinkaCopy.value("mac.history.compare.action"))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandAccentWarm)
            .disabled(selectedComparisonIDs.count != 2)
            .accessibilityIdentifier("mac.history.compare.button")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.textPrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
        .frame(maxWidth: 480)
    }

    private static var shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = LinkaLanguagePreference.currentLocale
        f.dateFormat = "dd MMM, HH:mm"
        return f
    }()

    private func localizedNumber(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .locale(LinkaLanguagePreference.currentLocale)
        )
    }
    #endif

    private var filteredMeasurements: [NetworkMeasurement] {
        let scoped = measurements.filter { measurement in
            let kindMatch: Bool
            switch filter {
            case .all: kindMatch = true
            case .wifi: kindMatch = measurement.connectionKind == .wifi
            case .mobile: kindMatch = measurement.connectionKind == .cellular
            }
            guard kindMatch else { return false }
            #if os(macOS)
            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let query = trimmed.lowercased()
                let ssid = (measurement.wifiContext?.ssid ?? "").lowercased()
                let network = (measurement.networkIdentifier ?? "").lowercased()
                let band = (measurement.wifiContext?.bandDisplay ?? "").lowercased()
                if !ssid.contains(query) && !network.contains(query) && !band.contains(query) {
                    return false
                }
            }
            #endif
            return true
        }
        switch sort {
        case .recent: return scoped.sorted { $0.measuredAt > $1.measuredAt }
        case .fastest: return scoped.sorted { ($0.downloadMbps ?? 0) > ($1.downloadMbps ?? 0) }
        case .slowest: return scoped.sorted { ($0.downloadMbps ?? 0) < ($1.downloadMbps ?? 0) }
        }
    }

    private var availableFilters: [HistoryFilter] {
        #if os(macOS)
        // Um Mac não mede rede celular. Não oferecemos um filtro que nunca
        // pode ter dado real, mas preservamos a mesma consulta de histórico.
        return [.all, .wifi]
        #else
        return HistoryFilter.allCases
        #endif
    }

    private var historyVisualizationState: HistoryVisualizationState {
        HistoryVisualizationState.resolve(measurementCount: filteredMeasurements.count)
    }

    private var isEligibleForAds: Bool {
        LinkaEntitlementPolicy.shouldShowAds(for: entitlements.snapshot, at: Date())
    }

    private var showsHistoryAd: Bool {
        // Em `List`, um `EmptyView` ainda pode manter a linha/separador do
        // lugar onde ele foi declarado. Só inserimos a linha depois que o
        // native ad existe de fato; carregamento e no-fill não viram buraco.
        #if os(iOS)
        return entitlements.isEntitlementResolved && isEligibleForAds
            && !filteredMeasurements.isEmpty
            && ads.nativeAd(for: .history) != nil
        #else
        return false
        #endif
    }

    private var historyAdRow: some View {
        Section {
            BannerView(placement: .history)
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4))
        .listRowBackground(Color.clear)
    }

    private func loadData() {
        Task {
            let decision = LinkaEntitlementPolicy.decision(
                for: .insights,
                snapshot: entitlements.snapshot,
                at: Date()
            )

            hasPlus = decision.isGranted

            let query = MeasurementQuery(limit: 50, sortOrder: .newestFirst)
            measurements = (try? await repository.measurements(matching: query)) ?? []
            
            if hasPlus {
                insightText = weeklyInsightText(from: measurements)
            }

            prepareHistoryAdIfEligible()

            isLoading = false
        }
    }

    private func prepareHistoryAdIfEligible() {
        ads.prepareHistoryAd(
            isEligibleForAds: isEligibleForAds,
            isEntitlementResolved: entitlements.isEntitlementResolved,
            hasHistory: !measurements.isEmpty
        )
    }

    private func weeklyInsightText(from measurements: [NetworkMeasurement]) -> String? {
        let now = Date()
        let cutoff7d = now.addingTimeInterval(-7 * 86_400)
        let cutoff14d = now.addingTimeInterval(-14 * 86_400)

        let last7 = measurements.filter { $0.measuredAt >= cutoff7d }
        let baseline = measurements.filter { $0.measuredAt >= cutoff14d && $0.measuredAt < cutoff7d }

        guard last7.count >= 2, baseline.count >= 2 else { return nil }

        let insightsAnalyzer = EntitlementGatedNetworkInsightsAnalyzer(
            wrapping: BasicNetworkInsightsAnalyzer(),
            snapshot: entitlements.snapshot
        )

        let comparison: NetworkPeriodComparison
        do {
            comparison = try insightsAnalyzer.comparePeriods(current: last7, baseline: baseline)
        } catch {
            return nil
        }

        guard let download = comparison.comparison(for: .downloadMbps),
              let percentDelta = download.percentDelta,
              abs(percentDelta) >= 5 else {
            return nil
        }

        let deltaStr = abs(percentDelta).formatted(.number.precision(.fractionLength(0)).locale(LinkaLanguagePreference.currentLocale))
        switch download.direction {
        case .improved:
            return LinkaCopy.format("history.insight.improved", deltaStr)
        case .worsened:
            return LinkaCopy.format("history.insight.worsened", deltaStr)
        case .stable, .unavailable:
            return nil
        }
    }
}

private struct HistorySingleMeasurementSummary: View {
    let measurement: NetworkMeasurement

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LinkaCopy.value("history.single.title"))
                .font(.bodyRegularStrong)
            Text(LinkaCopy.value("history.single.message"))
                .font(.captionSmall)
                .foregroundColor(.textSecondary)
            HStack(spacing: 16) {
                metric("arrow.down", value: measurement.downloadMbps)
                metric("arrow.up", value: measurement.uploadMbps)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .linkaCard()
    }

    private func metric(_ icon: String, value: Double?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundColor(.textSecondary)
            Text(value.map {
                "\($0.formatted(.number.precision(.fractionLength(1)).locale(LinkaLanguagePreference.currentLocale))) Mbps"
            } ?? "—")
                .font(.monoCaption)
        }
    }
}

// MARK: - Gráfico em Linha Horizontal Estilo Ondas (Dois Eixos)

/// Cor da série de download nos gráficos e linhas de histórico — sem token
/// equivalente no Design System (`DesignSystem.swift` só define a cor de
/// marca laranja); mantida aqui como constante única em vez de duplicada em
/// cada view para evitar drift entre `HistoryWaveChartView` e
/// `AppleStyleHistoryRow`.
let linkaDownloadSeriesColor = Color(red: 0.12, green: 0.53, blue: 0.98) // Azul Royal Apple

struct HistoryWaveChartView: View {
    let measurements: [NetworkMeasurement]
    @State private var selectedIndex: Int? = nil

    private var chronologicalMeasurements: [NetworkMeasurement] {
        measurements.sorted { $0.measuredAt < $1.measuredAt }
    }

    private var maxDownload: Double {
        let maxVal = chronologicalMeasurements.compactMap { $0.downloadMbps }.max() ?? 100
        return max(maxVal, 10)
    }

    private var maxUpload: Double {
        let maxVal = chronologicalMeasurements.compactMap { $0.uploadMbps }.max() ?? 50
        return max(maxVal, 5)
    }

    private var latestMeasurement: NetworkMeasurement? {
        chronologicalMeasurements.last
    }

    private var activeMeasurement: NetworkMeasurement? {
        if let idx = selectedIndex, idx >= 0, idx < chronologicalMeasurements.count {
            return chronologicalMeasurements[idx]
        }
        return latestMeasurement
    }

    private let downloadColor = linkaDownloadSeriesColor
    private let uploadColor = Color(red: 0.95, green: 0.50, blue: 0.15)   // Laranja Quente Linka

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                chartHeader(horizontal: true)
                chartHeader(horizontal: false)
            }

            // Canvas da Onda com Dois Eixos Horizontais
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                ZStack(alignment: .topLeading) {
                    chartGrid(height: height)
                    chartLines(width: width, height: height)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let count = chronologicalMeasurements.count
                            guard count > 1 else { return }
                            let stepX = width / CGFloat(count - 1)
                            selectedIndex = max(0, min(count - 1, Int(round(value.location.x / stepX))))
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedIndex = nil }
                            }
                        }
                )
            }
            .frame(height: 140)

            if let firstDate = chronologicalMeasurements.first?.measuredAt,
               let lastDate = chronologicalMeasurements.last?.measuredAt {
                HStack {
                    Text(formatAxisDate(firstDate)).font(.caption2.weight(.medium)).foregroundColor(.textSecondary)
                    Spacer()
                    Text(formatAxisDate(lastDate)).font(.caption2.weight(.medium)).foregroundColor(.textSecondary)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(18)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous).stroke(Color.borderDefault.opacity(0.4), lineWidth: 0.6))
    }

    @ViewBuilder
    private func chartHeader(horizontal: Bool) -> some View {
        if horizontal {
            HStack(alignment: .top) {
                chartTitle
                Spacer()
                chartLegend
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                chartTitle
                chartLegend
            }
        }
    }

    private var chartTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LinkaCopy.value("history.observedVariation")).font(.subheadline.weight(.bold)).foregroundColor(.textPrimary)
            if let active = activeMeasurement { Text(formatHeaderDate(active.measuredAt)).font(.caption2.weight(.medium)).foregroundColor(.textSecondary) }
        }
    }

    private var chartLegend: some View {
        HStack(spacing: 14) {
            legend(color: downloadColor, title: LinkaCopy.value("detail.download"), value: activeMeasurement?.downloadMbps)
            legend(color: uploadColor, title: LinkaCopy.value("detail.upload"), value: activeMeasurement?.uploadMbps)
        }
    }

    private func legend(color: Color, title: String, value: Double?) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 7, height: 7); Text("\(title) \(formatValue(value)) Mbps").font(.caption2.weight(.medium).monospacedDigit()).foregroundColor(.textSecondary) }
    }

    /// Duas bandas verticais compartilhadas pela grade e pelas ondas: a banda
    /// de download vai de `top` (máximo) a `mid` (zero) e a de upload de
    /// `mid` (máximo) a `bottom` (zero). Sem esse contrato único, a grade
    /// reservava metade da altura para o upload mas a onda era desenhada na
    /// altura quase inteira — sobrava espaço vazio abaixo das duas linhas.
    private func chartBands(height: CGFloat) -> (top: CGFloat, mid: CGFloat, bottom: CGFloat) {
        let top: CGFloat = 16
        let bottom: CGFloat = max(height - 10, top + 20)
        return (top, (top + bottom) / 2, bottom)
    }

    private func chartGrid(height: CGFloat) -> some View {
        let bands = chartBands(height: height)
        return ZStack(alignment: .topLeading) {
            gridLine(opacity: 0.35).offset(y: bands.top)
            gridLine(opacity: 0.25).offset(y: bands.mid)
            gridLine(opacity: 0.35).offset(y: bands.bottom)

            Text("↓ \(Int(round(maxDownload))) Mbps")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(downloadColor.opacity(0.8))
                .offset(y: max(bands.top - 13, 0))

            Text("↑ \(Int(round(maxUpload))) Mbps")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(uploadColor.opacity(0.8))
                .offset(y: bands.mid - 13)
        }
    }

    private func gridLine(opacity: Double) -> some View {
        Rectangle()
            .fill(Color.borderDefault.opacity(opacity))
            .frame(height: 0.8)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func chartLines(width: CGFloat, height: CGFloat) -> some View {
        let bands = chartBands(height: height)
        let downloadBandHeight = bands.mid - bands.top
        let uploadBandHeight = bands.bottom - bands.mid
        let count = chronologicalMeasurements.count
        let stepX = width / CGFloat(max(count - 1, 1))
        let dlPoints = chronologicalMeasurements.enumerated().compactMap { index, measurement -> CGPoint? in
            guard let value = measurement.downloadMbps else { return nil }
            let ratio = maxDownload > 0 ? CGFloat(value / maxDownload) : 0
            return CGPoint(x: CGFloat(index) * stepX, y: bands.mid - ratio * downloadBandHeight)
        }
        let ulPoints = chronologicalMeasurements.enumerated().compactMap { index, measurement -> CGPoint? in
            guard let value = measurement.uploadMbps else { return nil }
            let ratio = maxUpload > 0 ? CGFloat(value / maxUpload) : 0
            return CGPoint(x: CGFloat(index) * stepX, y: bands.bottom - ratio * uploadBandHeight)
        }
        if dlPoints.count >= 2 { wavePath(points: dlPoints, isClosed: false, height: height).stroke(downloadColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)) }
        if ulPoints.count >= 2 { wavePath(points: ulPoints, isClosed: false, height: height).stroke(uploadColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)) }
    }

    // Suavizador de Curvas Catmull-Rom para Bézier Cúbica
    private func wavePath(points: [CGPoint], isClosed: Bool, height: CGFloat) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }

        if points.count == 1 {
            let pt = points[0]
            if isClosed {
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: 0, y: pt.y))
                path.addLine(to: CGPoint(x: pt.x * 2, y: pt.y))
                path.addLine(to: CGPoint(x: pt.x * 2, y: height))
                path.closeSubpath()
            } else {
                path.move(to: CGPoint(x: 0, y: pt.y))
                path.addLine(to: CGPoint(x: pt.x * 2, y: pt.y))
            }
            return path
        }

        if isClosed {
            path.move(to: CGPoint(x: points[0].x, y: height))
            path.addLine(to: points[0])
        } else {
            path.move(to: points[0])
        }

        let tension: CGFloat = 0.32
        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : p2

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * tension,
                y: p1.y + (p2.y - p0.y) * tension
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * tension,
                y: p2.y - (p3.y - p1.y) * tension
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        if isClosed {
            path.addLine(to: CGPoint(x: points.last!.x, y: height))
            path.closeSubpath()
        }

        return path
    }

    private func formatValue(_ value: Double?) -> String {
        guard let v = value else { return "—" }
        return "\(Int(round(v)))"
    }

    /// Usa `setLocalizedDateFormatFromTemplate` em vez de um `dateFormat`
    /// fixo: o padrão anterior tinha o conectivo "de" (gramática do pt-BR)
    /// escrito literalmente no formato, então em en/es a data misturava um
    /// conectivo português com o mês no idioma selecionado. O template deixa
    /// o sistema escolher a ordem/conectivo corretos por idioma.
    private func formatHeaderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LinkaLanguagePreference.currentLocale
        formatter.setLocalizedDateFormatFromTemplate("dMMMMHHmm")
        return formatter.string(from: date)
    }

    private func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LinkaLanguagePreference.currentLocale
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
}

// MARK: - Célula de Histórico no Estilo Nativo Apple

struct AppleStyleHistoryRow: View {
    let measurement: NetworkMeasurement

    var body: some View {
        HStack(spacing: 14) {
            // 1. Ícone do Tipo de Rede (Apple Style Rounded Tile)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconBackgroundColor)
                    .frame(width: 42, height: 42)

                Image(systemName: networkIconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconTintColor)
            }

            // 2. Título, Data e Origem (Mac vs iPhone)
            VStack(alignment: .leading, spacing: 4) {
                Text(networkTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.textSecondary)

                    if let platform = measurement.devicePlatform {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.textSecondary.opacity(0.6))

                        HStack(spacing: 3) {
                            Image(systemName: platform == "macOS" ? "macbook" : "iphone")
                                .font(.caption2)
                            Text(platform == "macOS" ? "Mac" : "iPhone")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundColor(.textSecondary)
                    }
                }
            }

            Spacer(minLength: 8)

            // 3. Bloco de Métricas (Download Hero + Upload/Ping)
            VStack(alignment: .trailing, spacing: 3) {
                // Download em Destaque
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(linkaDownloadSeriesColor)
                    Text(formatSpeed(measurement.downloadMbps))
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("Mbps")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.textSecondary)
                }

                // Linha Secundária: Upload e Latência
                HStack(spacing: 8) {
                    if let up = measurement.uploadMbps {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.brandAccentWarm)
                            Text("\(Int(round(up)))")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundColor(.textSecondary)
                        }
                    }

                    if let ping = measurement.latencyMs {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                            Text("\(Int(round(ping)))ms")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
            }

            // 4. Chevron Nativo Apple
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.textSecondary.opacity(0.35))
                .padding(.leading, 2)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var networkTitle: String {
        switch measurement.connectionKind {
        case .wifi: return measurement.wifiContext?.ssid ?? LinkaCopy.value("network.wifi")
        case .cellular: return measurement.networkIdentifier ?? LinkaCopy.value("network.cellular")
        case .ethernet: return "Ethernet"
        default: return LinkaCopy.value("history.measurement")
        }
    }

    private var networkIconName: String {
        switch measurement.connectionKind {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        default: return "network"
        }
    }

    private var iconTintColor: Color {
        switch measurement.connectionKind {
        case .wifi: return linkaDownloadSeriesColor
        case .cellular: return .statusGood
        case .ethernet: return .statusAttention
        default: return .textSecondary
        }
    }

    private var iconBackgroundColor: Color {
        iconTintColor.opacity(0.12)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = LinkaLanguagePreference.currentLocale
        formatter.setLocalizedDateFormatFromTemplate("dMMMjm")
        return formatter.string(from: measurement.measuredAt)
    }

    private func formatSpeed(_ speed: Double?) -> String {
        guard let speed = speed else { return "—" }
        return speed.formatted(.number.precision(.fractionLength(0)).locale(LinkaLanguagePreference.currentLocale))
    }
}

struct HistoryRow: View {
    let measurement: NetworkMeasurement

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(networkTitle)
                    .font(.bodyRegularStrong)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(formatDate(measurement.measuredAt))
                        .font(.captionSmall)
                        .foregroundColor(.textSecondary)

                    Text("·")
                        .font(.captionSmall)
                        .foregroundColor(.textSecondary)

                    Image(systemName: connectionIconName(for: measurement.connectionKind))
                        .font(.captionSmall)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.captionSmallStrong)
                        .foregroundColor(.brandAccentWarm)
                    Text("\(formatSpeed(measurement.downloadMbps)) Mbps")
                        .font(.bodySmallStrong)
                        .foregroundColor(.textPrimary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.captionSmall)
                        .foregroundColor(.textSecondary)
                    Text("\(formatSpeed(measurement.uploadMbps)) Mbps")
                        .font(.captionSmall)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var networkTitle: String {
        if measurement.connectionKind == .wifi {
            return measurement.wifiContext?.ssid ?? LinkaCopy.value("network.wifi")
        } else if measurement.connectionKind == .cellular {
            return measurement.networkIdentifier ?? LinkaCopy.value("network.cellular")
        } else if measurement.connectionKind == .ethernet {
            return "Ethernet"
        }
        return LinkaCopy.value("history.measurement")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = LinkaLanguagePreference.currentLocale
        return formatter.string(from: date)
    }

    private func formatSpeed(_ speed: Double?) -> String {
        guard let speed = speed else { return "--" }
        return speed.formatted(.number.precision(.fractionLength(0)).locale(LinkaLanguagePreference.currentLocale))
    }

    private func connectionIconName(for kind: NetworkConnectionKind?) -> String {
        switch kind {
        case .wifi: return "wifi"
        case .cellular: return "cellularbars"
        case .ethernet: return "cable.connector"
        case .other, .none: return "network"
        }
    }
}

struct MapLocationItem: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
}

struct MapHistoryView: View {
    let measurements: [NetworkMeasurement]
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -23.55052, longitude: -46.633308),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    var locationItems: [MapLocationItem] {
        measurements.compactMap { m in
            if let loc = m.location {
                return MapLocationItem(id: m.id, coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude), title: m.serverIdentifier ?? LinkaCopy.value("history.measurement"))
            }
            return nil
        }
    }

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: locationItems) { item in
            MapAnnotation(coordinate: item.coordinate) {
                Circle()
                    .fill(Color.brandAccentWarm)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
        .onAppear {
            if let first = locationItems.first {
                region.center = first.coordinate
                region.span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            }
        }
    }
}
