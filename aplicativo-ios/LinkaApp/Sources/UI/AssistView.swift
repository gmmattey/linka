import SwiftUI
import MeasurementHistory
import NetworkCore
import NetworkAssist
import LinkaEntitlements
import LinkaModules

struct AssistView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL

    @StateObject private var viewModel: AssistViewModel
    @StateObject private var stabilityViewModel: NetworkStabilityPatternsViewModel
    @State private var showRecommendationDetails = false

    /// Fecha o sheet inteiro: usa `onCloseSheet` (fluxo guiado via
    /// `AssistProblemSelectionView`) quando fornecido, senão cai no
    /// `dismiss()` local (fluxo direto de `HistoryView`/`MainView` legado).
    private func closeSheet() {
        if let onCloseSheet {
            onCloseSheet()
        } else {
            dismiss()
        }
    }

    let currentMeasurement: NetworkMeasurement?
    let recentMeasurements: [NetworkMeasurement]
    /// Quando o Assist foi aberto sem amostra, a coleta acontece por trás
    /// deste sheet. Não se usa nenhum resultado anterior nesse intervalo.
    let isCollectingMeasurement: Bool
    let usageContext: String?
    let failureSignal: NetworkAssistFailureSignal?
    let onRetry: (() -> Void)?
    /// Ação real de "Ver detalhes da medição" (issue UI Polish v2) — antes
    /// esse botão só chamava `dismiss()`, sem navegar a lugar nenhum
    /// (visualmente parecia ir a algum lugar, na prática só voltava).
    /// Quando fornecido (hoje só por `MainView`, que tem um estado
    /// `detailsOpen` para expandir), o botão abre os detalhes de verdade
    /// antes de fechar este sheet. `nil` quando não existe um destino de
    /// detalhes no contexto do chamador (ex.: `HistoryView`, que empurra
    /// esta view numa `NavigationStack` sem resultado "vivo" para expandir)
    /// — nesse caso o botão vira "Voltar", copy honesta para o que
    /// `dismiss()` realmente faz.
    let onShowDetails: (() -> Void)?
    let entitlements: StoreKitEntitlementProvider?
    /// Macro-grupo e subcategoria coletados por `AssistProblemSelectionView`
    /// antes de abrir esta tela, quando o usuário passou pela seleção
    /// guiada. `nil`/`nil` no fluxo observacional puro (comportamento de
    /// hoje, sem mudança).
    let objective: String?
    let subcategory: String?
    /// Texto livre de "Outro problema" (ver `AssistProblemSelectionView`),
    /// quando o usuário optou por descrever em vez de escolher um
    /// `objective` fechado. Mutuamente exclusivo com `objective`/
    /// `subcategory` na prática — o fluxo guiado nunca preenche os dois.
    let reportedProblem: String?
    /// Fecha o sheet INTEIRO em vez de só dar pop dentro do `NavigationStack`
    /// local (bug reportado na revisão do PR #141): quando `AssistView` é
    /// empurrada por `AssistProblemSelectionView.swift` via
    /// `navigationDestination` dentro do próprio `NavigationStack` daquela
    /// tela, `@Environment(\.dismiss)` capturado aqui só faz pop de volta
    /// para a seleção — não fecha o sheet apresentado por `MainView`.
    /// `AssistProblemSelectionView` passa aqui o `dismiss` capturado na
    /// RAIZ do seu próprio `NavigationStack` (que sim fecha o sheet).
    /// `nil` (default) preserva o comportamento existente de `HistoryView`,
    /// que empurra `AssistView` no seu próprio `NavigationStack` direto,
    /// sem tela de seleção no meio — lá `dismiss()` local já faz a coisa
    /// certa.
    let onCloseSheet: (() -> Void)?

    init(
        currentMeasurement: NetworkMeasurement?,
        recentMeasurements: [NetworkMeasurement] = [],
        isCollectingMeasurement: Bool = false,
        usageContext: String? = nil,
        failureSignal: NetworkAssistFailureSignal? = nil,
        objective: String? = nil,
        subcategory: String? = nil,
        reportedProblem: String? = nil,
        onRetry: (() -> Void)? = nil,
        onShowDetails: (() -> Void)? = nil,
        entitlements: StoreKitEntitlementProvider? = nil,
        assistProvider: (any NetworkAssistProviding)? = nil,
        assistIsRemote: Bool = AssistContainer.isRemoteAssistEnabled(),
        onCloseSheet: (() -> Void)? = nil
    ) {
        self.currentMeasurement = currentMeasurement
        self.recentMeasurements = recentMeasurements
        self.isCollectingMeasurement = isCollectingMeasurement
        self.usageContext = usageContext
        self.failureSignal = failureSignal
        self.objective = objective
        self.subcategory = subcategory
        self.reportedProblem = reportedProblem
        self.onRetry = onRetry
        self.onShowDetails = onShowDetails
        self.entitlements = entitlements
        self.onCloseSheet = onCloseSheet

        let resolvedProvider: any NetworkAssistProviding
        if let assistProvider {
            resolvedProvider = assistProvider
        } else if let entitlements {
            resolvedProvider = AssistContainer.makeAssistProvider(entitlements: entitlements)
        } else {
            resolvedProvider = NetworkAssistService(transport: UnconfiguredNetworkAssistTransport())
        }

        self._viewModel = StateObject(wrappedValue: AssistViewModel(assistProvider: resolvedProvider))
        self._stabilityViewModel = StateObject(
            wrappedValue: NetworkStabilityPatternsViewModel(entitlements: entitlements)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinkaScreenBackground(variant: .gradientOnly, showWaves: false)
                    .ignoresSafeArea()
                contentView
            }
            .linkaSheetToolbar(title: LinkaCopy.value("assist.title"), onDismiss: closeSheet)
            // Uma única tarefa coordena análise e estabilidade para a mesma
            // identidade de medição. Duas `.task(id:)` paralelas reagem ao
            // mesmo redraw e deixam o ciclo de análise suscetível a repetição.
            .task(id: currentMeasurement?.id) {
                guard !isCollectingMeasurement, let current = currentMeasurement else { return }
                // A análise de histórico muda a altura do ScrollView. Ela
                // precisa terminar antes de publicar o diagnóstico, para a
                // pessoa não perder o ponto que estava lendo quando a
                // seção de padrões aparece no meio da tela.
                await stabilityViewModel.load(currentMeasurement: current)
                await loadAssist(with: current)
            }
        }
    }

    private func loadAssist(with measurement: NetworkMeasurement) async {
        await viewModel.load(
            currentMeasurement: measurement,
            recentMeasurements: recentMeasurements,
            usageContext: usageContext,
            failureSignal: failureSignal,
            objective: objective,
            subcategory: subcategory,
            reportedProblem: reportedProblem
        )
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .idle, .loading:
            if isCollectingMeasurement {
                AssistCollectingMeasurementView()
            } else if let currentMeasurement {
                AssistWaitingAnalysisView(measurement: currentMeasurement)
            } else {
                unavailableMeasurementView
            }
        case .error(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.statusAttention)
                Text(LinkaCopy.value("assist.error.title"))
                    .font(.displayTitle)
                Text(message)
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button(LinkaCopy.value("common.tryAgain")) {
                    Task {
                        await viewModel.retry(
                            currentMeasurement: currentMeasurement,
                            recentMeasurements: recentMeasurements,
                            usageContext: usageContext,
                            failureSignal: failureSignal,
                            objective: objective,
                            subcategory: subcategory,
                            reportedProblem: reportedProblem
                        )
                    }
                }
                .buttonStyle(.linkaPrimary)
                .padding(.horizontal, 24)
                Button(LinkaCopy.value("common.back")) { closeSheet() }
                    .buttonStyle(.plain)
                    .foregroundColor(.brandAccentWarm)
            }
            .frame(maxHeight: .infinity)
        case .success(let data):
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // ─── 1. PROBLEMA IDENTIFICADO / ESTADO DA CONEXÃO ───
                    let isHealthy = isHealthyAnalysis(headerStatus: data.headerStatus, title: data.title, recommendation: data.recommendation)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isHealthy ? Color.statusGood : Color.statusAttention)
                                .frame(width: 9, height: 9)
                            Text(isHealthy ? LinkaCopy.value("assist.status.healthy") : LinkaCopy.value("assist.status.problem"))
                                .font(.captionStrong)
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                        }

                        Text(data.title)
                            .font(.displayMedium)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(summaryWithoutRepeatedRecommendation(data))
                            .font(.bodyRegular)
                            .foregroundColor(.textSecondary)
                            .lineSpacing(4)

                        if let attribution = data.aiAttribution {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .accessibilityHidden(true)
                                Text(attribution)
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundColor(.textSecondary.opacity(0.8))
                            .padding(.top, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text("Origem da análise: \(attribution)"))
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg))

                    // ─── 2. O QUE FAZER PARA RESOLVER OU MELHORAR ───
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LinkaCopy.value("assist.recommendations.title"))
                            .font(.bodyRegularStrong)
                            .foregroundColor(.textPrimary)

                        if let rec = data.recommendation {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.brandAccentWarm)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(rec.title)
                                            .font(.bodyRegularStrong)
                                            .foregroundColor(.textPrimary)
                                        
                                        let detailLines = recommendationDetailLines(rec, summary: data.summary)
                                        if !detailLines.isEmpty {
                                            VStack(alignment: .leading, spacing: 6) {
                                                ForEach(Array(detailLines.enumerated()), id: \.offset) { index, line in
                                                    HStack(alignment: .top, spacing: 6) {
                                                        Text(detailLines.count > 1 ? "\(index + 1)." : "•")
                                                            .font(.bodySmallStrong)
                                                            .foregroundColor(.brandAccentWarm)
                                                        Text(line)
                                                            .font(.bodySmall)
                                                            .foregroundColor(.textSecondary)
                                                    }
                                                }
                                            }
                                            .padding(.top, 4)
                                        }

                                        if let actionURL = rec.actionURL ?? currentMeasurement?.wifiContext?.gatewayAdminURL.flatMap(URL.init),
                                           (rec.actionLabel != nil || rec.title.lowercased().contains("roteador") || rec.title.lowercased().contains("wi-fi") || rec.title.lowercased().contains("canal")) {
                                            let label = rec.actionLabel ?? LinkaCopy.value("assist.openRouterSettings")
                                            Button(action: {
                                                openURL(actionURL)
                                            }) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "slider.horizontal.3")
                                                        .font(.system(size: 13, weight: .semibold))
                                                    Text(label)
                                                }
                                                .foregroundColor(.brandAccentWarm)
                                                .padding(.vertical, 8)
                                                .padding(.horizontal, 12)
                                                .background(Color.brandAccentWarm.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.top, 6)
                                        }
                                    }
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg))
                        } else {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.title2)
                                    .foregroundColor(.statusGood)

                                Text(LinkaCopy.value("assist.noAction"))
                                    .font(.bodyRegular)
                                    .foregroundColor(.textSecondary)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg))
                        }
                    }

                    // ─── 3. COMO CHEGOU À CONCLUSÃO ───
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LinkaCopy.value("assist.evidence.title"))
                            .font(.bodyRegularStrong)
                            .foregroundColor(.textPrimary)

                        VStack(spacing: 10) {
                            if !data.dimensions.isEmpty {
                                ForEach(data.dimensions, id: \.name) { dim in
                                    dimensionRow(dim)
                                    if dim.name != data.dimensions.last?.name {
                                        Divider()
                                    }
                                }
                            } else if let measurement = currentMeasurement {
                                measurementEvidenceRow(
                                    title: LinkaCopy.value("detail.download"),
                                    value: measurement.downloadMbps.map(formattedSpeed) ?? LinkaCopy.value("common.unavailable")
                                )
                                if let upload = measurement.uploadMbps, upload > 0 {
                                    Divider()
                                    measurementEvidenceRow(
                                        title: LinkaCopy.value("detail.upload"),
                                        value: formattedSpeed(upload)
                                    )
                                }
                                Divider()
                                measurementEvidenceRow(
                                    title: LinkaCopy.value("assist.latency"),
                                    value: measurement.latencyMs.map(formattedMilliseconds) ?? LinkaCopy.value("common.unavailable")
                                )
                                Divider()
                                measurementEvidenceRow(
                                    title: LinkaCopy.value("assist.network"),
                                    value: measurement.connectionKind.map { connectionLabel($0) } ?? LinkaCopy.value("common.unavailable")
                                )
                            }
                        }
                        .padding(18)
                        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg))
                    }

                    // Padrões no seu histórico (quando aplicável)
                    stabilityPatternsSection

                    // Ações de Rodapé
                    VStack(spacing: 12) {
                        if let retry = onRetry {
                            Button(action: {
                                closeSheet()
                                retry()
                            }) {
                                Text(LinkaCopy.value("common.retry"))
                            }
                            .buttonStyle(.linkaPrimary)
                        }

                        if let onShowDetails {
                            Button(action: {
                                closeSheet()
                                onShowDetails()
                            }) {
                                HStack(spacing: 6) {
                                    Text(LinkaCopy.value("assist.technicalDetails"))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .font(.bodySmallStrong)
                                .foregroundColor(.brandAccentWarm)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }

    @ViewBuilder
    private var stabilityPatternsSection: some View {
        switch stabilityViewModel.state {
        case .loading, .unavailable:
            // `.unavailable` cobre Free, sem histórico ou falha ao
            // consultar — silenciar a seção é honesto aqui porque a
            // `AssistView` já é Plus-only na entrada; não é um bloqueio
            // escondido, é a ausência de dado para essa leitura específica.
            EmptyView()
        case .insufficientHistory:
            stabilityPatternsContainer {
                Text(LinkaCopy.value("assist.history.insufficient"))
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
            }
        case .noPatternDetected:
            stabilityPatternsContainer {
                Text(LinkaCopy.value("assist.history.noPattern"))
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
            }
        case .detected(let sentences):
            stabilityPatternsContainer {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                                .foregroundColor(.statusAttention)
                            Text(sentence)
                                .font(.bodyRegular)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stabilityPatternsContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LinkaCopy.value("assist.history.title"))
                .font(.bodyRegularStrong)
                .foregroundColor(.textPrimary)
            content()
        }
    }

    /// Checklist compacto (issue UI Polish v2) — antes cada dimensão tinha
    /// um círculo de 40pt com ícone dentro; agora é uma linha simples, mais
    /// próxima de um `Form`/lista nativa: um símbolo de estado + rótulo +
    /// valor à direita.
    private func dimensionRow(_ dimension: NetworkAssistDimension) -> some View {
        let statusColor = colorForStatus(dimension.status)
        return HStack(spacing: 10) {
            Image(systemName: iconForStatus(dimension.status))
                .font(.bodyRegular)
                .foregroundColor(statusColor)
                .frame(width: 20)

            Text(labelForDimension(dimension.name))
                .font(.bodyRegular)
                .foregroundColor(.textPrimary)

            Spacer()

            Text(labelForStatus(dimension.status, metric: dimension.name))
                .font(.bodyRegularStrong)
                .foregroundColor(statusColor)
        }
        .accessibilityElement(children: .combine)
    }

    private func iconForStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "excellent", "good": return "checkmark.circle.fill"
        case "attention": return "exclamationmark.circle.fill"
        case "critical": return "xmark.circle.fill"
        default: return "circle"
        }
    }
    
    private func labelForDimension(_ name: String) -> String {
        switch name.lowercased() {
        case "download": return LinkaCopy.value("detail.download")
        case "upload": return LinkaCopy.value("detail.upload")
        case "latency": return LinkaCopy.value("assist.latency")
        case "stability", "packet_loss", "perda": return LinkaCopy.value("assist.dimension.stability")
        default: return name.capitalized
        }
    }
    
    private func labelForStatus(_ status: String, metric: String) -> String {
        let metricLower = metric.lowercased()
        switch status.lowercased() {
        case "excellent":
            if metricLower == "latency" { return LinkaCopy.value("assist.status.excellent.feminine") }
            if metricLower == "stability" || metricLower == "packet_loss" || metricLower == "perda" { return LinkaCopy.value("assist.status.noLoss") }
            return LinkaCopy.value("assist.status.excellent")
        case "good":
            if metricLower == "latency" { return LinkaCopy.value("assist.status.good.feminine") }
            if metricLower == "stability" || metricLower == "packet_loss" || metricLower == "perda" { return LinkaCopy.value("assist.status.stable") }
            return LinkaCopy.value("assist.status.good")
        case "attention":
            return LinkaCopy.value("assist.status.attention")
        case "critical":
            return LinkaCopy.value("assist.status.poor")
        case "unknown":
            return LinkaCopy.value("assist.status.notAssessed")
        default:
            return status.capitalized
        }
    }
    
    /// A resposta do NDS costuma repetir a mesma frase em
    /// `recommendation.description` e em `recommendation.steps` (e às vezes
    /// no próprio `summary` da Hero) — issue UI Polish v2. Aqui a UI escolhe
    /// uma única fonte de detalhe por recomendação: os passos quando
    /// existem (são a forma mais acionável), senão a descrição, e nunca a
    /// descrição se ela só repete o que "O que isso significa" já disse.
    private func recommendationDetailLines(_ rec: NetworkAssistRecommendation, summary: String) -> [String] {
        if !rec.steps.isEmpty {
            return rec.steps
        }
        let trimmedDescription = rec.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty, trimmedDescription != trimmedSummary else { return [] }
        return [rec.description]
    }

    /// O problema descreve o que foi medido; a recomendação guarda a próxima
    /// ação. Quando o servidor repete literalmente a ação no resumo, removê-la
    /// do primeiro cartão evita duas instruções iguais em sequência.
    private func summaryWithoutRepeatedRecommendation(_ data: AssistViewModel.DiagnosticData) -> String {
        guard let recommendation = data.recommendation else { return data.summary }
        let action = recommendation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            return data.summary
        }

        let sentences = data.summary.split(whereSeparator: { ".!?".contains($0) })
        let summary = sentences
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.localizedCaseInsensitiveContains(action) }
            .joined(separator: ". ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? data.summary : summary
    }

    private func isHealthyAnalysis(headerStatus: String, title: String, recommendation: NetworkAssistRecommendation?) -> Bool {
        if isGoodStatus(headerStatus) { return true }
        if recommendation == nil { return true }
        let t = title.lowercased()
        if t.contains("sem causa") || t.contains("saudável") || t.contains("tudo certo") || t.contains("normal") || t.contains("no specific cause") || t.contains("no se identificó") {
            return true
        }
        return false
    }

    private func isGoodStatus(_ status: String) -> Bool {
        let s = status.uppercased()
        return s.contains("TUDO CERTO") || s.contains("BOM") || s.contains("EXCELENTE") || s.contains("SAUDÁVEL") || s.contains("CONCLUÍDO") || s.contains("ALL GOOD") || s.contains("TODO BIEN")
    }

    private func measurementEvidenceRow(title: String, value: String, isWarning: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.bodyRegular)
                .foregroundColor(isWarning ? .statusAttention : .statusGood)
                .frame(width: 20)

            Text(title)
                .font(.bodyRegular)
                .foregroundColor(.textPrimary)

            Spacer()

            Text(value)
                .font(.bodyRegularStrong)
                .foregroundColor(isWarning ? .statusAttention : .textSecondary)
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status.lowercased() {
        case "excellent", "good": return .statusGood
        case "attention": return .statusAttention
        case "critical": return .statusCritical
        default: return .textSecondary
        }
    }
    
    private var unavailableMeasurementView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundColor(.textSecondary)
            Text(LinkaCopy.value("assist.unavailable.title"))
                .font(.displayTitle)
            Text(LinkaCopy.value("assist.unavailable.message"))
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(LinkaCopy.value("common.back"), action: closeSheet)
                .font(.bodySmallStrong)
        }
        .frame(maxHeight: .infinity)
    }

    private func formattedSpeed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(LinkaLanguagePreference.currentLocale)) + " Mbps"
    }

    private func formattedMilliseconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(LinkaLanguagePreference.currentLocale)) + " ms"
    }

    private func connectionLabel(_ kind: NetworkConnectionKind) -> String {
        switch kind {
        case .wifi: return LinkaCopy.value("network.wifi")
        case .cellular: return LinkaCopy.value("network.cellular")
        case .ethernet: return LinkaCopy.value("network.ethernet")
        case .other: return LinkaCopy.value("network.other")
        }
    }
}

