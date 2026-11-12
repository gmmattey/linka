import Foundation

public enum LinkaWidgetShared {
    public static let appGroupIdentifier = "group.com.linka.assist"
    public static let widgetKind = "LinkaSpeedTestWidget"
    private static let latestSummaryKey = "com.linka.speedtest.widget.latestSummary"
    public static let languagePreferenceKey = "linka.language.preference.v1"

    /// Persists the app language choice where the app and widget can both read it.
    /// `system` deliberately means the device's current language, not Portuguese.
    public static func writeLanguagePreference(
        _ preference: String,
        userDefaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    ) {
        userDefaults?.set(preference, forKey: languagePreferenceKey)
    }

    public static func languagePreference(
        userDefaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    ) -> String {
        guard let value = userDefaults?.string(forKey: languagePreferenceKey),
              ["system", "pt-BR", "en", "es-419"].contains(value) else {
            return "system"
        }
        return value
    }

    public static func effectiveLocale(
        preference: String,
        systemLocale: Locale = .autoupdatingCurrent
    ) -> Locale {
        switch preference {
        case "pt-BR": return Locale(identifier: "pt-BR")
        case "en": return Locale(identifier: "en")
        case "es-419": return Locale(identifier: "es-419")
        default:
            // Linka currently ships these three localizations. Keep System
            // faithful whenever it is supported, and use English as the
            // predictable international fallback until another catalog lands.
            switch systemLocale.language.languageCode?.identifier.lowercased() {
            case "pt": return Locale(identifier: "pt-BR")
            case "es": return Locale(identifier: "es-419")
            case "en": return Locale(identifier: "en")
            default: return Locale(identifier: "en")
            }
        }
    }

    public static func effectiveLanguageTag(
        preference: String,
        systemLocale: Locale = .autoupdatingCurrent
    ) -> String {
        switch preference {
        case "pt-BR", "en", "es-419":
            return preference
        default:
            switch systemLocale.language.languageCode?.identifier.lowercased() {
            case "pt": return "pt-BR"
            case "es": return "es-419"
            default: return "en"
            }
        }
    }

    public struct LatestMeasurementSummary: Codable, Equatable, Sendable {
        public let downloadMbps: Double
        public let uploadMbps: Double?
        public let latencyMs: Double?
        public let measuredAt: Date

        public init(
            downloadMbps: Double,
            uploadMbps: Double?,
            latencyMs: Double?,
            measuredAt: Date
        ) {
            self.downloadMbps = downloadMbps
            self.uploadMbps = uploadMbps
            self.latencyMs = latencyMs
            self.measuredAt = measuredAt
        }
    }

    public static func writeLatestSummary(
        _ summary: LatestMeasurementSummary,
        userDefaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    ) {
        guard let defaults = userDefaults,
              let data = try? JSONEncoder().encode(summary) else { return }
        defaults.set(data, forKey: latestSummaryKey)
    }

    public static func readLatestSummary(
        userDefaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    ) -> LatestMeasurementSummary? {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: latestSummaryKey) else { return nil }
        return try? JSONDecoder().decode(LatestMeasurementSummary.self, from: data)
    }
}
