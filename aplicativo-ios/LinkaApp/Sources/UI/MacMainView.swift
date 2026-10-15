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
import NetworkDNSBenchmark

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

private enum DotPhase { case pending, active, done }

private extension MacDestination {
    var accessibilityIdentifier: String {
        switch self {
        case .speedTest: return "speedTest"
        case .history: return "history"
        case .assist: return "assist"
        case .dns: return "dns"
        case .optimization: return "optimization"
        case .myNetwork: return "myNetwork"
        case .settings: return "settings"
        }
    }

    var title: String {
        switch self {
        case .speedTest: return LinkaCopy.value("mac.destination.speedTest")
        case .history: return LinkaCopy.value("mac.destination.history")
        case .assist: return LinkaCopy.value("assist.title")
        case .dns: return LinkaCopy.value("mac.destination.dns")
        case .optimization: return LinkaCopy.value("optimization.title")
        case .myNetwork: return LinkaCopy.value("inventory.title")
        case .settings: return LinkaCopy.value("settings.title")
        }
    }

    var systemImage: String {
        switch self {
        case .speedTest: return "gauge.medium"
        case .history: return "clock.arrow.circlepath"
        case .assist: return "sparkles"
        case .dns: return "globe"
        case .optimization: return "slider.horizontal.3"
        case .myNetwork: return "wifi.router"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - MacMainView

struct MacMainView: View {
    @StateObject private var viewModel = SpeedTestViewModel()
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @ObservedObject private var intentCoordinator = AppIntentCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    @State private var destination: MacDestination = .speedTest
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showPurchase = false
    @State private var optimizationBaseline: NetworkMeasurement?
    @State private var optimizationRetestResult: OptimizationRetestComparison?
    @State private var showOptimizationRetestResult = false
    @State private var showSubscriptionManagement = false
    @State private var pendingPurchaseDismissalAction: MacPurchaseDismissalAction?
    @State private var purchaseEntryPoint: PurchaseEntryPoint = .settings
    @State private var assistEntryPoint: MacAssistEntryPoint = .fresh
    @State private var showAssistProblemSelection = false
    @State private var showAssistResult = false
    @State private var showNetscopeAnalysis = false
    @State private var pendingAssistMeasurement = false
    @State private var pendingAssistObjective: String?
    @State private var pendingAssistSubcategory: String?
    @State private var pendingAssistReportedProblem: String?
    @State private var showConnectivityTriage = false
    @State private var speedGaugeUpperBound = 1.0
    @State private var selectedHistoricalMeasurement: NetworkMeasurement?
    @State private var inspectedHistoricalMeasurement: NetworkMeasurement?
    @State private var showCurrentMeasurementDetails = false
    @State private var showUsageDiagnostics = false
    @State private var showConnectionPath = false
    @State private var showShareSheet = false
    @State private var showAdvancedWiFiUnavailable = false
    @State private var showMeasurementDetails = false
    @State private var showLiveNetworkDetails = false
    @State private var showInspector = true
    @State private var measurementMode: String = "Completo"
    @State private var selectedUsageModalKind: String?
    @State private var showUsageExplanationModal = false
    @State private var optimizationComparisonPair: [NetworkMeasurement]?
    @State private var showOptimizationComparisonSheet = false

    // MARK: Computed

    private var isPlusActive: Bool {
        LinkaEntitlementPolicy.decision(for: .assist, snapshot: entitlements.snapshot, at: Date()).isGranted
    }

    private var canUseOptimization: Bool {
        LinkaEntitlementPolicy.decision(for: .optimization, snapshot: entitlements.snapshot, at: Date()).isGranted
    }

    private var activeMeasurement: NetworkMeasurement? {
        if viewModel.uiPhase == .done {
            return viewModel.latestFinishedMeasurement
        }
        return inspectedHistoricalMeasurement
    }

    private var currentMeasurement: NetworkMeasurement? {
        activeMeasurement
    }

    private var latestMeasurementForIntent: NetworkMeasurement? {
        viewModel.latestFinishedMeasurement ?? viewModel.recentMeasurements.first
    }

    private var connectionPathReport: ConnectionPathReport? {
        guard let m = currentMeasurement else { return nil }
        return ConnectionPathEvaluator().evaluate(m)
    }

    private var assistMeasurement: NetworkMeasurement? {
        switch assistEntryPoint {
        case .result(let m): return m
        case .fresh: return pendingAssistMeasurement ? nil : currentMeasurement
        }
    }

    private var isMeasuring: Bool {
        switch viewModel.uiPhase {
        case .connecting, .downloading, .uploading: return true
        default: return false
        }
    }

    private var isFinalResult: Bool { viewModel.uiPhase == .done }
    private var isDownloading: Bool { viewModel.uiPhase == .downloading }

    private var canStartAdvancedWiFiMeasurement: Bool {
        guard viewModel.liveConnectionKind == .wifi,
              LinkaWiFiPreferences.isAdvancedDiagnosticsEnabled else { return false }
        return LinkaEntitlementPolicy.decision(
            for: .advancedWiFiDiagnostics,
            snapshot: entitlements.snapshot,
            at: Date()
        ).isGranted
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            navigationSidebar
        } detail: {
            destinationContent
        }
        // Links contextuais (por exemplo, dentro de Ajustes) pertencem à
        // mesma pilha do split view. Ao trocar o destino principal, reinicie
        // a casca para não deixar um detalhe antigo cobrir o novo espaço.
        .id("\(destination.accessibilityIdentifier)-\(locale.identifier)")
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 600)
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
        .sheet(isPresented: $showOptimizationComparisonSheet) {
            if let pair = optimizationComparisonPair, pair.count == 2 {
                MacHistoryComparisonSheet(measurements: pair) {
                    showOptimizationComparisonSheet = false
                    requestAssist(from: .result(pair[1]))
                }
                .frame(minWidth: 680, minHeight: 540)
            }
        }
        .sheet(isPresented: $showUsageExplanationModal) {
            usageExplanationSheet
        }
        .sheet(isPresented: $showSubscriptionManagement) {
            SubscriptionManagementSheet()
                .environmentObject(entitlements)
                .frame(minWidth: 620, minHeight: 560)
        }
        .sheet(isPresented: $showAssistProblemSelection, onDismiss: beginPendingAssistCollection) {
            AssistProblemSelectionView(
                currentMeasurement: assistEntryPoint.measurement,
                recentMeasurements: [],
                onStartFreshMeasurement: { objective, subcategory, reportedProblem in
                    pendingAssistObjective = objective
                    pendingAssistSubcategory = subcategory
                    pendingAssistReportedProblem = reportedProblem
                    pendingAssistMeasurement = true
                },
                entitlements: entitlements
            )
            .frame(minWidth: 680, minHeight: 620)
        }
        .sheet(isPresented: $showAssistResult) {
            AssistView(
                currentMeasurement: assistMeasurement,
                recentMeasurements: [],
                isCollectingMeasurement: pendingAssistMeasurement,
                objective: pendingAssistObjective,
                subcategory: pendingAssistSubcategory,
                reportedProblem: pendingAssistReportedProblem,
                onRetry: { pendingAssistMeasurement = true; viewModel.startTest() },
                onShowDetails: {},
                entitlements: entitlements
            )
            .frame(minWidth: 680, minHeight: 620)
        }
        .sheet(isPresented: $showNetscopeAnalysis) {
            if let currentMeasurement {
                NetscopeAnalysisView(
                    input: NetscopeAnalysisInput(projectingFinalMeasurement: currentMeasurement)
                )
                .frame(minWidth: 520, minHeight: 380)
            } else {
                NetscopeAnalysisView()
                    .frame(minWidth: 520, minHeight: 380)
            }
        }
        .sheet(isPresented: $showConnectivityTriage) {
            ConnectivityTriageView(onRetry: { viewModel.startTest() })
                .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(item: $selectedHistoricalMeasurement) { measurement in
            NavigationStack {
                HistoricalMeasurementDetailView(
                    measurement: measurement,
                    onStartNewMeasurement: startMeasurementFromHistory,
                    onStartNewMeasurementWithAdvancedWiFi: startMeasurementWithAdvancedWiFi
                )
            }
            .environmentObject(entitlements)
            .frame(minWidth: 680, minHeight: 680)
        }
        .sheet(isPresented: $showCurrentMeasurementDetails) {
            NavigationStack {
                MeasurementDetailView(measurement: currentMeasurement, duration: viewModel.testDuration)
                    .environmentObject(entitlements)
            }
            .frame(minWidth: 680, minHeight: 680)
        }
        .sheet(isPresented: $showUsageDiagnostics) {
            UsageDiagnosticsView(measurement: currentMeasurement)
                .frame(minWidth: 680, minHeight: 580)
        }
        .sheet(isPresented: $showConnectionPath) {
            if let connectionPathReport {
                ConnectionPathDetailView(report: connectionPathReport)
                    .frame(minWidth: 680, minHeight: 580)
            }
        }
        .shareMeasurementSheet(isPresented: $showShareSheet, measurement: currentMeasurement)
        .alert(LinkaCopy.value("mac.alert.advancedWiFi.title"), isPresented: $showAdvancedWiFiUnavailable) {
            Button(LinkaCopy.value("common.ok"), role: .cancel) {}
        } message: {
            Text(LinkaCopy.value("mac.alert.advancedWiFi.message"))
        }
        .onChange(of: viewModel.downloadSpeed) { speed in
            guard viewModel.uiPhase == .downloading, speed > speedGaugeUpperBound else { return }
            speedGaugeUpperBound = Self.speedGaugeScale(for: speed)
        }
        .onChange(of: viewModel.uiPhase) { phase in
            intentCoordinator.setMeasurementActive(isMeasuring)
            if phase == .connecting { speedGaugeUpperBound = 1 }
            if phase == .done {
                inspectedHistoricalMeasurement = nil
            }
            handleOptimizationRetestCompletion(phase)
            guard phase == .done, pendingAssistMeasurement else { return }
            pendingAssistMeasurement = false
            showAssistResult = true
        }
        .onChange(of: intentCoordinator.pendingStartSpeedTest) { pending in
            guard pending else { return }
            guard !isMeasuring else { intentCoordinator.consumeStartSpeedTestRequest(); return }
            destination = .speedTest
            viewModel.startTest()
            intentCoordinator.consumeStartSpeedTestRequest()
        }
        .onChange(of: intentCoordinator.pendingOpenHistory) { pending in
            handleOpenHistoryRequest(pending)
        }
        .onChange(of: intentCoordinator.pendingPurchasePrompt) { pending in
            guard pending else { return }
            guard !isMeasuring else { intentCoordinator.consumePurchasePrompt(); return }
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
            if !isMeasuring { destination = .settings }
            intentCoordinator.consumeOpenSettings()
        }
        .onAppear {
            intentCoordinator.setMeasurementActive(isMeasuring)
            viewModel.refreshLiveNetwork()
        }
        .onDisappear { intentCoordinator.setMeasurementActive(false) }
    }

    // MARK: - Native navigation shell

    private var navigationSidebar: some View {
        List(selection: $destination) {
            Section(LinkaCopy.value("mac.sidebar.yourConnection")) {
                destinationLink(.speedTest)
                destinationLink(.history, isDisabled: !MacNavigationPolicy.isAvailable(.history, isMeasuring: isMeasuring, hasMeasurement: currentMeasurement != nil, minhaRedeEnabled: MinhaRedeAvailability.isEnabled))
                destinationLink(.assist, isDisabled: !MacNavigationPolicy.isAvailable(.assist, isMeasuring: isMeasuring, hasMeasurement: currentMeasurement != nil, minhaRedeEnabled: MinhaRedeAvailability.isEnabled))
            }

            Section(LinkaCopy.value("mac.sidebar.tools")) {
                destinationLink(.dns, isDisabled: !MacNavigationPolicy.isAvailable(.dns, isMeasuring: isMeasuring, hasMeasurement: currentMeasurement != nil, minhaRedeEnabled: MinhaRedeAvailability.isEnabled))
                destinationLink(.optimization, isDisabled: !MacNavigationPolicy.isAvailable(.optimization, isMeasuring: isMeasuring, hasMeasurement: currentMeasurement != nil, minhaRedeEnabled: MinhaRedeAvailability.isEnabled))
                if MinhaRedeAvailability.isEnabled {
                    destinationLink(.myNetwork, isDisabled: !MacNavigationPolicy.isAvailable(.myNetwork, isMeasuring: isMeasuring, hasMeasurement: currentMeasurement != nil, minhaRedeEnabled: MinhaRedeAvailability.isEnabled))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, alignment: .leading) {
            VStack(alignment: .leading, spacing: 3) {
                Image("wordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 98, height: 30)
                    .accessibilityLabel("Linka")
                Text("FEITO PARA O SEU MAC")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.textSecondary.opacity(0.8))
                    .tracking(0.8)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom) {
            sidebarBottomSection
        }
    }

    private var sidebarBottomSection: some View {
        VStack(spacing: 4) {
            Divider()

            // Conexão atual compacta
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: "wifi")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(liveConnectionName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(viewModel.connectionKind == nil && viewModel.liveConnectionKind == nil ? "Sem internet" : "Wi-Fi conectado")
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            // Ações de rodapé: Ajustes e Linka Plus
            Button {
                destination = .settings
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    Text(LinkaCopy.value("settings.title"))
                        .font(.system(size: 11))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("⌘ ,")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mac.sidebar.bottom.settings")

            Button {
                purchaseEntryPoint = .settings
                showPurchase = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(.brandAccentWarm)
                    Text("Linka Plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("Conhecer")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.brandAccentWarm.opacity(0.18))
                        .foregroundColor(.brandAccentWarm)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
        }
    }

    private func destinationLink(_ destination: MacDestination, isDisabled: Bool = false) -> some View {
        NavigationLink(value: destination) {
            HStack {
                Label(destination.title, systemImage: destination.systemImage)
                Spacer()
                if destination == .myNetwork {
                    Text("Proposta")
                        .font(.system(size: 9))
                        .italic()
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .disabled(isDisabled)
        .accessibilityIdentifier("mac.sidebar.\(destination.accessibilityIdentifier)")
    }

    @ViewBuilder
    private var destinationContent: some View {
        VStack(spacing: 0) {
            Group {
                switch destination {
                case .speedTest:
                    speedTestWorkspace
                case .history:
                    historyView
                case .assist:
                    assistView
                case .dns:
                    dnsView
                case .optimization:
                    optimizationView
                case .myNetwork:
                    MyNetworkView(onNavigateToAssist: { destination = .assist })
                        .environmentObject(entitlements)
                case .settings:
                    settingsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            macStatusBar
        }
        .navigationTitle(destination.title)
        .navigationSubtitle(liveConnectionName)
        .accessibilityIdentifier("mac.workspace.\(destination.accessibilityIdentifier)")
        .background(
            LinkaScreenBackground(
                variant: .gradientOnly,
                showWaves: false
            )
        )
        .background {
            Group {
                Button("") { destination = .speedTest }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { destination = .history }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { destination = .assist }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { destination = .dns }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { destination = .optimization }
                    .keyboardShortcut("5", modifiers: .command)
                if MinhaRedeAvailability.isEnabled {
                    Button("") { destination = .myNetwork }
                        .keyboardShortcut("6", modifiers: .command)
                }
                Button("") { destination = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if destination != .speedTest {
                    if isMeasuring {
                        Button(LinkaCopy.value("common.cancel"), action: viewModel.skipOrCancel)
                            .keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button(LinkaCopy.value("home.testSpeed"), action: startMeasurementFromGlobalAction)
                            .keyboardShortcut("r", modifiers: .command)
                    }
                } else {
                    if isMeasuring {
                        Button(LinkaCopy.value("common.cancel"), action: viewModel.skipOrCancel)
                            .keyboardShortcut(".", modifiers: .command)
                    } else if activeMeasurement != nil {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Compartilhar", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("mac.toolbar.share")

                        Button {
                            startMeasurementFromGlobalAction()
                        } label: {
                            Label(LinkaCopy.value("common.testAgain"), systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        .accessibilityIdentifier("mac.toolbar.retest")
                    } else {
                        Button {
                            startMeasurementFromGlobalAction()
                        } label: {
                            Label(LinkaCopy.value("home.testSpeed"), systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        .accessibilityIdentifier("mac.toolbar.startTest")
                    }
                }

                Button {
                    destination = .settings
                } label: {
                    Label(LinkaCopy.value("settings.title"), systemImage: "gearshape")
                }
                .disabled(isMeasuring || destination == .settings)
                .accessibilityIdentifier("mac.toolbar.settings")

                if destination == .speedTest {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showInspector.toggle()
                        }
                    } label: {
                        Label("Detalhes da conexão", systemImage: showInspector ? "info.circle.fill" : "info.circle")
                    }
                    .accessibilityIdentifier("mac.toolbar.inspector")
                }
            }
        }
    }

    private var speedTestWorkspace: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                mainStage

                if showInspector && (proxy.size.width >= 720 || MacHomeLayout.showsInspector(contentWidth: proxy.size.width, hasMeasurement: activeMeasurement != nil)) {
                    Divider()
                    rightPanel
                        .frame(width: 300)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Main Stage

    private var mainStage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Header (Network name)
                    HStack {
                        Text(liveConnectionName)
                            .font(.bodySmallStrong)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if !isMeasuring, let measurement = activeMeasurement {
                            resultToolbarActions(for: measurement)
                        }
                        statusPill
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 28)

                    if isMeasuring {
                        macTestingView
                            .padding(.horizontal, 28)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                    } else if let m = activeMeasurement {
                        macResultView(for: m)
                            .padding(.horizontal, 28)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                    } else {
                        cleanIdleCenterView
                            .padding(.horizontal, 28)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                    }
                }
                .frame(maxWidth: 970)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            // "Sua rede agora" Footer + Wi-Fi Metadata
            macContextFooter
                .frame(maxWidth: 970)
        }
    }

    private var cleanIdleCenterView: some View {
        VStack(spacing: 18) {
            // Hero Icon
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.brandAccentWarm.opacity(0.12))
                    .frame(width: 76, height: 76)
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundColor(.brandAccentWarm)
            }
            .padding(.top, 12)

            // Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.statusGood)
                    .frame(width: 6, height: 6)
                Text(LinkaCopy.value("mac.result.good"))
                    .font(.captionSmallStrong)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.statusGood.opacity(0.12), in: Capsule())

            // Title & Subtitle
            VStack(spacing: 8) {
                Text(LinkaCopy.value("mac.idle.question"))
                    .font(.title2.weight(.bold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text(LinkaCopy.value("mac.idle.subtitle"))
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            // Mode Selector
            Picker("", selection: $measurementMode) {
                Text(LinkaCopy.value("mac.idle.mode.fast")).tag("Rápido")
                Text(LinkaCopy.value("mac.idle.mode.complete")).tag("Completo")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .padding(.top, 4)

            // Start Button
            Button {
                startMeasurement()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.medium")
                    Text(LinkaCopy.value("mac.idle.start"))
                    Text("⌘ R")
                        .font(.caption2)
                        .opacity(0.7)
                }
                .font(.bodySmallStrong)
                .frame(minWidth: 190)
            }
            .buttonStyle(.macPrimary)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityIdentifier("mac.idle.startButton")
            .padding(.top, 6)

            // Privacy Card
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.brandAccentWarm.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "shield")
                        .font(.system(size: 16))
                        .foregroundColor(.brandAccentWarm)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(LinkaCopy.value("mac.idle.privacy.title"))
                        .font(.bodySmallStrong)
                        .foregroundColor(.textPrimary)
                    Text(LinkaCopy.value("mac.idle.privacy.desc"))
                        .font(.captionSmall)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
            )
            .frame(maxWidth: 480)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func measurementMetadataBadge(for m: NetworkMeasurement) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .regular))
                Text(Self.dateFormatter.string(from: m.measuredAt))
                    .font(.captionMedium)
            }
            Text("•")
                .foregroundColor(.borderDefault)
            HStack(spacing: 5) {
                Image(systemName: "network")
                    .font(.system(size: 11, weight: .regular))
                Text(networkLabel(for: m))
                    .font(.captionMedium)
            }
            if let server = m.networkIdentifier, !server.isEmpty {
                Text("•")
                    .foregroundColor(.borderDefault)
                HStack(spacing: 5) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 11, weight: .regular))
                    Text(server)
                        .font(.captionMedium)
                }
            }
        }
        .foregroundColor(.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.surfaceCard, in: Capsule())
    }

    private func measurementMetadataLine(for m: NetworkMeasurement) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
            Text(Self.dateFormatter.string(from: m.measuredAt))
            Text("•")
            Image(systemName: "wifi")
            Text(networkLabel(for: m))
            if let server = m.networkIdentifier, !server.isEmpty {
                Text("•")
                Text(server)
                    .lineLimit(1)
            }
        }
        .font(.captionMedium)
        .foregroundColor(.textSecondary)
        .lineLimit(1)
    }

    private func resultToolbarActions(for measurement: NetworkMeasurement) -> some View {
        HStack(spacing: 14) {
            Button {
                requestAssist(from: .result(measurement))
            } label: {
                Label(LinkaCopy.value("assist.title"), systemImage: "sparkles")
            }
            .buttonStyle(.plain)

            Button {
                destination = .optimization
            } label: {
                Label(LinkaCopy.value("optimization.title"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)

            Button {
                showCurrentMeasurementDetails = true
            } label: {
                Label(LinkaCopy.value("assist.technicalDetails"), systemImage: "info.circle")
            }
            .buttonStyle(.plain)
        }
        .font(.captionMedium)
        .foregroundColor(.textSecondary)
    }
    
    private var horizontalHero: some View {
        HStack(spacing: 32) {
            heroBlock(label: LinkaCopy.value("detail.download"), value: downloadFooterValue, unit: "Mbps", isActive: downloadDotState == .active)
            heroBlock(label: LinkaCopy.value("detail.upload"), value: uploadFooterValue, unit: "Mbps", isActive: uploadDotState == .active)
        }
        .padding(.horizontal, 20)
    }

    private func horizontalHero(for m: NetworkMeasurement) -> some View {
        HStack(spacing: 32) {
            heroBlock(
                label: LinkaCopy.value("detail.download"),
                value: m.downloadMbps.map { localizedNumber($0, fractionDigits: 1) } ?? "—",
                unit: "Mbps",
                isActive: false
            )
            heroBlock(
                label: LinkaCopy.value("detail.upload"),
                value: m.uploadMbps.map { localizedNumber($0, fractionDigits: 1) } ?? "—",
                unit: "Mbps",
                isActive: false
            )
        }
        .padding(.horizontal, 20)
    }
    
    private func heroBlock(label: String, value: String, unit: String, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .bold, design: .default))
                .foregroundColor(isActive ? .brandAccentWarm : .textSecondary)
                .tracking(1.1)
                .lineLimit(1)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundColor(isActive ? .brandAccentWarm : .textPrimary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                
                Text(unit)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 80, maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value) \(unit)")
    }
    
    private func advancedMetricsRow(for measurement: NetworkMeasurement) -> some View {
        HStack(spacing: 0) {
            if let ping = measurement.latencyMs {
                miniDetailCell(label: LinkaCopy.value("detail.ping"), value: localizedNumber(ping, fractionDigits: 0), unit: "ms")
                    .frame(maxWidth: .infinity)
            }
            if let jitter = measurement.jitterMs {
                miniDetailCell(label: LinkaCopy.value("detail.jitter"), value: localizedNumber(jitter, fractionDigits: 0), unit: "ms")
                    .frame(maxWidth: .infinity)
            }
            if let loss = measurement.packetLossPercent {
                let formattedLoss = localizedNumber(loss, fractionDigits: loss == 0 ? 0 : 1)
                miniDetailCell(label: LinkaCopy.value("detail.packetLoss"), value: formattedLoss, unit: "%")
                    .frame(maxWidth: .infinity)
            }
            if let dns = measurement.dnsResolutionMs {
                miniDetailCell(label: LinkaCopy.value("detail.dns"), value: localizedNumber(dns, fractionDigits: 0), unit: "ms")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }
    
    private func miniDetailCell(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textSecondary)
                .tracking(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.textSecondary)
            }
        }
    }
    
    // MARK: - Testing View (Phase 2)

    private var macTestingView: some View {
        VStack(spacing: 20) {
            // Warm Badge
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.brandAccentWarm)
                Text("\(LinkaCopy.value("mac.testing.badge")) · \(measurementMode.lowercased())")
                    .font(.captionSmallStrong)
                    .foregroundColor(.brandAccentWarm)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())

            // Stage Title
            Text(currentTestingStageTitle)
                .font(.title2.weight(.semibold))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .animation(.easeInOut, value: testingStageIndex)

            // Circular Progress Ring (168x168)
            ZStack {
                Circle()
                    .stroke(Color.borderDefault.opacity(0.35), lineWidth: 7)
                    .frame(width: 168, height: 168)

                Circle()
                    .trim(from: 0, to: testingProgressRatio)
                    .stroke(
                        Color.brandAccentWarm,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 168, height: 168)
                    .animation(.snappy(duration: 0.3), value: testingProgressRatio)

                VStack(spacing: 2) {
                    Text(currentTestingCenterNumber)
                        .font(.system(size: testingCenterFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText())

                    Text(currentTestingCenterUnit)
                        .font(.captionSmallStrong)
                        .foregroundColor(.textSecondary)
                }
                .frame(width: 130)
            }
            .padding(.vertical, 6)

            // 5-Phase Indicator
            HStack(spacing: 16) {
                ForEach(0..<5) { idx in
                    HStack(spacing: 4) {
                        Text(idx < testingStageIndex ? "✓" : "·")
                            .font(.captionSmallStrong)
                        Text(testingPhaseName(at: idx))
                            .font(idx == testingStageIndex ? .captionSmallStrong : .captionSmall)
                    }
                    .foregroundColor(testingPhaseColor(at: idx))
                }
            }
            .padding(.top, 4)

            // Footnote
            Text(LinkaCopy.value("mac.testing.footnote"))
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            // Cancel Button
            Button(LinkaCopy.value("common.cancel")) {
                viewModel.skipOrCancel()
            }
            .buttonStyle(.macSecondary)
            .keyboardShortcut(".", modifiers: .command)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var testingStageIndex: Int {
        switch viewModel.uiPhase {
        case .connecting:
            return viewModel.hasMeasuredPing ? 1 : 0
        case .downloading:
            return 2
        case .uploading:
            return 3
        case .done:
            return 4
        default:
            return 0
        }
    }

    private var currentTestingStageTitle: String {
        switch viewModel.uiPhase {
        case .connecting:
            return viewModel.hasMeasuredPing
                ? LinkaCopy.value("mac.testing.stage.latency")
                : LinkaCopy.value("mac.testing.stage.connecting")
        case .downloading:
            return LinkaCopy.value("mac.testing.stage.download")
        case .uploading:
            return LinkaCopy.value("mac.testing.stage.upload")
        case .done:
            return LinkaCopy.value("mac.testing.stage.finishing")
        default:
            return LinkaCopy.value("mac.testing.stage.connecting")
        }
    }

    private var currentTestingCenterNumber: String {
        switch viewModel.uiPhase {
        case .connecting:
            return viewModel.hasMeasuredPing ? "\(viewModel.ping)" : "15%"
        case .downloading:
            return viewModel.downloadSpeed > 0 ? localizedNumber(viewModel.downloadSpeed, fractionDigits: 1) : "—"
        case .uploading:
            return viewModel.uploadSpeed > 0 ? localizedNumber(viewModel.uploadSpeed, fractionDigits: 1) : "—"
        case .done:
            return "100%"
        default:
            return "—"
        }
    }

    private var currentTestingCenterUnit: String {
        switch viewModel.uiPhase {
        case .connecting:
            return viewModel.hasMeasuredPing ? "ms" : "preparando"
        case .downloading, .uploading:
            return "Mbps"
        case .done:
            return "concluído"
        default:
            return ""
        }
    }

    private var testingCenterFontSize: CGFloat {
        switch viewModel.uiPhase {
        case .downloading, .uploading:
            return 34
        default:
            return 40
        }
    }

    private var testingProgressRatio: CGFloat {
        switch viewModel.uiPhase {
        case .connecting:
            return viewModel.hasMeasuredPing ? 0.25 : 0.12
        case .downloading:
            let relative = CGFloat(min(1.0, max(0.0, viewModel.downloadSpeed / max(speedGaugeUpperBound, 10.0))))
            return 0.25 + 0.35 * relative
        case .uploading:
            let relative = CGFloat(min(1.0, max(0.0, viewModel.uploadSpeed / max(speedGaugeUpperBound, 10.0))))
            return 0.60 + 0.35 * relative
        case .done:
            return 1.0
        default:
            return 0.05
        }
    }

    private func testingPhaseName(at index: Int) -> String {
        switch index {
        case 0: return LinkaCopy.value("mac.testing.phase.connection")
        case 1: return LinkaCopy.value("mac.testing.phase.latency")
        case 2: return LinkaCopy.value("mac.testing.phase.download")
        case 3: return LinkaCopy.value("mac.testing.phase.upload")
        case 4: return LinkaCopy.value("mac.testing.phase.diagnostics")
        default: return ""
        }
    }

    private func testingPhaseColor(at index: Int) -> Color {
        if index < testingStageIndex {
            return .statusGood
        } else if index == testingStageIndex {
            return .brandAccentWarm
        } else {
            return .textSecondary.opacity(0.6)
        }
    }

    // MARK: - Result View (Phase 3)

    private func macResultView(for m: NetworkMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Status Header
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    Image(systemName: isAttentionResult(m) ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(isAttentionResult(m) ? .statusAttention : .statusGood)
                    Text(isAttentionResult(m) ? LinkaCopy.value("mac.result.attention") : LinkaCopy.value("mac.result.good"))
                        .font(.captionSmallStrong)
                        .foregroundColor(isAttentionResult(m) ? .statusAttention : .statusGood)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background((isAttentionResult(m) ? Color.statusAttention : Color.statusGood).opacity(0.12), in: Capsule())

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(networkLabel(for: m)) · \(confirmedWiFiBandDisplay)")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.textSecondary)
                    Text(Self.dateFormatter.string(from: m.measuredAt))
                        .font(.caption2)
                        .foregroundColor(.textSecondary.opacity(0.8))
                }
            }

            // Headline & Subtitle
            VStack(alignment: .leading, spacing: 6) {
                Text(isAttentionResult(m) ? LinkaCopy.value("mac.result.attention.title") : LinkaCopy.value("mac.result.good.title"))
                    .font(.title2.weight(.bold))
                    .foregroundColor(.textPrimary)

                Text(isAttentionResult(m) ? LinkaCopy.value("mac.result.attention.subtitle") : LinkaCopy.value("mac.result.good.subtitle"))
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
            }

            // 3-Column Dominant Metrics
            dominantMetricsGrid(for: m)

            // Speed Curve Graph
            MacSpeedCurveChartView(measurement: m)

            // 3 Practical Usage Cards
            practicalUsageCards(for: m)

            // Assist Insight Card
            assistInsightCard(for: m)

            // Actions (Medir novamente + Detalhes + Nota)
            HStack(spacing: 12) {
                Button {
                    startMeasurement()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text(LinkaCopy.value("common.testAgain"))
                        Text("⌘ R")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                }
                .buttonStyle(.macPrimary)
                .keyboardShortcut("r", modifiers: .command)

                Button(LinkaCopy.value("assist.technicalDetails")) {
                    showCurrentMeasurementDetails = true
                }
                .buttonStyle(.macSecondary)

                Spacer()

                Text(LinkaCopy.value("mac.result.savedLocal"))
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 16)
    }

    private func isAttentionResult(_ m: NetworkMeasurement) -> Bool {
        (m.latencyMs ?? 0) > 45 || (m.jitterMs ?? 0) > 10 || (m.packetLossPercent ?? 0) > 1.0
    }

    private func dominantMetricsGrid(for m: NetworkMeasurement) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Dominant Download
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down")
                        .font(.caption2.weight(.semibold))
                    Text(LinkaCopy.value("detail.download").uppercased())
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.downloadMbps.map { localizedNumber($0, fractionDigits: 1) } ?? "—")
                        .font(.system(size: 45, weight: .heavy, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("Mbps")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.textSecondary)
                }

                Text(LinkaCopy.value("detail.downloadSpeed", defaultValue: "Velocidade de recebimento"))
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.horizontal, 16)

            // Upload
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up")
                        .font(.caption2.weight(.semibold))
                    Text(LinkaCopy.value("detail.upload").uppercased())
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.uploadMbps.map { localizedNumber($0, fractionDigits: 1) } ?? "—")
                        .font(.system(size: 33, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("Mbps")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.textSecondary)
                }

