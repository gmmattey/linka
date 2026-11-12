#if os(macOS)
import SwiftUI
import AppKit
import LinkaEngine
import MeasurementHistory
import NetworkCore
import LinkaEntitlements
import LinkaModules
import NetworkConnectivityTriage
import NetworkInsights
import NetworkOptimization

private enum MacPurchaseDismissalAction {
    case assistProblemSelection
    case subscriptionManagement
}

private enum MacAssistEntryPoint {
    case fresh
    case result(NetworkMeasurement)

    var measurement: NetworkMeasurement? {
        guard case .result(let m) = self else { return nil }
        return m
    }
}

private enum MacPhaseStep { case pending, active, done }

// MARK: - Janela principal

/// Janela principal do Linka no Mac: barra lateral flutuante, barra de
/// ferramentas com título e ações, conteúdo e inspetor à direita.
struct MacMainView: View {
    @AppStorage(LinkaLanguagePreference.storageKey) private var languagePreference = LinkaLanguagePreference.system.rawValue
    @AppStorage(MacWindowPreferences.inspectorKey) private var inspectorVisible = true
    @StateObject private var viewModel = SpeedTestViewModel()
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @ObservedObject private var intentCoordinator = AppIntentCoordinator.shared
    @ObservedObject private var center = MacCommandCenter.shared

    @State private var destination: MacDestination = .speedTest
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showPurchase = false
    @State private var purchaseEntryPoint: PurchaseEntryPoint = .settings
    @State private var pendingPurchaseDismissalAction: MacPurchaseDismissalAction?
    @State private var showSubscriptionManagement = false
    @State private var optimizationBaseline: NetworkMeasurement?
    @State private var optimizationRetestResult: OptimizationRetestComparison?
    @State private var showOptimizationRetestResult = false
    @State private var assistEntryPoint: MacAssistEntryPoint = .fresh
    @State private var showAssistResult = false
    @State private var pendingAssistMeasurement = false
    @State private var showNetscopeAnalysis = false
    @State private var showConnectivityTriage = false
    @State private var selectedHistoricalMeasurement: NetworkMeasurement?
    @State private var inspectedMeasurement: NetworkMeasurement?
    @State private var showCurrentMeasurementDetails = false
    @State private var showUsageDiagnostics = false
    @State private var showConnectionPath = false
    @State private var showShareSheet = false
    @State private var showAdvancedWiFiUnavailable = false
    @State private var speedSamples: [Double] = []
    @State private var gaugeScale = 100.0
    @State private var networkDetails = MacNetworkDetails()
    @State private var navigationMethod = "sidebar"
    @State private var lastScreen = ""

    // MARK: Estado derivado

    private var isPlusActive: Bool {
        LinkaEntitlementPolicy.decision(for: .assist, snapshot: entitlements.snapshot, at: Date()).isGranted
    }

    private var canUseOptimization: Bool {
        LinkaEntitlementPolicy.decision(for: .optimization, snapshot: entitlements.snapshot, at: Date()).isGranted
    }

    private var showsAssist: Bool { MacFeatures.assist && !LinkaDistribution.isDirectDownload }
    private var showsOptimization: Bool { MacFeatures.optimization && !LinkaDistribution.isDirectDownload }
    private var showsTools: Bool { showsAssist || showsOptimization }
    private var offersPlus: Bool { MacFeatures.plusPurchase && !LinkaDistribution.isDirectDownload }

    private var activeMeasurement: NetworkMeasurement? {
        if viewModel.uiPhase == .done { return viewModel.latestFinishedMeasurement }
        return inspectedMeasurement
    }

    private var latestMeasurementForIntent: NetworkMeasurement? {
        viewModel.latestFinishedMeasurement ?? viewModel.recentMeasurements.first
    }

    private var connectionPathReport: ConnectionPathReport? {
        guard let m = activeMeasurement else { return nil }
        return ConnectionPathEvaluator().evaluate(m)
    }

    private var isMeasuring: Bool {
        switch viewModel.uiPhase {
        case .connecting, .downloading, .uploading: return true
        default: return false
        }
    }

    private var canStartAdvancedWiFiMeasurement: Bool {
        guard viewModel.liveConnectionKind == .wifi,
              LinkaWiFiPreferences.isAdvancedDiagnosticsEnabled else { return false }
        return LinkaEntitlementPolicy.decision(
            for: .advancedWiFiDiagnostics,
            snapshot: entitlements.snapshot,
            at: Date()
        ).isGranted
    }

    private var liveConnectionName: String {
        viewModel.liveNetworkLabel.isEmpty ? LinkaCopy.value("Conexão atual") : viewModel.liveNetworkLabel
    }

