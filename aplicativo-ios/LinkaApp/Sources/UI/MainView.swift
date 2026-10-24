import SwiftUI
import LinkaEngine
import MeasurementHistory
import NetworkCore
import NetworkInsights
import LinkaEntitlements
import LinkaModules
import NetworkOptimization
import NetworkConnectivityTriage

enum AppRoute: Hashable {
    case settings
    case myNetwork
    case history
    case measurementDetail(NetworkMeasurement)
}

private enum LinkaPrimaryNavigationDestination: CaseIterable, Hashable, Identifiable {
    case speedTest
    case history
    case myNetwork
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .speedTest: return LinkaCopy.value("home.measure")
        case .history: return LinkaCopy.value("Histórico")
        case .myNetwork: return LinkaCopy.value("inventory.title")
        case .settings: return LinkaCopy.value("settings.title")
        }
    }

    var systemImage: String {
        switch self {
        case .speedTest: return "speedometer"
        case .history: return "clock"
        case .myNetwork: return "wifi.router"
        case .settings: return "slider.horizontal.3"
        }
    }
}

private struct LiveUsageDetailSheet: View {
    @ObservedObject var viewModel: SpeedTestViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let telemetry = viewModel.liveUsageReport?.telemetry ?? viewModel.liveTelemetryCollector.snapshot(
            connectionKind: viewModel.liveConnectionKind,
            interfaceLabel: viewModel.liveNetworkLabel,
            isExpensive: viewModel.liveConnectionKind == .cellular,
            wifiRssiDbm: viewModel.liveWifiRSSI
        )
        let confidence = viewModel.liveUsageReport?.verdict(for: .videoCall)?.confidence
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                LiveMetricsView(telemetry: telemetry)
                Divider()
                Text(LinkaCopy.format("home.live.samples", telemetry.sampleCount))
                    .font(.captionSmall)
                    .foregroundColor(.textSecondary)
                Text(confidenceCopy(confidence))
                    .font(.captionSmall)
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            .padding(24)
            .linkaStaticScreenBackground()
            .navigationTitle(LinkaCopy.value("home.live.details"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(LinkaCopy.value("common.close")) { dismiss() } } }
        }
        .presentationDetents([.height(260)])
    }

    private func confidenceCopy(_ confidence: LiveAssessmentConfidence?) -> String {
        switch confidence {
        case .historicalBaselineInferred: return LinkaCopy.value("usage.live.historicalBaseline")
        case .liveTelemetry: return LinkaCopy.value("home.live.confidence.live")
        case .insufficientData, .none: return LinkaCopy.value("home.live.confidence.insufficient")
        }
    }
}

private struct LiveMetricsView: View {
    let telemetry: LiveNetworkTelemetrySnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    metric(LinkaCopy.value("home.live.response"), value: telemetry.latencyMs, suffix: "ms")
                    Divider().opacity(0.35)
                    metric(LinkaCopy.value("home.live.variation"), value: telemetry.jitterMs, suffix: "ms")
                    Divider().opacity(0.35)
                    metric(LinkaCopy.value("home.live.loss"), value: telemetry.packetLossPercent, suffix: "%")
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 0) {
                    metric(LinkaCopy.value("home.live.response"), value: telemetry.latencyMs, suffix: "ms")
                    Divider().frame(height: 32).opacity(0.35)
                    metric(LinkaCopy.value("home.live.variation"), value: telemetry.jitterMs, suffix: "ms")
                    Divider().frame(height: 32).opacity(0.35)
                    metric(LinkaCopy.value("home.live.loss"), value: telemetry.packetLossPercent, suffix: "%")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metric(_ label: String, value: Double?, suffix: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label).font(.captionSmall).foregroundColor(.textSecondary)
            Text(value.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(suffix)" } ?? "—")
                .font(.bodyRegularStrong)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
    }
}

private enum AssistEntryPoint {
    case fresh
    case result(NetworkMeasurement)

    var measurement: NetworkMeasurement? {
        guard case .result(let measurement) = self else { return nil }
        return measurement
    }
}

struct MainView: View {
    private var mainTitle: String {
        viewModel.uiPhase == .done
            ? LinkaCopy.value("result.title")
            : LinkaCopy.value("home.measure")
    }

    @StateObject private var viewModel = SpeedTestViewModel()
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @EnvironmentObject private var ads: LinkaAdsCoordinator
    @ObservedObject private var intentCoordinator = AppIntentCoordinator.shared

    @State private var navPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var selectedTab: LinkaPrimaryNavigationDestination = .speedTest
    @State private var showPurchase: Bool = false
    @State private var showOptimization: Bool = false
    @State private var optimizationBaseline: NetworkMeasurement?
    @State private var optimizationRetestResult: OptimizationRetestComparison?
    @State private var showOptimizationRetestResult = false
    @State private var purchaseEntryPoint: PurchaseEntryPoint = .settings
    @State private var showAssistResult: Bool = false
    @State private var showNetscopeAnalysis: Bool = false
    @State private var assistEntryPoint: AssistEntryPoint = .fresh
    @State private var pendingAssistMeasurement = false
    @State private var pendingAdvancedWiFiMeasurement = false
    @State private var showAdvancedWiFiRecovery = false
    @State private var pendingAssistObjective: String?
    @State private var pendingAssistSubcategory: String?
    @State private var pendingAssistReportedProblem: String?
    @State private var showShareSheet: Bool = false
    @State private var showDetails: Bool = false
    @State private var showUsage: Bool = false
    @State private var showConnectionPath: Bool = false
    @State private var showConnectivityTriage: Bool = false
    @State private var showExpertModeMigrationBanner: Bool = false
    @State private var selectedLiveUsageCase: UsageCase?
    @State private var showLiveUsageDetail = false
    @Namespace private var animation

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Em .regular (iPad, agora sem limite de largura) os ícones e o anel
    /// de medição precisam de um degrau maior — sem isso, o conteúdo
    /// original (pensado pro iPhone) fica pequeno demais boiando numa tela
    /// grande, mesmo com o fundo preenchendo tudo.
    private var isPad: Bool { horizontalSizeClass == .regular }

