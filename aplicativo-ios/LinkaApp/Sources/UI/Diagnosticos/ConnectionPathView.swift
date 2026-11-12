import SwiftUI
import NetworkInsights
import NetworkCore

/// Contexto factual antes de haver uma medição. Ao contrário de
/// `ConnectionPathView`, não avalia saúde de roteador, operadora ou internet:
/// apenas representa a rota que o sistema expõe neste instante.
struct LiveConnectionPathView: View {
    let kind: NetworkConnectionKind?
    let label: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var interfaceIcon: String {
        switch kind {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        case .other: return "network"
        case nil: return "wifi.exclamationmark"
        }
    }

    private var interfaceLabel: String {
        if !label.isEmpty { return label }
        switch kind {
        case .wifi: return LinkaCopy.value("network.wifi")
        case .cellular: return LinkaCopy.value("network.cellular")
        case .ethernet: return LinkaCopy.value("network.ethernet")
        case .other: return LinkaCopy.value("network.connection")
        case nil: return LinkaCopy.value("network.offline")
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    pathRow(icon: "iphone", label: LinkaCopy.value("connectionPath.thisDevice"))
                    pathRow(icon: interfaceIcon, label: interfaceLabel)
                    pathRow(icon: "globe", label: LinkaCopy.value("connectionPath.internet"), muted: kind == nil)
                }
            } else {
                HStack(spacing: 0) {
                    pathItem(icon: "iphone", label: LinkaCopy.value("connectionPath.thisDevice"))
                    pathArrow
                    pathItem(icon: interfaceIcon, label: interfaceLabel)
                    pathArrow
                    pathItem(icon: "globe", label: LinkaCopy.value("connectionPath.internet"), muted: kind == nil)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 6)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LinkaCopy.format("connectionPath.live.accessibility", interfaceLabel))
    }

    private var pathArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.textSecondary.opacity(0.48))
            .frame(width: 15)
    }

    private func pathItem(icon: String, label: String, muted: Bool = false) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 30, height: 30)
                .background(Color.surfacePage, in: Circle())
            Text(label)
                .font(.captionSmall)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(muted ? .textSecondary : .textPrimary)
        .frame(maxWidth: .infinity)
    }

    private func pathRow(icon: String, label: String, muted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 32)

            Text(label)
                .font(.body)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundColor(muted ? .textSecondary : .textPrimary)
    }
}

/// Caminho da Conexão — leitura visual simplificada de "onde provavelmente
/// está o problema", entre o diagnóstico curto e as ações de navegação.
///
/// Mostra a sequência de 5 etapas com glifos discretos:
/// iPhone → Wi-Fi → Roteador → Operadora → Internet
/// Ao tocar, navega diretamente para `ConnectionPathDetailView`.
struct ConnectionPathView: View {
    let report: ConnectionPathReport
    var onOpen: (() -> Void)? = nil

    private var visibleStages: [ConnectionPathStage] {
        report.stages.map { $0.stage }
    }