private struct AssistCollectingMeasurementView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(LinkaCopy.value("assist.collecting.title"))
                .font(.displayTitle)
            Text(LinkaCopy.value("assist.collecting.message"))
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct AssistWaitingAnalysisView: View {
    let measurement: NetworkMeasurement
    @State private var checkedCount: Int = 0

    private struct FactItem: Identifiable {
        let id: String
        let title: String
        let value: String
    }

    private var facts: [FactItem] {
        var list: [FactItem] = []
        if let dl = measurement.downloadMbps {
            list.append(FactItem(id: "dl", title: LinkaCopy.value("assist.fact.download"), value: formattedSpeed(dl)))
        }
        if let ul = measurement.uploadMbps {
            list.append(FactItem(id: "ul", title: LinkaCopy.value("assist.fact.upload"), value: formattedSpeed(ul)))
        }
        if let ping = measurement.latencyMs {
            list.append(FactItem(id: "ping", title: LinkaCopy.value("assist.latency"), value: formattedMilliseconds(ping)))
        }
        if let kind = measurement.connectionKind {
            list.append(FactItem(id: "kind", title: LinkaCopy.value("assist.fact.networkType"), value: connectionLabel(kind)))
        }
        if let adv = measurement.advancedWiFiDiagnostics {
            if let band = adv.bandGHz {
                list.append(FactItem(id: "band", title: LinkaCopy.value("assist.fact.wifiFrequency"), value: formattedGigahertz(band)))
            } else if let channel = adv.channelNumber {
                list.append(FactItem(id: "chan", title: LinkaCopy.value("assist.fact.wifiChannel"), value: String(format: LinkaCopy.value("assist.fact.wifiChannel.value"), locale: LinkaLanguagePreference.currentLocale, channel)))
            }
        } else if let band = measurement.wifiBandGHz {
            list.append(FactItem(id: "band", title: LinkaCopy.value("assist.fact.wifiFrequency"), value: formattedGigahertz(band)))
        } else if let jitter = measurement.jitterMs {
            list.append(FactItem(id: "jitter", title: LinkaCopy.value("assist.fact.stability"), value: formattedMilliseconds(jitter)))
        }
        return list
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Assist Wordmark
            Image("AssistWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text(LinkaCopy.value("assist.analyzing.title"))
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                Text(LinkaCopy.value("assist.analyzing.message"))
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Fatos preenchidos aos poucos com intervalos aleatórios
            VStack(spacing: 12) {
                ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                    HStack {
                        Text(fact.title)
                            .font(.bodyRegular)
                            .foregroundColor(index <= checkedCount ? .textPrimary : .textSecondary.opacity(0.45))

                        Spacer()

                        if index < checkedCount {
                            Text(fact.value)
                                .font(.bodyRegularStrong)
                                .foregroundColor(.textSecondary)
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.statusGood)
                                .transition(.scale.combined(with: .opacity))
                        } else if index == checkedCount {
                            ProgressView()
                                .controlSize(.small)
                                .transition(.opacity)
                        } else {
                            Image(systemName: "circle")
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary.opacity(0.25))
                        }
                    }
                    if index < facts.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(18)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg))
            .padding(.horizontal, 24)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(LinkaCopy.value("assist.analyzing.synthesizing"))
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .task {
            await animateFactsProgress()
        }
    }

    private func animateFactsProgress() async {
        checkedCount = 0
        for i in 1...facts.count {
            let randomDelay = Double.random(in: 0.35...0.7)
            try? await Task.sleep(nanoseconds: UInt64(randomDelay * 1_000_000_000))
            if Task.isCancelled { break }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                checkedCount = i
            }
        }
    }

    private func formattedSpeed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(LinkaLanguagePreference.currentLocale)) + " Mbps"
    }

    private func formattedMilliseconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(LinkaLanguagePreference.currentLocale)) + " ms"
    }

    private func formattedGigahertz(_ value: Double) -> String {
        let precision = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1
        return value.formatted(.number.precision(.fractionLength(precision)).locale(LinkaLanguagePreference.currentLocale)) + " GHz"
    }

    private func connectionLabel(_ kind: NetworkConnectionKind) -> String {
        switch kind {
        case .wifi: return LinkaCopy.value("network.wifi")
        case .cellular: return LinkaCopy.value("network.cellular")
        case .ethernet: return LinkaCopy.value("network.ethernet")
        case .other: return LinkaCopy.value("network.other")
        }
    }
}
