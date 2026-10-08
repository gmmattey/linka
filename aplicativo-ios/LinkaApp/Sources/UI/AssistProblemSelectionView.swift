import SwiftUI
import NetworkCore
import NetworkAssist
import LinkaEntitlements

/// Macro-grupo do problema relatado.
enum AssistProblemObjective: String, CaseIterable, Identifiable {
    case jogosComLag = "JOGOS_COM_LAG"
    case videosTravam = "VIDEOS_TRAVAM"
    case chamadasCongelam = "CHAMADAS_CONGELAM"
    case sitesDemoram = "SITES_DEMORAM"
    case internetCaiOscila = "INTERNET_CAI_OSCILA"
    case velocidadeNaoChega = "VELOCIDADE_NAO_CHEGA"
    case wifiVsOperadora = "WIFI_VS_OPERADORA"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jogosComLag: return LinkaCopy.value("assist.problem.games")
        case .videosTravam: return LinkaCopy.value("assist.problem.video")
        case .chamadasCongelam: return LinkaCopy.value("assist.problem.calls")
        case .sitesDemoram: return LinkaCopy.value("assist.problem.sites")
        case .internetCaiOscila: return LinkaCopy.value("assist.problem.outages")
        case .velocidadeNaoChega: return LinkaCopy.value("assist.problem.speed")
        case .wifiVsOperadora: return LinkaCopy.value("assist.problem.wifiOrCarrier")
        }
    }

    var systemImage: String {
        switch self {
        case .jogosComLag: return "gamecontroller"
        case .videosTravam: return "play.rectangle"
        case .chamadasCongelam: return "video"
        case .sitesDemoram: return "safari"
        case .internetCaiOscila: return "wifi.exclamationmark"
        case .velocidadeNaoChega: return "speedometer"
        case .wifiVsOperadora: return "antenna.radiowaves.left.and.right"
        }
    }

    var subcategories: [AssistProblemSubcategory] {
        switch self {
        case .jogosComLag:
            return [
                AssistProblemSubcategory(key: "PING_ALTO", label: LinkaCopy.value("assist.subcategory.highPing")),
                AssistProblemSubcategory(key: "LAG_INTERMITENTE", label: LinkaCopy.value("assist.subcategory.intermittentLag")),
                AssistProblemSubcategory(key: "DESCONECTA_DA_PARTIDA", label: LinkaCopy.value("assist.subcategory.gameDisconnect"))
            ]
        case .videosTravam:
            return [
                AssistProblemSubcategory(key: "BUFFERING_FREQUENTE", label: LinkaCopy.value("assist.subcategory.buffering")),
                AssistProblemSubcategory(key: "QUALIDADE_CAI_SOZINHA", label: LinkaCopy.value("assist.subcategory.qualityDrops")),
                AssistProblemSubcategory(key: "SO_EM_HORARIO_DE_PICO", label: LinkaCopy.value("assist.subcategory.peakHours"))
            ]
        case .chamadasCongelam:
            return [
                AssistProblemSubcategory(key: "IMAGEM_CONGELA", label: LinkaCopy.value("assist.subcategory.videoFreezes")),
                AssistProblemSubcategory(key: "AUDIO_CORTA", label: LinkaCopy.value("assist.subcategory.audioCuts")),
                AssistProblemSubcategory(key: "CHAMADA_CAI", label: LinkaCopy.value("assist.subcategory.callDrops"))
            ]
        case .sitesDemoram:
            return [
                AssistProblemSubcategory(key: "PRIMEIRO_CARREGAMENTO_LENTO", label: LinkaCopy.value("assist.subcategory.pagesSlow")),
                AssistProblemSubcategory(key: "LENTO_O_TEMPO_TODO", label: LinkaCopy.value("assist.subcategory.alwaysSlow")),
                AssistProblemSubcategory(key: "LENTO_SO_EM_ALGUNS_SITES", label: LinkaCopy.value("assist.subcategory.someSites"))
            ]
        case .internetCaiOscila:
            return [
                AssistProblemSubcategory(key: "QUEDA_TOTAL_ESPORADICA", label: LinkaCopy.value("assist.subcategory.noSignal")),
                AssistProblemSubcategory(key: "OSCILACAO_SEM_QUEDA_TOTAL", label: LinkaCopy.value("assist.subcategory.unstable")),
                AssistProblemSubcategory(key: "PIORA_EM_HORARIO_FIXO", label: LinkaCopy.value("assist.subcategory.sameTime"))
            ]
        case .velocidadeNaoChega:
            return [
                AssistProblemSubcategory(key: "DOWNLOAD_ABAIXO_DO_PLANO", label: LinkaCopy.value("assist.subcategory.downloadBelowPlan")),
                AssistProblemSubcategory(key: "UPLOAD_ABAIXO_DO_PLANO", label: LinkaCopy.value("assist.subcategory.uploadBelowPlan")),
                AssistProblemSubcategory(key: "SO_NO_WIFI_A_CABO_OK", label: LinkaCopy.value("assist.subcategory.wifiOnly"))
            ]
        case .wifiVsOperadora:
            return [
                AssistProblemSubcategory(key: "WIFI_PIOR_QUE_DADOS_MOVEIS", label: LinkaCopy.value("assist.subcategory.wifiWorse")),
                AssistProblemSubcategory(key: "DADOS_MOVEIS_PIOR_QUE_WIFI", label: LinkaCopy.value("assist.subcategory.mobileWorse")),
                AssistProblemSubcategory(key: "AMBOS_RUINS", label: LinkaCopy.value("assist.subcategory.bothBad"))
            ]
        }
    }
}

