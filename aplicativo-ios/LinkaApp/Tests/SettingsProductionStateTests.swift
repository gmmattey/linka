import XCTest
import SwiftUI
import LinkaWidgetShared
#if canImport(CoreLocation)
import CoreLocation
#endif
@testable import LinkaApp

final class SettingsProductionStateTests: XCTestCase {
    func testExternalLinksUseCanonicalOriginAndSpecificPaths() {
        XCTAssertEqual(LinkaExternalLinks.canonicalOrigin.absoluteString, "https://linka-speedtest.web.app")
        XCTAssertEqual(LinkaExternalLinks.website.absoluteString, "https://linka-speedtest.web.app")
        XCTAssertEqual(LinkaExternalLinks.about.absoluteString, "https://linka-speedtest.web.app/sobre")
        XCTAssertEqual(LinkaExternalLinks.howWeMeasure.absoluteString, "https://linka-speedtest.web.app/como-medimos")
        XCTAssertEqual(LinkaExternalLinks.privacy.absoluteString, "https://linka-speedtest.web.app/privacidade")
        XCTAssertEqual(LinkaExternalLinks.terms.absoluteString, "https://linka-speedtest.web.app/termos")
        XCTAssertEqual(LinkaExternalLinks.support.absoluteString, "https://linka-speedtest.web.app/suporte")
    }

    func testAdvancedWiFiStateReflectsEntitlementConfigurationAndEnabledFlag() {
        XCTAssertEqual(
            LinkaAdvancedWiFiSettingsState.state(hasEntitlement: false, configured: false, enabled: true),
            .requiresPlus
        )
        XCTAssertEqual(
            LinkaAdvancedWiFiSettingsState.state(hasEntitlement: true, configured: false, enabled: true),
            .needsConfiguration
        )
        XCTAssertEqual(
            LinkaAdvancedWiFiSettingsState.state(hasEntitlement: true, configured: true, enabled: true),
            .active
        )
        XCTAssertEqual(
            LinkaAdvancedWiFiSettingsState.state(hasEntitlement: true, configured: true, enabled: false),
            .disabled
        )
    }

    func testAppearancePreferenceMapsToSystemLightAndDark() {
        XCTAssertNil(LinkaAppearancePreference.system.colorScheme)
        XCTAssertEqual(LinkaAppearancePreference.light.colorScheme, .light)
        XCTAssertEqual(LinkaAppearancePreference.dark.colorScheme, .dark)
        XCTAssertNil(LinkaAppearancePreference(rawValue: "unknown")?.colorScheme)
    }

    func testLanguagePreferenceSupportsSystemPortugueseEnglishAndLatinAmericanSpanish() {
        XCTAssertEqual(LinkaLanguagePreference.allCases.map(\.rawValue), ["system", "pt-BR", "en", "es-419"])
        XCTAssertEqual(LinkaLanguagePreference.fromStoredValue("en"), .english)
        XCTAssertEqual(LinkaLanguagePreference.fromStoredValue("unknown"), .system)
    }

    func testLanguageSelectorKeepsPortugueseSystemLocaleUntilTheUserOverridesIt() {
        let portugueseSystem = Locale(identifier: "pt-BR")
        XCTAssertEqual(
            LinkaWidgetShared.effectiveLocale(preference: LinkaLanguagePreference.system.rawValue, systemLocale: portugueseSystem).identifier,
            "pt-BR"
        )
        XCTAssertEqual(
            LinkaWidgetShared.effectiveLocale(preference: LinkaLanguagePreference.english.rawValue, systemLocale: portugueseSystem).identifier,
            "en"
        )
    }

    func testLanguageTagUsesTheEffectiveAppLanguageForRemoteContracts() {
        XCTAssertEqual(
            LinkaLanguagePreference.system.languageTag(systemLocale: Locale(identifier: "pt-BR")),
            "pt-BR"
        )
        XCTAssertEqual(
            LinkaLanguagePreference.system.languageTag(systemLocale: Locale(identifier: "es-MX")),
            "es-419"
        )
        XCTAssertEqual(
            LinkaLanguagePreference.system.languageTag(systemLocale: Locale(identifier: "fr-FR")),
            "en"
        )
        XCTAssertEqual(LinkaLanguagePreference.english.languageTag(systemLocale: Locale(identifier: "pt-BR")), "en")
        XCTAssertEqual(LinkaLanguagePreference.spanishLatinAmerica.languageTag(systemLocale: Locale(identifier: "en-US")), "es-419")
    }

