import SwiftUI

/// Jornada guiada B2C orientada a problemas (DNA Linka / Lagcheck)
/// Permite ao consumidor identificar a dor, medir o ponto específico,
/// receber hipóteses honestas e comparar Antes × Depois sem obrigação de mapear a casa inteira.
@available(iOS 17.0, macOS 14.0, *)
public struct ProblemDiagnosticSheet: View {
    public let problem: HomeProblemCase
    public let house: House
    public let diagnosticEngine: WiFiDiagnosticEngine
    public let dataStore: DataStore
    public let apTracker: AccessPointTracker?
    public let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRoom: Room
    @State private var diagnosticMode: DiagnosticMode = .guidedTwoPoint
    @State private var step: FlowStep = .selectRoom
    @State private var currentDiagnosticStep: DiagnosticStep = .verifyingWiFi
    @State private var progress: Double = 0.0
    @State private var baselineResult: MeasurementResult?
    @State private var afterResult: MeasurementResult?
    @State private var errorMessage: String?
    @State private var measurementTask: Task<Void, Never>?
    @State private var hasTriggeredRouterWarning: Bool = false

    @ScaledMetric(relativeTo: .largeTitle) private var scoreFontSize: CGFloat = 52
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 120
    @ScaledMetric(relativeTo: .body) private var roomIconWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var stepBadgeSize: CGFloat = 20
    @ScaledMetric(relativeTo: .caption) private var bulletSize: CGFloat = 6
    @ScaledMetric(relativeTo: .caption) private var bulletPadding: CGFloat = 5

    private var hasConfiguredRouter: Bool {
        house.rooms.contains(where: { $0.hasRouter })
    }

    private var canRunGuidedMode: Bool {
        hasConfiguredRouter && !selectedRoom.hasRouter
    }