struct AssistProblemSubcategory: Identifiable, Hashable {
    let key: String
    let label: String
    var id: String { key }
}

/// Seleção guiada de problemas do Assist em formato de List nativa da Apple.
struct AssistProblemSelectionView: View {
    @Environment(\.dismiss) private var dismissSheet

    private static let reportedProblemMaxLength = 200

    let currentMeasurement: NetworkMeasurement?
    let recentMeasurements: [NetworkMeasurement]
    let usageContext: String?
    let onRetry: (() -> Void)?
    let onShowDetails: (() -> Void)?
    /// Quando presente, esta tela apenas coleta o sintoma e devolve o
    /// controle para a Home iniciar uma medição nova antes do Assist.
    let onStartFreshMeasurement: ((String?, String?, String?) -> Void)?
    let entitlements: StoreKitEntitlementProvider?
    let isInline: Bool

    @State private var reportedProblemText: String = ""
    @State private var selectedObjective: AssistProblemObjective?
    @State private var showingReportedProblem = false
    @State private var showAssist = false
    @State private var assistObjective: String?
    @State private var assistSubcategory: String?
    @State private var assistReportedProblem: String?

    init(
        currentMeasurement: NetworkMeasurement?,
        recentMeasurements: [NetworkMeasurement] = [],
        usageContext: String? = nil,
        onRetry: (() -> Void)? = nil,
        onShowDetails: (() -> Void)? = nil,
        onStartFreshMeasurement: ((String?, String?, String?) -> Void)? = nil,
        entitlements: StoreKitEntitlementProvider? = nil,
        isInline: Bool = false
    ) {
        self.currentMeasurement = currentMeasurement
        self.recentMeasurements = recentMeasurements
        self.usageContext = usageContext
        self.onRetry = onRetry
        self.onShowDetails = onShowDetails
        self.onStartFreshMeasurement = onStartFreshMeasurement
        self.entitlements = entitlements
        self.isInline = isInline
    }

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        iOSContent
        #endif
    }

    private var iOSContent: some View {
        NavigationStack {
            Group {
                if let objective = selectedObjective { subcategoryStep(for: objective) }
                else if showingReportedProblem { reportedProblemStep }
                else { objectiveStep }
            }
            .navigationTitle(LinkaCopy.value("assist.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !isInline || selectedObjective != nil || showingReportedProblem {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(navigationActionTitle, action: handleNavigationAction)
                    }
                }
            }
        }
        .sheet(isPresented: $showAssist) {
            assistDestination(objective: assistObjective, subcategory: assistSubcategory, reportedProblem: assistReportedProblem)
                // O resultado é uma etapa conclusiva da jornada. Ele fecha
                // explicitamente por "Fechar"; não deve revelar a seleção
                // anterior enquanto a pessoa arrasta a tela.
                .interactiveDismissDisabled()
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LinkaCopy.value("assist.title"))
                        .font(.title.weight(.bold))
                    Text(macSubtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if let objective = selectedObjective {
                    macSubcategoryStep(for: objective)
                } else if showingReportedProblem {
                    macReportedProblemStep
                } else {
                    macObjectiveStep
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(LinkaCopy.value("assist.title"))
        .toolbar {
            if !isInline || selectedObjective != nil || showingReportedProblem {
                ToolbarItem(placement: .cancellationAction) {
                    Button(navigationActionTitle, action: handleNavigationAction)
                }
            }
        }
        .sheet(isPresented: $showAssist) {
            assistDestination(objective: assistObjective, subcategory: assistSubcategory, reportedProblem: assistReportedProblem)
                .interactiveDismissDisabled()
                .frame(minWidth: 680, minHeight: 620)
        }
    }

    private var macSubtitle: String {
        if let objective = selectedObjective {
            return "Escolha o tipo de \(objective.label.lowercased()) para direcionar a análise."
        }
        if showingReportedProblem {
            return "Descreva o que está acontecendo para a análise considerar seu contexto."
        }
        return "Conte o que está acontecendo. O Linka usa a medição atual para explicar o próximo passo."
    }

    private var macObjectiveStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let currentMeasurement {
                macCard(title: "Medição para análise") {
                    HStack(spacing: 24) {
                        if let down = currentMeasurement.downloadMbps {
                            macMeasurementValue("Download", value: String(format: "%.1f Mbps", down), symbol: "arrow.down")
                        }
                        if let up = currentMeasurement.uploadMbps {
                            macMeasurementValue("Upload", value: String(format: "%.1f Mbps", up), symbol: "arrow.up")
                        }
                        if let latency = currentMeasurement.latencyMs {
                            macMeasurementValue("Ping", value: String(format: "%.0f ms", latency), symbol: "gauge.with.needle")
                        }
                    }
                }
            }

            macCard(title: LinkaCopy.value("assist.problem.question")) {
                ForEach(AssistProblemObjective.allCases) { objective in
                    Button {
                        selectedObjective = objective
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: objective.systemImage)
                                .frame(width: 20)
                                .foregroundStyle(Color.brandAccentWarm)
                            Text(objective.label)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if objective != AssistProblemObjective.allCases.last { Divider() }
                }
                Divider()
                Button {
                    showingReportedProblem = true
                } label: {
                    Label(LinkaCopy.value("assist.problem.other"), systemImage: "ellipsis.bubble")
                }
                .buttonStyle(.plain)
            }

            Button(LinkaCopy.value("assist.problem.skipToGeneral")) {
                presentAssist(objective: nil, subcategory: nil, reportedProblem: nil)
            }
            .buttonStyle(.bordered)
        }
    }

    private func macSubcategoryStep(for objective: AssistProblemObjective) -> some View {
        macCard(title: objective.label) {
            Text(LinkaCopy.value("assist.problem.subcategoryHint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider()
            ForEach(objective.subcategories) { subcategory in
                Button(subcategory.label) {
                    presentAssist(objective: objective.rawValue, subcategory: subcategory.key, reportedProblem: nil)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                if subcategory.id != objective.subcategories.last?.id { Divider() }
            }
            Divider()
            Button(LinkaCopy.value("assist.problem.skipQuestion")) {
                presentAssist(objective: objective.rawValue, subcategory: nil, reportedProblem: nil)
            }
            .buttonStyle(.bordered)
        }
    }

    private var macReportedProblemStep: some View {
        macCard(title: LinkaCopy.value("assist.problem.describeTitle")) {
            Text(LinkaCopy.value("assist.problem.describeHint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $reportedProblemText)
                .font(.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color.surfacePage, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: reportedProblemText) { newValue in
                    if newValue.count > Self.reportedProblemMaxLength {
                        reportedProblemText = String(newValue.prefix(Self.reportedProblemMaxLength))
                    }
                }
            HStack {
                Spacer()
                Text("\(reportedProblemText.count)/\(Self.reportedProblemMaxLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(LinkaCopy.value("common.continue")) {
                presentAssist(
                    objective: nil,
                    subcategory: nil,
                    reportedProblem: String(reportedProblemText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.reportedProblemMaxLength))
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandAccentWarm)
            .disabled(reportedProblemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .onAppear { reportedProblemText = "" }
        }
    }

    private func macMeasurementValue(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func macCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(18)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    #endif

    private var navigationActionTitle: String {
        selectedObjective == nil && !showingReportedProblem ? LinkaCopy.value("common.close") : LinkaCopy.value("common.back")
    }

    private func handleNavigationAction() {
        if selectedObjective != nil {
            selectedObjective = nil
        } else if showingReportedProblem {
            showingReportedProblem = false
        } else {
            dismissSheet()
        }
    }

    // MARK: - Etapa 1 — macro-grupo
    private var objectiveStep: some View {
        List {
            if let currentMeasurement {
                Section("Medição para análise") {
                    HStack(spacing: 16) {
                        if let down = currentMeasurement.downloadMbps {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .foregroundColor(.brandAccentWarm)
                                Text(String(format: "%.1f Mbps", down))
                                    .fontWeight(.semibold)
                            }
                        }
                        if let up = currentMeasurement.uploadMbps {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .foregroundColor(.brandAccentWarm)
                                Text(String(format: "%.1f Mbps", up))
                                    .fontWeight(.semibold)
                            }
                        }
                        if let lat = currentMeasurement.latencyMs {
                            HStack(spacing: 4) {
                                Image(systemName: "gauge.with.needle")
                                    .foregroundColor(.textSecondary)
                                Text(String(format: "%.0f ms", lat))
                            }
                        }
                    }
                    .font(.bodySmall)
                    .foregroundColor(.textPrimary)
                    .padding(.vertical, 2)
                }
            }

            Section(LinkaCopy.value("assist.problem.question")) {
                ForEach(AssistProblemObjective.allCases) { objective in
                    Button { selectedObjective = objective } label: {
                        Label(objective.label, systemImage: objective.systemImage)
                            .font(.bodyRegular)
                            .foregroundColor(.textPrimary)
                    }
                }

                Button { showingReportedProblem = true } label: {
                    Label(LinkaCopy.value("assist.problem.other"), systemImage: "ellipsis.bubble")
                        .font(.bodyRegular)
                        .foregroundColor(.textPrimary)
                }
            }

            Section {
                Button { presentAssist(objective: nil, subcategory: nil, reportedProblem: nil) } label: {
                    Text(LinkaCopy.value("assist.problem.skipToGeneral"))
                        .font(.bodySmallMedium)
                        .foregroundColor(.brandAccentWarm)
                }
            }
        }
        .linkaGradientScreenBackground()
    }

    // MARK: - Etapa 2 — subcategoria
    private func subcategoryStep(for objective: AssistProblemObjective) -> some View {
        List {
            Section(header: Text(objective.label), footer: Text(LinkaCopy.value("assist.problem.subcategoryHint"))) {
                ForEach(objective.subcategories) { subcategory in
                    Button { presentAssist(objective: objective.rawValue, subcategory: subcategory.key, reportedProblem: nil) } label: {
                        Text(subcategory.label)
                            .font(.bodyRegular)
                            .foregroundColor(.textPrimary)
                    }
                }
            }

            Section {
                Button { presentAssist(objective: objective.rawValue, subcategory: nil, reportedProblem: nil) } label: {
                    Text(LinkaCopy.value("assist.problem.skipQuestion"))
                        .font(.bodySmallMedium)
                        .foregroundColor(.brandAccentWarm)
                }
            }
        }
        .linkaGradientScreenBackground()
    }

    // MARK: - Etapa alternativa — "Outro problema"
    private var reportedProblemStep: some View {
        Form {
            Section(header: Text(LinkaCopy.value("assist.problem.describeTitle")), footer: Text(LinkaCopy.value("assist.problem.describeHint"))) {
                TextEditor(text: $reportedProblemText)
                    .frame(minHeight: 100)
                    .onChange(of: reportedProblemText) { newValue in
                        if newValue.count > Self.reportedProblemMaxLength {
                            reportedProblemText = String(newValue.prefix(Self.reportedProblemMaxLength))
                        }
                    }

                HStack {
                    Spacer()
                    Text("\(reportedProblemText.count)/\(Self.reportedProblemMaxLength)")
                        .font(.captionSmall)
                        .foregroundColor(.textSecondary)
                }
            }

            Section {
                Button { presentAssist(objective: nil, subcategory: nil, reportedProblem: String(reportedProblemText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.reportedProblemMaxLength))) } label: {
                    Text(LinkaCopy.value("common.continue"))
                        .font(.bodyRegularStrong)
                        .foregroundColor(.brandAccentWarm)
                }
                .disabled(reportedProblemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .linkaGradientScreenBackground()
        .onAppear { reportedProblemText = "" }
    }

    // MARK: - Destino final
    private func assistDestination(objective: String?, subcategory: String?, reportedProblem: String?) -> some View {
        AssistView(
            currentMeasurement: currentMeasurement,
            recentMeasurements: recentMeasurements,
            usageContext: usageContext,
            objective: objective,
            subcategory: subcategory,
            reportedProblem: reportedProblem,
            onRetry: onRetry,
            onShowDetails: onShowDetails,
            entitlements: entitlements,
            onCloseSheet: {
                dismissSheet()
            }
        )
    }

    private func presentAssist(objective: String?, subcategory: String?, reportedProblem: String?) {
        // A medição só é reaproveitada quando esta jornada foi aberta da
        // própria tela de resultado. Os demais pontos de entrada chegam sem
        // amostra e iniciam uma coleta nova pelo callback.
        if currentMeasurement == nil, let onStartFreshMeasurement {
            onStartFreshMeasurement(objective, subcategory, reportedProblem)
            dismissSheet()
            return
        }
        assistObjective = objective
        assistSubcategory = subcategory
        assistReportedProblem = reportedProblem
        showAssist = true
    }
}