    func testDynamicCopyUsesTheManualLanguageChoiceForPortugueseEnglishAndSpanish() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: LinkaLanguagePreference.storageKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: LinkaLanguagePreference.storageKey)
            } else {
                defaults.removeObject(forKey: LinkaLanguagePreference.storageKey)
            }
        }

        let expectations: [(String, String, String, String, String, String)] = [
            ("pt-BR", "Nenhuma medição encontrada para diagnóstico.", "Sua conexão sustenta bem chamada em vídeo agora.", "Interprete esta medição com os dados disponíveis.", "Ainda não há dados suficientes para uma interpretação confiável.", "Rede móvel"),
            ("en", "No measurement found for diagnosis.", "Your connection supports video calls well right now.", "Interpret this measurement using the available data.", "There is not enough data yet for a reliable interpretation.", "Mobile network"),
            ("es-419", "No se encontró ninguna medición para el diagnóstico.", "Tu conexión admite bien las videollamadas ahora.", "Interpreta esta medición con los datos disponibles.", "Aún no hay datos suficientes para una interpretación confiable.", "Red móvil")
        ]

        for (language, assistMessage, usageMessage, defaultQuestion, insufficientMessage, cellularNetwork) in expectations {
            defaults.set(language, forKey: LinkaLanguagePreference.storageKey)
            XCTAssertEqual(LinkaCopy.value("assist.noMeasurement"), assistMessage, "language: \(language)")
            XCTAssertEqual(LinkaCopy.value("usage.case.videoCall.positive"), usageMessage, "language: \(language)")
            XCTAssertEqual(LinkaCopy.value("assist.defaultQuestion"), defaultQuestion, "language: \(language)")
            XCTAssertEqual(LinkaCopy.value("assist.insufficient"), insufficientMessage, "language: \(language)")
            XCTAssertEqual(LinkaCopy.value("network.cellular"), cellularNetwork, "language: \(language)")
        }
    }

    func testAssistFallbackUsesTheRequestLanguageInsteadOfTheSystemLanguage() {
        XCTAssertEqual(AssistContainer.inconclusiveMessage(locale: "pt-BR"), "Diagnóstico inconclusivo.")
        XCTAssertEqual(AssistContainer.inconclusiveMessage(locale: "en"), "Diagnosis inconclusive.")
        XCTAssertEqual(AssistContainer.inconclusiveMessage(locale: "es-419"), "Diagnóstico no concluyente.")
    }

    func testAssistPaywallUsesTheManualLanguageChoice() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: LinkaLanguagePreference.storageKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: LinkaLanguagePreference.storageKey)
            } else {
                defaults.removeObject(forKey: LinkaLanguagePreference.storageKey)
            }
        }

        let expectations: [(String, String, String)] = [
            ("pt-BR", "Entenda esta medição", "O Linka Plus interpreta o resultado e mostra o que merece atenção."),
            ("en", "Understand this measurement", "Linka Plus interprets the result and shows what needs attention."),
            ("es-419", "Entiende esta medición", "Linka Plus interpreta el resultado y muestra lo que requiere atención.")
        ]

        for (language, title, subtitle) in expectations {
            defaults.set(language, forKey: LinkaLanguagePreference.storageKey)
            XCTAssertEqual(PurchaseEntryPoint.assist.title, title, "language: \(language)")
            XCTAssertEqual(PurchaseEntryPoint.assist.subtitle, subtitle, "language: \(language)")
        }
    }

    func testPermissionPromptsRemainBoundToSystemLanguageResources() throws {
        // iOS owns permission prompts. The in-app language picker must not
        // override the device language used by InfoPlist.strings.
        let appDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for language in ["pt-BR", "en", "es-419"] {
            let url = appDirectory
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(language).lproj")
                .appendingPathComponent("InfoPlist.strings")
            let contents = try String(contentsOf: url)
            XCTAssertTrue(contents.contains("NSLocationWhenInUseUsageDescription"))
            XCTAssertTrue(contents.contains("NSLocalNetworkUsageDescription"))
            XCTAssertTrue(contents.contains("NSUserTrackingUsageDescription"))
        }
    }

    func testVersionDisplayUsesRealBundleKeysAndFallbacks() {
        XCTAssertEqual(
            LinkaAppVersion.displayString(
                infoDictionary: [
                    "CFBundleShortVersionString": "2.3.4",
                    "CFBundleVersion": "57"
                ]
            ),
            "2.3.4 (57)"
        )
        XCTAssertEqual(
            LinkaAppVersion.displayString(infoDictionary: [:]),
            "1.0.0 (1)"
        )
    }

    #if canImport(CoreLocation)
    func testWiFiIdentificationStateDistinguishesUserAndSystemStates() {
        XCTAssertEqual(
            WiFiNetworkPermission.state(
                enabled: false,
                authorizationStatus: .authorizedWhenInUse,
                accuracyAuthorization: .fullAccuracy
            ),
            .disabledByUser
        )
        XCTAssertEqual(
            WiFiNetworkPermission.state(
                enabled: true,
                authorizationStatus: .authorizedWhenInUse,
                accuracyAuthorization: .fullAccuracy
            ),
            .active
        )
        XCTAssertEqual(
            WiFiNetworkPermission.state(
                enabled: true,
                authorizationStatus: .authorizedWhenInUse,
                accuracyAuthorization: .reducedAccuracy
            ),
            .permissionRequired
        )
        XCTAssertEqual(
            WiFiNetworkPermission.state(
                enabled: true,
                authorizationStatus: .denied,
                accuracyAuthorization: .fullAccuracy
            ),
            .permissionDenied
        )
        XCTAssertEqual(
            WiFiNetworkPermission.state(
                enabled: true,
                authorizationStatus: .notDetermined,
                accuracyAuthorization: .fullAccuracy
            ),
            .permissionRequired
        )
    }
    #endif
}