    var body: some View {
        Button(action: { onOpen?() }) {
            HStack(spacing: 0) {
                ForEach(Array(visibleStages.enumerated()), id: \.element) { index, stage in
                    if let verdict = report.verdict(for: stage) {
                        stageGlyph(verdict, highlighted: report.highlightedStage == stage)
                        if index < visibleStages.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textSecondary.opacity(0.35))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ConnectionPathCopy.accessibilitySummary(for: report))
        .accessibilityHint(LinkaCopy.value("connectionPath.open.hint"))
    }

    @ViewBuilder
    private func stageGlyph(_ verdict: ConnectionPathStageVerdict, highlighted: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: ConnectionPathCopy.icon(for: verdict.stage))
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(highlighted ? statusColor(verdict.status) : .textSecondary)

            Image(systemName: ConnectionPathCopy.statusSymbol(for: verdict.status))
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(statusColor(verdict.status))
                .background(Circle().fill(Color.surfacePage).frame(width: 11, height: 11))
                .offset(x: 5, y: 4)
        }
        .frame(width: 26, height: 26)
        .frame(maxWidth: .infinity)
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

/// Copy do Caminho da Conexão — vive só na UI.
enum ConnectionPathCopy {
    static let orderedStages: [ConnectionPathStage] = [.device, .wifi, .router, .carrier, .internet]

    static func title(for stage: ConnectionPathStage) -> String {
        switch stage {
        case .device:
            #if os(macOS)
            return LinkaCopy.value("connectionPath.stage.device.mac")
            #else
            return LinkaCopy.value("connectionPath.stage.device")
            #endif
        case .wifi: return LinkaCopy.value("connectionPath.stage.wifi")
        case .router: return LinkaCopy.value("connectionPath.stage.router")
        case .carrier: return LinkaCopy.value("connectionPath.stage.carrier")
        case .internet: return LinkaCopy.value("connectionPath.stage.internet")
        }
    }

    static func icon(for stage: ConnectionPathStage) -> String {
        switch stage {
        case .device:
            #if os(macOS)
            return "laptopcomputer"
            #else
            return "iphone"
            #endif
        case .wifi: return "wifi"
        case .router: return "wifi.router"
        case .carrier: return "antenna.radiowaves.left.and.right"
        case .internet: return "globe"
        }
    }

    static func statusSymbol(for status: ConnectionPathStageStatus) -> String {
        switch status {
        case .normal: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .likelyProblem: return "xmark.circle.fill"
        case .unavailable: return "questionmark.circle.fill"
        }
    }

    static func statusAccessibilityLabel(_ status: ConnectionPathStageStatus) -> String {
        switch status {
        case .normal: return LinkaCopy.value("connectionPath.status.normal")
        case .attention: return LinkaCopy.value("connectionPath.status.attention")
        case .likelyProblem: return LinkaCopy.value("connectionPath.status.problem")
        case .unavailable: return LinkaCopy.value("connectionPath.status.unavailable")
        }
    }

    private static let explanationKeys: [ConnectionPathStage: [ConnectionPathStageStatus: String]] = [
        .device: [
            .normal: "connectionPath.explanation.device.normal"
        ],
        .wifi: [
            .normal: "connectionPath.explanation.wifi.normal",
            .attention: "connectionPath.explanation.wifi.attention",
            .likelyProblem: "connectionPath.explanation.wifi.problem",
            .unavailable: "connectionPath.explanation.unavailable"
        ],
        .router: [
            .normal: "connectionPath.explanation.router.normal",
            .attention: "connectionPath.explanation.router.attention",
            .likelyProblem: "connectionPath.explanation.router.problem",
            .unavailable: "connectionPath.explanation.unavailable"
        ],
        .carrier: [
            .normal: "connectionPath.explanation.carrier.normal",
            .attention: "connectionPath.explanation.carrier.attention",
            .likelyProblem: "connectionPath.explanation.carrier.problem",
            .unavailable: "connectionPath.explanation.unavailable"
        ],
        .internet: [
            .normal: "connectionPath.explanation.internet.normal",
            .attention: "connectionPath.explanation.internet.attention",
            .likelyProblem: "connectionPath.explanation.internet.problem",
            .unavailable: "connectionPath.explanation.unavailable"
        ]
    ]

    static func explanation(for verdict: ConnectionPathStageVerdict) -> String {
        let key = explanationKeys[verdict.stage]?[verdict.status]
            ?? explanationKeys[verdict.stage]?[.unavailable]
            ?? "connectionPath.explanation.unavailable"
        return LinkaCopy.value(key)
    }

    /// Diagnóstico curto para a tela principal (Apple-style)
    static func shortConclusion(for report: ConnectionPathReport) -> String {
        switch report.category {
        case .healthy:
            return LinkaCopy.value("connectionPath.shortConclusion.healthy")
        case .inconclusive:
            return LinkaCopy.value("connectionPath.shortConclusion.inconclusive")
        case .local:
            return LinkaCopy.value("connectionPath.shortConclusion.local")
        case .wifi:
            return LinkaCopy.value("connectionPath.shortConclusion.wifi")
        case .carrier:
            return LinkaCopy.value("connectionPath.shortConclusion.carrier")
        case .external:
            return LinkaCopy.value("connectionPath.shortConclusion.external")
        }
    }

    /// Frase detalhada de conclusão (usada em telas de detalhe e acessibilidade)
    static func conclusion(for report: ConnectionPathReport) -> String {
        switch report.category {
        case .healthy:
            return LinkaCopy.value("connectionPath.conclusion.healthy")
        case .inconclusive:
            return LinkaCopy.value("connectionPath.conclusion.inconclusive")
        case .local:
            return LinkaCopy.value("connectionPath.conclusion.local")
        case .wifi:
            if report.highlightedStage == .router {
                return LinkaCopy.value("connectionPath.conclusion.wifi.router")
            }
            return LinkaCopy.value("connectionPath.conclusion.wifi")
        case .carrier:
            return LinkaCopy.value("connectionPath.conclusion.carrier")
        case .external:
            return LinkaCopy.value("connectionPath.conclusion.external")
        }
    }

    static func accessibilitySummary(for report: ConnectionPathReport) -> String {
        let visibleStages = report.stages.map { $0.stage }
        let stagesText = visibleStages.compactMap { stage -> String? in
            guard let verdict = report.verdict(for: stage) else { return nil }
            return "\(title(for: stage)): \(statusAccessibilityLabel(verdict.status))"
        }.joined(separator: ". ")
        return LinkaCopy.format("connectionPath.accessibility.summary", stagesText, conclusion(for: report))
    }
}
