import SwiftUI

/// Aviso único, pós-resultado, sobre a reorganização de jitter/perda de
/// pacotes/DNS em "Modo Expert" (Plus) — decisão de produto de 2026-08-29.
/// Enquadra como reorganização (o que ficou grátis + o que é novo + o que
/// passou a ser Plus), não como remoção silenciosa. Só aparece depois do
/// primeiro resultado (nunca antes/durante a medição, AGENTS.md §6), uma
/// única vez por instalação, e só para quem via essas métricas de graça.
struct ExpertModeMigrationBanner: View {
    let onOpenPurchase: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("expert.banner.title")
                    .font(.bodySmallStrong)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.captionStrong)
                        .foregroundColor(.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.textSecondary.opacity(0.14))
                        .clipShape(Circle())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("expert.banner.close")
                }
            }

            Text("expert.banner.message")
                .font(.bodySmall)
                .foregroundColor(.textSecondary)

            Button(action: onOpenPurchase) {
                LinkaPlusWordmarkView(height: 18)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.borderDefault, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Estado do aviso único (`UserDefaults`, mesmo padrão de `FeatureFlags`) —
/// só dispara para quem nunca viu, e só depois do primeiro resultado.
enum ExpertModeMigrationBannerState {
    private static let key = "hasSeenExpertModeMigrationBanner"

    static func hasBeenSeen(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}