    public enum DiagnosticMode: String, CaseIterable, Identifiable {
        case guidedTwoPoint = "Investigação Completa"
        case quickSingle = "Teste Rápido"
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .guidedTwoPoint:
                return SpatialCopy.value("spatial.mode.guidedTwoPoint", defaultValue: "Investigação Completa")
            case .quickSingle:
                return SpatialCopy.value("spatial.mode.quickSingle", defaultValue: "Teste Rápido")
            }
        }
    }

    private enum FlowStep {
        case selectRoom
        // Modo Rápido (1 cômodo)
        case measuring(isSecondRound: Bool)
        case resultReady(result: MeasurementResult, hypothesis: String, action: String)
        case comparisonReady(before: MeasurementResult, after: MeasurementResult)
        // Modo Guiado Completo (Fase 3: Base + Cômodo + Ação + Decisão)
        case guideToBase(baseRoom: Room)
        case measuringBase(baseRoom: Room)
        case guideToTarget(baseResult: MeasurementResult)
        case measuringTarget(baseResult: MeasurementResult)
        case guidedAnalysisReady(analysis: TwoPointAnalysis, plan: PhysicalActionPlan)
        case measuringAfterGuided(analysis: TwoPointAnalysis)
        case guidedVerdictReady(verdict: GuidedVerdict, before: MeasurementResult, after: MeasurementResult)
    }

    public init(
        problem: HomeProblemCase,
        house: House,
        diagnosticEngine: WiFiDiagnosticEngine = .shared,
        dataStore: DataStore = DataStore(),
        apTracker: AccessPointTracker? = nil,
        onFinish: @escaping () -> Void
    ) {
        self.problem = problem
        self.house = house
        self.diagnosticEngine = diagnosticEngine
        self.dataStore = dataStore
        self.apTracker = apTracker
        self.onFinish = onFinish

        // Seleciona por padrão o primeiro cômodo não roteador ou o primeiro disponível
        let defaultRoom = house.rooms.first(where: { !$0.hasRouter }) ?? house.rooms.first ?? Room(name: "Cômodo Principal", icon: "sofa")
        _selectedRoom = State(initialValue: defaultRoom)
        let hasRouter = house.rooms.contains(where: { $0.hasRouter })
        let initialMode: DiagnosticMode = (hasRouter && !defaultRoom.hasRouter) ? .guidedTwoPoint : .quickSingle
        _diagnosticMode = State(initialValue: initialMode)
    }

    private var routerRoom: Room {
        house.rooms.first(where: { $0.hasRouter }) ?? house.rooms.first ?? selectedRoom
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                WiFiCasaTheme.backgroundBase.ignoresSafeArea()

                switch step {
                case .selectRoom:
                    selectRoomView

                // Fluxo Rápido
                case .measuring(let isSecondRound):
                    measuringView(
                        title: isSecondRound ? SpatialCopy.value("spatial.problem.measuringAgain", defaultValue: "Medindo Novamente...") : SpatialCopy.format("spatial.problem.measuringTarget", selectedRoom.name),
                        icon: problem.icon,
                        onRetry: { startTargetedMeasurement(isSecondRound: isSecondRound) },
                        onBack: { errorMessage = nil; step = .selectRoom }
                    )
                case .resultReady(let result, let hypothesis, let action):
                    resultView(result: result, hypothesis: hypothesis, action: action)
                case .comparisonReady(let before, let after):
                    comparisonView(before: before, after: after)

                // Fluxo Guiado Completo (Fase 3)
                case .guideToBase(let baseRoom):
                    guideStepView(
                        stepBadge: SpatialCopy.value("spatial.problem.step1Badge", defaultValue: "Passo 1 de 3 • Ponto de Origem"),
                        title: SpatialCopy.format("spatial.problem.step1Title", baseRoom.name),
                        description: SpatialCopy.value("spatial.problem.step1Desc", defaultValue: "Para descobrir com precisão se a lentidão decorre de paredes ou da sua operadora, primeiro medimos a conexão ao lado do roteador."),
                        icon: "router.fill",
                        buttonText: SpatialCopy.value("spatial.problem.step1Button", defaultValue: "Estou ao Lado do Roteador — Medir Base"),
                        onContinue: { startMeasuringBase(baseRoom: baseRoom) },
                        onBack: { step = .selectRoom }
                    )
                case .measuringBase(let baseRoom):
                    measuringView(
                        title: SpatialCopy.format("spatial.problem.measuringBase", baseRoom.name),
                        icon: "router.fill",
                        onRetry: { startMeasuringBase(baseRoom: baseRoom) },
                        onBack: { errorMessage = nil; step = .selectRoom }
                    )
                case .guideToTarget(let baseResult):
                    guideStepView(
                        stepBadge: SpatialCopy.value("spatial.problem.step2Badge", defaultValue: "Passo 2 de 3 • Ponto Problemático"),
                        title: SpatialCopy.format("spatial.problem.step2Title", selectedRoom.name),
                        description: SpatialCopy.format("spatial.problem.step2Desc", baseResult.score, selectedRoom.name),
                        icon: selectedRoom.icon,
                        buttonText: SpatialCopy.format("spatial.problem.step2Button", selectedRoom.name),
                        onContinue: { startMeasuringTarget(baseResult: baseResult) },
                        onBack: { step = .selectRoom }
                    )
                case .measuringTarget(let baseResult):
                    measuringView(
                        title: SpatialCopy.format("spatial.problem.measuringTarget", selectedRoom.name),
                        icon: selectedRoom.icon,
                        onRetry: { startMeasuringTarget(baseResult: baseResult) },
                        onBack: { errorMessage = nil; step = .guideToTarget(baseResult: baseResult) }
                    )
                case .guidedAnalysisReady(let analysis, let plan):
                    guidedAnalysisView(analysis: analysis, plan: plan)
                case .measuringAfterGuided(let analysis):
                    measuringView(
                        title: SpatialCopy.format("spatial.problem.validatingGain", selectedRoom.name),
                        icon: "arrow.triangle.swap",
                        onRetry: { startMeasuringAfterGuided(analysis: analysis) },
                        onBack: { errorMessage = nil; step = .guidedAnalysisReady(analysis: analysis, plan: GuidedSolutionEngine.generateActionPlan(for: analysis, problem: problem)) }
                    )
                case .guidedVerdictReady(let verdict, let before, let after):
                    guidedVerdictView(verdict: verdict, before: before, after: after)
                }
            }
            .navigationTitle(problem.title)
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SpatialCopy.value("spatial.common.close", defaultValue: "Fechar")) {
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.success, trigger: baselineResult?.id)
            .sensoryFeedback(.success, trigger: afterResult?.id)
            .sensoryFeedback(.error, trigger: errorMessage)
            .sensoryFeedback(.warning, trigger: hasTriggeredRouterWarning)
            .onAppear {
                if !hasConfiguredRouter && !hasTriggeredRouterWarning {
                    hasTriggeredRouterWarning = true
                }
            }
            .onDisappear {
                measurementTask?.cancel()
                onFinish()
            }
        }
    }

    // MARK: - 1. Seleção do Local & Modo de Diagnóstico

    private var selectRoomView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(problem.promptQuestion)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                Text(problem.diagnosticFocus)
                    .font(.subheadline)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Seletor de Modo de Diagnóstico (exibido apenas se a casa tiver roteador e o cômodo não for o roteador)
            if canRunGuidedMode {
                Picker("Modo de Diagnóstico", selection: $diagnosticMode) {
                    ForEach(DiagnosticMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
            } else if !hasConfiguredRouter {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(WiFiCasaTheme.scoreFair)
                    Text(SpatialCopy.value("spatial.problem.markRouterNote", defaultValue: "Marque o cômodo com roteador na planta para habilitar a Investigação Completa de 2 pontos."))
                        .font(.caption)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
                .padding(.horizontal, 20)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(house.rooms) { room in
                        Button {
                            selectedRoom = room
                            if !hasConfiguredRouter || room.hasRouter {
                                diagnosticMode = .quickSingle
                            }
                        } label: {
                            roomRow(for: room)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            let isGuided = canRunGuidedMode && diagnosticMode == .guidedTwoPoint
            VStack(spacing: 8) {
                Button {
                    if isGuided {
                        step = .guideToBase(baseRoom: routerRoom)
                    } else {
                        startTargetedMeasurement(isSecondRound: false)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isGuided ? "arrow.triangle.branch" : "play.fill")
                        Text(isGuided ? SpatialCopy.value("spatial.problem.startGuided", defaultValue: "Iniciar Investigação Completa") : SpatialCopy.format("spatial.problem.startRoom", selectedRoom.name))
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(WiFiCasaTheme.brandAccent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func roomRow(for room: Room) -> some View {
        let isSelected = selectedRoom.id == room.id
        let lastScoreText: String
        if let last = room.lastMeasurement {
            lastScoreText = SpatialCopy.format("spatial.problem.lastScore", last.score, last.rating.label)
        } else {
            lastScoreText = SpatialCopy.value("spatial.room.unmeasured", defaultValue: "Ainda não medido")
        }

        return HStack(spacing: 14) {
            Image(systemName: room.icon)
                .font(.title3)
                .foregroundStyle(isSelected ? WiFiCasaTheme.brandAccent : WiFiCasaTheme.textSecondary)
                .frame(width: roomIconWidth)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(room.name)
                        .font(.headline)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                    if room.hasRouter {
                        Text(SpatialCopy.value("spatial.room.router", defaultValue: "Roteador"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WiFiCasaTheme.backgroundOverlay)
                            .foregroundStyle(WiFiCasaTheme.brandAccent)
                            .clipShape(Capsule())
                    }
                }

                if room.hasRouter {
                    Text(SpatialCopy.value("spatial.problem.routerNote", defaultValue: "Ponto base do sinal. Use para checar a emissão original."))
                        .font(.caption2)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                } else if let last = room.lastMeasurement {
                    Text(lastScoreText)
                        .font(.caption)
                        .foregroundStyle(Color.ratingColor(for: last.rating))
                } else {
                    Text(lastScoreText)
                        .font(.caption)
                        .foregroundStyle(WiFiCasaTheme.textTertiary)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(WiFiCasaTheme.brandAccent)
                    .font(.title3)
            }
        }
        .padding(14)
        .frame(minHeight: 54)
        .background(WiFiCasaTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(room.name)
        .accessibilityValue(room.hasRouter ? "Roteador principal. \(lastScoreText)" : lastScoreText)
        .accessibilityHint("Toque duas vezes para selecionar este cômodo para o teste")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Tela de Transição e Orientação Guiada (Fase 3)

    private func guideStepView(
        stepBadge: String,
        title: String,
        description: String,
        icon: String,
        buttonText: String,
        onContinue: @escaping () -> Void,
        onBack: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(WiFiCasaTheme.brandAccentSubtle)
                    .frame(width: circleSize, height: circleSize)

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(WiFiCasaTheme.brandAccent)
            }

            VStack(spacing: 8) {
                Text(stepBadge.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WiFiCasaTheme.brandAccent)

                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()

            VStack(spacing: 10) {
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text(buttonText)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(WiFiCasaTheme.brandAccent)

                if let onBack {
                    Button(SpatialCopy.value("spatial.problem.backToRooms", defaultValue: "Voltar para Escolha de Cômodo")) {
                        onBack()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 2. Tela de Medição Ativa Reutilizável

    private func measuringView(
        title: String,
        icon: String,
        onRetry: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()

            if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: iconSize))
                        .foregroundStyle(WiFiCasaTheme.scoreFair)

                    Text(SpatialCopy.value("spatial.problem.errorTitle", defaultValue: "Não foi possível concluir o teste"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        #if os(iOS)
                        if error.contains("Rede Local") || error.contains("Ajustes") {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "gear")
                                    Text(SpatialCopy.value("spatial.common.settings", defaultValue: "Abrir Ajustes do iOS"))
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        #endif

                        Button(action: onRetry) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text(SpatialCopy.value("spatial.common.tryAgain", defaultValue: "Tentar Novamente"))
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(WiFiCasaTheme.brandAccent)

                        Button("Voltar") {
                            onBack()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .frame(minHeight: 44)
                    }
                    .padding(.top, 12)
                }
                .padding(24)
                .background(WiFiCasaTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 20)
            } else {
                ZStack {
                    Circle()
                        .fill(WiFiCasaTheme.brandAccentSubtle)
                        .frame(width: circleSize, height: circleSize)

                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundStyle(WiFiCasaTheme.brandAccent)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                    Text(currentDiagnosticStep.label)
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(WiFiCasaTheme.brandAccent)
                    .padding(.horizontal, 40)
                    .accessibilityLabel("Progresso do teste de conexão")
                    .accessibilityValue("\(Int(progress * 100)) por cento concluído")
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - 3. Resultado & Hipótese (Modo Rápido)

    private func resultView(result: MeasurementResult, hypothesis: String, action: String) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                // Placar de Qualidade
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: result.rating.systemImage)
                            .font(.title2)
                        Text(result.rating.label)
                            .font(.title2.weight(.bold))
                    }
                    .foregroundStyle(Color.ratingColor(for: result.rating))

                    Text("\(result.score)")
                        .font(.system(size: scoreFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                    Text(SpatialCopy.format("spatial.problem.scoreInRoom", selectedRoom.name))
                        .font(.caption)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(WiFiCasaTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                // Métricas Objetivas (LAN vs WAN)
                HStack(spacing: 12) {
                    let lanVal = result.metrics.gatewayMedianMs ?? result.metrics.gatewayLatencyMs
                    let lanLoss = result.metrics.gatewayPacketLossPercent
                    let isLanAlert = lanVal > 35.0 || lanLoss > 2.0
                    let lanLossText = lanLoss > 0.0 ? SpatialCopy.format("spatial.problem.lossSuffix", String(format: "%.1f%%", lanLoss)) : ""

                    metricPill(
                        title: SpatialCopy.value("spatial.problem.routerLAN", defaultValue: "Roteador (LAN)"),
                        value: "\(Int(round(lanVal))) ms\(lanLossText)",
                        statusText: isLanAlert ? SpatialCopy.value("spatial.problem.attention", defaultValue: "Atenção") : SpatialCopy.value("spatial.problem.normal", defaultValue: "Normal"),
                        statusIcon: isLanAlert ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        isAlert: isLanAlert
                    )

                    let wanVal = result.metrics.wanMedianMs ?? result.metrics.wanLatencyMs
                    let wanLoss = result.metrics.wanPacketLossPercent
                    let isWanAlert = wanVal > 100.0 || wanLoss > 2.0
                    let wanLossText = wanLoss > 0.0 ? SpatialCopy.format("spatial.problem.lossSuffix", String(format: "%.1f%%", wanLoss)) : ""

                    metricPill(
                        title: SpatialCopy.value("spatial.problem.internetWAN", defaultValue: "Internet (WAN)"),
                        value: "\(Int(round(wanVal))) ms\(wanLossText)",
                        statusText: isWanAlert ? SpatialCopy.value("spatial.problem.attention", defaultValue: "Atenção") : SpatialCopy.value("spatial.problem.normal", defaultValue: "Normal"),
                        statusIcon: isWanAlert ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        isAlert: isWanAlert
                    )
                }

                // Hipótese Técnica
                VStack(alignment: .leading, spacing: 8) {
                    Label(SpatialCopy.value("spatial.problem.observedHypothesis", defaultValue: "HIPÓTESE OBSERVADA"), systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.brandAccent)

                    Text(hypothesis)
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WiFiCasaTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Ação Recomendada
                VStack(alignment: .leading, spacing: 8) {
                    Label(SpatialCopy.value("spatial.problem.suggestedAction", defaultValue: "AÇÃO PRÁTICA SUGERIDA"), systemImage: "hand.tap.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.scoreFair)

                    Text(action)
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WiFiCasaTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Botões de Ação
                VStack(spacing: 10) {
                    Button {
                        startTargetedMeasurement(isSecondRound: true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.swap")
                            Text(SpatialCopy.value("spatial.problem.didChangeRemeasure", defaultValue: "Fiz a Mudança — Medir Novamente"))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(WiFiCasaTheme.brandAccent)

                    Button(SpatialCopy.value("spatial.problem.finishDiagnostic", defaultValue: "Concluir Diagnóstico")) {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .frame(minHeight: 44)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }

    // MARK: - 4. Comparativo Antes × Depois (Modo Rápido)

    private func comparisonView(before: MeasurementResult, after: MeasurementResult) -> some View {
        let delta = after.score - before.score

        return VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                if delta >= 3 {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: iconSize))
                        .foregroundStyle(WiFiCasaTheme.scoreExcellent)

                    Text(SpatialCopy.value("spatial.problem.evolutionConfirmed", defaultValue: "Evolução Confirmada!"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                    Text(SpatialCopy.format("spatial.problem.evolutionDesc", delta))
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else if abs(delta) < 3 {
                    Image(systemName: "equal.circle.fill")
                        .font(.system(size: iconSize))
                        .foregroundStyle(WiFiCasaTheme.textSecondary)

                    Text(SpatialCopy.value("spatial.problem.samePerformance", defaultValue: "Mesmo Desempenho"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                    Text(SpatialCopy.format("spatial.problem.sameDesc", before.score, after.score))
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: iconSize))
                        .foregroundStyle(WiFiCasaTheme.scoreFair)

                    Text(SpatialCopy.value("spatial.problem.dropPerformance", defaultValue: "Queda de Desempenho"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                    Text(SpatialCopy.format("spatial.problem.dropDesc", delta))
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            // Cards lado a lado
            HStack(spacing: 16) {
                comparisonCard(title: SpatialCopy.value("spatial.comparison.before", defaultValue: "Antes"), result: before)
                comparisonCard(title: SpatialCopy.value("spatial.comparison.after", defaultValue: "Depois"), result: after)
            }
            .padding(.horizontal, 20)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text(SpatialCopy.value("spatial.problem.saveAndClose", defaultValue: "Salvar e Fechar"))
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(WiFiCasaTheme.brandAccent)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 5. Análise de 2 Pontos e Ação Física Assistida (Fase 3)

    private func guidedAnalysisView(analysis: TwoPointAnalysis, plan: PhysicalActionPlan) -> some View {
        let baseLAN = Int(round(analysis.baseResult.metrics.gatewayMedianMs ?? analysis.baseResult.metrics.gatewayLatencyMs))
        let targetLAN = Int(round(analysis.targetResult.metrics.gatewayMedianMs ?? analysis.targetResult.metrics.gatewayLatencyMs))
        let deltaVal = Int(round(analysis.lanDeltaMs))
        let deltaStr = GuidedSolutionEngine.formatSignedDeltaMs(analysis.lanDeltaMs)
        let deltaColor = deltaVal > 20 ? WiFiCasaTheme.scoreFair : WiFiCasaTheme.textSecondary
        let spokenDelta = deltaVal > 0 ? "aumento de \(deltaVal) milissegundos" : (deltaVal < 0 ? "redução de \(abs(deltaVal)) milissegundos" : "mesma latência da base")

        return ScrollView {
            VStack(spacing: 18) {
                // Header de Análise Comparativa
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: analysis.confidence.systemImage)
                            .foregroundStyle(analysis.confidence == .high ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.scoreFair)
                        Text(analysis.confidence.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                    }

                    Text(analysis.bottleneck.label)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(analysis.explanation)
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(WiFiCasaTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Diagnóstico: \(analysis.bottleneck.label). Nível de confiança: \(analysis.confidence.label). \(analysis.explanation)")

                // Placar Base vs Ponto Crítico
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text(SpatialCopy.value("spatial.problem.baseRouter", defaultValue: "Base (Roteador)"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                        Text("\(analysis.baseResult.score)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.ratingColor(for: analysis.baseResult.rating))
                        Text("\(baseLAN) ms")
                            .font(.caption2)
                            .foregroundStyle(WiFiCasaTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(WiFiCasaTheme.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Image(systemName: "arrow.right")
                        .foregroundStyle(WiFiCasaTheme.textTertiary)

                    VStack(spacing: 4) {
                        Text(selectedRoom.name)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                        Text("\(analysis.targetResult.score)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.ratingColor(for: analysis.targetResult.rating))
                        Text("\(targetLAN) ms (\(deltaStr))")
                            .font(.caption2)
                            .foregroundStyle(deltaColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(WiFiCasaTheme.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Comparativo de latência no roteador: Base \(baseLAN) milissegundos versus \(selectedRoom.name) \(targetLAN) milissegundos (\(spokenDelta)).")

                // Plano de Ação Física Assistida
                VStack(alignment: .leading, spacing: 12) {
                    Label(plan.title.uppercased(), systemImage: plan.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.brandAccent)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(plan.instructions.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WiFiCasaTheme.brandAccent)
                                    .frame(width: stepBadgeSize, height: stepBadgeSize)
                                    .background(WiFiCasaTheme.backgroundOverlay)
                                    .clipShape(Circle())

                                Text(step)
                                    .font(.subheadline)
                                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                            }
                        }
                    }

                    Divider()
                        .background(WiFiCasaTheme.backgroundOverlay)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(WiFiCasaTheme.scoreFair)
                            .font(.subheadline)

                        Text(plan.tip)
                            .font(.caption)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WiFiCasaTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                // CTAs
                VStack(spacing: 10) {
                    Button {
                        startMeasuringAfterGuided(analysis: analysis)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.swap")
                            Text(SpatialCopy.format("spatial.problem.retestTarget", selectedRoom.name))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(WiFiCasaTheme.brandAccent)

                    Button(SpatialCopy.value("spatial.problem.finishWithoutRetest", defaultValue: "Concluir sem Re-teste")) {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .frame(minHeight: 44)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }

    // MARK: - 6. Veredicto Final da Decisão Assistida (Fase 3)

    private func guidedVerdictView(verdict: GuidedVerdict, before: MeasurementResult, after: MeasurementResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header com Ícone e Veredicto
                VStack(spacing: 12) {
                    Image(systemName: verdictIcon(for: verdict.type))
                        .font(.system(size: iconSize))
                        .foregroundStyle(verdictColor(for: verdict.type))

                    Text(verdict.headline)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(verdict.description)
                        .font(.subheadline)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(WiFiCasaTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Veredicto final: \(verdict.headline). \(verdict.description)")

                // Antes x Depois Comparativo
                HStack(spacing: 16) {
                    comparisonCard(title: SpatialCopy.value("spatial.problem.beforeChange", defaultValue: "Antes da Mudança"), result: before)
                    comparisonCard(title: SpatialCopy.value("spatial.problem.afterChange", defaultValue: "Depois da Mudança"), result: after)
                }

                // Evidências Técnicas
                VStack(alignment: .leading, spacing: 10) {
                    Label(SpatialCopy.value("spatial.problem.observedEvidence", defaultValue: "EVIDÊNCIAS OBSERVADAS"), systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WiFiCasaTheme.brandAccent)

                    ForEach(verdict.technicalSummary, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(WiFiCasaTheme.brandAccent)
                                .frame(width: bulletSize, height: bulletSize)
                                .padding(.top, bulletPadding)
                                .accessibilityHidden(true)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(WiFiCasaTheme.textPrimary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WiFiCasaTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    dismiss()
                } label: {
                    Text(SpatialCopy.value("spatial.problem.saveVerdictReport", defaultValue: "Salvar Relatório da Solução e Fechar"))
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(WiFiCasaTheme.brandAccent)
                .padding(.top, 10)
            }
            .padding(20)
        }
    }

    private func verdictIcon(for type: VerdictType) -> String {
        switch type {
        case .solvedWithoutCost: return "checkmark.seal.fill"
        case .ispContactNeeded: return "phone.badge.waveform"
        case .meshOrEquipmentRecommended: return "point.3.connected.trianglepath.dotted"
        case .repositionAgain: return "arrow.triangle.swap"
        }
    }

    private func verdictColor(for type: VerdictType) -> Color {
        switch type {
        case .solvedWithoutCost: return WiFiCasaTheme.scoreExcellent
        case .ispContactNeeded: return WiFiCasaTheme.scoreFair
        case .meshOrEquipmentRecommended: return WiFiCasaTheme.brandAccent
        case .repositionAgain: return WiFiCasaTheme.textSecondary
        }
    }

    private func comparisonCard(title: String, result: MeasurementResult) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(WiFiCasaTheme.textSecondary)
            Text("\(result.score)")
                .font(.title.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.ratingColor(for: result.rating))
            HStack(spacing: 4) {
                Image(systemName: result.rating.systemImage)
                    .font(.caption2)
                Text(result.rating.label)
                    .font(.caption2)
            }
            .foregroundStyle(WiFiCasaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(WiFiCasaTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(result.score) de 100 pontos. Qualidade \(result.rating.label).")
    }

    private func metricPill(
        title: String,
        value: String,
        statusText: String,
        statusIcon: String,
        isAlert: Bool
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(WiFiCasaTheme.textSecondary)

            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isAlert ? WiFiCasaTheme.scoreFair : WiFiCasaTheme.textPrimary)

            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.caption2)
                Text(statusText)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(isAlert ? WiFiCasaTheme.scoreFair : WiFiCasaTheme.scoreExcellent)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(WiFiCasaTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityValue("Status: \(statusText)")
    }

    // MARK: - Lógica de Medição

    // Medição Rápida
    private func startTargetedMeasurement(isSecondRound: Bool) {
        measurementTask?.cancel()
        measurementTask = nil
        step = .measuring(isSecondRound: isSecondRound)
        errorMessage = nil

        measurementTask = Task { @MainActor in
            do {
                let result = try await diagnosticEngine.performMeasurement(
                    for: selectedRoom.id,
                    isRouterRoom: selectedRoom.hasRouter,
                    progressHandler: { step, progress in
                        Task { @MainActor in
                            self.currentDiagnosticStep = step
                            self.progress = progress
                        }
                    }
                )
                guard !Task.isCancelled else { return }

                dataStore.saveMeasurement(result, for: selectedRoom.id)
                _ = apTracker?.registerMeasurement(result: result, roomName: selectedRoom.name)

                let advice = problem.generateTargetedAdvice(
                    lanMedianMs: result.metrics.gatewayMedianMs ?? result.metrics.gatewayLatencyMs,
                    wanMedianMs: result.metrics.wanMedianMs ?? result.metrics.wanLatencyMs,
                    lanJitterMs: result.metrics.gatewayJitterMs,
                    lanPacketLossPercent: result.metrics.gatewayPacketLossPercent,
                    wanJitterMs: result.metrics.wanJitterMs,
                    wanPacketLossPercent: result.metrics.wanPacketLossPercent,
                    downloadThroughputMbps: result.metrics.downloadThroughputMbps,
                    rating: result.rating
                )

                if isSecondRound, let first = baselineResult {
                    self.afterResult = result
                    let comparison = BeforeAfterComparison(
                        title: "Diagnóstico Rápido: \(problem.title)",
                        date: Date(),
                        baselineCoveragePercent: first.score,
                        afterCoveragePercent: result.score,
                        roomComparisons: [
                            RoomComparison(
                                roomName: selectedRoom.name,
                                roomIcon: selectedRoom.icon,
                                beforeRating: first.rating,
                                beforeScore: first.score,
                                afterRating: result.rating,
                                afterScore: result.score
                            )
                        ]
                    )
                    dataStore.saveComparison(comparison)
                    self.step = .comparisonReady(before: first, after: result)
                } else {
                    self.baselineResult = result
                    self.step = .resultReady(result: result, hypothesis: advice.hypothesis, action: advice.action)
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // Passo 1 da Jornada Guiada: Medir Base
    private func startMeasuringBase(baseRoom: Room) {
        measurementTask?.cancel()
        measurementTask = nil
        step = .measuringBase(baseRoom: baseRoom)
        errorMessage = nil

        measurementTask = Task { @MainActor in
            do {
                let result = try await diagnosticEngine.performMeasurement(
                    for: baseRoom.id,
                    isRouterRoom: true,
                    progressHandler: { step, progress in
                        Task { @MainActor in
                            self.currentDiagnosticStep = step
                            self.progress = progress
                        }
                    }
                )
                guard !Task.isCancelled else { return }

                dataStore.saveMeasurement(result, for: baseRoom.id)
                _ = apTracker?.registerMeasurement(result: result, roomName: baseRoom.name)
                self.baselineResult = result
                self.step = .guideToTarget(baseResult: result)
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // Passo 2 da Jornada Guiada: Medir Cômodo Alvo
    private func startMeasuringTarget(baseResult: MeasurementResult) {
        measurementTask?.cancel()
        measurementTask = nil
        step = .measuringTarget(baseResult: baseResult)
        errorMessage = nil

        measurementTask = Task { @MainActor in
            do {
                let result = try await diagnosticEngine.performMeasurement(
                    for: selectedRoom.id,
                    isRouterRoom: false,
                    progressHandler: { step, progress in
                        Task { @MainActor in
                            self.currentDiagnosticStep = step
                            self.progress = progress
                        }
                    }
                )
                guard !Task.isCancelled else { return }

                dataStore.saveMeasurement(result, for: selectedRoom.id)
                _ = apTracker?.registerMeasurement(result: result, roomName: selectedRoom.name)

                let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: baseResult, target: result)
                let plan = GuidedSolutionEngine.generateActionPlan(for: analysis, problem: problem)
                self.step = .guidedAnalysisReady(analysis: analysis, plan: plan)
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // Passo 3 da Jornada Guiada: Re-testar Cômodo Após Ação Física
    private func startMeasuringAfterGuided(analysis: TwoPointAnalysis) {
        measurementTask?.cancel()
        measurementTask = nil
        step = .measuringAfterGuided(analysis: analysis)
        errorMessage = nil

        measurementTask = Task { @MainActor in
            do {
                let result = try await diagnosticEngine.performMeasurement(
                    for: selectedRoom.id,
                    isRouterRoom: false,
                    progressHandler: { step, progress in
                        Task { @MainActor in
                            self.currentDiagnosticStep = step
                            self.progress = progress
                        }
                    }
                )
                guard !Task.isCancelled else { return }

                dataStore.saveMeasurement(result, for: selectedRoom.id)
                _ = apTracker?.registerMeasurement(result: result, roomName: selectedRoom.name)
                self.afterResult = result

                let verdict = GuidedSolutionEngine.evaluateFinalVerdict(
                    initialTarget: analysis.targetResult,
                    afterTarget: result,
                    analysis: analysis
                )

                // Salva relatório da jornada completa no histórico
                let comparison = BeforeAfterComparison(
                    title: "Jornada Guiada: \(problem.title)",
                    date: Date(),
                    baselineCoveragePercent: analysis.targetResult.score,
                    afterCoveragePercent: result.score,
                    roomComparisons: [
                        RoomComparison(
                            roomName: selectedRoom.name,
                            roomIcon: selectedRoom.icon,
                            beforeRating: analysis.targetResult.rating,
                            beforeScore: analysis.targetResult.score,
                            afterRating: result.rating,
                            afterScore: result.score
                        )
                    ]
                )
                dataStore.saveComparison(comparison)
                self.step = .guidedVerdictReady(verdict: verdict, before: analysis.targetResult, after: result)
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
