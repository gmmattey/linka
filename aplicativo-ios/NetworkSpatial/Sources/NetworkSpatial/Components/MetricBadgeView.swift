import SwiftUI

public struct MetricBadgeView: View {
    public let title: String
    public let value: String
    public let unit: String
    public let systemImage: String?

    public init(title: String, value: String, unit: String = "", systemImage: String? = nil) {
        self.title = title
        self.value = value
        self.unit = unit
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(WiFiCasaTheme.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(WiFiCasaTheme.textPrimary)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Camada 2: backgroundOverlay para badges com profundidade, sem bordas
        .background(WiFiCasaTheme.backgroundOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
