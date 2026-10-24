import SwiftUI

public struct CoverageHeaderView: View {
    public let house: House
    public let isWiFiActive: Bool
    public let currentSSID: String
    public let onHelpTap: () -> Void

    public init(
        house: House,
        isWiFiActive: Bool,
        currentSSID: String,
        onHelpTap: @escaping () -> Void
    ) {
        self.house = house
        self.isWiFiActive = isWiFiActive
        self.currentSSID = currentSSID
        self.onHelpTap = onHelpTap
    }

    private var coveragePercent: Int {
        house.totalCoveragePercent
    }

    private var measuredCount: Int {
        house.rooms.compactMap(\.lastMeasurement).count
    }

    private var totalRooms: Int {
        house.rooms.count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Linha superior: Nome da casa e status do Wi-Fi
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(house.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(isWiFiActive ? WiFiCasaTheme.scoreExcellent : WiFiCasaTheme.scorePoor)
                            .frame(width: 8, height: 8)

                        Text(isWiFiActive ? currentSSID : "Wi-Fi Desconectado")
                            .font(.subheadline)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                    }
                }

                Spacer()

                Button(action: onHelpTap) {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)
                }
                .frame(width: 44, height: 44) // A11y Touch Target
                .accessibilityLabel("Ajuda e dicas de posicionamento do roteador")
            }

            // Cartão de Resumo de Qualidade Média — Profundidade pura em superfície elevada sem bordas
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QUALIDADE NOS PONTOS MEDIDOS")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(WiFiCasaTheme.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(coveragePercent)")
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(WiFiCasaTheme.textPrimary)
                            .monospacedDigit()

                        Text("%")
                            .font(.headline)
                            .foregroundStyle(WiFiCasaTheme.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(measuredCount) de \(totalRooms) cômodos")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(WiFiCasaTheme.textPrimary)

                    // Barra de progresso com track na Camada 2 (backgroundOverlay) e fill no azul da marca
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(WiFiCasaTheme.backgroundOverlay)
                                .frame(height: 6)

                            Capsule()
                                .fill(WiFiCasaTheme.brandAccent)
                                .frame(width: totalRooms > 0 ? geo.size.width * CGFloat(measuredCount) / CGFloat(totalRooms) : 0, height: 6)
                        }
                    }
                    .frame(width: 120, height: 6)
                }
            }
            .padding(16)
            .background(WiFiCasaTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(house.name). Qualidade média de \(coveragePercent) por cento em \(measuredCount) de \(totalRooms) cômodos avaliados.")
    }
}
