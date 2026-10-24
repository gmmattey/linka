import SwiftUI

/// Linha descritiva de benefício do WiFi Casa Pro.
/// Respeita alvos de toque >= 44 pt, Dynamic Type e superfícies tonais sem bordas.
public struct ProBenefitRow: View {
    public let icon: String
    public let title: String
    public let subtitle: String

    public init(icon: String, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(WiFiCasaTheme.brandAccent)
                .frame(width: 32, height: 32)
                .background(WiFiCasaTheme.backgroundOverlay)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(WiFiCasaTheme.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 44) // A11y Touch Target
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        WiFiCasaTheme.backgroundRaised
        ProBenefitRow(
            icon: "viewfinder",
            title: "Escaneamento 3D com LiDAR",
            subtitle: "Capture as medidas e cômodos exatos da sua casa em segundos usando os sensores do iPhone Pro."
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
