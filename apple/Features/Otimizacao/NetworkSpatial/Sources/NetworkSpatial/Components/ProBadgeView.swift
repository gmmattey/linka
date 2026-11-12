import SwiftUI

/// Badge discreta indicadora de funcionalidade Pro no WiFi Casa.
/// Construída em Camada 2 (#2C2C2E) com acento Roxo Gamer, sem bordas ou contornos.
public struct ProBadgeView: View {
    public var isCompact: Bool

    public init(isCompact: Bool = false) {
        self.isCompact = isCompact
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(isCompact ? .caption2.weight(.bold) : .caption.weight(.bold))
                .foregroundStyle(WiFiCasaTheme.brandAccent)

            Text("PRO")
                .font(isCompact ? .caption2.weight(.heavy) : .caption.weight(.heavy))
                .foregroundStyle(WiFiCasaTheme.brandAccent)
        }
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 2 : 4)
        .background(WiFiCasaTheme.backgroundOverlay)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recurso exclusivo do WiFi Casa Pro")
    }
}

#Preview {
    ZStack {
        WiFiCasaTheme.backgroundBase.ignoresSafeArea()
        VStack(spacing: 16) {
            ProBadgeView()
            ProBadgeView(isCompact: true)
        }
    }
    .preferredColorScheme(.dark)
}