                Text(LinkaCopy.value("detail.uploadSpeed", defaultValue: "Velocidade de envio"))
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.horizontal, 16)

            // Latency
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption2.weight(.semibold))
                    Text(LinkaCopy.value("detail.ping").uppercased())
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.latencyMs.map { localizedNumber($0, fractionDigits: 0) } ?? "—")
                        .font(.system(size: 33, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("ms")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.textSecondary)
                }

                Text(LinkaCopy.value("detail.pingSubtitle", defaultValue: "Resposta da conexão"))
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    private func practicalUsageCards(for measurement: NetworkMeasurement) -> some View {
        let report = UsageSuitabilityEvaluator().evaluate(measurement)
        return HStack(spacing: 12) {
            usageCard(
                icon: "video.fill",
                title: LinkaCopy.value("mac.result.usage.videoCall"),
                subtitle: practicalUsageSubtitle(for: .videoCall, in: report),
                isGood: report.verdict(for: .videoCall)?.level == .adequate,
                kind: LinkaCopy.value("mac.result.usage.videoCall")
            )
            usageCard(
                icon: "play.tv.fill",
                title: LinkaCopy.value("mac.result.usage.streaming4k"),
                subtitle: practicalUsageSubtitle(for: .streaming4K, in: report),
                isGood: report.verdict(for: .streaming4K)?.level == .adequate,
                kind: LinkaCopy.value("mac.result.usage.streaming4k")
            )
            usageCard(
                icon: "gamecontroller.fill",
                title: LinkaCopy.value("mac.result.usage.gaming"),
                subtitle: practicalUsageSubtitle(for: .onlineGaming, in: report),
                isGood: report.verdict(for: .onlineGaming)?.level == .adequate,
                kind: LinkaCopy.value("mac.result.usage.gaming")
            )
        }
    }

    private func practicalUsageSubtitle(for usage: UsageCase, in report: UsageSuitabilityReport) -> String {
        let verdict = report.verdict(for: usage)
        if verdict?.level == .adequate {
            return LinkaCopy.value("mac.result.usage.goodCondition")
        } else if verdict?.level == .limited {
            return LinkaCopy.value("mac.result.usage.reviewStability")
        } else {
            return LinkaCopy.value("mac.result.usage.understandResult")
        }
    }

    private func usageCard(icon: String, title: String, subtitle: String, isGood: Bool, kind: String) -> some View {
        Button {
            selectedUsageModalKind = kind
            showUsageExplanationModal = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isGood ? .statusGood : .brandAccentWarm)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodySmallStrong)
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(isGood ? .statusGood : .brandAccentWarm)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private func assistInsightCard(for m: NetworkMeasurement) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.brandAccentWarm.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundColor(.brandAccentWarm)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(LinkaCopy.value("mac.result.practicalExperience"))
                    .font(.bodySmallStrong)
                    .foregroundColor(.textPrimary)

                Text(LinkaCopy.value("mac.result.practicalExperience.desc"))
                    .font(.captionSmall)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    requestAssist(from: .result(m))
                } label: {
                    HStack(spacing: 4) {
                        Text(LinkaCopy.value("mac.result.understandConnection"))
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                    }
                    .font(.captionSmallStrong)
                    .foregroundColor(.brandAccentWarm)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }

    private var usageExplanationSheet: some View {
        let kind = selectedUsageModalKind ?? ""
        let iconName: String = {
            if kind.contains("Video") || kind.contains("video") { return "video.fill" }
            if kind.contains("Stream") || kind.contains("stream") { return "play.tv.fill" }
            return "gamecontroller.fill"
        }()
        let explanationText: String = {
            if kind.contains("Video") || kind.contains("video") {
                return LinkaCopy.value("mac.usage.sheet.videoCall.desc")
            }
            if kind.contains("Stream") || kind.contains("stream") {
                return LinkaCopy.value("mac.usage.sheet.streaming4k.desc")
            }
            return LinkaCopy.value("mac.usage.sheet.gaming.desc")
        }()

        return NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.brandAccentWarm.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: iconName)
                            .font(.system(size: 20))
                            .foregroundColor(.brandAccentWarm)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text(LinkaCopy.value("mac.usage.sheet.question"))
                            .font(.captionMedium)
                            .foregroundColor(.textSecondary)
                    }
                }

                Text(explanationText)
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LinkaCopy.value("mac.usage.sheet.disclaimer"))
                    .font(.caption2)
                    .foregroundColor(.textSecondary.opacity(0.8))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfacePage, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer()

                HStack {
                    Button(LinkaCopy.value("common.ok")) {
                        showUsageExplanationModal = false
                    }
                    .buttonStyle(.macSecondary)

                    Spacer()

                    Button {
                        showUsageExplanationModal = false
                        if let m = activeMeasurement {
                            requestAssist(from: .result(m))
                        } else {
                            requestAssist(from: .fresh)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text(LinkaCopy.value("mac.usage.sheet.investigate"))
                        }
                    }
                    .buttonStyle(.macPrimary)
                }
            }
            .padding(24)
            .frame(minWidth: 460, minHeight: 280)
        }
    }

    // MARK: - Sua rede agora (Bloco Temático de Telemetria e Hardware)
    
    private var macContextFooter: some View {
        DisclosureGroup(isExpanded: $showLiveNetworkDetails) {
            VStack(alignment: .leading, spacing: 14) {
            // Sinais Físicos em Tempo Real (Hardware e Rádio)
            HStack(spacing: 10) {
                if viewModel.liveConnectionKind == .wifi {
                    if let ctx = viewModel.liveWiFiContext {
                        liveMetricCard(
                            title: LinkaCopy.value("mac.live.linkPHY"),
                            value: ctx.linkSpeedMbps.map { "\(Int($0)) Mbps" } ?? "—",
                            icon: "speedometer",
                            statusColor: .brandAccentWarm
                        )
                    }
                    
                    liveMetricCard(
                        title: LinkaCopy.value("detail.wifi.signal"),
                        value: wifiSignalTechnicalValue,
                        icon: "wifi",
                        statusColor: liveWifiColor
                    )

                    liveMetricCard(
                        title: LinkaCopy.value("network.wifiBand"),
                        value: confirmedWiFiBandDisplay,
                        icon: "antenna.radiowaves.left.and.right",
                        statusColor: .textSecondary
                    )
                } else if viewModel.liveConnectionKind == .ethernet {
                    liveMetricCard(
                        title: LinkaCopy.value("network.connection"),
                        value: LinkaCopy.value("network.ethernet"),
                        icon: "cable.connector",
                        statusColor: .statusGood
                    )
                    liveMetricCard(
                        title: LinkaCopy.value("mac.live.status"),
                        value: LinkaCopy.value("mac.live.connected"),
                        icon: "checkmark.circle.fill",
                        statusColor: .statusGood
                    )
                } else if viewModel.liveConnectionKind == .cellular {
                    liveMetricCard(
                        title: LinkaCopy.value("network.connection"),
                        value: LinkaCopy.value("network.cellular"),
                        icon: "antenna.radiowaves.left.and.right",
                        statusColor: .brandAccentWarm
                    )
                    liveMetricCard(
                        title: LinkaCopy.value("mac.live.status"),
                        value: LinkaCopy.value("mac.live.connected"),
                        icon: "checkmark.circle.fill",
                        statusColor: .statusGood
                    )
                } else {
                    liveMetricCard(
                        title: LinkaCopy.value("mac.live.interface"),
                        value: liveConnectionName,
                        icon: "network",
                        statusColor: .textSecondary
                    )
                    liveMetricCard(
                        title: LinkaCopy.value("mac.live.status"),
                        value: LinkaCopy.value("mac.live.active"),
                        icon: "checkmark.circle.fill",
                        statusColor: .statusGood
                    )
                }
            }

            // Metadados Físicos Complementares de Wi-Fi
            if viewModel.liveConnectionKind == .wifi, let ctx = viewModel.liveWiFiContext {
                HStack(spacing: 16) {
                    wifiDetail(label: "SSID", value: ctx.ssid ?? LinkaCopy.value("common.unavailable"))
                    if let std = viewModel.advancedWiFiDiagnostics?.wifiStandard {
                        wifiDetail(label: LinkaCopy.value("detail.wifi.standard"), value: std)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }

            }
        } label: {
            Label(LinkaCopy.value("home.live.metrics"), systemImage: "wifi")
                .font(.captionSmallStrong)
                .foregroundColor(.textPrimary)
        }
        .padding(16)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }
    
    private func liveMetricCard(title: String, value: String, icon: String? = nil, statusColor: Color) -> some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(statusColor)
                    .frame(width: 18)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .frame(width: 14)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color.surfacePage, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
    
    private var liveLatencyColor: Color {
        guard let latency = viewModel.liveDnsLatencyMs else { return .textSecondary }
        if latency <= 40 { return .statusGood }
        if latency <= 100 { return .statusAttention }
        return .statusCritical
    }
    
    private var liveStabilityColor: Color {
        guard let loss = viewModel.livePacketLossPercent else { return .textSecondary }
        if loss < 1.0 { return .statusGood }
        if loss < 5.0 { return .statusAttention }
        return .statusCritical
    }
    
    private var liveWifiColor: Color {
        guard let rssi = viewModel.liveWifiRSSI else { return .textSecondary }
        if rssi >= -60 { return .statusGood }
        if rssi >= -75 { return .statusAttention }
        return .statusCritical
    }
    
    private var wifiSignalLabel: String {
        guard let rssi = viewModel.liveWifiRSSI else { return "—" }
        if rssi >= -60 { return LinkaCopy.value("mac.live.signal.strong") }
        if rssi >= -75 { return LinkaCopy.value("mac.live.signal.medium") }
        return LinkaCopy.value("mac.live.signal.weak")
    }

    private var wifiSignalTechnicalValue: String {
        guard let rssi = viewModel.liveWifiRSSI else { return "—" }
        return "\(Int(rssi)) dBm"
    }

    /// Banda confirmada pelo rádio Wi-Fi do Mac. Não usa SSID, nem dados
    /// opcionais importados de Diagnóstico Wi-Fi Avançado, para não inferir
    /// nem combinar fontes de verdade distintas.
    private var confirmedWiFiBandDisplay: String {
        switch ApplePlatformSignalProvider.currentWifiBandGHz() {
        case 2.4: return LinkaCopy.value("network.wifiBand.value2_4GHz")
        case 5.0: return LinkaCopy.value("network.wifiBand.value5GHz")
        case 6.0: return LinkaCopy.value("network.wifiBand.value6GHz")
        default: return LinkaCopy.value("common.unavailable")
        }
    }

    private func wifiDetail(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(.captionMedium)
                .foregroundColor(.textSecondary)
            Text(value)
                .font(.captionSmallStrong)
                .foregroundColor(.textPrimary)
        }
    }

    // MARK: Phase Dots

    private var phaseDots: some View {
        HStack(spacing: 28) {
            phaseDot(label: LinkaCopy.value("detail.ping"), state: pingDotState)
            phaseDot(label: LinkaCopy.value("detail.download"), state: downloadDotState)
            phaseDot(label: LinkaCopy.value("detail.upload"), state: uploadDotState)
        }
    }

    private func phaseDot(label: String, state: DotPhase) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(dotFill(state))
                    .frame(width: 22, height: 22)
                Circle()
                    .strokeBorder(dotBorder(state), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.brandOnSurface)
                }
            }
            Text(label)
                .font(.system(size: 12, weight: state == .active ? .semibold : .medium))
                .foregroundColor(state == .active ? .textPrimary : .textSecondary)
        }
    }

    private func dotFill(_ state: DotPhase) -> Color {
        switch state {
        case .pending: return .clear
        case .active:  return .brandAccentWarm
        case .done:    return .brandSurface
        }
    }

    private func dotBorder(_ state: DotPhase) -> Color {
        switch state {
        case .pending: return .borderDefault
        case .active:  return .brandAccentWarm
        case .done:    return .brandSurface
        }
    }

    private var pingDotState: DotPhase {
        switch viewModel.uiPhase {
        case .connecting: return .active
        case .downloading, .uploading, .done: return .done
        default: return .pending
        }
    }

    private var downloadDotState: DotPhase {
        switch viewModel.uiPhase {
        case .downloading: return .active
        case .uploading, .done: return .done
        default: return .pending
        }
    }

    private var uploadDotState: DotPhase {
        switch viewModel.uiPhase {
        case .uploading: return .active
        case .done: return .done
        default: return .pending
        }
    }

    // MARK: Status pill

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 6, height: 6)
            Text(phaseMessage)
                .font(.captionSmallStrong)
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.surfaceCard, in: Capsule())
    }

    private var statusDotColor: Color {
        if isMeasuring {
            return .brandAccentWarm
        }
        if let _ = activeMeasurement {
            return .statusGood
        }
        switch viewModel.uiPhase {
        case .connecting, .downloading, .uploading: return .brandAccentWarm
        case .done: return .statusGood
        case .error: return .statusCritical
        case .connectionChanged: return .statusAttention
        case .idle: return .textSecondary
        }
    }

    // MARK: Footer stat blocks

    private func footerStatBlock(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.captionMedium)
                .foregroundColor(.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                Text(unit)
                    .font(.captionSmallStrong)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private var pingFooterValue: String {
        viewModel.hasMeasuredPing ? "\(viewModel.ping)" : "—"
    }
    private var downloadFooterValue: String {
        viewModel.downloadSpeed > 0 ? localizedNumber(viewModel.downloadSpeed, fractionDigits: 1) : "—"
    }
    private var uploadFooterValue: String {
        viewModel.hasMeasuredUpload ? localizedNumber(viewModel.uploadSpeed, fractionDigits: 1) : "—"
    }

    // MARK: - Action Row

    private var actionRow: some View {
        if isMeasuring {
            return AnyView(
                Button(LinkaCopy.value("common.cancel")) { viewModel.skipOrCancel() }
                    .buttonStyle(.macSecondary)
                    .keyboardShortcut(".", modifiers: .command)
            )
        }

        if activeMeasurement != nil {
            return AnyView(
                Button(LinkaCopy.value("common.testAgain")) { startMeasurement() }
                    .buttonStyle(.macPrimary)
                    .frame(maxWidth: 280)
                    .keyboardShortcut("r", modifiers: .command)
            )
        }

        switch viewModel.uiPhase {
        case .idle:
            return AnyView(
                Button(LinkaCopy.value("home.testSpeed")) { startMeasurement() }
                    .buttonStyle(.macPrimary)
                    .frame(maxWidth: 280)
                    .keyboardShortcut("r", modifiers: .command)
            )
        case .connecting, .downloading, .uploading, .done:
            return AnyView(
                Button(LinkaCopy.value("home.testSpeed")) { startMeasurement() }
                    .buttonStyle(.macPrimary)
                    .frame(maxWidth: 280)
                    .keyboardShortcut("r", modifiers: .command)
            )
        case .error:
            return AnyView(
                HStack(spacing: 10) {
                    Button(LinkaCopy.value("common.tryAgain")) { startMeasurement() }
                        .buttonStyle(.macPrimary)
                        .frame(maxWidth: 280)
                        .keyboardShortcut("r", modifiers: .command)
                    Button(LinkaCopy.value("home.checkConnection")) { showConnectivityTriage = true }
                        .buttonStyle(.macSecondary)
                }
            )
        case .connectionChanged:
            return AnyView(
                Button(LinkaCopy.value("home.connectionChanged.cta")) { startMeasurement() }
                    .buttonStyle(.macPrimary)
                    .frame(maxWidth: 280)
                    .keyboardShortcut("r", modifiers: .command)
            )
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header da conexão
                HStack {
                    Text("Conexão atual")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Image(systemName: "wifi")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                }

                // Cartão "Este Mac"
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.surfacePage)
                            .frame(width: 42, height: 42)
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 20))
                            .foregroundColor(.textPrimary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Este Mac")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(liveConnectionName)
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                }

                Divider()

                // Pares de telemetria da conexão
                VStack(spacing: 8) {
                    inspectPair(label: "Rede", value: liveConnectionName)
                    inspectPair(label: "Interface", value: "Wi-Fi · en0")
                    if let band = viewModel.wifiBandGHz {
                        inspectPair(label: "Banda", value: "\(localizedNumber(band, fractionDigits: band == floor(band) ? 0 : 1)) GHz")
                    } else {
                        inspectPair(label: "Banda", value: "5 GHz")
                    }
                    if let rssi = viewModel.liveWifiRSSI {
                        inspectPair(label: "Sinal recebido", value: "\(Int(rssi)) dBm")
                    }
                    inspectPair(label: "Gateway", value: "192.168.1.1")
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Plano informado")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                    Text("500 Mbps de download")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Button {
                        destination = .settings
                    } label: {
                        HStack(spacing: 4) {
                            Text("Editar plano")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.brandAccentWarm)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }

                Divider()

                // Indicadores medidos (se houver medição ativa)
                VStack(alignment: .leading, spacing: 10) {
                    Text(LinkaCopy.value("mac.inspector.measured"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    qualityCard
                }

                Divider()

                // Privacidade
                HStack(spacing: 6) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.brandAccentWarm)
                    Text("Seus dados ficam com você")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textPrimary)
                }

                Text("Os testes são executados localmente no seu Mac. Nenhuma informação pessoal ou endereço de rede é compartilhado sem a sua ação explícita.")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)

                Button {
                    showCurrentMeasurementDetails = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Ver detalhes técnicos")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.brandAccentWarm)
                }
                .buttonStyle(.plain)

                if isFinalResult {
                    NetscopeResultEntryCard {
                        showNetscopeAnalysis = true
                    }
                }
            }
            .padding(20)
        }
        .background(Color.surfaceCard)
    }

    private func inspectPair(label: String, value: String) -> some View {
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

    private var qualityCard: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            qualityGridCell(label: LinkaCopy.value("assist.latency"), value: latencyQualityValue, icon: "clock")
            qualityGridCell(label: LinkaCopy.value("detail.jitter"), value: jitterQualityValue, icon: "waveform")
            qualityGridCell(label: LinkaCopy.value("detail.packetLoss"), value: lossQualityValue, icon: "exclamationmark.triangle")
        }
    }

    private func qualityGridCell(label: String, value: String, icon: String) -> some View {
        let isPlaceholder = value == "—"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .opacity(isPlaceholder ? 0.55 : 1.0)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
                .opacity(isPlaceholder ? 0.55 : 1.0)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfacePage, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var latencyQualityValue: String {
        guard let ms = activeMeasurement?.latencyMs else { return "—" }
        return "\(Int(round(ms))) ms"
    }
    private var jitterQualityValue: String {
        guard let ms = activeMeasurement?.jitterMs else { return "—" }
        return "\(localizedNumber(ms, fractionDigits: 1)) ms"
    }
    private var lossQualityValue: String {
        guard let loss = activeMeasurement?.packetLossPercent else { return "—" }
        return "\(localizedNumber(loss, fractionDigits: 1))%"
    }

    // MARK: - History View (full width)

    private var historyView: some View {
        HistoryView { measurement in
            selectedHistoricalMeasurement = measurement
        }
    }

    // MARK: - Settings View (full width, inline)

    private var settingsView: some View {
        SettingsView(
            onPurchaseRequest: { entryPoint in
                destination = .speedTest
                purchaseEntryPoint = entryPoint
                showPurchase = true
            },
            onSubscriptionManagementRequest: {
                destination = .speedTest
                showSubscriptionManagement = true
            }
        )
        .environmentObject(entitlements)
    }

    // MARK: - Assist Tool View (full width, inline)

    private var assistView: some View {
        assistToolContent
    }

    private var assistToolContent: some View {
        AssistProblemSelectionView(
            currentMeasurement: assistEntryPoint.measurement ?? activeMeasurement ?? viewModel.latestFinishedMeasurement,
            recentMeasurements: viewModel.recentMeasurements,
            onRetry: { startMeasurement() },
            onShowDetails: {
                if let m = assistEntryPoint.measurement ?? activeMeasurement ?? viewModel.latestFinishedMeasurement {
                    selectedHistoricalMeasurement = m
                }
            },
            onStartFreshMeasurement: { objective, subcategory, reportedProblem in
                pendingAssistObjective = objective
                pendingAssistSubcategory = subcategory
                pendingAssistReportedProblem = reportedProblem
                pendingAssistMeasurement = true
                destination = .speedTest
                startMeasurement()
            },
            entitlements: entitlements,
            isInline: true
        )
    }

    private var fallbackOptimizationMeasurement: NetworkMeasurement {
        NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 482.6,
            uploadMbps: 236.4,
            latencyMs: 12.7,
            jitterMs: 2.1,
            packetLossPercent: 0.0,
            connectionKind: .wifi,
            wifiBandGHz: 5.0,
            networkIdentifier: "Minha casa"
        )
    }

    private var macStatusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(statusBarStatusText)
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("Linka para macOS · Pronto para medição")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 20)
            .frame(height: 28)
            .background(Color.surfacePage)
        }
    }

    private var statusBarStatusText: String {
        if isMeasuring {
            return "Medição em andamento… você pode navegar pelo app"
        }
        if activeMeasurement != nil {
            return "Medição concluída · Salvo no histórico"
        }
        return "Pronto para medição"
    }

    private var assistUpgradeView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.brandAccentWarm.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.brandAccentWarm)
            }

            VStack(spacing: 8) {
                Text(LinkaCopy.value("assist.title"))
                    .font(.displayLarge)
                    .foregroundColor(.textPrimary)
                Text(LinkaCopy.value("mac.assist.upgrade.subtitle"))
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(alignment: .leading, spacing: 14) {
                assistBenefitRow(icon: "sparkles", text: LinkaCopy.value("mac.assist.upgrade.benefit.guided"))
                assistBenefitRow(icon: "chart.line.uptrend.xyaxis", text: LinkaCopy.value("mac.assist.upgrade.benefit.hypotheses"))
                assistBenefitRow(icon: "wrench.and.screwdriver", text: LinkaCopy.value("assist.plus.benefit.investigate"))
                assistBenefitRow(icon: "waveform.path.ecg", text: LinkaCopy.value("mac.assist.upgrade.benefit.history"))
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(.vertical, 8)

            Button(LinkaCopy.value("settings.subscription.learnPlus")) {
                purchaseEntryPoint = .assist
                showPurchase = true
            }
            .buttonStyle(.linkaPrimary)
            .frame(maxWidth: 280)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func assistBenefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.brandAccentWarm)
                .frame(width: 24)
            Text(text)
                .font(.bodyRegular)
                .foregroundColor(.textPrimary)
        }
    }

    // MARK: - Assist

    private func requestAssist(from entryPoint: MacAssistEntryPoint) {
        assistEntryPoint = entryPoint
        if isPlusActive { destination = .assist }
        else { purchaseEntryPoint = .assist; showPurchase = true }
    }

    private func requestAssistFromResult() {
        guard let m = currentMeasurement else { return }
        requestAssist(from: .result(m))
    }

    private func startMeasurementFromHistory() {
        selectedHistoricalMeasurement = nil
        destination = .speedTest
        DispatchQueue.main.async { startMeasurement() }
    }

    private func startMeasurementFromGlobalAction() {
        guard !isMeasuring else { return }
        destination = MacNavigationPolicy.measurementDestination
        DispatchQueue.main.async { startMeasurement() }
    }

    private func startMeasurement() {
        guard !isMeasuring else { return }
        inspectedHistoricalMeasurement = nil
        let diagnostics = canStartAdvancedWiFiMeasurement
            ? MacAdvancedWiFiDiagnosticsProvider().capture(entitlement: entitlements.snapshot)
            : nil
        viewModel.startTest(advancedWiFiDiagnostics: diagnostics)
    }

    // MARK: - DNS View

    private var dnsView: some View {
        DNSBenchmarkView {
            destination = .speedTest
            startMeasurement()
        }
    }

    private var optimizationView: some View {
        let baseline = currentMeasurement ?? viewModel.latestFinishedMeasurement ?? viewModel.recentMeasurements.first ?? fallbackOptimizationMeasurement
        return OptimizationView(
            baseline: baseline,
            history: viewModel.recentMeasurements,
            isPlusActive: canUseOptimization,
            onRequestPurchase: {
                purchaseEntryPoint = .optimization
                showPurchase = true
            },
            onRetest: {
                optimizationBaseline = baseline
                destination = .speedTest
                startMeasurement()
            },
            onManageIdentification: { destination = .settings }
        )
    }

    private func handleOptimizationRetestCompletion(_ phase: SpeedTestUIPhase) {
        guard let baseline = optimizationBaseline else { return }

        switch phase {
        case .done:
            guard let retest = currentMeasurement else {
                optimizationBaseline = nil
                return
            }
            optimizationBaseline = nil
            optimizationComparisonPair = [baseline, retest]
            optimizationRetestResult = OptimizationRetestComparator.compare(baseline: baseline, retest: retest)
            showOptimizationComparisonSheet = true
        case .idle, .error, .connectionChanged:
            optimizationBaseline = nil
        case .connecting, .downloading, .uploading:
            break
        }
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
        case .assistProblemSelection: showAssistProblemSelection = true
        case .subscriptionManagement: showSubscriptionManagement = true
        }
    }

    private func handleOpenHistoryRequest(_ pending: Bool) {
        guard pending else { return }
        guard !isMeasuring else { intentCoordinator.consumeOpenHistory(); return }
        destination = .history
        intentCoordinator.consumeOpenHistory()
    }

    private func handleOpenLatestMeasurementRequest(_ pending: Bool) {
        guard pending else { return }
        defer { intentCoordinator.consumeOpenLatestMeasurement() }
        guard !isMeasuring else { return }
        guard isPlusActive else { purchaseEntryPoint = .shortcut; showPurchase = true; return }
        guard let latest = latestMeasurementForIntent else { return }
        selectedHistoricalMeasurement = latest
    }

    private func beginPendingAssistCollection() {
        guard pendingAssistMeasurement, !showAssistResult else { return }
        showAssistResult = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard pendingAssistMeasurement else { return }
            viewModel.startTest()
        }
    }

    // MARK: - Formatação

    /// Cache por tag de idioma: evita reconstruir o `DateFormatter` (caro)
    /// a cada acesso — `phaseMessage` é reavaliado a cada atualização da
    /// view durante uma medição — mas ainda assim reflete a preferência de
    /// idioma corrente em vez de ficar fixo em `pt_BR` como antes.
    private static var dateFormatterCache: [String: DateFormatter] = [:]

    private static var dateFormatter: DateFormatter {
        let locale = LinkaLanguagePreference.currentLocale
        let key = locale.identifier
        if let cached = dateFormatterCache[key] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "d MMM · HH:mm"
        dateFormatterCache[key] = f
        return f
    }

    private func networkLabel(for m: NetworkMeasurement) -> String {
        switch m.connectionKind {
        case .wifi:     return m.wifiContext?.ssid ?? LinkaCopy.value("network.wifi")
        case .cellular: return LinkaCopy.value("network.cellular")
        case .ethernet: return LinkaCopy.value("network.ethernet")
        default:        return LinkaCopy.value("network.connection")
        }
    }

    private var liveConnectionName: String {
        viewModel.liveNetworkLabel.isEmpty ? LinkaCopy.value("home.currentConnection") : viewModel.liveNetworkLabel
    }

    // MARK: - Gauge helpers

    private var gaugeFraction: Double {
        guard let value = downloadGaugeValue else { return 0 }
        let scale = max(speedGaugeUpperBound, Self.speedGaugeScale(for: value))
        return max(0, min(1, value / scale))
    }

    private var downloadGaugeValue: Double? {
        switch viewModel.uiPhase {
        case .downloading, .uploading, .done: return viewModel.downloadSpeed
        default: return nil
        }
    }

    private var macRingValue: String {
        guard downloadGaugeValue != nil else { return "" }
        return localizedNumber(viewModel.downloadSpeed, fractionDigits: 2)
    }

    private var macRingUnit: String? {
        downloadGaugeValue != nil ? "Mbps" : nil
    }

    private var gaugeAccessibilityValue: String {
        switch viewModel.uiPhase {
        case .idle: return LinkaCopy.value("mac.gauge.idle")
        case .connecting: return LinkaCopy.value("mac.gauge.connecting")
        case .downloading:
            return macFormattedCopy("mac.gauge.downloading", String(Int(round(viewModel.downloadSpeed))))
        case .uploading:
            return macFormattedCopy("mac.gauge.uploading", String(Int(round(viewModel.downloadSpeed))))
        case .done:
            return macFormattedCopy("mac.gauge.done", String(Int(round(viewModel.downloadSpeed))))
        case .error: return LinkaCopy.value("mac.gauge.error")
        case .connectionChanged: return LinkaCopy.value("mac.gauge.connectionChanged")
        }
    }

    private static var timeFormatterCache: [String: DateFormatter] = [:]

    private static var timeFormatter: DateFormatter {
        let locale = LinkaLanguagePreference.currentLocale
        let key = locale.identifier
        if let cached = timeFormatterCache[key] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "HH:mm"
        timeFormatterCache[key] = f
        return f
    }

    private var phaseMessage: String {
        switch viewModel.uiPhase {
        case .connecting:       return LinkaCopy.value("home.phase.connecting")
        case .downloading:      return LinkaCopy.value("home.phase.downloading")
        case .uploading:        return LinkaCopy.value("home.phase.uploading")
        case .done:
            if let m = viewModel.latestFinishedMeasurement {
                return macFormattedCopy("mac.phase.lastAt", Self.timeFormatter.string(from: m.measuredAt))
            }
            return LinkaCopy.value("mac.result.complete")
        case .error:
            return viewModel.failureReason == .offline ? LinkaCopy.value("network.offline") : LinkaCopy.value("home.error.generic.title")
        case .connectionChanged: return LinkaCopy.value("home.connectionChanged.message")
        case .idle:
            if let m = inspectedHistoricalMeasurement {
                return macFormattedCopy("mac.phase.measurementAt", Self.dateFormatter.string(from: m.measuredAt))
            }
            return LinkaCopy.value("mac.gauge.idle")
        }
    }

    private func macFormattedCopy(_ key: String, _ value: String) -> String {
        String(format: LinkaCopy.value(key), locale: LinkaLanguagePreference.currentLocale, value)
    }

    private func localizedNumber(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .locale(LinkaLanguagePreference.currentLocale)
        )
    }

    private static func speedGaugeScale(for value: Double) -> Double {
        guard value > 0 else { return 1 }
        let mag = pow(10, floor(log10(value)))
        for m in [1.0, 2.0, 5.0, 10.0] {
            let c = m * mag; if value <= c { return c }
        }
        return 10 * mag
    }
}


