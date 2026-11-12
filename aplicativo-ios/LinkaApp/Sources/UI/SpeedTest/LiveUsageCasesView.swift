import SwiftUI
import NetworkCore
import NetworkInsights

/// Componente visual para exibição dos casos de uso calculados ao vivo (tempo real).
///
/// Projetado para a tela Início (Idle) do iOS e painel lateral do macOS,
/// oferecendo leitura imediata sem competir visualmente com o CTA primário de teste.
struct LiveUsageCasesView: View {
    let report: LiveUsageSuitabilityReport?
    var cases: [UsageCase] = [.videoCall, .onlineGaming]
    var isEmbedded: Bool = false
    var onSelect: ((UsageCase) -> Void)? = nil

    var body: some View {
        let content = VStack(spacing: 0) {
            ForEach(cases, id: \.self) { usageCase in
                node(for: usageCase)
                if usageCase != cases.last {
                    Divider().overlay(Color.borderDefault.opacity(0.55))
                }
            }
        }

        if isEmbedded {
            content
        } else {
            content
                .linkaCard(cornerRadius: LinkaRadius.lg)
        }
    }

    @ViewBuilder
    private func node(for usageCase: UsageCase) -> some View {
        let verdict = report?.verdict(for: usageCase)
        let isActionable = onSelect != nil
        let title = isEmbedded && usageCase == .videoCall
            ? LinkaCopy.value("home.live.calls")
            : UsageSuitabilityCopy.title(for: usageCase)
        let badge: (label: String, color: Color, icon: String) = {
            if let verdict {
                return UsageSuitabilityCopy.liveStatusBadge(for: verdict)
            } else {
                return (LinkaCopy.value("usage.live.measuring"), .textSecondary, "ellipsis")
            }
        }()

        let content = HStack(spacing: 14) {
            Image(systemName: UsageSuitabilityCopy.iconName(for: usageCase))
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.textPrimary)
                .frame(width: 46, height: 46)
                .background(Color.surfacePage.opacity(isEmbedded ? 0.7 : 1), in: Circle())

            Text(title)
                .font(.bodyRegular)
                .foregroundColor(.textPrimary)
            Spacer(minLength: 8)

            if verdict?.level == .adequate {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.statusGood)
            } else if isActionable {
                Image(systemName: "chevron.right")
                    .font(.captionSmallStrong)
                    .foregroundColor(.textSecondary)
            } else {
                Image(systemName: "minus.circle")
                    .font(.bodyRegular)
                    .foregroundColor(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isEmbedded ? 70 : 64)
        .padding(.horizontal, 4)

        if isActionable {
            Button { onSelect?(usageCase) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title): \(badge.label)")
                .accessibilityHint(verdict.map { UsageSuitabilityCopy.liveDetail(for: $0) } ?? "")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title): \(badge.label)")
                .accessibilityHint(verdict.map { UsageSuitabilityCopy.liveDetail(for: $0) } ?? "")
        }
    }
}
