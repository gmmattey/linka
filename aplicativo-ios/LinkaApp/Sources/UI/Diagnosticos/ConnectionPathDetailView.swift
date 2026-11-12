import SwiftUI
import NetworkInsights

/// Tela dedicada do Caminho da Conexão.
/// Apresenta o diagnóstico de cada uma das 5 etapas da rede em formato de lista nativa.
struct ConnectionPathDetailView: View {
    let report: ConnectionPathReport
    @Environment(\.dismiss) private var dismiss

    private var visibleStages: [ConnectionPathStage] {
        report.stages.map { $0.stage }
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
                        Text("connectionPath.diagnosis")
                            .font(.captionSmallStrong)
                            .foregroundColor(.textSecondary)
                            .textCase(.uppercase)

                        Text(ConnectionPathCopy.conclusion(for: report))
                            .font(.bodyRegularStrong)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                Section("connectionPath.stages") {
                    ForEach(visibleStages, id: \.self) { stage in
                        if let verdict = report.verdict(for: stage) {
                            stageRow(verdict: verdict, isHighlighted: report.highlightedStage == stage)
                        }
                    }
                }
            }
            .linkaGradientScreenBackground()
            .linkaSheetToolbar(title: LinkaCopy.value("connectionPath.title")) { dismiss() }
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        MacSheetScaffold(
            title: LinkaCopy.value("connectionPath.title"),
            systemImage: "point.3.connected.trianglepath.dotted",
            tint: MacPalette.upload,
            onClose: { dismiss() }
        ) {
            MacBanner(
                systemImage: "stethoscope",
                tint: MacPalette.upload,
                title: LinkaCopy.value("connectionPath.diagnosis"),
                message: ConnectionPathCopy.conclusion(for: report)
            )
            VStack(alignment: .leading, spacing: 12) {
                Text(LinkaCopy.value("connectionPath.stages")).font(MacType.section)
                VStack(spacing: 16) {
                    ForEach(Array(visibleStages.enumerated()), id: \.element) { index, stage in
                        if let verdict = report.verdict(for: stage) {
                            macStageCard(index: index + 1, verdict: verdict, isHighlighted: report.highlightedStage == stage)
                        }
                    }
                }
            }
        }
    }

    private func macStageCard(index: Int, verdict: ConnectionPathStageVerdict, isHighlighted: Bool) -> some View {
        let tint = statusColor(verdict.status)
        return HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: ConnectionPathCopy.icon(for: verdict.stage))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(index). \(ConnectionPathCopy.title(for: verdict.stage))").font(MacType.headline)
                    Spacer()
                    Image(systemName: ConnectionPathCopy.statusSymbol(for: verdict.status))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(ConnectionPathCopy.explanation(for: verdict))
                    .font(MacType.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .linkaMacCard()
        .overlay(alignment: .topTrailing) {
            if isHighlighted {
                MacStatusTag(label: LinkaCopy.value("Ponto de atenção"), color: tint).padding(12).offset(y: -2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ConnectionPathCopy.title(for: verdict.stage)): \(ConnectionPathCopy.statusAccessibilityLabel(verdict.status)). \(ConnectionPathCopy.explanation(for: verdict))")
    }
    #endif

    @ViewBuilder
    private func stageRow(verdict: ConnectionPathStageVerdict, isHighlighted: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: ConnectionPathCopy.icon(for: verdict.stage))
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isHighlighted ? statusColor(verdict.status) : .textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(statusColor(verdict.status).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(ConnectionPathCopy.title(for: verdict.stage))
                        .font(.bodyRegularStrong)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Image(systemName: ConnectionPathCopy.statusSymbol(for: verdict.status))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(statusColor(verdict.status))
                }

                Text(ConnectionPathCopy.explanation(for: verdict))
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ConnectionPathCopy.title(for: verdict.stage)): \(ConnectionPathCopy.statusAccessibilityLabel(verdict.status)). \(ConnectionPathCopy.explanation(for: verdict))")
    }

    private func statusColor(_ status: ConnectionPathStageStatus) -> Color {
        switch status {
        case .normal: return .statusGood
        case .attention: return .statusAttention
        case .likelyProblem: return .statusCritical
        case .unavailable: return .textSecondary
        }
    }
}
