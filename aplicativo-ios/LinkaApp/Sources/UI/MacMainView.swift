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

private enum DotPhase { case pending, active, done }

private extension MacDestination {
    var accessibilityIdentifier: String {
        switch self {
        case .speedTest: return "speedTest"
        case .history: return "history"
        case .myNetwork: return "myNetwork"
        case .assist: return "assist"
        case .optimization: return "optimization"
        case .settings: return "settings"
        }
    }

    var title: String {
        switch self {
        case .speedTest: return LinkaCopy.value("mac.destination.speedTest")
        case .history: return LinkaCopy.value("mac.destination.history")
        case .myNetwork: return LinkaCopy.value("inventory.title")
        case .assist: return LinkaCopy.value("assist.title")
        case .optimization: return LinkaCopy.value("optimization.title")
        case .settings: return LinkaCopy.value("settings.title")
        }
    }

    var systemImage: String {
        switch self {
        case .speedTest: return "gauge.medium"
        case .history: return "chart.bar"
        case .myNetwork: return "wifi.router"
        case .assist: return "sparkles"
        case .optimization: return "slider.horizontal.3"
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
            Section(LinkaCopy.value("mac.sidebar.measurement")) {
                destinationLink(.speedTest)
                destinationLink(.history, isDisabled: !MacNavigationPolicy.isAvailable(.history, isMeasuring: isMeasuring, hasMeasurement: currentMeasurement != nil, minhaRedeEnabled: MinhaRedeAvailability.isEnabled))
            }

            if MinhaRedeAvailability.isEnabled {
                Section(LinkaCopy.value("inventory.title")) {
                    destinationLink(.myNetwork, isDisabled: !MacNavigationPolicy.isAvailable(.myNetwork, isMeasuring: isMeasuring, hasMeasurement: currentMeasurement != nil, minhaRedeEnabled: MinhaRedeAvailability.isEnabled))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, alignment: .leading) {
            Image("wordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 98, height: 30)
                .accessibilityLabel("Linka")
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
        }
    }

    private func destinationLink(_ destination: MacDestination, isDisabled: Bool = false) -> some View {
        NavigationLink(value: destination) {
            Label(destination.title, systemImage: destination.systemImage)
        }
        .disabled(isDisabled)
        .accessibilityIdentifier("mac.sidebar.\(destination.accessibilityIdentifier)")
    }

    @ViewBuilder
    private var destinationContent: some View {
        Group {
            switch destination {
            case .speedTest:
                speedTestWorkspace
            case .myNetwork:
                MyNetworkView()
                    .environmentObject(entitlements)
            case .history:
                historyView
            case .assist:
                assistView
            case .optimization:
                optimizationView
            case .settings:
                settingsView
            }
        }
        .navigationTitle(destination.title)
        .accessibilityIdentifier("mac.workspace.\(destination.accessibilityIdentifier)")
        .background(
            LinkaScreenBackground(
                variant: .gradientOnly,
                showWaves: false
            )
        )
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
                }

                Button {
                    destination = .settings
                } label: {
                    Label(LinkaCopy.value("settings.title"), systemImage: "gearshape")
                }
                .disabled(isMeasuring || destination == .settings)
                .accessibilityIdentifier("mac.toolbar.settings")
            }
        }
    }

    private var speedTestWorkspace: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                mainStage

