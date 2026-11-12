import SwiftUI

/// Card de seleção de problema para a Home B2C (Design System Linka)
/// Camada 1 tonal (#1C1C1E), sem traços de borda, touch target >= 44pt e Dynamic Type.
public struct ProblemCardView: View {
    public let problem: HomeProblemCase
    public var isEnabled: Bool = true
    public let onTap: () -> Void

    public init(problem: HomeProblemCase, isEnabled: Bool = true, onTap: @escaping () -> Void) {
        self.problem = problem
        self.isEnabled = isEnabled
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: {
            if isEnabled {
                onTap()
            }
        }) {
            HStack(spacing: 14) {
                // Ícone na Camada 2 translúcida
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WiFiCasaTheme.backgroundOverlay)
                        .frame(width: 44, height: 44)

                    Image(systemName: problem.icon)
                        .font(.title3)
                        .foregroundStyle(isEnabled ? WiFiCasaTheme.brandAccent : WiFiCasaTheme.textTertiary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(problem.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(isEnabled ? WiFiCasaTheme.textPrimary : WiFiCasaTheme.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(problem.subtitle)
                        .font(.caption)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WiFiCasaTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 54)
            .background(WiFiCasaTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(problem.title). \(problem.subtitle)")
        .accessibilityHint(isEnabled ? "Toque para iniciar diagnóstico guiado deste problema" : "Indisponível: conecte-se ao Wi-Fi para diagnosticar")
    }
}