    @AppStorage(LinkaWiFiPreferences.advancedConfiguredKey) private var advancedWiFiConfigured = false
    @AppStorage(LinkaWiFiPreferences.advancedDiagnosticsEnabledKey) private var advancedWiFiEnabled = true

    private var currentMeasurement: NetworkMeasurement? {
        guard viewModel.uiPhase == .done else { return nil }
        // A medição exibida, compartilhada e enviada ao Assist precisa ser a
        // mesma instância que o ViewModel acabou de persistir. Reconstruí-la
        // aqui gerava um UUID novo em cada redraw e fazia o Assist analisar a
        // mesma coleta mais de uma vez.
        return viewModel.latestFinishedMeasurement
    }

    /// O CTA do resultado trabalha estritamente com a amostra daquele
    /// resultado. Já o Assist iniciado pela Home (ou outra entrada fresca)
    /// não pode receber a última medição enquanto sua própria coleta ainda
    /// acontece — mesmo que a tela principal ainda esteja mostrando um
    /// resultado anterior por baixo do sheet.
    private var assistMeasurement: NetworkMeasurement? {
        switch assistEntryPoint {
        case .result(let measurement):
            return measurement
        case .fresh:
            return pendingAssistMeasurement ? nil : currentMeasurement
        }
    }

    private var latestMeasurementForIntent: NetworkMeasurement? {
        viewModel.latestFinishedMeasurement ?? viewModel.recentMeasurements.first
    }

    private var isPlusActive: Bool {
        LinkaEntitlementPolicy.decision(
            for: .assist,
            snapshot: entitlements.snapshot,
            at: Date()
        ).isGranted
    }

    private var canUseUsageDiagnostics: Bool {
        LinkaEntitlementPolicy.decision(
            for: .usageDiagnostics,
            snapshot: entitlements.snapshot
        ).isGranted
    }

    private var canUseOptimization: Bool {
        LinkaEntitlementPolicy.decision(for: .optimization, snapshot: entitlements.snapshot, at: Date()).isGranted
    }

    private var isMeasuring: Bool {
        switch viewModel.uiPhase {
        case .connecting, .downloading, .uploading:
            return true
        default:
            return false
        }
    }

    private var connectionPathReport: ConnectionPathReport? {
        if viewModel.uiPhase == .done, let currentMeasurement {
            return ConnectionPathEvaluator().evaluate(currentMeasurement)
        }
        return nil
    }

    private var usageSuitabilityReport: UsageSuitabilityReport? {
        guard let currentMeasurement else { return nil }
        return UsageSuitabilityEvaluator().evaluate(currentMeasurement)
    }

    private var usageQualityLevel: UsageQualityLevel? {
        guard let usageSuitabilityReport else { return nil }
        return UsageSuitabilityCopy.qualityLevel(for: usageSuitabilityReport)
    }

    private var videoCallVerdict: (label: String, color: Color) {
        if let v = usageSuitabilityReport?.verdict(for: .videoCall) {
            switch v.level {
            case .adequate: return (LinkaCopy.value("home.verdict.good"), .statusGood)
            case .limited: return (LinkaCopy.value("home.verdict.fair"), .statusAttention)
            case .notAssessed: return unavailableUsageVerdict
            }
        }
        return unavailableUsageVerdict
    }

    private var gamingVerdict: (label: String, color: Color) {
        if let v = usageSuitabilityReport?.verdict(for: .onlineGaming) {
            switch v.level {
            case .adequate: return (LinkaCopy.value("home.verdict.good"), .statusGood)
            case .limited: return (LinkaCopy.value("home.verdict.fair"), .statusAttention)
            case .notAssessed: return unavailableUsageVerdict
            }
        }
        return unavailableUsageVerdict
    }

    private var streamingVerdict: (label: String, color: Color) {
        guard let report = usageSuitabilityReport else { return unavailableUsageVerdict }
        if let v4k = report.verdict(for: .streaming4K), v4k.level == .adequate {
            return (LinkaCopy.value("home.verdict.4k"), .statusGood)
        } else if let vHD = report.verdict(for: .streamingHD) {
            switch vHD.level {
            case .adequate: return (LinkaCopy.value("home.verdict.hd"), .statusGood)
            case .limited: return (LinkaCopy.value("home.verdict.sd"), .statusAttention)
            case .notAssessed: return unavailableUsageVerdict
            }
        }
        return unavailableUsageVerdict
    }

    private var unavailableUsageVerdict: (label: String, color: Color) {
        (LinkaCopy.value("common.unavailable"), .textSecondary)
    }

