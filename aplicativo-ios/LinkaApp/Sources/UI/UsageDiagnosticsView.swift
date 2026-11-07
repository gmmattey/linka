import SwiftUI
import NetworkCore
import NetworkInsights

/// Tela de Diagnóstico de Adequação por Uso.
/// Apresenta a qualidade da rede para cada caso de uso em uma List nativa.
struct UsageDiagnosticsView: View {
    let measurement: NetworkMeasurement?
    @Environment(\.dismiss) private var dismiss

    private var report: UsageSuitabilityReport? {
        guard let measurement else { return nil }
        return UsageSuitabilityEvaluator().evaluate(measurement)
    }

    private var summarySubtitle: String {
        guard let report else { return LinkaCopy.value("usage.summary.noMeasurement") }
        let quality = UsageSuitabilityCopy.qualityLevel(for: report)
        switch quality {
        case .good:
            return LinkaCopy.value("usage.summary.good")
        case .medium:
            return LinkaCopy.value("usage.summary.medium")
        case .poor:
            return LinkaCopy.value("usage.summary.poor")
        case nil:
            return LinkaCopy.value("usage.summary.default")
        }
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
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LinkaCopy.value("usage.summary.title"))
                            .font(.captionSmallStrong)
                            .foregroundColor(.textSecondary)
                            .textCase(.uppercase)

                        Text(summarySubtitle)
                            .font(.bodyRegularStrong)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                if let report {
                    Section(LinkaCopy.value("usage.cases")) {
                        ForEach(UsageCase.allCases, id: \.self) { usageCase in
                            if let verdict = report.verdict(for: usageCase) {
                                UsageVerdictRow(usageCase: usageCase, verdict: verdict)
                            }
                        }
                    }
                } else {
                    Section {
                        LinkaUnavailableState(
                            title: LinkaCopy.value("usage.noMeasurement.title"),
                            message: LinkaCopy.value("usage.noMeasurement.message"),
                            systemImage: "speedometer"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .linkaGradientScreenBackground()
            .linkaSheetToolbar(title: LinkaCopy.value("usage.title")) { dismiss() }
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        MacSheetScaffold(
            title: LinkaCopy.value("usage.title"),
            systemImage: "speedometer",
            onClose: { dismiss() }
        ) {
            if let report {
                let quality = UsageSuitabilityCopy.qualityLevel(for: report)
                MacBanner(
                    systemImage: quality == .poor ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                    tint: quality == .poor ? .statusAttention : (quality == .medium ? .statusAttention : .statusGood),
                    title: summarySubtitle
                )
                VStack(alignment: .leading, spacing: 12) {
                    Text(LinkaCopy.value("usage.cases")).font(MacType.section)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(UsageCase.allCases, id: \.self) { usageCase in
                            if let verdict = report.verdict(for: usageCase) {
                                MacUsageVerdictCard(usageCase: usageCase, verdict: verdict)
                            }
                        }
                    }
                }
            } else {
                MacBanner(
                    systemImage: "speedometer", tint: MacPalette.download,
                    title: LinkaCopy.value("usage.noMeasurement.title"),
                    message: LinkaCopy.value("usage.noMeasurement.message")
                )
            }
        }
    }
    #endif
}

#if os(macOS)
private struct MacUsageVerdictCard: View {
    let usageCase: UsageCase
    let verdict: UsageCaseVerdict

    private var tint: Color {
        switch verdict.level {
        case .adequate: return .statusGood
        case .limited: return .statusAttention
        case .notAssessed: return .textSecondary
        }
    }

    private var label: String {
        switch verdict.level {
        case .adequate: return LinkaCopy.value("usage.status.adequate")
        case .limited: return LinkaCopy.value("usage.status.limited")
        case .notAssessed: return LinkaCopy.value("usage.status.notAssessed")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MacIconBadge(systemImage: UsageSuitabilityCopy.iconName(for: usageCase), tint: tint, size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(UsageSuitabilityCopy.title(for: usageCase)).font(MacType.headline)
                    MacStatusTag(label: label, color: tint)
                }
                Spacer(minLength: 0)
            }
            let detail = UsageSuitabilityCopy.detail(for: verdict)
            if !detail.isEmpty {
                Text(detail)
                    .font(MacType.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .linkaMacCard()
        .accessibilityElement(children: .combine)
    }
}
#endif

private struct UsageVerdictRow: View {
    let usageCase: UsageCase
    let verdict: UsageCaseVerdict

    private var badgeColor: Color {
        switch verdict.level {
        case .adequate: return .statusGood
        case .limited: return .statusAttention
        case .notAssessed: return .textSecondary
        }
    }

    private var statusIcon: String {
        switch verdict.level {
        case .adequate: return "checkmark.circle.fill"
        case .limited: return "exclamationmark.triangle.fill"
        case .notAssessed: return "questionmark.circle.fill"
        }
    }

    private var badgeLabel: String {
        switch verdict.level {
        case .adequate: return LinkaCopy.value("usage.status.adequate")
        case .limited: return LinkaCopy.value("usage.status.limited")
        case .notAssessed: return LinkaCopy.value("usage.status.notAssessed")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(UsageSuitabilityCopy.title(for: usageCase))
                    .font(.bodyRegularStrong)
                    .foregroundColor(.textPrimary)

                Spacer()

                HStack(spacing: 4) {
                    Text(badgeLabel)
                        .font(.bodySmallStrong)
                        .foregroundColor(badgeColor)

                    Image(systemName: statusIcon)
                        .font(.captionSmallStrong)
                        .foregroundColor(badgeColor)
                }
            }

            let detail = UsageSuitabilityCopy.detail(for: verdict)
            if !detail.isEmpty {
                Text(detail)
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(UsageSuitabilityCopy.title(for: usageCase)): \(badgeLabel). \(UsageSuitabilityCopy.detail(for: verdict))")
    }
}