    // MARK: Corpo

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            NavigationStack {
                detailContent
                    .background(Color.macPage)
                    .navigationTitle(destinationTitle)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showPurchase, onDismiss: handlePurchaseDismissal) {
            PurchaseSheet(entryPoint: purchaseEntryPoint) {
                if purchaseEntryPoint == .assist {
                    pendingPurchaseDismissalAction = .assistProblemSelection
                } else if purchaseEntryPoint == .settings {
                    pendingPurchaseDismissalAction = .subscriptionManagement
                }
            }
            .environmentObject(entitlements)
            .frame(minWidth: 620, minHeight: 620)
        }
        .sheet(isPresented: $showOptimizationRetestResult) {
            if let result = optimizationRetestResult {
                OptimizationRetestResultView(result: result)
                    .frame(minWidth: 620, minHeight: 420)
            }
        }
        .sheet(isPresented: $showSubscriptionManagement) {
            SubscriptionManagementSheet()
                .environmentObject(entitlements)
                .frame(minWidth: 620, minHeight: 560)
        }
        .sheet(isPresented: $showAssistResult) {
            AssistView(
                currentMeasurement: assistMeasurement,
                recentMeasurements: viewModel.recentMeasurements,
                onRetry: {
                    pendingAssistMeasurement = true
                    viewModel.startTest()
                },
                onRetest: {
                    pendingAssistMeasurement = true
                    viewModel.startTest()
                },
                onCloseSheet: { showAssistResult = false }
            )
            .frame(minWidth: 680, minHeight: 620)
        }
        .sheet(isPresented: $showNetscopeAnalysis) {
            if let activeMeasurement {
                NetscopeAnalysisView(input: NetscopeAnalysisInput(projectingFinalMeasurement: activeMeasurement))
                    .frame(minWidth: 520, minHeight: 380)
            } else {
                NetscopeAnalysisView()
                    .frame(minWidth: 520, minHeight: 380)
            }
        }
        .sheet(isPresented: $showConnectivityTriage) {
            ConnectivityTriageView(onRetry: { startMeasurement() })
                .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(item: $selectedHistoricalMeasurement) { measurement in
            NavigationStack {
                HistoricalMeasurementDetailView(
                    measurement: measurement,
                    onStartNewMeasurement: startMeasurementFromHistory,
                    onStartNewMeasurementWithAdvancedWiFi: startMeasurementWithAdvancedWiFi
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LinkaCopy.value("common.done")) { selectedHistoricalMeasurement = nil }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .environmentObject(entitlements)
            .frame(minWidth: 680, minHeight: 680)
        }
        .sheet(isPresented: $showCurrentMeasurementDetails) {
            NavigationStack {
                MeasurementDetailView(measurement: activeMeasurement, duration: viewModel.testDuration)
                    .environmentObject(entitlements)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(LinkaCopy.value("common.done")) { showCurrentMeasurementDetails = false }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
            }
            .frame(minWidth: 680, minHeight: 680)
        }
        .sheet(isPresented: $showUsageDiagnostics) {
            UsageDiagnosticsView(measurement: activeMeasurement)
                .frame(minWidth: 680, minHeight: 580)
        }
        .sheet(isPresented: $showConnectionPath) {
            if let connectionPathReport {
                ConnectionPathDetailView(report: connectionPathReport)
                    .frame(minWidth: 680, minHeight: 580)
            }
        }
        .shareMeasurementSheet(isPresented: $showShareSheet, measurement: activeMeasurement)
        .alert(LinkaCopy.value("Detalhes de Wi-Fi indisponíveis"), isPresented: $showAdvancedWiFiUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LinkaCopy.value("O Mac não informou detalhes suficientes do Wi-Fi agora. Nenhuma medição foi iniciada."))
        }
        .onChange(of: viewModel.uploadSpeed) { speed in
            guard viewModel.uiPhase == .uploading, speed > 0 else { return }
            gaugeScale = max(gaugeScale, MacGauge<EmptyView>.scale(for: speed))
        }
        .onChange(of: viewModel.downloadSpeed) { speed in
            guard viewModel.uiPhase == .downloading, speed > 0 else { return }
            gaugeScale = max(gaugeScale, MacGauge<EmptyView>.scale(for: speed))
            speedSamples.append(speed)
            if speedSamples.count > 90 { speedSamples.removeFirst(speedSamples.count - 90) }
        }
        .onChange(of: viewModel.uiPhase) { phase in
            center.isMeasuring = isMeasuring
            intentCoordinator.setMeasurementActive(isMeasuring)
            if phase == .connecting { speedSamples = []; gaugeScale = 100 }
            trackScreen()
            if phase == .done || phase == .idle { networkDetails = MacNetworkDetails.capture() }
            if phase == .done { inspectedMeasurement = nil }
            updateShareState()
            handleOptimizationRetestCompletion(phase)
            guard phase == .done, pendingAssistMeasurement else { return }
            pendingAssistMeasurement = false
            showAssistResult = true
        }
        .onChange(of: destination) { new in
            updateShareState()
            MacAnalytics.shared.track(.navigate(to: Self.analyticsName(new), method: navigationMethod))
            navigationMethod = "sidebar"
            trackScreen()
        }
        .onChange(of: inspectorVisible) { MacAnalytics.shared.track(.inspectorToggled(visible: $0)) }
        .onChange(of: showShareSheet) { if $0 { MacAnalytics.shared.track(.resultShared(method: "share_sheet")) } }
        .onChange(of: intentCoordinator.pendingStartSpeedTest) { pending in
            guard pending else { return }
            guard !isMeasuring else { intentCoordinator.consumeStartSpeedTestRequest(); return }
            navigationMethod = "menu_or_intent"
            destination = .speedTest
            MacAnalytics.shared.markNextTestTrigger("menu_or_intent")
            startMeasurement()
            intentCoordinator.consumeStartSpeedTestRequest()
        }
        .onChange(of: intentCoordinator.pendingOpenHistory) { pending in
            guard pending else { return }
            destination = .history
            intentCoordinator.consumeOpenHistory()
        }
        .onChange(of: intentCoordinator.pendingPurchasePrompt) { pending in
            guard pending else { return }
            guard !isMeasuring, offersPlus else { intentCoordinator.consumePurchasePrompt(); return }
            purchaseEntryPoint = .shortcut
            showPurchase = true
            intentCoordinator.consumePurchasePrompt()
        }
        .onChange(of: intentCoordinator.pendingOpenLatestMeasurement) { pending in
            handleOpenLatestMeasurementRequest(pending)
        }
        .onChange(of: intentCoordinator.pendingCancelMeasurement) { pending in
            guard pending else { return }
            if isMeasuring { cancelMeasurement() }
            intentCoordinator.consumeCancelMeasurement()
        }
        .onChange(of: intentCoordinator.pendingOpenSettings) { pending in
            guard pending else { return }
            MacSettingsOpener.open()
            intentCoordinator.consumeOpenSettings()
        }
        .onChange(of: intentCoordinator.pendingPublicUniversalLink) { route in
            handlePublicUniversalLink(route)
        }
        .onChange(of: center.navigationRequest) { request in
            guard let request else { return }
            center.navigationRequest = nil
            navigationMethod = "menu"
            destination = request
        }
        .onChange(of: center.exportHistoryRequest) { requested in
            guard requested else { return }
            center.exportHistoryRequest = false
            Task { @MainActor in
                let repo = LinkaMeasurementHistory.makeRepository(entitlements: entitlements)
                let all = (try? await repo.measurements(matching: MeasurementQuery(sortOrder: .newestFirst))) ?? []
                MacMeasurementFormat.exportCSV(all)
            }
        }
        .onChange(of: center.shareRequest) { requested in
            guard requested, destination == .speedTest else { return }
            center.shareRequest = false
            if activeMeasurement?.outcome == .complete { showShareSheet = true }
        }
        .onChange(of: center.latestResultRequest) { requested in
            guard requested else { return }
            center.latestResultRequest = false
            destination = .speedTest
            if !isMeasuring, viewModel.uiPhase != .done { inspectedMeasurement = latestMeasurementForIntent }
        }
        .onAppear {
            center.showsAssist = showsAssist
            center.showsOptimization = showsOptimization
            center.isMeasuring = isMeasuring
            intentCoordinator.setMeasurementActive(isMeasuring)
            // O macOS só informa o nome da rede Wi-Fi com Serviços de Localização autorizados.
            WiFiNetworkPermission.requestIdentification()
            viewModel.refreshLiveNetwork()
            trackScreen()
            handlePublicUniversalLink(intentCoordinator.pendingPublicUniversalLink)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wiFiAuthorizationDidChange)) { _ in
            viewModel.refreshLiveNetwork()
            networkDetails = MacNetworkDetails.capture()
            MacAnalytics.shared.track(.locationPermission(status: Self.analyticsName(WiFiNetworkPermission.state(enabled: true))))
        }
        .task {
            while !Task.isCancelled {
                networkDetails = MacNetworkDetails.capture()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onDisappear {
            center.isMeasuring = false
            intentCoordinator.setMeasurementActive(false)
        }
    }

    // MARK: Barra lateral

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section(LinkaCopy.value("Testes")) {
                sidebarRow(LinkaCopy.value("Velocímetro"), systemImage: "gauge.medium", dest: .speedTest)
                sidebarRow(LinkaCopy.value("Histórico"), systemImage: "chart.bar", dest: .history)
                if MinhaRedeAvailability.isEnabled {
                    sidebarRow(LinkaCopy.value("inventory.title"), systemImage: "wifi.router", dest: .myNetwork)
                }
            }
            if showsTools {
                Section(LinkaCopy.value("Ferramentas")) {
                    if showsAssist { sidebarRow("Assist", systemImage: "sparkles", dest: .assist) }
                    if showsOptimization { sidebarRow(LinkaCopy.value("optimization.title"), systemImage: "slider.horizontal.3", dest: .optimization) }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { MacSettingsOpener.open() } label: {
                Label(LinkaCopy.value("settings.title"), systemImage: "gearshape")
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(LinkaCopy.value("settings.title"))
            .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Image("wordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .accessibilityHidden(true)
        }
    }

    private var sidebarSelection: Binding<MacDestination?> {
        Binding(get: { destination }, set: { if let new = $0 { destination = new } })
    }

    private func sidebarRow(_ title: String, systemImage: String, dest: MacDestination) -> some View {
        Label(title, systemImage: systemImage)
            .tag(dest)
            .accessibilityLabel(title)
    }

    private var destinationTitle: String {
        switch destination {
        case .speedTest: return LinkaCopy.value("Velocímetro")
        case .history: return LinkaCopy.value("Histórico")
        case .myNetwork: return LinkaCopy.value("inventory.title")
        case .assist: return "Assist"
        case .optimization: return LinkaCopy.value("optimization.title")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch destination {
        case .speedTest:
            speedTestScreen
        case .history:
            MacHistoryView(onMeasureAgain: {
                destination = .speedTest
                DispatchQueue.main.async { startMeasurement() }
            })
            .environmentObject(entitlements)
        case .myNetwork:
            MacMyNetworkView()
                .environmentObject(entitlements)
        case .assist:
            assistView
        case .optimization:
            optimizationView
        }
    }

    // MARK: Velocímetro

    private var speedTestScreen: some View {
        HStack(spacing: 0) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if inspectorVisible {
                speedInspector
            }
        }
        .navigationSubtitle(liveConnectionName)
        .toolbar {
            if !isMeasuring, let measurement = activeMeasurement {
                if showsAssist {
                    ToolbarItem(placement: .primaryAction) {
                        Button { requestAssist(from: .result(measurement)) } label: {
                            Label("Assist", systemImage: "sparkles")
                        }
                        .help("Assist")
                    }
                }
                if showsOptimization {
                    ToolbarItem(placement: .primaryAction) {
                        Button { destination = .optimization } label: {
                            Label(LinkaCopy.value("optimization.title"), systemImage: "slider.horizontal.3")
                        }
                        .help(LinkaCopy.value("optimization.title"))
                    }
                }
                if measurement.outcome == .complete {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showShareSheet = true } label: {
                            Label(LinkaCopy.value("Compartilhar"), systemImage: "square.and.arrow.up")
                        }
                        .help(LinkaCopy.value("Compartilhar"))
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { inspectorVisible.toggle() } label: {
                    Label(LinkaCopy.value("Inspetor"), systemImage: "sidebar.right")
                }
                .help(LinkaCopy.value(inspectorVisible ? "Ocultar inspetor" : "Mostrar inspetor"))
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        GeometryReader { proxy in
            ScrollView {
                Group {
                    if isMeasuring {
                        measuringStage
                    } else if viewModel.uiPhase == .error {
                        errorStage
                    } else if viewModel.uiPhase == .connectionChanged {
                        connectionChangedStage
                    } else if let m = activeMeasurement {
                        resultStage(m)
                    } else {
                        idleStage
                    }
                }
                .padding(28)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    // Pronto para medir

    private var idleStage: some View {
        VStack(spacing: 28) {
            VStack(spacing: 16) {
                MacGauge(progress: 0, diameter: 300, lineWidth: 24) {
                    Button { startMeasurement() } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.system(size: 38, weight: .bold))
                            Text(LinkaCopy.value("Iniciar teste")).font(.system(size: 20, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 176, height: 176)
                        .background(
                            Circle().fill(LinearGradient(
                                colors: [Color(red: 0.55, green: 0.36, blue: 0.97), Color(red: 0.40, green: 0.13, blue: 0.82)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: Color.brandAccentWarm.opacity(0.45), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LinkaCopy.value("Iniciar teste"))
                }
                Text(LinkaCopy.value("O teste usa a sua conexão enquanto mede."))
                    .font(MacType.label)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)

            if let last = viewModel.recentMeasurements.first {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LinkaCopy.value("Última medição")).font(MacType.section)
                        Text(last.measuredAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                            .font(MacType.label).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 16) {
                        MacMetricTile(title: "Download", value: MacMeasurementFormat.mbps(last.downloadMbps), unit: "Mbps",
                                      systemImage: "arrow.down.circle.fill", tint: MacPalette.download, valueSize: 40)
                        MacMetricTile(title: "Upload", value: MacMeasurementFormat.mbps(last.uploadMbps), unit: "Mbps",
                                      systemImage: "arrow.up.circle.fill", tint: MacPalette.upload, valueSize: 40)
                        MacMetricTile(title: "Ping", value: last.latencyMs.map { String(Int(round($0))) } ?? "—", unit: "ms",
                                      systemImage: "timer", tint: MacPalette.ping, valueSize: 40)
                    }
                }
            }

            MacNetworkCard(details: networkDetails, fallbackName: liveConnectionName)
        }
    }

    // Medindo

    private var measuringStage: some View {
        let uploading = viewModel.uiPhase == .uploading
        let value = uploading ? viewModel.uploadSpeed : viewModel.downloadSpeed
        return VStack(spacing: 24) {
            HStack(spacing: 12) {
                phaseChip("Ping", step: pingStep)
                phaseLink(done: pingStep == .done)
                phaseChip("Download", step: downloadStep)
                phaseLink(done: downloadStep == .done)
                phaseChip("Upload", step: uploadStep)
            }

            MacGauge(progress: value / gaugeScale, diameter: 340, lineWidth: 26) {
                VStack(spacing: 4) {
                    Text(value > 0 ? MacMeasurementFormat.mbps(value) : "—")
                        .font(MacType.metric(84))
                        .monospacedDigit()
                        .foregroundStyle(Color.brandAccentWarmInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Mbps").font(MacType.headline).foregroundStyle(.secondary)
                    Text(LinkaCopy.value(uploading ? "Upload agora" : "Download agora"))
                        .font(MacType.label).foregroundStyle(.secondary).padding(.top, 2)
                }
                .frame(width: 230)
            }

            MacSparkline(values: speedSamples)
                .frame(height: 84)
                .linkaMacCard(padding: 16)

            HStack(spacing: 16) {
                MacMetricTile(title: "Ping", value: viewModel.hasMeasuredPing ? "\(viewModel.ping)" : "—", unit: "ms",
                              systemImage: "timer", tint: MacPalette.ping, valueSize: 34)
                MacMetricTile(title: "Upload", value: viewModel.hasMeasuredUpload ? MacMeasurementFormat.mbps(viewModel.uploadSpeed) : "—", unit: "Mbps",
                              systemImage: "arrow.up.circle.fill", tint: MacPalette.upload, valueSize: 34)
            }

            Button(LinkaCopy.value("Cancelar")) { cancelMeasurement() }
                .controlSize(.large)
        }
    }

    private func phaseChip(_ title: String, step: MacPhaseStep) -> some View {
        HStack(spacing: 6) {
            if step == .done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
            Text(title).font(MacType.labelStrong)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .foregroundStyle(step == .active ? Color.white : (step == .done ? Color.statusGood : Color.textSecondary))
        .background(
            Capsule().fill(step == .active ? Color.brandAccentWarm : (step == .done ? Color.statusGood.opacity(0.14) : Color.primary.opacity(0.06)))
        )
    }

    private func phaseLink(done: Bool) -> some View {
        Capsule()
            .fill(done ? Color.brandAccentWarm : Color.primary.opacity(0.12))
            .frame(width: 34, height: 3)
    }

    private var pingStep: MacPhaseStep {
        switch viewModel.uiPhase {
        case .connecting: return .active
        case .downloading, .uploading, .done: return .done
        default: return .pending
        }
    }

    private var downloadStep: MacPhaseStep {
        switch viewModel.uiPhase {
        case .downloading: return .active
        case .uploading, .done: return .done
        default: return .pending
        }
    }

    private var uploadStep: MacPhaseStep {
        switch viewModel.uiPhase {
        case .uploading: return .active
        case .done: return .done
        default: return .pending
        }
    }

    // Resultado

    private func resultStage(_ m: NetworkMeasurement) -> some View {
        VStack(spacing: 28) {
            resultHero(m)

            if m.outcome == .complete {
                let report = UsageSuitabilityEvaluator().evaluate(m)
                verdictLine(report)
                usageCard(report)
            } else {
                Label(LinkaCopy.value("Resultado parcial: algumas medições não foram concluídas."), systemImage: "exclamationmark.triangle.fill")
                    .font(MacType.body)
                    .foregroundStyle(Color.statusAttention)
            }

            Button(LinkaCopy.value("Medir novamente")) { startMeasurement() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.brandAccentWarm)
        }
        .frame(maxWidth: 640)
    }

    /// Um único cartão: o download é o protagonista; upload e ping são apoio.
    private func resultHero(_ m: NetworkMeasurement) -> some View {
        VStack(spacing: 26) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(MacPalette.download)
                    Text("Download").font(MacType.headline).foregroundStyle(.secondary)
                    if let quality = MacMeasurementFormat.quality(m) {
                        MacStatusTag(label: quality.label, color: quality.color).padding(.leading, 4)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MacMeasurementFormat.mbps(m.downloadMbps))
                        .font(MacType.metric(96))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(
                            LinearGradient(colors: [MacPalette.upload, Color.brandAccentWarmInk], startPoint: .top, endPoint: .bottom))
                    Text("Mbps").font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                heroSecondary(icon: "arrow.up.circle.fill", tint: MacPalette.upload, title: "Upload",
                              value: MacMeasurementFormat.mbps(m.uploadMbps), unit: "Mbps")
                heroSecondary(icon: "timer", tint: MacPalette.ping, title: "Ping",
                              value: m.latencyMs.map { String(Int(round($0))) } ?? "—", unit: "ms")
            }
        }
        .frame(maxWidth: .infinity)
        .linkaMacCard(padding: 30)
        .accessibilityElement(children: .contain)
    }

    private func heroSecondary(icon: String, tint: Color, title: String, value: String, unit: String) -> some View {
        HStack(spacing: 14) {
            MacIconBadge(systemImage: icon, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MacType.label).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(MacType.metric(30)).monospacedDigit()
                    Text(unit).font(MacType.label).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .linkaMacWell(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private func verdictLine(_ report: UsageSuitabilityReport) -> some View {
        let hasAdequate = UsageCase.allCases.contains { report.verdict(for: $0)?.level == .adequate }
        return HStack(spacing: 12) {
            Image(systemName: hasAdequate ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(hasAdequate ? Color.statusGood : Color.statusAttention)
            Text(UsageSuitabilityCopy.sentence(for: report))
                .font(.system(size: 19, weight: .semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Os quatro usos em um só cartão, com poços compactos.
    private func usageCard(_ report: UsageSuitabilityReport) -> some View {
        let cases: [UsageCase] = [.videoCall, .streaming4K, .onlineGaming, .workUpload]
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 14) {
            Text(LinkaCopy.value("Para que serve agora")).font(MacType.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(cases, id: \.self) { usageCase in
                    if let verdict = report.verdict(for: usageCase) {
                        Button { showUsageDiagnostics = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: UsageSuitabilityCopy.iconName(for: usageCase))
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(usageTint(verdict.level))
                                    .frame(width: 26)
                                Text(UsageSuitabilityCopy.title(for: usageCase))
                                    .font(MacType.body)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 4)
                                Circle().fill(usageTint(verdict.level)).frame(width: 10, height: 10)
                            }
                            .linkaMacWell(padding: 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(UsageSuitabilityCopy.title(for: usageCase)): \(usageLabel(verdict.level))")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .linkaMacCard(padding: 22)
    }

    private func usageLabel(_ level: SuitabilityLevel) -> String {
        switch level {
        case .adequate: return LinkaCopy.value("Adequada")
        case .limited: return LinkaCopy.value("Limitada")
        default: return LinkaCopy.value("Insuficiente")
        }
    }

    private func usageTint(_ level: SuitabilityLevel) -> Color {
        switch level {
        case .adequate: return .statusGood
        case .limited: return .statusAttention
        default: return .statusCritical
        }
    }

    @ViewBuilder
    private func usageTag(_ level: SuitabilityLevel) -> some View {
        switch level {
        case .adequate: MacStatusTag(label: LinkaCopy.value("Adequada"), color: .statusGood)
        case .limited: MacStatusTag(label: LinkaCopy.value("Limitada"), color: .statusAttention)
        default: MacStatusTag(label: LinkaCopy.value("Insuficiente"), color: .statusCritical)
        }
    }

    // Erro e troca de rede

    private var errorStage: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.statusCritical)
            Text(LinkaCopy.value(viewModel.failureReason == .offline ? "Sem conexão com a internet" : "Não foi possível concluir a medição"))
                .font(MacType.section)
            Text(LinkaCopy.value("Verifique sua rede e tente novamente."))
                .font(MacType.body)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(LinkaCopy.value("Tentar novamente")) { startMeasurement() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandAccentWarm)
                Button(LinkaCopy.value("Verificar conexão")) { showConnectivityTriage = true }
            }
            .controlSize(.large)
            .padding(.top, 10)
        }
        .padding(40)
    }

    private var connectionChangedStage: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.statusAttention)
            Text(LinkaCopy.value("A rede mudou durante a medição."))
                .font(MacType.section)
            Button(LinkaCopy.value("Testar conexão")) { startMeasurement() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.brandAccentWarm)
                .padding(.top, 10)
        }
        .padding(40)
    }

    // MARK: Inspetor do velocímetro

    private var speedInspector: some View {
        MacInspectorPanel {
            if !isMeasuring, let m = activeMeasurement {
                MacInspectorSection(LinkaCopy.value("detail.quality")) {
                    MacInspectorRow(label: "Jitter", value: MacMeasurementFormat.ms(m.jitterMs), systemImage: "waveform.path", tint: MacPalette.quality)
                    if let loss = m.packetLossPercent {
                        MacInspectorRow(label: LinkaCopy.value("Perda de pacotes"), value: loss == 0 ? "0 %" : String(format: "%.1f %%", loss), systemImage: "exclamationmark.triangle.fill", tint: MacPalette.quality)
                    }
                    if let dns = m.dnsResolutionMs {
                        MacInspectorRow(label: LinkaCopy.value("Resolução de DNS"), value: MacMeasurementFormat.ms(dns), systemImage: "server.rack", tint: MacPalette.upload)
                    }
                    if let loaded = m.loadedLatencyMs {
                        MacInspectorRow(label: LinkaCopy.value("Latência sob carga"), value: MacMeasurementFormat.ms(loaded), systemImage: "gauge.with.dots.needle.67percent", tint: MacPalette.ping)
                    }
                }
                MacInspectorSection(LinkaCopy.value("Detalhes da medição")) {
                    if let server = m.networkIdentifier, !server.isEmpty {
                        MacInspectorRow(label: LinkaCopy.value("Servidor"), value: server, systemImage: "network", tint: MacPalette.upload)
                    }
                    if let duration = m.durationMs {
                        MacInspectorRow(label: LinkaCopy.value("Duração"), value: "\(Int(round(Double(duration) / 1000))) s", systemImage: "clock.fill", tint: MacPalette.ping)
                    }
                    MacInspectorRow(label: LinkaCopy.value("Rede"), value: MacMeasurementFormat.networkName(m), systemImage: "wifi", tint: MacPalette.network)
                    if let band = m.wifiContext?.bandGHz {
                        MacInspectorRow(label: LinkaCopy.value("network.wifiBand"), value: String(format: "%g GHz", band))
                    }
                    if let rssi = m.wifiContext?.rssiDbm {
                        MacInspectorRow(label: LinkaCopy.value("Sinal"), value: "\(Int(rssi)) dBm", systemImage: "cellularbars", tint: MacPalette.ping)
                    }
                    if let link = m.wifiContext?.linkSpeedMbps {
                        MacInspectorRow(label: LinkaCopy.value("Velocidade do link"), value: "\(Int(link)) Mbps", systemImage: "speedometer", tint: MacPalette.download)
                    }
                }
                MacInspectorSection {
                    MacInspectorAction(title: LinkaCopy.value("Detalhes completos…")) { showCurrentMeasurementDetails = true }
                    if connectionPathReport != nil {
                        MacInspectorAction(title: LinkaCopy.value("Caminho da conexão")) { showConnectionPath = true }
                    }
                    if MacFeatures.netscopeAnalysis && viewModel.uiPhase == .done {
                        MacInspectorAction(title: LinkaCopy.value("Análise detalhada")) { showNetscopeAnalysis = true }
                    }
                    MacInspectorAction(title: LinkaCopy.value("Como medimos")) {
                        NSWorkspace.shared.open(LinkaExternalLinks.howWeMeasure)
                    }
                }
            } else {
                MacInspectorSection(LinkaCopy.value("Últimas medições")) {
                    let recent = Array(viewModel.recentMeasurements.prefix(6))
                    let peak = max(recent.compactMap(\.downloadMbps).max() ?? 1, 1)
                    if recent.isEmpty {
                        Text(LinkaCopy.value("Nenhuma medição ainda"))
                            .font(MacType.body).foregroundStyle(.secondary)
                    }
                    ForEach(recent) { m in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(m.measuredAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                    .font(MacType.label).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(MacMeasurementFormat.mbps(m.downloadMbps)) Mbps")
                                    .font(MacType.bodyStrong).monospacedDigit()
                            }
                            GeometryReader { proxy in
                                Capsule().fill(Color.macWell)
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(MacPalette.download)
                                            .frame(width: proxy.size.width * CGFloat((m.downloadMbps ?? 0) / peak))
                                    }
                            }
                            .frame(height: 6)
                        }
                        .padding(.vertical, 6)
                    }
                }
                MacInspectorSection {
                    MacInspectorAction(title: LinkaCopy.value("Ver histórico completo"), shortcut: "⌘2") {
                        destination = .history
                    }
                }
            }
        }
    }

    private var liveConnectionKindName: String {
        switch viewModel.liveConnectionKind {
        case .wifi: return "Wi-Fi"
        case .ethernet: return LinkaCopy.value("network.ethernet")
        case .cellular: return LinkaCopy.value("network.cellular")
        case .other: return LinkaCopy.value("Rede")
        case nil: return LinkaCopy.value("Desconectado")
        }
    }

    /// Banda confirmada pelo rádio Wi-Fi do Mac, sem inferir por SSID.
    private var confirmedWiFiBandDisplay: String {
        switch ApplePlatformSignalProvider.currentWifiBandGHz() {
        case 2.4: return LinkaCopy.value("network.wifiBand.value2_4GHz")
        case 5.0: return LinkaCopy.value("network.wifiBand.value5GHz")
        case 6.0: return LinkaCopy.value("network.wifiBand.value6GHz")
        default: return LinkaCopy.value("common.unavailable")
        }
    }

    // MARK: Assist e Otimização (versão da App Store)

    private var assistMeasurement: NetworkMeasurement? {
        switch assistEntryPoint {
        case .result(let m): return m
        case .fresh: return pendingAssistMeasurement ? nil : activeMeasurement
        }
    }

    private var assistView: some View {
        Group {
            if isPlusActive {
                AssistView(
                    currentMeasurement: assistEntryPoint.measurement ?? activeMeasurement ?? viewModel.latestFinishedMeasurement,
                    recentMeasurements: viewModel.recentMeasurements,
                    onRetry: {
                        destination = .speedTest
                        startMeasurement()
                    },
                    onRetest: {
                        destination = .speedTest
                        startMeasurement()
                    },
                    onShowDetails: {
                        if let m = assistEntryPoint.measurement ?? activeMeasurement ?? viewModel.latestFinishedMeasurement {
                            selectedHistoricalMeasurement = m
                        }
                    }
                )
            } else {
                assistUpgradeView
            }
        }
    }

    private var assistUpgradeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Color.brandAccentWarm)
            Text("Linka Assist").font(.title.weight(.bold))
            Text(LinkaCopy.value("Diagnóstico inteligente e recomendações guiadas para a sua conexão."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button(LinkaCopy.value("Conhecer o Linka Plus")) {
                purchaseEntryPoint = .assist
                showPurchase = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.brandAccentWarm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func requestAssist(from entryPoint: MacAssistEntryPoint) {
        assistEntryPoint = entryPoint
        if isPlusActive { destination = .assist } else { purchaseEntryPoint = .assist; showPurchase = true }
    }

    private var optimizationView: some View {
        Group {
            if let measurement = activeMeasurement ?? latestMeasurementForIntent {
                OptimizationView(
                    baseline: measurement,
                    history: viewModel.recentMeasurements,
                    isPlusActive: canUseOptimization,
                    onRequestPurchase: {
                        purchaseEntryPoint = .optimization
                        showPurchase = true
                    },
                    onRetest: {
                        optimizationBaseline = measurement
                        destination = .speedTest
                        startMeasurement()
                    },
                    onManageIdentification: {
                        MacSettingsOpener.open()
                    }
                )
            } else {
                NetworkProfilesManagementView(isPlusActive: canUseOptimization) {
                    purchaseEntryPoint = .optimization; showPurchase = true
                }
            }
        }
    }

    private func handleOptimizationRetestCompletion(_ phase: SpeedTestUIPhase) {
        guard let baseline = optimizationBaseline else { return }
        switch phase {
        case .done:
            guard let retest = activeMeasurement else {
                optimizationBaseline = nil
                return
            }
            optimizationBaseline = nil
            optimizationRetestResult = OptimizationRetestComparator.compare(baseline: baseline, retest: retest)
            showOptimizationRetestResult = true
        case .idle, .error, .connectionChanged:
            optimizationBaseline = nil
        case .connecting, .downloading, .uploading:
            break
        }
    }

    // MARK: Ações

    private static func analyticsName(_ destination: MacDestination) -> String {
        switch destination {
        case .speedTest: return "speedtest"
        case .history: return "history"
        case .myNetwork: return "my_network"
        case .assist: return "assist"
        case .optimization: return "optimization"
        }
    }

    private static func analyticsName(_ state: WiFiNetworkIdentificationState) -> String {
        switch state {
        case .active: return "granted"
        case .disabledByUser: return "disabled_by_user"
        case .permissionRequired: return "not_determined"
        case .permissionDenied: return "denied"
        case .unavailable: return "unavailable"
        }
    }

    /// Nome de tela do Firebase para o que está visível agora; só registra quando muda.
    private func trackScreen() {
        let name: String
        switch destination {
        case .speedTest:
            switch viewModel.uiPhase {
            case .idle: name = MacScreenName.speedtest
            case .done: name = MacScreenName.result
            case .error, .connectionChanged: name = MacScreenName.error
            default: name = MacScreenName.measuring
            }
        case .history: name = MacScreenName.history
        case .myNetwork: name = MacScreenName.myNetwork
        case .assist: name = MacScreenName.sheet("Assist")
        case .optimization: name = MacScreenName.sheet("Optimization")
        }
        guard name != lastScreen else { return }
        lastScreen = name
        MacAnalytics.shared.track(.screenView(name))
    }

    private func startMeasurement() {
        guard !isMeasuring else { return }
        inspectedMeasurement = nil
        let diagnostics = canStartAdvancedWiFiMeasurement
            ? MacAdvancedWiFiDiagnosticsProvider().capture(entitlement: entitlements.snapshot)
            : nil
        viewModel.startTest(advancedWiFiDiagnostics: diagnostics)
    }

    private func cancelMeasurement() {
        MacAnalytics.shared.track(.speedtestCancelled(phase: String(describing: viewModel.uiPhase)))
        viewModel.skipOrCancel()
    }

    private func startMeasurementFromHistory() {
        selectedHistoricalMeasurement = nil
        MacAnalytics.shared.markNextTestTrigger("history")
        destination = .speedTest
        DispatchQueue.main.async { startMeasurement() }
    }

    private func startMeasurementWithAdvancedWiFi() {
        guard !isMeasuring else { return }
        selectedHistoricalMeasurement = nil
        destination = .speedTest
        guard let diagnostics = MacAdvancedWiFiDiagnosticsProvider().capture(entitlement: entitlements.snapshot) else {
            showAdvancedWiFiUnavailable = true
            return
        }
        DispatchQueue.main.async { viewModel.startTest(advancedWiFiDiagnostics: diagnostics) }
    }

    private func handlePurchaseDismissal() {
        guard let action = pendingPurchaseDismissalAction else { return }
        pendingPurchaseDismissalAction = nil
        switch action {
        case .assistProblemSelection: destination = .assist
        case .subscriptionManagement: showSubscriptionManagement = true
        }
    }

    private func handlePublicUniversalLink(_ route: PublicUniversalLink?) {
        guard let route else { return }
        defer { intentCoordinator.consumePublicUniversalLink() }
        switch route {
        case .home: destination = .speedTest
        case .history: destination = .history
        case .myNetwork: destination = .myNetwork
        }
    }

    private func handleOpenLatestMeasurementRequest(_ pending: Bool) {
        guard pending else { return }
        defer { intentCoordinator.consumeOpenLatestMeasurement() }
        guard !isMeasuring else { return }
        guard isPlusActive else {
            if offersPlus { purchaseEntryPoint = .shortcut; showPurchase = true }
            return
        }
        guard let latest = latestMeasurementForIntent else { return }
        selectedHistoricalMeasurement = latest
    }

    private func updateShareState() {
        center.canShare = destination == .speedTest && !isMeasuring && activeMeasurement?.outcome == .complete
    }
}
#endif