    var body: some View {
        #if os(iOS)
        TabView(selection: $selectedTab) {
            NavigationStack(path: $navPath) {
                navigationContent
            }
            .tabItem {
                Label(LinkaPrimaryNavigationDestination.speedTest.title, systemImage: LinkaPrimaryNavigationDestination.speedTest.systemImage)
            }
            .tag(LinkaPrimaryNavigationDestination.speedTest)

            NavigationStack(path: $historyPath) {
                HistoryView(onSelectMeasurement: selectHistoricalMeasurement)
                    .environmentObject(entitlements)
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationView(for: route)
                    }
            }
            .tabItem {
                Label(LinkaPrimaryNavigationDestination.history.title, systemImage: LinkaPrimaryNavigationDestination.history.systemImage)
            }
            .tag(LinkaPrimaryNavigationDestination.history)

            if MinhaRedeAvailability.isEnabled {
                NavigationStack {
                    MyNetworkView()
                        .environmentObject(entitlements)
                }
                .tabItem {
                    Label(LinkaPrimaryNavigationDestination.myNetwork.title, systemImage: LinkaPrimaryNavigationDestination.myNetwork.systemImage)
                }
                .tag(LinkaPrimaryNavigationDestination.myNetwork)
            }

            NavigationStack {
                SettingsView()
                    .environmentObject(entitlements)
            }
            .tabItem {
                Label(LinkaPrimaryNavigationDestination.settings.title, systemImage: LinkaPrimaryNavigationDestination.settings.systemImage)
            }
            .tag(LinkaPrimaryNavigationDestination.settings)
        }
        .tint(.brandAccentWarm)
        #else
        NavigationStack(path: $navPath) {
            navigationContent
        }
        #endif
    }

    /// Dividido em funções `attach*` porque uma única cadeia com todos os
    /// `.sheet`/`.onChange` (mais de 20 modificadores numa expressão só)
    /// estourava o limite de tempo do type-checker do Swift em CI — cada
    /// função aqui é uma expressão pequena o bastante para inferir rápido.
    private var navigationContent: some View {
        let base = ZStack {
            LinkaScreenBackground(showWaves: isMeasuring)
            // Em iPhone (.compact) trava em 500pt — sem isso o conteúdo
            // (pensado na largura de um iPhone) esticaria borda a borda
            // mesmo aí. Em iPad (.regular), por pedido explícito do Luiz,
            // preenche a tela inteira sem limite (ver
            // linkaAdaptiveContentWidth() em DesignSystem.swift). Não afeta
            // o Mac (MacMainView é uma tela própria, sem relação com este
            // arquivo).
            activeMeasurementView
                .linkaAdaptiveContentWidth()
        }
        .navigationTitle(mainTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(isPad ? .inline : .large)
        #endif
        .navigationDestination(for: AppRoute.self) { route in
            destinationView(for: route)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                toolbarShareButton
            }
        }

        return attachLifecycleHandlers(
            attachSecondaryPresentation(
                attachResultPresentation(
                    attachIntentHandlers(
                        attachAssistPresentation(base)
                    )
                )
            )
        )
    }

    private func attachAssistPresentation<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showAssistResult) {
                AssistView(
                    currentMeasurement: assistMeasurement,
                    recentMeasurements: viewModel.recentMeasurements,
                    onRetry: { retryAssistMeasurement() },
                    onRetest: { startSpeedTest() },
                    onShowDetails: { showDetails = true }
                )
            }
            .sheet(isPresented: $showNetscopeAnalysis) {
                if let currentMeasurement {
                    NetscopeAnalysisView(
                        input: NetscopeAnalysisInput(projectingFinalMeasurement: currentMeasurement)
                    )
                } else {
                    NetscopeAnalysisView()
                }
            }
    }

    private func attachIntentHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: intentCoordinator.pendingStartSpeedTest) { pending in
                guard pending else { return }
                beginSpeedTest()
                intentCoordinator.consumeStartSpeedTestRequest()
            }
            .onChange(of: viewModel.uiPhase) { phase in
                handleAssistMeasurementCompletion(phase)
                handleOptimizationRetestCompletion(phase)
            }
            .onChange(of: viewModel.latestFinishedMeasurement) { measurement in
                if measurement != nil && pendingAssistMeasurement && viewModel.uiPhase == .done {
                    pendingAssistMeasurement = false
                    showAssistResult = true
                }
            }
            .onChange(of: intentCoordinator.pendingAdvancedWiFiDiagnosticsImport) { pending in
                guard pending else { return }
                viewModel.consumePendingAdvancedWiFiDiagnostics()
                intentCoordinator.consumeAdvancedWiFiDiagnosticsImport()
                guard pendingAdvancedWiFiMeasurement else { return }
                pendingAdvancedWiFiMeasurement = false
                beginSpeedTest()
            }
            .onChange(of: intentCoordinator.pendingPurchasePrompt) { pending in
                guard pending else { return }
                purchaseEntryPoint = .settings
                showPurchase = true
                intentCoordinator.consumePurchasePrompt()
            }
            .onChange(of: intentCoordinator.pendingOpenHistory) { pending in
                handleOpenHistoryRequest(pending)
            }
            .onChange(of: intentCoordinator.pendingOpenLatestMeasurement) { pending in
                handleOpenLatestMeasurementRequest(pending)
            }
            .onChange(of: intentCoordinator.pendingPublicUniversalLink) { route in
                handlePublicUniversalLink(route)
            }
            .onAppear {
                handlePublicUniversalLink(intentCoordinator.pendingPublicUniversalLink)
            }
    }

    private func attachResultPresentation<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showOptimization) {
                if let measurement = currentMeasurement {
                    OptimizationView(
                        baseline: measurement,
                        history: viewModel.recentMeasurements,
                        isPlusActive: canUseOptimization,
                        onRequestPurchase: {
                            showOptimization = false
                            purchaseEntryPoint = .optimization
                            showPurchase = true
                        },
                        onRetest: { optimizationBaseline = measurement; startSpeedTest() },
                        onManageIdentification: { showOptimization = false; selectedTab = .settings }
                    )
                }
            }
            .sheet(isPresented: $showPurchase) {
                PurchaseSheet(entryPoint: purchaseEntryPoint) {
                    if purchaseEntryPoint == .assist { showAssistResult = true }
                }
                .environmentObject(entitlements)
            }
            .sheet(isPresented: $showConnectivityTriage) {
                ConnectivityTriageView(onRetry: { beginSpeedTest() })
            }
            .sheet(isPresented: $showOptimizationRetestResult) {
                if let result = optimizationRetestResult { OptimizationRetestResultView(result: result) }
            }
            .confirmationDialog(LinkaCopy.value("home.advancedWiFiRecovery.title"), isPresented: $showAdvancedWiFiRecovery, titleVisibility: .visible) {
                Button(LinkaCopy.value("common.tryAgain")) { startSpeedTest() }
                Button(LinkaCopy.value("home.advancedWiFiRecovery.measureWithout")) { beginSpeedTest() }
                Button(LinkaCopy.value("common.cancel"), role: .cancel) {}
            } message: {
                Text(LinkaCopy.value("home.advancedWiFiRecovery.message"))
            }
            .shareMeasurementSheet(isPresented: $showShareSheet, measurement: currentMeasurement)
            .onChange(of: showShareSheet) { isPresented in
                if !isPresented { requestAppStoreReviewAfterResultInteraction() }
            }
            .sheet(isPresented: $showDetails) {
                NavigationStack {
                    MeasurementDetailView(measurement: currentMeasurement, duration: viewModel.testDuration)
                        .environmentObject(entitlements)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(LinkaCopy.value("common.back")) {
                                    showDetails = false
                                }
                            }
                        }
                }
            }
            .onChange(of: showDetails) { isPresented in
                if !isPresented { requestAppStoreReviewAfterResultInteraction() }
            }
    }

    private func attachSecondaryPresentation<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showUsage) {
                UsageDiagnosticsView(measurement: currentMeasurement)
            }
            .sheet(isPresented: $showLiveUsageDetail) {
                LiveUsageDetailSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showConnectionPath) {
                if let connectionPathReport { ConnectionPathDetailView(report: connectionPathReport) }
            }
            .sheet(isPresented: $showExpertModeMigrationBanner, onDismiss: {
                ExpertModeMigrationBannerState.markSeen()
            }) {
                ExpertModeMigrationBanner(
                    onOpenPurchase: {
                        showExpertModeMigrationBanner = false
                        purchaseEntryPoint = .settings
                        showPurchase = true
                    },
                    onDismiss: { showExpertModeMigrationBanner = false }
                )
                .presentationDetents([.medium])
            }
    }

    private func attachLifecycleHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                viewModel.refreshLiveNetwork()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wiFiAuthorizationDidChange)) { _ in
                viewModel.refreshLiveNetwork()
            }
            .animation(reduceMotion ? nil : LinkaMotion.spring, value: viewModel.uiPhase)
            .onChange(of: scenePhase) { newPhase in
                viewModel.handleScenePhaseChange(newPhase)
                switch newPhase {
                case .active:
                    recoverAdvancedWiFiMeasurementIfNeeded()
                    if viewModel.uiPhase == .idle, selectedTab == .speedTest, navPath.isEmpty {
                        prepareHomeAdIfEligible()
                    }
                case .background, .inactive:
                    break
                }
            }
            .onChange(of: viewModel.uiPhase) { handleUIPhaseChange($0) }
            .onChange(of: entitlements.isEntitlementResolved) { resolved in
                guard resolved else { return }
                switch viewModel.uiPhase {
                case .idle:
                    prepareHomeAdIfEligible()
                case .done:
                    prepareResultAdIfEligible()
                case .connecting, .downloading, .uploading, .error, .connectionChanged:
                    break
                }
            }
    }

    // MARK: - Toolbar

    /// Extraídos do closure `.toolbar` para o type-checker não precisar
    /// inferir vários `if` de botão dentro da mesma expressão — sem isso o
    /// build estourava o limite de tempo de type-check em CI.
    @ViewBuilder
    private var toolbarShareButton: some View {
        if viewModel.uiPhase == .done, currentMeasurement?.outcome == .complete {
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.medium))
                    .foregroundColor(.textPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(LinkaCopy.value("home.accessibility.share"))
        }
    }

    // MARK: - Subviews

    private var activeMeasurementView: AnyView {
        switch viewModel.uiPhase {
        case .error:
            return AnyView(errorView)
        case .connectionChanged:
            return AnyView(connectionChangedView)
        case .idle:
            return AnyView(idleView)
        case .connecting, .downloading, .uploading:
            return AnyView(measuringView.accessibilityIdentifier("home.measurementInProgress"))
        case .done:
            return AnyView(resultView)
        }
    }

    private func destinationView(for route: AppRoute) -> AnyView {
        switch route {
        case .myNetwork:
            return AnyView(MyNetworkView().environmentObject(entitlements))
        case .settings:
            return AnyView(SettingsView().environmentObject(entitlements))
        case .history:
            return AnyView(
                HistoryView(onSelectMeasurement: selectHistoricalMeasurement)
                    .environmentObject(entitlements)
            )
        case .measurementDetail(let measurement):
            return AnyView(
                HistoricalMeasurementDetailView(
                    measurement: measurement,
                    onStartNewMeasurement: startNewMeasurementFromHistory,
                    onStartNewMeasurementWithAdvancedWiFi: startNewMeasurementFromHistory
                )
                .environmentObject(entitlements)
            )
        }
    }

    private func handleUIPhaseChange(_ newPhase: SpeedTestUIPhase) {
        switch newPhase {
        case .connecting, .downloading, .uploading:
            ads.measurementDidStart()
        case .idle, .done, .error, .connectionChanged:
            ads.measurementDidEnd()
        }

        if case .error = newPhase {
        } else {
            showConnectivityTriage = false
        }
        switch newPhase {
        case .uploading:
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        case .downloading, .done:
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        default:
            break
        }
        guard newPhase == .done else { return }
        prepareResultAdIfEligible()
        if !isPlusActive, !ExpertModeMigrationBannerState.hasBeenSeen() {
            showExpertModeMigrationBanner = true
        }
        if let category = connectionPathReport?.category, category != .healthy {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
        }
    }

    private var isReviewPromptSafeToPresent: Bool {
        AppStoreReviewPromptPresentationPolicy.isSafe(
            sceneIsActive: scenePhase == .active,
            resultIsVisible: selectedTab == .speedTest && navPath.isEmpty && viewModel.uiPhase == .done,
            hasBlockingPresentation: showAssistResult
                || showPurchase
                || showShareSheet
                || showDetails
                || showUsage
                || showConnectionPath
                || showConnectivityTriage
                || showExpertModeMigrationBanner
                || showAdvancedWiFiRecovery
        )
    }

    /// Só pede depois de uma ação no resultado; nunca na abertura ou no fim
    /// da medição. A espera preserva o número e o CTA de reteste como foco.
    private func requestAppStoreReviewAfterResultInteraction() {
        guard isReviewPromptSafeToPresent else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard isReviewPromptSafeToPresent,
                  let history = await viewModel.appStoreReviewHistory() else {
                return
            }

            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let policy = AppStoreReviewPolicy()
            guard policy.shouldRequestReview(
                completedMeasurementCount: history.completedCount,
                firstCompletedMeasurementAt: history.firstCompletedAt,
                hasInteractedWithCurrentResult: true,
                appVersion: version
            ) else { return }
            policy.recordAutomaticRequest(appVersion: version)
            requestReview()
        }
    }

    // MARK: - Subviews

    // 1. Início (Idle)
    private var idleView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: LinkaSpacing.lg) {
                idleHeroStatus
                    .padding(.top, 40)

                connectionContextLine

                primarySpeedTestButton
                    // O anúncio native é uma ponte UIKit. Mantemos o CTA
                    // acima dela na hierarquia de toque mesmo se o SDK
                    // devolver uma área de hit-testing maior que o card.
                    .zIndex(1)

                latestResultLink

                // O anúncio entra abaixo do conteúdo essencial. Assim, a
                // chegada assíncrona dele não reposiciona título, contexto ou
                // CTA — só ocupa espaço depois do link discreto.
                BannerView(placement: .home)
                    .padding(.top, LinkaSpacing.sm)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear {
            prepareHomeAdIfEligible()
        }
    }

    @ViewBuilder
    private var latestResultLink: some View {
        if let measurement = latestMeasurementForIntent {
            Button {
                navPath.append(AppRoute.measurementDetail(measurement))
            } label: {
                Label(LinkaCopy.value("home.latestResult"), systemImage: "clock.arrow.circlepath")
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint(LinkaCopy.value("home.latestResult.hint"))
        }
    }

    private var isEligibleForAds: Bool {
        LinkaEntitlementPolicy.shouldShowAds(for: entitlements.snapshot, at: Date())
    }

    private func prepareHomeAdIfEligible() {
        ads.prepareHomeAd(
            isEligibleForAds: isEligibleForAds,
            isEntitlementResolved: entitlements.isEntitlementResolved
        )
    }

    private func prepareResultAdIfEligible() {
        ads.prepareResultAd(
            isEligibleForAds: isEligibleForAds,
            isEntitlementResolved: entitlements.isEntitlementResolved
        )
    }

    private var idleHeroStatus: some View {
        VStack(spacing: 10) {
            Image(systemName: "speedometer")
                .font(.system(size: isPad ? 56 : 40, weight: .medium))
                .foregroundColor(.brandAccentWarm)
                .symbolRenderingMode(.hierarchical)

            Text(LinkaCopy.value("home.hero.ready.title"))
                .font(.displayMedium)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)

            Text(LinkaCopy.value("home.hero.ready.subtitle"))
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
    }

    private var connectionContextLine: some View {
        HStack(spacing: 6) {
            Button {
                showLiveUsageDetail = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: liveConnectionIcon)
                        .font(.system(size: 13, weight: .medium))
                    Text(liveConnectionName)
                        .font(.captionSmall)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.6)
                }
                .foregroundColor(.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LinkaCopy.value("home.live.viewDetails"))

            #if os(iOS)
            if viewModel.liveConnectionKind == .wifi && viewModel.liveWiFiContext?.ssid == nil {
                Button {
                    WiFiNetworkPermission.requestIdentification()
                } label: {
                    Text(LinkaCopy.value("detail.identify"))
                        .font(.captionSmallStrong)
                        .foregroundColor(.brandAccentWarmInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
            }
            #endif
        }
        .padding(.vertical, 6)
    }

    private var primarySpeedTestButton: some View {
        Button {
            startSpeedTest()
        } label: {
            Label(LinkaCopy.value("home.testSpeed"), systemImage: "speedometer")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.brandAccentWarm)
        .controlSize(.large)
        .frame(maxWidth: isPad ? 420 : 300)
        .accessibilityIdentifier("home.speedTestCTA")
    }

    // 2. Medindo (Connecting / Downloading / Uploading)
    private var measuringView: some View {
        VStack(spacing: 0) {
            Spacer()

            MeasurementNetworkFlowView(
                phase: measurementFlowPhase,
                pingMilliseconds: viewModel.hasMeasuredPing ? viewModel.ping : nil,
                width: isPad ? 300 : 240
            )
            .padding(.bottom, viewModel.uiPhase == .connecting ? 24 : 16)

            if viewModel.uiPhase != .connecting {
                MetricRing(
                    connecting: false,
                    progress: viewModel.progress,
                    value: ringValue,
                    unit: "Mbps",
                    size: isPad ? 220 : 160,
                    animation: animation,
                    matchedId: "downloadValue"
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .padding(.bottom, 24)
            }

            Text(phaseLabel)
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
                .padding(.bottom, 14)

            PhaseDots(
                phases: [
                    (key: "ping", label: LinkaCopy.value("measurement.phase.ping")),
                    (key: "downloading", label: LinkaCopy.value("measurement.phase.download")),
                    (key: "uploading", label: LinkaCopy.value("measurement.phase.upload"))
                ],
                activeKey: activePhaseKey
            )

            Button(action: {
                viewModel.skipOrCancel()
            }) {
                Text(LinkaCopy.value("common.cancel"))
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)

            Spacer()
        }
    }

    // 3. Resultado (Done)
    private var resultView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Download é a resposta imediata da medição. O restante fica
                // compacto para que a pessoa compreenda o resultado sem
                // precisar atravessar uma vitrine de módulos.
                VStack(spacing: 4) {
                    Text(LinkaCopy.value("detail.download"))
                        .font(.bodyRegular)
                        .foregroundColor(.textSecondary)

                    Text("\(Int(round(viewModel.downloadSpeed)))")
                        .font(.heroValueHuge)
                        .foregroundColor(.textPrimary)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)

                    Text("Mbps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textSecondary)
                }
                .padding(.top, 24)

                HStack(spacing: 0) {
                    metricColumn(
                        title: LinkaCopy.value("metric.upload"),
                        value: metricValue(viewModel.uploadSpeed, isMeasured: viewModel.hasMeasuredUpload),
                        unit: viewModel.hasMeasuredUpload ? "Mbps" : nil
                    )
                    Divider().frame(height: 42)
                    metricColumn(
                        title: LinkaCopy.value("metric.ping"),
                        value: metricValue(Double(viewModel.ping), isMeasured: viewModel.hasMeasuredPing),
                        unit: viewModel.hasMeasuredPing ? "ms" : nil
                    )
                }
                .padding(.vertical, 14)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                        .stroke(Color.borderDefault.opacity(0.3), lineWidth: 0.5)
                )

                resultRetestButton

                // O card fica integralmente na área de conteúdo, antes dos
                // casos de uso. Isso preserva o resultado como protagonista e
                // evita que o native ad encoste na tab bar flutuante.
                BannerView(placement: .result)

                ResultUsageCasesView(
                    videoCall: videoCallVerdict,
                    gaming: gamingVerdict,
                    streaming: streamingVerdict
                )

                Button {
                    showDetails = true
                } label: {
                    Label(LinkaCopy.value("detail.title"), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.linkaSecondary)
            }
            .padding(.horizontal, 24)
            // Reserva o fim da rolagem acima da tab bar, sem criar uma faixa
            // escura atrás do CTA e sem sobrepor o native ad.
            .padding(.bottom, 112)
        }
    }

    private var resultRetestButton: some View {
        Button(action: startSpeedTest) {
            Text(LinkaCopy.value("common.testAgain"))
        }
        // O controle regular do sistema tem a altura de 44 pt recomendada
        // pela Apple, preservando um alvo confortável sem virar um hero.
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(.brandAccentWarm)
        .frame(maxWidth: .infinity)
        .padding(.top, LinkaSpacing.xs)
    }

    private func metricColumn(title: String, value: String, unit: String?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.captionSmall)
                .foregroundColor(.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.metricSecondary)
                    .foregroundColor(.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func metricValue(_ value: Double, isMeasured: Bool) -> String {
        isMeasured ? "\(Int(round(value)))" : LinkaCopy.value("metric.notMeasured")
    }

    // 4. Erro (Error)
    private var errorView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(.textSecondary)

            VStack(spacing: 8) {
                Text(errorTitle)
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)

                Text(errorMessage)
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Button(action: {
                startSpeedTest()
            }) {
                Text(LinkaCopy.value("common.tryAgain"))
            }
            .buttonStyle(.linkaPrimary)
            .padding(.horizontal, 24)
            .padding(.top, 4)

            Button(LinkaCopy.value("home.checkConnection")) {
                showConnectivityTriage = true
            }
            .buttonStyle(.linkaSecondary)
            .accessibilityHint(LinkaCopy.value("home.checkConnection.hint"))

            Spacer()
        }
    }

    private var connectionChangedView: some View {
        VStack(spacing: 20) {
            Spacer()
            LiveConnectionPathView(kind: viewModel.liveConnectionKind, label: viewModel.liveNetworkLabel)
                .padding(.horizontal, 24)
            VStack(spacing: 8) {
                Text(LinkaCopy.value("home.connectionChanged.title"))
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                Text(LinkaCopy.value("home.connectionChanged.message"))
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Button { startSpeedTest() } label: {
                Text(LinkaCopy.value("home.connectionChanged.cta"))
            }
            .buttonStyle(.linkaPrimary)
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var liveConnectionName: String {
        viewModel.liveNetworkLabel.isEmpty ? LinkaCopy.value("home.currentConnection") : viewModel.liveNetworkLabel
    }

    private var liveConnectionIcon: String {
        switch viewModel.liveConnectionKind {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        case .other: return "network"
        case nil: return "wifi.exclamationmark"
        }
    }

    private var ringValue: String {
        switch viewModel.uiPhase {
        case .idle, .connecting:
            return LinkaCopy.value("home.preparing")
        case .downloading:
            return formatted(viewModel.downloadSpeed)
        case .uploading, .done:
            return formatted(viewModel.uploadSpeed)
        case .error, .connectionChanged:
            return ""
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(LinkaLanguagePreference.currentLocale))
    }

    private var phaseLabel: String {
        switch viewModel.uiPhase {
        case .idle, .connecting:
            return LinkaCopy.value("measurement.phase.ping")
        case .downloading:
            return LinkaCopy.value("home.phase.downloading")
        case .uploading, .done:
            return LinkaCopy.value("home.phase.uploading")
        case .error, .connectionChanged:
            return ""
        }
    }

    private var activePhaseKey: String {
        switch viewModel.uiPhase {
        case .connecting:
            return "ping"
        case .idle:
            return ""
        case .downloading:
            return "downloading"
        case .uploading, .done:
            return "uploading"
        case .error, .connectionChanged:
            return ""
        }
    }

    private var measurementFlowPhase: MeasurementNetworkFlowPhase {
        switch viewModel.uiPhase {
        case .connecting:
            return .ping
        case .downloading:
            return .download
        case .uploading, .done, .idle, .error, .connectionChanged:
            return .upload
        }
    }

    private var errorTitle: String {
        switch viewModel.failureReason {
        case .offline:
            return LinkaCopy.value("home.offline")
        case .connectionLost:
            return LinkaCopy.value("home.error.connectionLost.title")
        case nil:
            return LinkaCopy.value("home.error.generic.title")
        }
    }

    private var errorMessage: String {
        switch viewModel.failureReason {
        case .offline:
            return LinkaCopy.value("home.error.offline.message")
        case .connectionLost:
            return LinkaCopy.value("home.error.connectionLost.message")
        case nil:
            return LinkaCopy.value("home.error.generic.message")
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let locale = LinkaLanguagePreference.currentLocale
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return LinkaCopy.format("home.relative.today", time)
        } else if calendar.isDateInYesterday(date) {
            return LinkaCopy.format("home.relative.yesterday", time)
        } else {
            return date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
        }
    }

    private var speedTestCTALabel: String {
        guard selectedLiveUsageCase == .videoCall,
              viewModel.liveUsageReport?.verdict(for: .videoCall)?.reason == .missingThroughputMeasurement else {
            return LinkaCopy.value("home.testSpeed")
        }
        return LinkaCopy.value("home.testSpeed.videoCall")
    }

    private func startSpeedTest() {
        selectedLiveUsageCase = nil
        let advancedWiFiAllowed = LinkaEntitlementPolicy.decision(
            for: .advancedWiFiDiagnostics,
            snapshot: entitlements.snapshot,
            at: Date()
        ).isGranted
        if viewModel.liveConnectionKind == .wifi,
           advancedWiFiConfigured,
           advancedWiFiEnabled,
           advancedWiFiAllowed {
            pendingAdvancedWiFiMeasurement = true
            if triggerWiFiAdvancedShortcut() {
                return
            }
            pendingAdvancedWiFiMeasurement = false
        }
        beginSpeedTest()
    }

    private func startAssistMeasurement(
        objective: String?,
        subcategory: String?,
        reportedProblem: String?
    ) {
        pendingAssistObjective = objective
        pendingAssistSubcategory = subcategory
        pendingAssistReportedProblem = reportedProblem
        pendingAssistMeasurement = true
        // A coleta só começa depois que o seletor fechar e o sheet do Assist
        // já estiver visível. Assim o Speed Test nunca toma a tela.
    }

    private func requestAssist(from entryPoint: AssistEntryPoint) {
        assistEntryPoint = entryPoint
        if isPlusActive {
            showAssistResult = true
        } else {
            purchaseEntryPoint = .assist
            showPurchase = true
        }
    }

    /// O CTA da tela de resultado nunca pode cair no caminho de coleta nova.
    /// A ausência de uma amostra é uma inconsistência de estado, não uma
    /// autorização para reiniciar o Speed Test.
    private func requestAssistFromResult() {
        guard let measurement = currentMeasurement else { return }
        requestAssist(from: .result(measurement))
    }

    private func selectHistoricalMeasurement(_ measurement: NetworkMeasurement) {
        historyPath.append(AppRoute.measurementDetail(measurement))
    }

    private func startNewMeasurementFromHistory() {
        navPath = NavigationPath()
        historyPath = NavigationPath()
        selectedTab = .speedTest
        startSpeedTest()
    }

    private func handleOpenHistoryRequest(_ pending: Bool) {
        guard pending else { return }
        historyPath = NavigationPath()
        selectedTab = .history
        intentCoordinator.consumeOpenHistory()
    }

    private func handlePublicUniversalLink(_ route: PublicUniversalLink?) {
        guard let route else { return }
        defer { intentCoordinator.consumePublicUniversalLink() }
        guard !isMeasuring else { return }

        navPath = NavigationPath()
        historyPath = NavigationPath()
        switch route {
        case .home:
            selectedTab = .speedTest
        case .history:
            selectedTab = .history
        case .myNetwork:
            selectedTab = MinhaRedeAvailability.isEnabled ? .myNetwork : .speedTest
        }
    }

    private func handleAssistMeasurementCompletion(_ phase: SpeedTestUIPhase) {
        guard pendingAssistMeasurement else { return }
        switch phase {
        case .done:
            guard viewModel.latestFinishedMeasurement != nil else { return }
            pendingAssistMeasurement = false
            showAssistResult = true
        case .error, .connectionChanged:
            pendingAssistMeasurement = false
        default:
            break
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
            // Um reteste interrompido não pode ser comparado com uma medição
            // futura e não relacionada. A pessoa pode iniciar outro reteste
            // explicitamente a partir da Otimização.
            optimizationBaseline = nil
        case .connecting, .downloading, .uploading:
            break
        }
    }

    private func handleOpenLatestMeasurementRequest(_ pending: Bool) {
        guard pending else { return }
        if isPlusActive, let latest = latestMeasurementForIntent {
            historyPath = NavigationPath()
            selectedTab = .history
            historyPath.append(AppRoute.measurementDetail(latest))
        } else if !isPlusActive {
            purchaseEntryPoint = .shortcut
            showPurchase = true
        }
        intentCoordinator.consumeOpenLatestMeasurement()
    }

    private func retryAssistMeasurement() {
        pendingAssistMeasurement = true
        startSpeedTest()
    }

    private func beginPendingAssistCollection() {
        guard pendingAssistMeasurement, !showAssistResult else { return }
        showAssistResult = true

        // Dá ao sheet do Assist a primeira apresentação antes de iniciar a
        // coleta. O teste segue ativo por trás dele, inclusive no retorno do
        // Atalho Wi-Fi avançado.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard pendingAssistMeasurement else { return }
            startSpeedTest()
        }
    }

    private func triggerWiFiAdvancedShortcut() -> Bool {
        #if canImport(UIKit)
        if UIApplication.shared.canOpenURL(LinkaAdvancedWiFiIntegration.runShortcutURL) {
            UIApplication.shared.open(LinkaAdvancedWiFiIntegration.runShortcutURL, options: [:], completionHandler: nil)
            return true
        }
        #endif
        return false
    }

    private func beginSpeedTest() {
        ads.measurementDidStart()
        withAnimation {
            viewModel.startTest()
        }
    }

    private func recoverAdvancedWiFiMeasurementIfNeeded() {
        guard pendingAdvancedWiFiMeasurement else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard pendingAdvancedWiFiMeasurement,
                  !intentCoordinator.pendingAdvancedWiFiDiagnosticsImport else { return }
            pendingAdvancedWiFiMeasurement = false
            showAdvancedWiFiRecovery = true
        }
    }
}

private struct ResultUsageCasesView: View {
    let videoCall: (label: String, color: Color)
    let gaming: (label: String, color: Color)
    let streaming: (label: String, color: Color)

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isPad: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(spacing: 12) {
            usageNode(
                title: LinkaCopy.value("home.usage.videoCalls"),
                icon: "video",
                result: videoCall.label,
                color: videoCall.color
            )
            usageNode(
                title: LinkaCopy.value("home.usage.onlineGaming"),
                icon: "gamecontroller",
                result: gaming.label,
                color: gaming.color
            )
            usageNode(
                title: LinkaCopy.value("home.usage.streaming"),
                icon: "play.tv",
                result: streaming.label,
                color: streaming.color
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .linkaCard(cornerRadius: LinkaRadius.lg)
    }

    private func usageNode(title: String, icon: String, result: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: isPad ? 26 : 20, weight: .medium))
                .foregroundColor(.textPrimary)
                .frame(width: isPad ? 60 : 44, height: isPad ? 60 : 44)
                .background(Color.surfacePage, in: Circle())

            Text(title)
                .font(.system(size: isPad ? 15 : 12, weight: .medium))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28)

            LinkaStatusBadge(result, color: color)
        }
        .frame(maxWidth: .infinity)
    }
}
