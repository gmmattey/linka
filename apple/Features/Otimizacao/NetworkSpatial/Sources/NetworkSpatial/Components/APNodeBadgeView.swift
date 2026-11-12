import SwiftUI

/// Badge visual para nós residenciais (Roteador, Nó Mesh e Repetidor).
/// Suporta acessibilidade total e independência de cor através da união de cor semântica, ícone SF Symbol e texto descritivo.
public struct APNodeBadgeView: View {
    public let type: AccessPointType
    public var customName: String?
    public var isCompact: Bool

    public init(
        type: AccessPointType,
        customName: String? = nil,
        isCompact: Bool = false
    ) {
        self.type = type
        self.customName = customName
        self.isCompact = isCompact
    }

    public var body: some View {
        if type.isAccessPoint {
            HStack(spacing: isCompact ? 4 : 6) {
                Image(systemName: type.systemImage)
                    .font(isCompact ? .caption2 : .caption)
                    .fontWeight(.bold)
                    .foregroundStyle(type.semanticColor)

                Text(isCompact ? (customName ?? type.shortLabel) : (customName ?? type.label))
                    .font(isCompact ? .caption2 : .caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, isCompact ? 6 : 8)
            .padding(.vertical, isCompact ? 3 : 4)
            .background(WiFiCasaTheme.backgroundOverlay)
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(type.accessibilityDescription)
        }
    }
}

#Preview {
    ZStack {
        WiFiCasaTheme.backgroundBase.ignoresSafeArea()
        VStack(spacing: 12) {
            APNodeBadgeView(type: .mainRouter)
            APNodeBadgeView(type: .meshSatellite, customName: "Satélite Corredor")
            APNodeBadgeView(type: .repeater)
            APNodeBadgeView(type: .meshSatellite, isCompact: true)
        }
    }
    .preferredColorScheme(.dark)
}
