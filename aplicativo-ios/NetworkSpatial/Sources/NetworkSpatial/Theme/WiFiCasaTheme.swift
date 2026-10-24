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

    // MARK: - Identidade compartilhada com LagCheck

    /// Roxo Gamer oficial: ação, seleção, foco e progresso.
    public static let brandAccent = Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255) // #7C3AED
    public static let brandAccentWarm = Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255) // #A78BFA
    public static let brandAccentSubtle = brandAccent.opacity(0.15)

    /// Variação da marca para elementos que já pedem um gradiente local.
    public static let gamerPurpleGradient = LinearGradient(
        colors: [
            Color(red: 91 / 255, green: 33 / 255, blue: 182 / 255),  // #5B21B6
            brandAccent,                                               // #7C3AED
            brandAccentWarm                                            // #A78BFA
        ],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )

    // MARK: - Escala Semântica de Qualidade (Mesmo Tom do Lagcheck, Alta Luminância Dark Mode)

    public static let scoreExcellent = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)       // #22C55E
    public static let scoreGood = scoreExcellent
    public static let scoreFair = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)           // #F59E0B
    public static let scorePoor = Color(red: 255 / 255, green: 90 / 255, blue: 54 / 255)            // #FF5A36
    public static let scoreNeutral = textSecondary

    public static let scoreExcellentSubtle = scoreExcellent.opacity(0.14)
    public static let scoreGoodSubtle = scoreGood.opacity(0.14)
    public static let scoreFairSubtle = scoreFair.opacity(0.14)
    public static let scorePoorSubtle = scorePoor.opacity(0.14)
    public static let scoreNeutralSubtle = textSecondary.opacity(0.12)
}

public typealias SpatialTheme = WiFiCasaTheme
