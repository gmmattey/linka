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

    // MARK: Estado derivado

    private var isPlusActive: Bool {
        LinkaEntitlementPolicy.decision(for: .assist, snapshot: entitlements.snapshot, at: Date()).isGranted
    }

    private var canUseOptimization: Bool {
        LinkaEntitlementPolicy.decision(for: .optimization, snapshot: entitlements.snapshot, at: Date()).isGranted
    }

    private var showsTools: Bool { !LinkaDistribution.isDirectDownload }

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
                    .background(Color.surfacePage)
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
        .onChange(of: viewModel.downloadSpeed) { speed in
            guard viewModel.uiPhase == .downloading, speed > 0 else { return }
            speedSamples.append(speed)
            if speedSamples.count > 90 { speedSamples.removeFirst(speedSamples.count - 90) }
        }
        .onChange(of: viewModel.uiPhase) { phase in
            center.isMeasuring = isMeasuring
            intentCoordinator.setMeasurementActive(isMeasuring)
            if phase == .connecting { speedSamples = [] }
            if phase == .done { inspectedMeasurement = nil }
            updateShareState()
            handleOptimizationRetestCompletion(phase)
            guard phase == .done, pendingAssistMeasurement else { return }
            pendingAssistMeasurement = false
            showAssistResult = true
        }
        .onChange(of: destination) { _ in updateShareState() }
        .onChange(of: intentCoordinator.pendingStartSpeedTest) { pending in
            guard pending else { return }
            guard !isMeasuring else { intentCoordinator.consumeStartSpeedTestRequest(); return }
            destination = .speedTest
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
            guard !isMeasuring, showsTools else { intentCoordinator.consumePurchasePrompt(); return }
            purchaseEntryPoint = .shortcut
            showPurchase = true
            intentCoordinator.consumePurchasePrompt()
        }
        .onChange(of: intentCoordinator.pendingOpenLatestMeasurement) { pending in
            handleOpenLatestMeasurementRequest(pending)
        }
        .onChange(of: intentCoordinator.pendingCancelMeasurement) { pending in
            guard pending else { return }
            if isMeasuring { viewModel.skipOrCancel() }
            intentCoordinator.consumeCancelMeasurement()
        }
        .onChange(of: intentCoordinator.pendingOpenSettings) { pending in
            guard pending else { return }
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            intentCoordinator.consumeOpenSettings()
        }
        .onChange(of: intentCoordinator.pendingPublicUniversalLink) { route in
            handlePublicUniversalLink(route)
        }
        .onChange(of: center.navigationRequest) { request in
            guard let request else { return }
            center.navigationRequest = nil
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
            center.showsTools = showsTools
            center.isMeasuring = isMeasuring
            intentCoordinator.setMeasurementActive(isMeasuring)
            // O macOS só informa o nome da rede Wi-Fi com Serviços de Localização autorizados.
            WiFiNetworkPermission.requestIdentification()
            viewModel.refreshLiveNetwork()
            handlePublicUniversalLink(intentCoordinator.pendingPublicUniversalLink)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wiFiAuthorizationDidChange)) { _ in
            viewModel.refreshLiveNetwork()
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
                    sidebarRow("Assist", systemImage: "sparkles", dest: .assist)
                    sidebarRow(LinkaCopy.value("optimization.title"), systemImage: "slider.horizontal.3", dest: .optimization)
                }
            }
        }
        .listStyle(.sidebar)
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
            MyNetworkView()
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
                if showsTools {
                    ToolbarItem(placement: .primaryAction) {
                        Button { requestAssist(from: .result(measurement)) } label: {
                            Label("Assist", systemImage: "sparkles")
                        }
                        .help("Assist")
                    }
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

    // Pronto para medir

    private var idleStage: some View {
        VStack(spacing: 0) {
            Text(LinkaCopy.value("Pronto para medir"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)
            if let last = viewModel.recentMeasurements.first {
                HStack(spacing: 36) {
                    ghostMetric(MacMeasurementFormat.mbps(last.downloadMbps), unit: "Mbps", label: "Download")
                    ghostMetric(MacMeasurementFormat.mbps(last.uploadMbps), unit: "Mbps", label: "Upload")
                    ghostMetric(last.latencyMs.map { String(Int(round($0))) } ?? "—", unit: "ms", label: "Ping")
                }
                Text("\(LinkaCopy.value("Última medição")) · \(last.measuredAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            } else {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.brandAccentWarm)
                Text(LinkaCopy.value("Pronto para testar sua velocidade"))
                    .font(.title2.weight(.semibold))
                    .padding(.top, 12)
            }
            Button(LinkaCopy.value("Iniciar teste")) { startMeasurement() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.brandAccentWarm)
                .padding(.top, 36)
            Text(LinkaCopy.value("O teste usa a sua conexão enquanto mede."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .padding(40)
    }

    private func ghostMetric(_ value: String, unit: String, label: String) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 48, weight: .semibold)).monospacedDigit().lineLimit(1).fixedSize()
                Text(unit).font(.callout.weight(.medium)).lineLimit(1).fixedSize()
            }
            Text(label).font(.caption)
        }
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .combine)
    }

    // Medindo

    private var measuringStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                phaseChip("Ping", step: pingStep)
                phaseLink(done: pingStep == .done)
                phaseChip("Download", step: downloadStep)
                phaseLink(done: downloadStep == .done)
                phaseChip("Upload", step: uploadStep)
            }
            .padding(.bottom, 28)

            let uploading = viewModel.uiPhase == .uploading
            let value = uploading ? viewModel.uploadSpeed : viewModel.downloadSpeed
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value > 0 ? MacMeasurementFormat.mbps(value) : "—")
                    .font(.system(size: 104, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.brandAccentWarmInk)
                Text("Mbps").font(.title2.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(LinkaCopy.value(uploading ? "Upload agora" : "Download agora"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            MacSparkline(values: speedSamples)
                .frame(width: 520, height: 90)

            HStack(spacing: 36) {
                liveFigure("Ping", viewModel.hasMeasuredPing ? "\(viewModel.ping) ms" : "—")
                liveFigure("Upload", viewModel.hasMeasuredUpload ? "\(MacMeasurementFormat.mbps(viewModel.uploadSpeed)) Mbps" : "—")
            }
            .padding(.vertical, 22)

            Button(LinkaCopy.value("Cancelar")) { viewModel.skipOrCancel() }
                .controlSize(.large)
        }
        .padding(40)
    }

    private func liveFigure(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .opacity(value == "—" ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    private func phaseChip(_ title: String, step: MacPhaseStep) -> some View {
        HStack(spacing: 5) {
            if step == .done { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
            Text(title).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .foregroundStyle(step == .active ? Color.white : (step == .done ? Color.statusGood : Color.textSecondary))
        .background(
            Capsule().fill(step == .active ? Color.brandAccentWarm : (step == .done ? Color.statusGood.opacity(0.14) : Color.primary.opacity(0.06)))
        )
    }

    private func phaseLink(done: Bool) -> some View {
        Capsule()
            .fill(done ? Color.brandAccentWarm : Color.primary.opacity(0.1))
            .frame(width: 28, height: 2)
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
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 56) {
                    resultMetric(MacMeasurementFormat.mbps(m.downloadMbps), unit: "Mbps", label: "Download", icon: "arrow.down", size: 88, accent: true)
                    resultMetric(MacMeasurementFormat.mbps(m.uploadMbps), unit: "Mbps", label: "Upload", icon: "arrow.up", size: 60, accent: false)
                    resultMetric(m.latencyMs.map { String(Int(round($0))) } ?? "—", unit: "ms", label: "Ping", icon: nil, size: 60, accent: false)
                }
                .padding(.top, 34)

                if m.outcome == .complete {
                    let report = UsageSuitabilityEvaluator().evaluate(m)
                    Text(UsageSuitabilityCopy.sentence(for: report))
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                        .padding(.top, 28)
                    usageList(report)
                        .padding(.top, 26)
                } else {
                    Text(LinkaCopy.value("Resultado parcial: algumas medições não foram concluídas."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                }

                Button(LinkaCopy.value("Medir novamente")) { startMeasurement() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.brandAccentWarm)
                    .padding(.vertical, 30)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)
        }
    }

    private func resultMetric(_ value: String, unit: String, label: String, icon: String?, size: CGFloat, accent: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: size, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(accent ? Color.brandAccentWarmInk : Color.primary)
                Text(unit).font(.headline).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
                Text(label)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func usageList(_ report: UsageSuitabilityReport) -> some View {
        let cases: [UsageCase] = [.videoCall, .streaming4K, .onlineGaming, .workUpload]
        return VStack(alignment: .leading, spacing: 6) {
            Text(LinkaCopy.value("Para que serve agora"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            VStack(spacing: 0) {
                Divider()
                ForEach(cases, id: \.self) { usageCase in
                    if let verdict = report.verdict(for: usageCase) {
                        Button { showUsageDiagnostics = true } label: {
                            HStack {
                                Text(UsageSuitabilityCopy.title(for: usageCase))
                                Spacer()
                                usageTag(verdict.level)
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: 560)
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
                .font(.title2.weight(.semibold))
            Text(LinkaCopy.value("Verifique sua rede e tente novamente."))
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
                .font(.title2.weight(.semibold))
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
                    if let server = m.networkIdentifier, !server.isEmpty {
                        MacInspectorRow(label: LinkaCopy.value("Servidor"), value: server)
                    }
                    if let duration = m.durationMs {
                        MacInspectorRow(label: LinkaCopy.value("Duração"), value: "\(Int(round(Double(duration) / 1000))) s")
                    }
                }
                MacInspectorSection(LinkaCopy.value("Rede")) {
                    MacInspectorRow(label: LinkaCopy.value("Rede"), value: MacMeasurementFormat.networkName(m))
                    if let band = m.wifiContext?.bandGHz {
                        MacInspectorRow(label: LinkaCopy.value("network.wifiBand"), value: String(format: "%g GHz", band))
                    }
                    if let rssi = m.wifiContext?.rssiDbm {
                        MacInspectorRow(label: LinkaCopy.value("Sinal"), value: "\(Int(rssi)) dBm")
                    }
                }
                MacInspectorSection {
                    MacInspectorAction(title: LinkaCopy.value("Detalhes completos…")) { showCurrentMeasurementDetails = true }
                    if connectionPathReport != nil {
                        Divider()
                        MacInspectorAction(title: LinkaCopy.value("Caminho da conexão")) { showConnectionPath = true }
                    }
                    if viewModel.uiPhase == .done {
                        Divider()
                        MacInspectorAction(title: LinkaCopy.value("Análise detalhada")) { showNetscopeAnalysis = true }
                    }
                    Divider()
                    MacInspectorAction(title: LinkaCopy.value("Como medimos")) {
                        NSWorkspace.shared.open(LinkaExternalLinks.howWeMeasure)
                    }
                }
            } else {
                MacInspectorSection(LinkaCopy.value("Rede agora")) {
                    MacInspectorRow(label: LinkaCopy.value("Rede"), value: liveConnectionName)
                    MacInspectorRow(label: LinkaCopy.value("Conexão"), value: liveConnectionKindName)
                    if viewModel.liveConnectionKind == .wifi {
                        MacInspectorRow(label: LinkaCopy.value("network.wifiBand"), value: confirmedWiFiBandDisplay)
                        MacInspectorRow(label: LinkaCopy.value("Sinal"), value: viewModel.liveWifiRSSI.map { "\(Int($0)) dBm" } ?? "—")
                        if let link = viewModel.liveWiFiContext?.linkSpeedMbps {
                            MacInspectorRow(label: LinkaCopy.value("Velocidade do link"), value: "\(Int(link)) Mbps")
                        }
                    }
                }
                Text(LinkaCopy.value("Observação ao vivo. Não mede velocidade e não inicia nenhum teste."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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

    private func startMeasurement() {
        guard !isMeasuring else { return }
        inspectedMeasurement = nil
        let diagnostics = canStartAdvancedWiFiMeasurement
            ? MacAdvancedWiFiDiagnosticsProvider().capture(entitlement: entitlements.snapshot)
            : nil
        viewModel.startTest(advancedWiFiDiagnostics: diagnostics)
    }

    private func startMeasurementFromHistory() {
        selectedHistoricalMeasurement = nil
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
            if showsTools { purchaseEntryPoint = .shortcut; showPurchase = true }
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