                if MacHomeLayout.showsInspector(contentWidth: proxy.size.width, hasMeasurement: activeMeasurement != nil) {
                    Divider()
                    rightPanel
                        .frame(width: 320)
                }
            }
        }
    }

    // MARK: - Main Stage

    private var mainStage: some View {
        VStack(spacing: 0) {
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
                .padding(.top, 36)

                Spacer()

                if isMeasuring {
                    // Estado: Medição em andamento
                    VStack(spacing: 20) {
                        horizontalHero
                        phaseDots
                            .padding(.top, 8)
                    }
                    .padding(.bottom, 28)
                } else if let m = activeMeasurement {
                    // Estado: Resultado Ativo (Recém medido ou selecionado do histórico)
                    VStack(spacing: 20) {
                        Text(LinkaCopy.value("mac.result.complete"))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        horizontalHero(for: m)
                        measurementMetadataLine(for: m)
                        DisclosureGroup(isExpanded: $showMeasurementDetails) {
                            advancedMetricsRow(for: m)
                                .padding(.top, 10)
                        } label: {
                            Label(LinkaCopy.value("detail.title"), systemImage: "chevron.down")
                                .font(.bodySmallMedium)
                                .foregroundColor(.textPrimary)
                        }
                        .padding(14)
                        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                                .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
                        )
                        .frame(maxWidth: 600)
                    }
                    .padding(.bottom, 24)
                } else {
                    // Estado: Idle Limpo (Pronto para medir)
                    cleanIdleCenterView
                        .padding(.bottom, 28)
                }

                Spacer()

                // Actions
                actionRow
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxHeight: .infinity)
            
            // "Sua rede agora" Footer + Wi-Fi Metadata
            macContextFooter
        }
    }

    private var cleanIdleCenterView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.surfaceCard)
                    .frame(width: 88, height: 88)
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 42, weight: .light))
                    .foregroundColor(.brandAccentWarm)
            }
            .padding(.bottom, 4)

            Text(LinkaCopy.value("mac.idle.title"))
                .font(.displayTitle)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity)
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
                value: m.downloadMbps.map { String(format: "%.1f", $0) } ?? "—",
                unit: "Mbps",
                isActive: false
            )
            heroBlock(
                label: LinkaCopy.value("detail.upload"),
                value: m.uploadMbps.map { String(format: "%.1f", $0) } ?? "—",
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
                miniDetailCell(label: LinkaCopy.value("detail.ping"), value: String(format: "%.0f", ping), unit: "ms")
                    .frame(maxWidth: .infinity)
            }
            if let jitter = measurement.jitterMs {
                miniDetailCell(label: LinkaCopy.value("detail.jitter"), value: String(format: "%.0f", jitter), unit: "ms")
                    .frame(maxWidth: .infinity)
            }
            if let loss = measurement.packetLossPercent {
                let formattedLoss = loss == 0 ? "0" : String(format: "%.1f", loss)
                miniDetailCell(label: LinkaCopy.value("detail.packetLoss"), value: formattedLoss, unit: "%")
                    .frame(maxWidth: .infinity)
            }
            if let dns = measurement.dnsResolutionMs {
                miniDetailCell(label: LinkaCopy.value("detail.dns"), value: String(format: "%.0f", dns), unit: "ms")
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
    
    private func usageSuitabilityRow(for measurement: NetworkMeasurement) -> some View {
        let report = UsageSuitabilityEvaluator().evaluate(measurement)
        return HStack(spacing: 16) {
            suitabilityBadge(for: .videoCall, in: report, icon: "video.fill", title: LinkaCopy.value("usage.case.videoCall.title"))
            suitabilityBadge(for: .streaming4K, in: report, icon: "play.tv.fill", title: LinkaCopy.value("usage.case.streaming4K.title"))
            suitabilityBadge(for: .onlineGaming, in: report, icon: "gamecontroller.fill", title: LinkaCopy.value("usage.case.onlineGaming.title"))
        }
    }

    private func suitabilityBadge(for usage: UsageCase, in report: UsageSuitabilityReport, icon: String, title: String) -> some View {
        let verdict = report.verdict(for: usage)
        let isAdequate = verdict?.level == .adequate
        let color: Color = isAdequate ? .statusGood : (verdict?.level == .limited ? .statusAttention : .textSecondary)
        
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(color)
            Text(title)
                .font(.captionMedium)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.surfaceCard, in: Capsule())
        .overlay(Capsule().stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6))
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
        viewModel.downloadSpeed > 0 ? String(format: "%.1f", viewModel.downloadSpeed) : "—"
    }
    private var uploadFooterValue: String {
        viewModel.hasMeasuredUpload ? String(format: "%.1f", viewModel.uploadSpeed) : "—"
    }

    // MARK: - Action Row

    private var actionRow: some View {
        if isMeasuring {
            return AnyView(
                Button(LinkaCopy.value("common.cancel")) { viewModel.skipOrCancel() }
                    .buttonStyle(.linkaSecondary)
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
                        .buttonStyle(.linkaSecondary)
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
            VStack(alignment: .leading, spacing: 28) {
                // O inspector é da medição selecionada. Histórico é um destino próprio,
                // para que contexto técnico não vire um dashboard concorrente da leitura.
                VStack(alignment: .leading, spacing: 14) {
                    Text(LinkaCopy.value("mac.inspector.measured"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)

                    qualityCard
                }

                if isFinalResult {
                    NetscopeResultEntryCard {
                        showNetscopeAnalysis = true
                    }
                }
            }
            .padding(24)
        }
        .background(Color.surfaceCard)
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
        return String(format: "%.1f ms", ms)
    }
    private var lossQualityValue: String {
        guard let loss = activeMeasurement?.packetLossPercent else { return "—" }
        return String(format: "%.1f%%", loss)
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
        Group {
            if isPlusActive {
                assistToolContent
            } else {
                assistUpgradeView
            }
        }
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

    private var optimizationView: some View {
        Group {
            if let measurement = currentMeasurement {
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
                    onManageIdentification: { destination = .settings }
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
            guard let retest = currentMeasurement else {
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
        return String(format: "%.2f", viewModel.downloadSpeed)
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

    private static func speedGaugeScale(for value: Double) -> Double {
        guard value > 0 else { return 1 }
        let mag = pow(10, floor(log10(value)))
        for m in [1.0, 2.0, 5.0, 10.0] {
            let c = m * mag; if value <= c { return c }
        }
        return 10 * mag
    }
}

// MARK: - MacPrimaryButtonStyle

private struct MacPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buttonLabel)
            .foregroundColor(.brandOnSurface)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.vertical, LinkaSpacing.sm)
            .padding(.horizontal, LinkaSpacing.md)
            .background(
                Color.brandSurface.opacity(isEnabled ? 1 : 0.42),
                in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.04 : 0.12), radius: 4, x: 0, y: 2)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private extension ButtonStyle where Self == MacPrimaryButtonStyle {
    static var macPrimary: MacPrimaryButtonStyle { MacPrimaryButtonStyle() }
}

#endif