// MARK: - MacSpeedCurveChartView (1:1 with Prototype graph(tab, r))

private enum MacCurveTab: String, CaseIterable {
    case download
    case upload
    case latency

    var label: String {
        switch self {
        case .download: return LinkaCopy.value("detail.download")
        case .upload: return LinkaCopy.value("detail.upload")
        case .latency: return LinkaCopy.value("detail.ping")
        }
    }

    var unit: String {
        switch self {
        case .download, .upload: return "Mbps"
        case .latency: return "ms"
        }
    }
}

private struct MacSpeedCurveChartView: View {
    let measurement: NetworkMeasurement
    @State private var selectedTab: MacCurveTab = .download

    private var averageValue: Double {
        switch selectedTab {
        case .download: return measurement.downloadMbps ?? 350.0
        case .upload: return measurement.uploadMbps ?? 120.0
        case .latency: return measurement.latencyMs ?? 18.0
        }
    }

    private var maxScale: Double {
        switch selectedTab {
        case .latency: return 50.0
        case .upload: return max(300.0, averageValue * 1.25)
        case .download: return max(600.0, averageValue * 1.25)
        }
    }

    private var seriesColor: Color {
        switch selectedTab {
        case .download: return .brandAccentWarm
        case .upload: return Color(red: 0.33, green: 0.47, blue: 0.58)
        case .latency: return .statusGood
        }
    }

