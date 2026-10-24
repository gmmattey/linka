import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Sistema de tokens visuais e profundidade para cobertura espacial.
/// Compartilha o mesmo tom e superfícies elevadas do Lagcheck e Linka.
public enum WiFiCasaTheme {
    // MARK: - Superfícies & Camadas de Profundidade (Sem Bordas)

    /// Camada 0: Fundo base do app (Preto puro `#000000` em Dark Mode, como no Lagcheck).
    public static var backgroundBase: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor.black : UIColor.systemGroupedBackground
        })
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Camada 1: Superfície elevada para cards e seções (`#1C1C1E` em Dark Mode, idêntico a NLColor.backgroundRaised).
    public static var backgroundRaised: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1.0)
                : UIColor.secondarySystemGroupedBackground
        })
        #else
        return Color.secondary.opacity(0.1)
        #endif
    }

    /// Camada 2: Superfície para badges, pills e controles secundários (`#2C2C2E` em Dark Mode).
    public static var backgroundOverlay: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1.0)
                : UIColor.tertiarySystemGroupedBackground
        })
        #else
        return Color.secondary.opacity(0.18)
        #endif
    }

    /// Camada de controle e interação translúcida.
    public static let controlOverlay = Color.white.opacity(0.08)

    // MARK: - Tipografia & Contraste

    public static let textPrimary = Color.primary

    /// Texto secundário (#8E8E93 em Dark Mode, com contraste AA garantido).
    public static var textSecondary: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1.0)
                : UIColor.secondaryLabel
        })
        #else
        return Color.secondary
        #endif
    }

    /// Texto terciário e auxiliar (#8A8A8E em Dark Mode).
    public static var textTertiary: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 138 / 255, green: 138 / 255, blue: 142 / 255, alpha: 1.0)
                : UIColor.tertiaryLabel
        })
        #else
        return Color.secondary.opacity(0.7)
        #endif
    }

    // MARK: - Identidade da Marca (Tom Coral Solar de Linka & Lagcheck)

    /// Coral Solar / Laranja de Conectividade Linka (#FF6B35 / #FF7A3D)
    public static let brandAccent = Color(red: 255 / 255, green: 107 / 255, blue: 53 / 255) // #FF6B35 (Coral Solar)
    public static let brandAccentWarm = Color(red: 255 / 255, green: 122 / 255, blue: 61 / 255) // #FF7A3D (Linka)
    public static let brandAccentSubtle = brandAccent.opacity(0.15)

    /// Gradiente Coral Solar oficial (Lagcheck & Linka: #FF3823 -> #FF6B35 -> #FFAB2E)
    public static let coralSolarGradient = LinearGradient(
        colors: [
            Color(red: 255 / 255, green: 56 / 255, blue: 35 / 255),  // #FF3823
            Color(red: 255 / 255, green: 107 / 255, blue: 53 / 255), // #FF6B35
            Color(red: 255 / 255, green: 171 / 255, blue: 46 / 255)  // #FFAB2E
        ],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )

    // MARK: - Escala Semântica de Qualidade (Mesmo Tom do Lagcheck, Alta Luminância Dark Mode)

    public static let scoreExcellent = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)       // #30D158 (Verde Apple HIG Vibrante)
    public static let scoreGood = Color(red: 100 / 255, green: 210 / 255, blue: 255 / 255)         // #64D2FF (Ciano Apple HIG Vibrante)
    public static let scoreFair = Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255)          // #FFD60A (Amarelo Apple HIG)
    public static let scorePoor = Color(red: 255 / 255, green: 95 / 255, blue: 85 / 255)           // #FF5F55 (Coral/Vermelho Vibrante Apple)
    public static let scoreNeutral = textSecondary

    public static let scoreExcellentSubtle = scoreExcellent.opacity(0.14)
    public static let scoreGoodSubtle = scoreGood.opacity(0.14)
    public static let scoreFairSubtle = scoreFair.opacity(0.14)
    public static let scorePoorSubtle = scorePoor.opacity(0.14)
    public static let scoreNeutralSubtle = textSecondary.opacity(0.12)
}

public typealias SpatialTheme = WiFiCasaTheme
