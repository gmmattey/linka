import SwiftUI
import NetworkCore
import NetworkInventory
import NetworkAssist
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Tela conversacional inteligente do Linka Genius (alimentada por Gemini 3.8 Flash).
/// Substitui o fluxo legado de diagnóstico estático por um especialista interativo de redes.
public struct AssistView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LinkaGeniusViewModel

    public let currentMeasurement: NetworkMeasurement?
    public let recentMeasurements: [NetworkMeasurement]
    public let isCollectingMeasurement: Bool
    public let usageContext: String?
    public let failureSignal: NetworkAssistFailureSignal?
    public let onRetry: (() -> Void)?
    public let onRetest: (() -> Void)?
    public let onShowDetails: (() -> Void)?
    public let onCloseSheet: (() -> Void)?

    @State private var hasCopiedScript: Bool = false
    @State private var copyResetTask: Task<Void, Never>?

    public init(
        currentMeasurement: NetworkMeasurement?,
        recentMeasurements: [NetworkMeasurement] = [],
        isCollectingMeasurement: Bool = false,
        usageContext: String? = nil,
        failureSignal: NetworkAssistFailureSignal? = nil,
        objective: String? = nil,
        subcategory: String? = nil,
        reportedProblem: String? = nil,
        onRetry: (() -> Void)? = nil,
        onRetest: (() -> Void)? = nil,
        onShowDetails: (() -> Void)? = nil,
        entitlements: Any? = nil,
        assistProvider: Any? = nil,
        assistIsRemote: Bool = true,
        onCloseSheet: (() -> Void)? = nil,
        geniusViewModel: LinkaGeniusViewModel? = nil
    ) {
        self.currentMeasurement = currentMeasurement
        self.recentMeasurements = recentMeasurements
        self.isCollectingMeasurement = isCollectingMeasurement
        self.usageContext = usageContext
        self.failureSignal = failureSignal
        self.onRetry = onRetry
        self.onRetest = onRetest
        self.onShowDetails = onShowDetails
        self.onCloseSheet = onCloseSheet

        if let geniusViewModel {
            self._viewModel = StateObject(wrappedValue: geniusViewModel)
        } else {
            let capturedMeasurement = currentMeasurement
            self._viewModel = StateObject(
                wrappedValue: LinkaGeniusViewModel(
                    measurementProvider: { capturedMeasurement }
                )
            )
        }
    }

    private func closeSheet() {
        if let onCloseSheet {
            onCloseSheet()
        } else {
            dismiss()
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                LinkaScreenBackground(variant: .gradientOnly, showWaves: false)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: LinkaSpacing.md) {
                        // 1. Header Hero do Genius
                        headerView

                        // 2. Prontuário visual da rede
                        telemetryCard

                        // 3. Área de Interação ou Resposta
                        switch viewModel.state {
                        case .idle:
                            interactionSection
                        case .readingTelemetry, .consultingGenius, .finalizing:
                            loadingSection
                        case .success(let analysis):
                            analysisResultSection(analysis: analysis)
                        case .failure(let error):
                            errorSection(error: error)
                        }

                        // 4. Rodapé sutil de atribuição da IA
                        footerView
                    }
                    .padding(.horizontal, LinkaSpacing.md)
                    .padding(.top, LinkaSpacing.sm)
                    .padding(.bottom, LinkaSpacing.xl)
                }
            }
            .linkaSheetToolbar(
                title: LinkaCopy.value("genius.title"),
                onDismiss: closeSheet
            )
        }
    }

    // MARK: - 1. Header

    private var headerView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.brandAccentWarm)
                Text(LinkaCopy.value("genius.title"))
                    .font(.displayTitle)
                    .foregroundColor(.textPrimary)
            }
            Text(LinkaCopy.value("genius.subtitle"))
                .font(.bodySmall)
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 2. Prontuário de Rede

    @ViewBuilder
    private var telemetryCard: some View {
        if let measurement = currentMeasurement {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(LinkaCopy.value("genius.telemetry.title"))
                        .font(.captionStrong)
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    connectionBadge(for: measurement)
                }

                HStack(spacing: 12) {
                    telemetryMetric(
                        icon: "arrow.down.circle.fill",
                        iconColor: .chartDownloadSeries,
                        title: LinkaCopy.value("detail.download"),
                        value: measurement.downloadMbps.map(formattedSpeed) ?? LinkaCopy.value("common.unavailable")
                    )

                    telemetryMetric(
                        icon: "arrow.up.circle.fill",
                        iconColor: .brandAccentWarm,
                        title: LinkaCopy.value("detail.upload"),
                        value: measurement.uploadMbps.map(formattedSpeed) ?? LinkaCopy.value("common.unavailable")
                    )

                    telemetryMetric(
                        icon: "gauge.with.dots.needle.bottom.50percent",
                        iconColor: .textSecondary,
                        title: LinkaCopy.value("assist.latency"),
                        value: measurement.latencyMs.map(formattedMilliseconds) ?? LinkaCopy.value("common.unavailable")
                    )
                }
            }
            .padding(LinkaSpacing.md)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.2), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.brandAccentWarm)
                    Text(LinkaCopy.value("genius.telemetry.empty.title"))
                        .font(.bodyRegularStrong)
                        .foregroundColor(.textPrimary)
                }

                Text(LinkaCopy.value("genius.telemetry.empty.message"))
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)

                if let testAction = onRetest ?? onRetry {
                    Button(action: {
                        closeSheet()
                        testAction()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(LinkaCopy.value("genius.telemetry.testNow"))
                                .font(.bodySmallStrong)
                        }
                        .foregroundColor(.brandAccentWarmInk)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.brandAccentWarm.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(LinkaSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func telemetryMetric(icon: String, iconColor: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
            }
            Text(value)
                .font(.bodySmallStrong)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectionBadge(for measurement: NetworkMeasurement) -> some View {
        let label: String
        let icon: String

        if let kind = measurement.connectionKind {
            switch kind {
            case .wifi:
                let band = measurement.advancedWiFiDiagnostics?.bandGHz ?? measurement.wifiBandGHz
                if let band {
                    label = "Wi-Fi \(formattedGigahertz(band))"
                } else {
                    label = LinkaCopy.value("network.wifi")
                }
                icon = "wifi"
            case .cellular:
                label = LinkaCopy.value("network.cellular")
                icon = "antenna.radiowaves.left.and.right"
            case .ethernet:
                label = LinkaCopy.value("network.ethernet")
                icon = "cable.connector"
            case .other:
                label = LinkaCopy.value("network.other")
                icon = "network"
            }
        } else {
            label = LinkaCopy.value("network.wifi")
            icon = "wifi"
        }

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.captionSmallStrong)
        }
        .foregroundColor(.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.surfacePage, in: Capsule())
    }

    // MARK: - 3. Interação (Campo + Atalhos)

    private var interactionSection: some View {
        VStack(alignment: .leading, spacing: LinkaSpacing.md) {
            // Campo de pergunta aberta
            promptInputField

            // Atalhos rápidos em pills
            shortcutsSection
        }
    }

    private var promptInputField: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundColor(.brandAccentWarm)
                .accessibilityHidden(true)

            TextField(
                LinkaCopy.value("genius.prompt.placeholder"),
                text: $viewModel.draft
            )
            .font(.bodyRegular)
            .textFieldStyle(.plain)
            .onSubmit {
                viewModel.submitDraft()
            }

            let canSubmit = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button(action: {
                viewModel.submitDraft()
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(canSubmit ? .brandAccentWarm : .borderStrong.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel(Text(LinkaCopy.value("genius.prompt.send")))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.3), lineWidth: 1)
        )
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LinkaCopy.value("genius.shortcuts.title"))
                .font(.captionStrong)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)

            let localeTag = LinkaLanguagePreference.currentLanguageTag

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(LinkaGeniusShortcut.allCases) { shortcut in
                    shortcutButton(shortcut: shortcut, locale: localeTag)
                }
            }
        }
    }

    private func shortcutButton(shortcut: LinkaGeniusShortcut, locale: String) -> some View {
        Button(action: {
            withAnimation(LinkaMotion.spring) {
                viewModel.ask(shortcut: shortcut)
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: iconForShortcut(shortcut))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.brandAccentWarmInk)
                    .frame(width: 18)

                Text(shortcut.title(for: locale))
                    .font(.bodySmallStrong)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LinkaRadius.md, style: .continuous)
                    .stroke(Color.borderDefault.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconForShortcut(_ shortcut: LinkaGeniusShortcut) -> String {
        switch shortcut {
        case .slowCalls:
            return "video.badge.waveform"
        case .routerAdequacy:
            return "wifi.router"
        case .operatorScript:
            return "doc.text.fill"
        case .meshNeed:
            return "point.3.filled.connected.trianglepath.dotted"
        }
    }

    // MARK: - 4. Estados de Carregamento

    private var loadingSection: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(.brandAccentWarm)
                .padding(.top, 16)

            VStack(spacing: 6) {
                Text(viewModel.state.loadingStepText ?? LinkaCopy.value("genius.loading.telemetry"))
                    .font(.bodyRegularStrong)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)

                Text("Correlacionando telemetria, estabilidade e capacidade...")
                    .font(.captionMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, LinkaSpacing.md)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous)
                .stroke(Color.brandAccentWarm.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 5. Exibição de Resposta

    private func analysisResultSection(analysis: LinkaGeniusAnalysis) -> some View {
        VStack(alignment: .leading, spacing: LinkaSpacing.md) {
            // Sintoma
            resultCard(
                icon: "stethoscope",
                iconColor: .brandAccentWarmInk,
                title: LinkaCopy.value("genius.result.symptom"),
                content: analysis.symptom
            )

            // Causa provável
            resultCard(
                icon: "wrench.and.screwdriver.fill",
                iconColor: .statusAttention,
                title: LinkaCopy.value("genius.result.cause"),
                content: analysis.cause
            )

            // Ações imediatas
            if !analysis.actions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.statusGood)
                        Text(LinkaCopy.value("genius.result.actions"))
                            .font(.captionStrong)
                            .foregroundColor(.textSecondary)
                            .textCase(.uppercase)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(analysis.actions.enumerated()), id: \.offset) { index, action in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.captionSmallStrong)
                                    .foregroundColor(.brandAccentWarmInk)
                                    .frame(width: 20, height: 20)
                                    .background(Color.brandAccentWarm.opacity(0.12), in: Circle())

                                Text(action)
                                    .font(.bodyRegular)
                                    .foregroundColor(.textPrimary)
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
                .padding(LinkaSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous)
                        .stroke(Color.borderDefault.opacity(0.2), lineWidth: 1)
                )
            }

            // Script para a operadora (quando presente)
            let trimmedScript = analysis.operatorScript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedScript.isEmpty {
                operatorScriptBlock(script: trimmedScript)
            }

            // Ações de fluxo (Reteste e Nova Pergunta)
            VStack(spacing: 12) {
                if analysis.needsRetest, let testAction = onRetest ?? onRetry {
                    Button(action: {
                        closeSheet()
                        testAction()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                            Text(LinkaCopy.value("genius.result.retest"))
                        }
                    }
                    .buttonStyle(.linkaPrimary)
                }

                Button(action: {
                    withAnimation(LinkaMotion.spring) {
                        viewModel.reset()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 14, weight: .semibold))
                        Text(LinkaCopy.value("genius.result.newQuestion"))
                    }
                }
                .buttonStyle(.linkaSecondary)
            }
            .padding(.top, 4)
        }
    }

    private func resultCard(icon: String, iconColor: Color, title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.captionStrong)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
            }

            Text(content)
                .font(.bodyRegular)
                .foregroundColor(.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LinkaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.2), lineWidth: 1)
        )
    }

    private func operatorScriptBlock(script: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "phone.bubble.left.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.brandAccentWarmInk)
                    Text(LinkaCopy.value("genius.result.script"))
                        .font(.captionStrong)
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                }

                Spacer()

                Button(action: {
                    copyToClipboard(text: script)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: hasCopiedScript ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                        Text(hasCopiedScript ? LinkaCopy.value("genius.result.script.copied") : LinkaCopy.value("genius.result.script.copy"))
                            .font(.captionSmallStrong)
                    }
                    .foregroundColor(hasCopiedScript ? .statusGood : .brandAccentWarmInk)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(
                        (hasCopiedScript ? Color.statusGood : Color.brandAccentWarm).opacity(0.12),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Text(script)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.textPrimary)
                .lineSpacing(3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfacePage, in: RoundedRectangle(cornerRadius: LinkaRadius.sm, style: .continuous))
        }
        .padding(LinkaSpacing.md)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous)
                .stroke(Color.borderDefault.opacity(0.2), lineWidth: 1)
        )
    }

    private func copyToClipboard(text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        withAnimation(LinkaMotion.spring) {
            hasCopiedScript = true
        }

        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(LinkaMotion.fade) {
                    hasCopiedScript = false
                }
            }
        }
    }

    // MARK: - 6. Erro

    private func errorSection(error: LinkaGeniusError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.statusAttention)

            Text(LinkaCopy.value("genius.error.title"))
                .font(.displayMedium)
                .foregroundColor(.textPrimary)

            Text(error.localizedDescription)
                .font(.bodyRegular)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button(action: {
                viewModel.retry()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(LinkaCopy.value("genius.error.retry"))
                }
            }
            .buttonStyle(.linkaPrimary)
            .padding(.top, 4)

            Button(action: {
                viewModel.reset()
            }) {
                Text(LinkaCopy.value("common.back"))
                    .font(.bodySmallStrong)
                    .foregroundColor(.brandAccentWarmInk)
            }
            .buttonStyle(.plain)
        }
        .padding(LinkaSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: LinkaRadius.lg, style: .continuous))
    }

    // MARK: - 7. Rodapé

    private var footerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.brandAccentWarm)
                .accessibilityHidden(true)
            Text(LinkaCopy.value("genius.footer.attribution"))
                .font(.caption2)
                .foregroundColor(.textSecondary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

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
}