    private var jitterString: String {
        guard let j = measurement.jitterMs else { return "—" }
        return "\(Int(round(j)))"
    }

    private var lossString: String {
        guard let l = measurement.packetLossPercent else { return "0" }
        return l == 0 ? "0" : String(format: "%.1f", locale: LinkaLanguagePreference.currentLocale, l)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text(LinkaCopy.value("mac.result.curve.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Spacer()

                Picker("", selection: $selectedTab) {
                    ForEach(MacCurveTab.allCases, id: \.self) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
            }

            // Curve Graph
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let xStart: CGFloat = 36
                let xEnd = w - 12
                let yTop: CGFloat = 16
                let yBottom = h - 24

                let pts: [CGPoint] = (0..<41).map { i in
                    let progress = CGFloat(i) / 40.0
                    var v = max(0.0, averageValue * (0.95 + sin(Double(i) * 1.8) * 0.035 + cos(Double(i) * 0.8) * 0.025))
                    if i < 5 && selectedTab != .latency {
                        v *= (0.48 + Double(i) * 0.105)
                    }
                    let ratio = CGFloat(min(1.0, max(0.0, v / maxScale)))
                    let x = xStart + progress * (xEnd - xStart)
                    let y = yBottom - ratio * (yBottom - yTop)
                    return CGPoint(x: x, y: y)
                }

                ZStack(alignment: .topLeading) {
                    // Dashed Grid Lines & Left Axis Labels
                    ForEach(0..<3) { idx in
                        let y = yTop + CGFloat(idx) * ((yBottom - yTop) / 2.0)
                        let val = Int(round(maxScale - Double(idx) * (maxScale / 2.0)))

                        Text("\(val)")
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary.opacity(0.8))
                            .frame(width: 28, alignment: .trailing)
                            .position(x: 16, y: y)

                        Path { path in
                            path.move(to: CGPoint(x: xStart, y: y))
                            path.addLine(to: CGPoint(x: xEnd, y: y))
                        }
                        .stroke(Color.borderDefault.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }

                    // Area Fill
                    if let firstPt = pts.first, let lastPt = pts.last {
                        Path { path in
                            path.move(to: CGPoint(x: firstPt.x, y: yBottom))
                            path.addLine(to: firstPt)
                            for pt in pts.dropFirst() {
                                path.addLine(to: pt)
                            }
                            path.addLine(to: CGPoint(x: lastPt.x, y: yBottom))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [seriesColor.opacity(0.20), seriesColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    // Curve Line
                    if let firstPt = pts.first {
                        Path { path in
                            path.move(to: firstPt)
                            for pt in pts.dropFirst() {
                                path.addLine(to: pt)
                            }
                        }
                        .stroke(seriesColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    }

                    // Terminal Point Dot
                    if let lastPt = pts.last {
                        Circle()
                            .fill(seriesColor)
                            .frame(width: 7, height: 7)
                            .position(lastPt)
                    }

                    // X-Axis Labels (0 s, 10 s, 20 s, 30 s)
                    ForEach(0..<4) { idx in
                        let progress = CGFloat(idx) / 3.0
                        let x = xStart + progress * (xEnd - xStart)
                        Text("\(idx * 10) s")
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary.opacity(0.8))
                            .position(x: x, y: h - 8)
                    }
                }
            }
            .frame(height: 136)

            // Footer
            HStack {
                Text(String(format: LinkaCopy.value("mac.result.curve.illustrative"), selectedTab.unit))
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)

                Spacer()

                Text(String(
                    format: LinkaCopy.value("mac.result.curve.jitterLoss"),
                    jitterString,
                    lossString
                ))
                .font(.system(size: 10))
                .foregroundColor(.textSecondary)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
        )
    }
}

#endif
