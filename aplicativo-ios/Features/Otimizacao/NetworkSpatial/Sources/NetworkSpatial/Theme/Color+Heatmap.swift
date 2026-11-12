import SwiftUI

extension Color {
    /// Camada elevada para superfícies de cartões e blocos (idêntico a #1C1C1E no Lagcheck)
    public static var appSecondaryBackground: Color {
        WiFiCasaTheme.backgroundRaised
    }

    /// Camada para badges, pills e fundos de métricas (idêntico a #2C2C2E no Lagcheck)
    public static var appTertiaryFill: Color {
        WiFiCasaTheme.backgroundOverlay
    }

    /// Cor de destaque semântica do score/rating (Verde, Menta, Amarelo, Coral)
    public static func ratingColor(for rating: QualityRating) -> Color {
        switch rating {
        case .excellent:
            return WiFiCasaTheme.scoreExcellent
        case .good:
            return WiFiCasaTheme.scoreGood
        case .fair:
            return WiFiCasaTheme.scoreFair
        case .poor:
            return WiFiCasaTheme.scorePoor
        case .unmeasured:
            return WiFiCasaTheme.scoreNeutral
        }
    }

    /// Matiz translúcido sutil para profundidade em superfícies elevadas (sem bordas)
    public static func ratingBackground(for rating: QualityRating) -> Color {
        switch rating {
        case .excellent:
            return WiFiCasaTheme.scoreExcellentSubtle
        case .good:
            return WiFiCasaTheme.scoreGoodSubtle
        case .fair:
            return WiFiCasaTheme.scoreFairSubtle
        case .poor:
            return WiFiCasaTheme.scorePoorSubtle
        case .unmeasured:
            return Color.clear
        }
    }
}
