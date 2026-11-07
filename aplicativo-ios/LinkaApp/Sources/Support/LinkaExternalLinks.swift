import Foundation
import SwiftUI
import LinkaWidgetShared

/// Destinos públicos do Linka. A base é única para que Ajustes, paywall e
/// futuras superfícies legais não divirjam silenciosamente.
enum LinkaExternalLinks {
    static let canonicalOrigin = URL(string: "https://linka-speedtest.web.app")!
    static let website = canonicalOrigin
    static let about = canonicalOrigin.appending(path: "sobre")
    static let howWeMeasure = canonicalOrigin.appending(path: "como-medimos")
    static let privacy = canonicalOrigin.appending(path: "privacidade")
    static let terms = canonicalOrigin.appending(path: "termos")
    static let support = canonicalOrigin.appending(path: "suporte")
    static let subscriptionManagement = URL(string: "https://apps.apple.com/account/subscriptions")!
}

/// Canal de distribuição do binário. O Mac baixado direto do site
/// (`LINKA_DIRECT_DOWNLOAD`) não passa pela App Store, então não vende nem
/// restaura o Linka Plus; a compra continua exclusiva da versão da loja.
enum LinkaDistribution {
    static var isDirectDownload: Bool {
        #if LINKA_DIRECT_DOWNLOAD
        true
        #else
        false
        #endif
    }

    static let appStoreListing = URL(string: "https://apps.apple.com/br/app/linka-wi-fi-e-internet/id6808479321")!
}

enum LinkaWiFiPreferences {
    static let identificationEnabledKey = "linka.wifi-identification.enabled.v1"
    static let advancedDiagnosticsEnabledKey = "linka.advanced-wifi.enabled.v1"
    static let advancedConfiguredKey = "linka.advanced-wifi.configured.v1"

    static var isIdentificationEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: identificationEnabledKey) != nil else { return true }
        return defaults.bool(forKey: identificationEnabledKey)
    }

    static var isAdvancedDiagnosticsEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: advancedDiagnosticsEnabledKey) != nil else { return true }
        return defaults.bool(forKey: advancedDiagnosticsEnabledKey)
    }
}

enum LinkaAdvancedWiFiIntegration {
    static let shortcutName = "Linka Wi-Fi Advanced"
    static let shortcutsAppURL = URL(string: "shortcuts://")!
    /// Template oficial publicado pela Buildea no iCloud Shortcuts.
    static let sharedShortcutURL = URL(string: "https://www.icloud.com/shortcuts/3f7b0f6b23924865b805177189c2638d")!
    /// A página oficial da Apple mostra o template e exige a confirmação de
    /// adição. O esquema `import-shortcut` só aceita arquivos .shortcut e
    /// não deve receber este link compartilhado do iCloud.
    static let importShortcutURL = sharedShortcutURL
    static let runShortcutURL = URL(string: "shortcuts://run-shortcut?name=Linka%20Wi-Fi%20Advanced")!
}

enum LinkaAdvancedWiFiSettingsState: Equatable {
    case requiresPlus
    case needsConfiguration
    case active
    case disabled

    var statusText: String {
        switch self {
        case .requiresPlus: return "Linka Plus"
        case .needsConfiguration: return "Configurar"
        case .active: return "Ativo"
        case .disabled: return "Desativado"
        }
    }

    static func state(hasEntitlement: Bool, configured: Bool, enabled: Bool) -> LinkaAdvancedWiFiSettingsState {
        guard hasEntitlement else { return .requiresPlus }
        guard configured else { return .needsConfiguration }
        return enabled ? .active : .disabled
    }
}

enum LinkaAppearancePreference: String, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Supported presentation languages. This is intentionally independent from
/// the device locale: selecting a language changes Linka only, while `system`
/// keeps following iOS as the user changes it.
enum LinkaLanguagePreference: String, CaseIterable, Identifiable {
    static let storageKey = "linka.language.preference.v1"

    case system
    case portugueseBrazil = "pt-BR"
    case english = "en"
    case spanishLatinAmerica = "es-419"

    var id: String { rawValue }

    var locale: Locale {
        LinkaWidgetShared.effectiveLocale(preference: rawValue)
    }

    static var currentLocale: Locale {
        fromStoredValue(UserDefaults.standard.string(forKey: storageKey) ?? system.rawValue).locale
    }

    /// BCP-47 tag used by remote copy contracts. It deliberately mirrors the
    /// app's effective locale instead of `Locale.current`, so a manual choice
    /// is honored even when the iPhone itself uses another language.
    static var currentLanguageTag: String {
        fromStoredValue(UserDefaults.standard.string(forKey: storageKey) ?? system.rawValue).languageTag
    }

    static func fromStoredValue(_ value: String) -> LinkaLanguagePreference {
        LinkaLanguagePreference(rawValue: value) ?? .system
    }

    var displayName: String {
        switch self {
        case .system: return String(localized: "settings.language.option.system", defaultValue: "Sistema")
        case .portugueseBrazil: return "Português (Brasil)"
        case .english: return "English"
        case .spanishLatinAmerica: return "Español (Latinoamérica)"
        }
    }

    var languageTag: String {
        languageTag(systemLocale: .autoupdatingCurrent)
    }

    func languageTag(systemLocale: Locale) -> String {
        switch self {
        case .system:
            switch systemLocale.language.languageCode?.identifier.lowercased() {
            case "pt": return "pt-BR"
            case "es": return "es-419"
            default: return "en"
            }
        case .portugueseBrazil, .english, .spanishLatinAmerica:
            return rawValue
        }
    }
}

enum LinkaAppVersion {
    static func displayString(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        let version = infoDictionary["CFBundleShortVersionString"] as? String
        let build = infoDictionary["CFBundleVersion"] as? String
        return "\(clean(version, fallback: "1.0.0")) (\(clean(build, fallback: "1")))"
    }

    private static func clean(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return fallback }
        return value
    }
}
