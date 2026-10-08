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
        switch viewModel.uiPhase {
        case .idle, .connectionChanged, .error:
            return LinkaCopy.value("home.title")
        case .connecting, .downloading, .uploading:
            return LinkaCopy.value("home.testing")
        case .done:
            return ""
        }
    }

    @StateObject private var viewModel = SpeedTestViewModel()
    @EnvironmentObject private var entitlements: StoreKitEntitlementProvider
    @EnvironmentObject private var ads: LinkaAdsCoordinator
    @ObservedObject private var intentCoordinator = AppIntentCoordinator.shared

    @State private var navPath = NavigationPath()
    @State private var showMoreMetrics: Bool = false
    @State private var showPurchase: Bool = false
    @State private var showOptimization: Bool = false
    @State private var optimizationBaseline: NetworkMeasurement?
    @State private var optimizationRetestResult: OptimizationRetestComparison?
    @State private var showOptimizationRetestResult = false
    @State private var purchaseEntryPoint: PurchaseEntryPoint = .settings
    @State private var showAssistProblemSelection: Bool = false
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
    @State private var ringScale: CGFloat = 1.0
    @State private var selectedLiveUsageCase: UsageCase?
    @State private var showLiveUsageDetail = false
    @Namespace private var animation

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            case .notAssessed: return (LinkaCopy.value("home.verdict.poor"), .statusCritical)
            }
        }
        return (LinkaCopy.value("home.verdict.poor"), .statusCritical)
    }

    private var gamingVerdict: (label: String, color: Color) {
        if let v = usageSuitabilityReport?.verdict(for: .onlineGaming) {
            switch v.level {
            case .adequate: return (LinkaCopy.value("home.verdict.good"), .statusGood)
            case .limited: return (LinkaCopy.value("home.verdict.fair"), .statusAttention)
            case .notAssessed: return (LinkaCopy.value("home.verdict.poor"), .statusCritical)
            }
        }
        return (LinkaCopy.value("home.verdict.poor"), .statusCritical)
    }

    private var streamingVerdict: (label: String, color: Color) {
        if let v4k = usageSuitabilityReport?.verdict(for: .streaming4K), v4k.level == .adequate {
            return (LinkaCopy.value("home.verdict.4k"), .statusGood)
        } else if let vHD = usageSuitabilityReport?.verdict(for: .streamingHD), vHD.level == .adequate {
            return (LinkaCopy.value("home.verdict.hd"), .statusGood)
        } else {
            return (LinkaCopy.value("home.verdict.sd"), .statusAttention)
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            navigationContent
        }
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
        .navigationBarTitleDisplayMode(viewModel.uiPhase == .idle || viewModel.uiPhase == .done ? .large : .inline)
        #endif
        .navigationDestination(for: AppRoute.self) { route in
            destinationView(for: route)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                toolbarBackButton
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                toolbarHistoryButton
                toolbarInventoryButton
                toolbarShareButton
                toolbarSettingsButton
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
            .sheet(
                isPresented: $showAssistProblemSelection,
                onDismiss: beginPendingAssistCollection
            ) {
                AssistProblemSelectionView(
                    currentMeasurement: assistEntryPoint.measurement,
                    recentMeasurements: [],
                    onStartFreshMeasurement: { objective, subcategory, reportedProblem in
                        startAssistMeasurement(objective: objective, subcategory: subcategory, reportedProblem: reportedProblem)
                    },
                    entitlements: entitlements
                )
            }
            .sheet(isPresented: $showAssistResult) {
                AssistView(
                    currentMeasurement: assistMeasurement,
                    recentMeasurements: [],
                    isCollectingMeasurement: pendingAssistMeasurement,
                    objective: pendingAssistObjective,
                    subcategory: pendingAssistSubcategory,
                    reportedProblem: pendingAssistReportedProblem,
                    onRetry: { retryAssistMeasurement() },
                    onShowDetails: { showDetails = true },
                    entitlements: entitlements
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
                        onManageIdentification: { showOptimization = false; navPath.append(AppRoute.settings) }
                    )
                }
            }
            .sheet(isPresented: $showPurchase) {
                PurchaseSheet(entryPoint: purchaseEntryPoint) {
                    if purchaseEntryPoint == .assist { showAssistProblemSelection = true }
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
                    if viewModel.uiPhase == .idle, navPath.isEmpty {
                        prepareHomeAdIfEligible()
                    }
                case .background, .inactive:
                    break
                }
            }
            .onChange(of: viewModel.uiPhase) { handleUIPhaseChange($0) }
            .onChange(of: entitlements.isEntitlementResolved) { resolved in
                guard resolved, viewModel.uiPhase == .idle else { return }
                prepareHomeAdIfEligible()
            }
    }

    // MARK: - Toolbar

    /// Extraídos do closure `.toolbar` para o type-checker não precisar
    /// inferir vários `if` de botão dentro da mesma expressão — sem isso o
    /// build estourava o limite de tempo de type-check em CI.
    @ViewBuilder
    private var toolbarBackButton: some View {
        if viewModel.uiPhase == .done {
            Button {
                withAnimation {
                    viewModel.resetToIdle()
                }
            } label: {
                Image(systemName: "house")
                    .font(.body.weight(.medium))
                    .foregroundColor(.textPrimary)
            }
            .accessibilityLabel(LinkaCopy.value("home.accessibility.back"))
        }
    }

    @ViewBuilder
    private var toolbarHistoryButton: some View {
        if viewModel.uiPhase == .idle || viewModel.uiPhase == .error || viewModel.uiPhase == .connectionChanged {
            Button { navPath.append(AppRoute.history) } label: {
                Image(systemName: "clock")
                    .font(.body.weight(.medium))
                    .foregroundColor(.textPrimary)
            }
            .accessibilityLabel(LinkaCopy.value("home.accessibility.history"))
        }
    }

    @ViewBuilder
    private var toolbarInventoryButton: some View {
        if MinhaRedeAvailability.isEnabled && (viewModel.uiPhase == .idle || viewModel.uiPhase == .error || viewModel.uiPhase == .connectionChanged) {
            Button { navPath.append(AppRoute.myNetwork) } label: {
                Label(LinkaCopy.value("inventory.title"), systemImage: "wifi.router")
            }
            .accessibilityIdentifier("inventory.open")
        }
    }

    @ViewBuilder
    private var toolbarShareButton: some View {
        if viewModel.uiPhase == .done {
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.medium))
                    .foregroundColor(.textPrimary)
            }
            .accessibilityLabel(LinkaCopy.value("home.accessibility.share"))
        }
    }

    @ViewBuilder
    private var toolbarSettingsButton: some View {
        if viewModel.uiPhase == .idle || viewModel.uiPhase == .done || viewModel.uiPhase == .error || viewModel.uiPhase == .connectionChanged {
            Button { navPath.append(AppRoute.settings) } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.medium))
                    .foregroundColor(.textPrimary)
            }
            .accessibilityLabel(LinkaCopy.value("home.accessibility.settings"))
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
            return AnyView(MyNetworkView())
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
            guard !reduceMotion else { return }
            withAnimation(LinkaMotion.pulse) { ringScale = 1.05 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(LinkaMotion.pulse) { ringScale = 1.0 }
            }
        case .downloading, .done:
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        default:
            break
        }
        guard newPhase == .done else { return }
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
            resultIsVisible: navPath.isEmpty && viewModel.uiPhase == .done,
            hasBlockingPresentation: showAssistProblemSelection
                || showAssistResult
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
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: LinkaSpacing.xl) {
                    Spacer(minLength: 8)

                    idleHeroStatus

                    connectionContextLine

                    primarySpeedTestButton
                        // O anúncio native é uma ponte UIKit. Mantemos o CTA
                        // acima dela na hierarquia de toque mesmo se o SDK
                        // devolver uma área de hit-testing maior que o card.
                        .zIndex(1)

                    BannerView(placement: .home)

                    homeSecondaryActionsGroup

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
        }
        .onAppear {
            prepareHomeAdIfEligible()
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

    private var idleHeroStatus: some View {
        VStack(spacing: 10) {
            Image(systemName: heroStateIcon)
                .font(.system(size: isPad ? 56 : 40, weight: .medium))
                .foregroundColor(heroStateIconColor)
                .symbolRenderingMode(.hierarchical)

            Text(heroStateTitle)
                .font(.displayMedium)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)

            Text(heroStateSubtitle)
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
                        .foregroundColor(.brandAccentWarm)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())
                }
                .frame(minHeight: 44)
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
            HStack(spacing: 10) {
                Image(systemName: "speedometer")
                    .font(isPad ? .title3.weight(.semibold) : .headline.weight(.semibold))
                Text(LinkaCopy.value("home.live.speedTest"))
            }
        }
        .buttonStyle(.linkaPrimary)
        .accessibilityIdentifier("home.speedTestCTA")
    }

    private var homeSecondaryActionsGroup: some View {
        VStack(spacing: 18) {
            Button {
                requestAssist(from: .fresh)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.brandAccentWarm)
                    Text(LinkaCopy.value("home.assist.cta"))
                        .font(.bodyRegular)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let latest = viewModel.latestFinishedMeasurement {
                Button {
                    navPath.append(AppRoute.history)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.medium))
                        Text(LinkaCopy.format("home.lastTest.value", formatted(latest.downloadMbps ?? 0), formatRelativeTime(latest.measuredAt)))
                            .font(.bodyRegular)
                            .lineLimit(1)
                    }
                    .foregroundColor(.textSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 2. Medindo (Connecting / Downloading / Uploading)
    private var measuringView: some View {
        VStack(spacing: 0) {
            Spacer()

            MetricRing(
                connecting: viewModel.uiPhase == .connecting,
                progress: viewModel.progress,
                value: ringValue,
                unit: viewModel.uiPhase == .connecting ? nil : "Mbps",
                size: isPad ? 220 : 160,
                animation: animation,
                matchedId: "downloadValue"
            )
            .scaleEffect(ringScale)
            .padding(.bottom, 28)

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
            VStack(spacing: 0) {
                

                // 1. Download Hero em número inteiro ocupando toda a largura
                VStack(spacing: 2) {
                    Text("\(Int(round(viewModel.downloadSpeed)))")
                        .font(.heroValueHuge)
                        .foregroundColor(.textPrimary)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)

                    Text(LinkaCopy.value("home.downloadUnit"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textSecondary)
                }
                .padding(.top, 16)
                .padding(.bottom, 16)

                // 2. Botão "Mais" com seta para baixo
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showMoreMetrics.toggle()
                    }
                    if showMoreMetrics { requestAppStoreReviewAfterResultInteraction() }
                } label: {
                    HStack(spacing: 5) {
                        Text(LinkaCopy.value("common.more"))
                            .font(.bodySmallStrong)
                        Image(systemName: showMoreMetrics ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, showMoreMetrics ? 14 : 22)

                // Demais métricas reveladas: Upload, Ping e Perdas organizadas por tema
                if showMoreMetrics {
                    HStack(spacing: 8) {
                        metricColumn(title: LinkaCopy.value("metric.upload"), value: metricValue(viewModel.uploadSpeed, isMeasured: viewModel.hasMeasuredUpload), unit: viewModel.hasMeasuredUpload ? "Mbps" : nil)
                            .frame(maxWidth: .infinity)
                        metricColumn(title: LinkaCopy.value("metric.ping"), value: metricValue(Double(viewModel.ping), isMeasured: viewModel.hasMeasuredPing), unit: viewModel.hasMeasuredPing ? "ms" : nil)
                            .frame(maxWidth: .infinity)
                        metricColumn(title: LinkaCopy.value("metric.loss"), value: viewModel.packetLossPercent.map { "\(Int(round($0)))" } ?? LinkaCopy.value("metric.notMeasured"), unit: viewModel.packetLossPercent == nil ? nil : "%")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                            .stroke(Color.borderDefault.opacity(0.3), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 3. Casos de Uso (Vídeo, Jogos, Streaming) estilo caminho de rede
                ResultUsageCasesView(
                    videoCall: videoCallVerdict,
                    gaming: gamingVerdict,
                    streaming: streamingVerdict
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 18)

                NetscopeResultEntryCard {
                    showNetscopeAnalysis = true
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // 4. CTA para o Assist: "Problemas com sua conexão?"
                Button {
                    requestAssistFromResult()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(LinkaCopy.value("home.assist.cta"))
                                .font(.bodyRegularStrong)
                                .foregroundColor(.textPrimary)
                            Text(LinkaCopy.value("home.assist.resultMessage"))
                                .font(.captionSmall)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: isPad ? 19 : 15, weight: .semibold))
                            .foregroundColor(.brandAccentWarm)
                            .frame(width: isPad ? 46 : 36, height: isPad ? 46 : 36)
                            .background(Color.brandAccentWarm.opacity(0.12), in: Circle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                Button {
                    showOptimization = true
                } label: {
                    Label(LinkaCopy.value("optimization.open"), systemImage: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.linkaSecondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // 5. Botão Testar Novamente
                Button(action: {
                    startSpeedTest()
                }) {
                    Text(LinkaCopy.value("common.testAgain"))
                }
                .buttonStyle(.linkaPrimary)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
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

    // MARK: - Idle hero state

    /// Qualidade da Home derivada da mesma janela que alimenta os casos de
    /// uso. Não consulta `LinkaHealthCheck`, para não criar uma segunda
    /// leitura concorrente para a pessoa.
    private enum IdleConnectionQuality {
        case warming       // janela ainda sem evidência suficiente
        case offline       // sem internet
        case good
        case fair
        case poor
    }

    private var idleConnectionQuality: IdleConnectionQuality {
        guard viewModel.liveConnectionKind != nil else { return .offline }
        guard let report = viewModel.liveUsageReport,
              report.telemetry.sampleCount >= 3 else { return .warming }

        guard let gaming = report.verdict(for: .onlineGaming) else { return .warming }
        switch gaming.level {
        case .adequate: return .good
        case .limited:
            return gaming.reason == .packetLossExceeded ? .poor : .fair
        case .notAssessed: return .warming
        }
    }

    private var heroStateIcon: String {
        switch idleConnectionQuality {
        case .warming:  return "ellipsis.circle"
        case .offline:  return "wifi.exclamationmark"
        case .good:     return "checkmark.circle.fill"
        case .fair:     return "exclamationmark.circle.fill"
        case .poor:     return "exclamationmark.triangle.fill"
        }
    }

    private var heroStateIconColor: Color {
        switch idleConnectionQuality {
        case .warming:  return .textSecondary
        case .offline:  return .statusCritical
        case .good:     return .statusGood
        case .fair:     return .statusAttention
        case .poor:     return .statusCritical
        }
    }

    private var heroStateTitle: String {
        switch idleConnectionQuality {
        case .warming:  return LinkaCopy.value("home.hero.warming.title")
        case .offline:  return LinkaCopy.value("home.offline")
        case .good:     return LinkaCopy.value("home.hero.good.title")
        case .fair:     return LinkaCopy.value("home.hero.fair.title")
        case .poor:     return LinkaCopy.value("home.hero.poor.title")
        }
    }

    private var heroStateSubtitle: String {
        switch idleConnectionQuality {
        case .warming:  return LinkaCopy.value("home.hero.warming.subtitle")
        case .offline:  return LinkaCopy.value("home.hero.connectToAnalyze")
        case .good:     return LinkaCopy.value("home.hero.good.subtitle")
        case .fair:     return LinkaCopy.value("home.hero.fair.subtitle")
        case .poor:     return LinkaCopy.value("home.hero.poor.subtitle")
        }
    }

    private var simpleNetworkContext: String? {
        if viewModel.connectionKind == .wifi {
            if let ssid = viewModel.wifiContext?.ssid {
                if let band = viewModel.wifiBandGHz {
                    let fractionLength = band.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1
                    let bandStr = band.formatted(
                        .number
                            .precision(.fractionLength(fractionLength))
                            .locale(LinkaLanguagePreference.currentLocale)
                    )
                    return "\(ssid) · \(bandStr) GHz"
                }
                return ssid
            }
            return LinkaCopy.value("network.wifi")
        } else if viewModel.connectionKind == .cellular {
            if !viewModel.liveNetworkLabel.isEmpty {
                return viewModel.liveNetworkLabel
            }
            return LinkaCopy.value("network.cellular")
        } else if viewModel.connectionKind == .ethernet {
            return LinkaCopy.value("network.ethernet")
        }
        return nil
    }

    private var liveConnectionType: String {
        switch viewModel.liveConnectionKind {
        case .wifi: return LinkaCopy.value("network.wifi")
        case .cellular: return LinkaCopy.value("network.cellular")
        case .ethernet: return LinkaCopy.value("network.ethernet")
        case .other: return LinkaCopy.value("network.other")
        case nil: return LinkaCopy.value("home.offline")
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
            return LinkaCopy.value("home.phase.connecting")
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
            showAssistProblemSelection = true
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
        navPath.append(AppRoute.measurementDetail(measurement))
    }

    private func startNewMeasurementFromHistory() {
        navPath = NavigationPath()
        startSpeedTest()
    }

    private func handleOpenHistoryRequest(_ pending: Bool) {
        guard pending else { return }
        navPath.append(AppRoute.history)
        intentCoordinator.consumeOpenHistory()
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
            navPath.append(AppRoute.measurementDetail(latest))
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
