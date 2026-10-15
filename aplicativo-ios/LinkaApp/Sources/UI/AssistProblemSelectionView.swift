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
    #if os(macOS)
    @State private var showingContextReview = false
    @State private var includeMeasurementInContext = true
    #endif

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
                if showingContextReview {
                    macContextReviewStep
                } else if let objective = selectedObjective {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LinkaCopy.value("assist.title"))
                            .font(.title.weight(.bold))
                        Text(macSubtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    macSubcategoryStep(for: objective)
                } else if showingReportedProblem {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LinkaCopy.value("assist.title"))
                            .font(.title.weight(.bold))
                        Text(macSubtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    macReportedProblemStep
                } else {
                    macObjectiveStep
                }
            }
            .frame(maxWidth: 970)
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle(LinkaCopy.value("assist.title"))
        .toolbar {
            if !isInline || selectedObjective != nil || showingReportedProblem || showingContextReview {
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
            return String(
                format: LinkaCopy.value("assist.mac.subtitle.objective"),
                locale: LinkaLanguagePreference.currentLocale,
                objective.label.lowercased(with: LinkaLanguagePreference.currentLocale)
            )
        }
        if showingReportedProblem {
            return LinkaCopy.value("assist.mac.subtitle.reported")
        }
        return LinkaCopy.value("assist.mac.subtitle.initial")
    }

    private var macObjectiveStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Brand & Heading
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.brandAccentWarm)
                    Text(LinkaCopy.value("assist.title"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.brandAccentWarm)
                    Text(LinkaCopy.value("mac.assist.context.proposalBadge"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())
                        .foregroundColor(.brandAccentWarm)
                }

                Text(LinkaCopy.value("mac.assist.start.heading"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineSpacing(3)

                Text(LinkaCopy.value("mac.assist.start.subhead"))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: 480, alignment: .leading)
            }
            .padding(.bottom, 6)

            // 2x2 Topic Grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                topicCard(
                    icon: "waveform.path.ecg",
                    title: LinkaCopy.value("mac.assist.start.topic1.title"),
                    desc: LinkaCopy.value("mac.assist.start.topic1.desc")
                ) {
                    startContextReview(objective: AssistProblemObjective.velocidadeNaoChega.rawValue, subcategory: nil, reportedProblem: LinkaCopy.value("mac.assist.start.topic1.title"))
                }

                topicCard(
                    icon: "wifi.router",
                    title: LinkaCopy.value("mac.assist.start.topic2.title"),
                    desc: LinkaCopy.value("mac.assist.start.topic2.desc")
                ) {
                    startContextReview(objective: AssistProblemObjective.wifiVsOperadora.rawValue, subcategory: nil, reportedProblem: LinkaCopy.value("mac.assist.start.topic2.title"))
                }

                topicCard(
                    icon: "banknote",
                    title: LinkaCopy.value("mac.assist.start.topic3.title"),
                    desc: LinkaCopy.value("mac.assist.start.topic3.desc")
                ) {
                    startContextReview(objective: AssistProblemObjective.velocidadeNaoChega.rawValue, subcategory: nil, reportedProblem: LinkaCopy.value("mac.assist.start.topic3.title"))
                }

                topicCard(
                    icon: "bubble.left",
                    title: LinkaCopy.value("mac.assist.start.topic4.title"),
                    desc: LinkaCopy.value("mac.assist.start.topic4.desc")
                ) {
                    showingReportedProblem = true
                }
            }

            // Composer Box
            VStack(alignment: .leading, spacing: 12) {
                TextField(
                    LinkaCopy.value("mac.assist.start.placeholder"),
                    text: $reportedProblemText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(10)
                .background(Color.macSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "shield")
                            .font(.system(size: 11))
                        Text(LinkaCopy.value("mac.assist.start.privacyNote"))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.textSecondary)

                    Spacer()

                    Button {
                        let trimmed = reportedProblemText.trimmingCharacters(in: .whitespacesAndNewlines)
                        startContextReview(
                            objective: nil,
                            subcategory: nil,
                            reportedProblem: trimmed.isEmpty ? LinkaCopy.value("mac.assist.start.topic4.title") : trimmed
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Text(LinkaCopy.value("common.continue"))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.brandAccentWarm, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
            )
            .padding(.top, 4)
        }
    }

    private func topicCard(icon: String, title: String, desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundColor(.brandAccentWarm)
                    .frame(height: 24, alignment: .leading)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                    .lineSpacing(2)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 115, alignment: .topLeading)
            .padding(18)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private func macSubcategoryStep(for objective: AssistProblemObjective) -> some View {
        macCard(title: objective.label) {
            Text(LinkaCopy.value("assist.problem.subcategoryHint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider()
            ForEach(objective.subcategories) { subcategory in
                Button(subcategory.label) {
                    startContextReview(objective: objective.rawValue, subcategory: subcategory.key, reportedProblem: nil)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                if subcategory.id != objective.subcategories.last?.id { Divider() }
            }
            Divider()
            Button(LinkaCopy.value("assist.problem.skipQuestion")) {
                startContextReview(objective: objective.rawValue, subcategory: nil, reportedProblem: nil)
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
                .accessibilityLabel(LinkaCopy.value("assist.problem.describeTitle"))
                .accessibilityHint(LinkaCopy.value("assist.problem.describeHint"))
            HStack {
                Spacer()
                Text("\(reportedProblemText.count)/\(Self.reportedProblemMaxLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(LinkaCopy.value("common.continue")) {
                startContextReview(
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

    private var macContextReviewStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                showingContextReview = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(LinkaCopy.value("mac.assist.context.allQuestions"))
                }
                .font(.system(size: 12))
                .foregroundColor(.brandAccentWarm)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.brandAccentWarm)
                Text(LinkaCopy.value("assist.title"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.brandAccentWarm)
                Text(LinkaCopy.value("mac.assist.context.proposalBadge"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())
                    .foregroundColor(.brandAccentWarm)
            }

            Text(contextReviewTopicTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.textPrimary)

            Text(LinkaCopy.value("mac.assist.context.review"))
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            VStack(alignment: .leading, spacing: 14) {
                Text(LinkaCopy.value("mac.assist.context.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)

                if let current = currentMeasurement {
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            includeMeasurementInContext.toggle()
                        } label: {
                            Image(systemName: includeMeasurementInContext ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundColor(includeMeasurementInContext ? .brandAccentWarm : .textSecondary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(LinkaCopy.value("mac.assist.context.measurement"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(contextMeasurementSummary(for: current))
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                            Text(LinkaCopy.value("mac.assist.context.measurement.desc"))
                                .font(.system(size: 10))
                                .foregroundColor(.textSecondary.opacity(0.8))
                        }
                    }
                    Divider()
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wifi.router")
                        .font(.system(size: 16))
                        .foregroundColor(.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LinkaCopy.value("mac.assist.context.equipment"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(LinkaCopy.value("mac.assist.context.equipment.desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield")
                        .font(.system(size: 16))
                        .foregroundColor(.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LinkaCopy.value("mac.assist.context.control"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(LinkaCopy.value("mac.assist.context.control.desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .padding(18)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.35), lineWidth: 0.6)
            )

            HStack {
                Text("Resposta ilustrativa, não um diagnóstico real.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                Spacer()
                Button {
                    executeAssistAnalysis()
                } label: {
                    HStack(spacing: 6) {
                        Text(LinkaCopy.value("mac.assist.context.analyze"))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandAccentWarm)
                .accessibilityIdentifier("mac.assist.context.analyzeButton")
            }
            .padding(.top, 6)
        }
    }

    private var contextReviewTopicTitle: String {
        if let problem = assistReportedProblem, !problem.isEmpty {
            return problem
        }
        if let sub = assistSubcategory, let obj = selectedObjective,
           let item = obj.subcategories.first(where: { $0.key == sub }) {
            return item.label
        }
        if let obj = selectedObjective {
            return obj.label
        }
        return LinkaCopy.value("assist.problem.question")
    }

    private func contextMeasurementSummary(for m: NetworkMeasurement) -> String {
        let down = m.downloadMbps.map { "\($0.formatted(.number.precision(.fractionLength(1)).locale(LinkaLanguagePreference.currentLocale))) Mbps ↓" } ?? ""
        let up = m.uploadMbps.map { "\($0.formatted(.number.precision(.fractionLength(1)).locale(LinkaLanguagePreference.currentLocale))) Mbps ↑" } ?? ""
        let lat = m.latencyMs.map { "\(Int(round($0))) ms" } ?? ""
        return [down, up, lat].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func startContextReview(objective: String?, subcategory: String?, reportedProblem: String?) {
        assistObjective = objective
        assistSubcategory = subcategory
        assistReportedProblem = reportedProblem
        showingContextReview = true
    }

    private func executeAssistAnalysis() {
        if currentMeasurement == nil, let onStartFreshMeasurement {
            onStartFreshMeasurement(assistObjective, assistSubcategory, assistReportedProblem)
            dismissSheet()
            return
        }
        showAssist = true
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

    private func macMeasurementValue(_ value: Double, unit: String, fractionLength: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionLength)).locale(LinkaLanguagePreference.currentLocale)) + " \(unit)"
    }

    private func macCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
            Divider()
        }
    }
    #endif

    private var navigationActionTitle: String {
        #if os(macOS)
        if showingContextReview || selectedObjective != nil || showingReportedProblem {
            return LinkaCopy.value("common.back")
        }
        return LinkaCopy.value("common.close")
        #else
        selectedObjective == nil && !showingReportedProblem ? LinkaCopy.value("common.close") : LinkaCopy.value("common.back")
        #endif
    }

    private func handleNavigationAction() {
        #if os(macOS)
        if showingContextReview {
            showingContextReview = false
            return
        }
        #endif
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
        let measurementToUse: NetworkMeasurement?
        #if os(macOS)
        measurementToUse = includeMeasurementInContext ? currentMeasurement : nil
        #else
        measurementToUse = currentMeasurement
        #endif

        return AssistView(
            currentMeasurement: measurementToUse,
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
