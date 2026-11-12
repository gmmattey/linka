import Foundation

/// Decide quando o Linka pode solicitar uma avaliação. A política fica no
/// app, não no motor nem no histórico: ela não lê nem guarda dados de rede.
struct AppStoreReviewPolicy {
    static let minimumCompletedMeasurements = 3
    static let minimumDaysSinceFirstMeasurement = 7
    static let cooldown: TimeInterval = 120 * 24 * 60 * 60

    private enum Key {
        static let lastAutomaticRequestAt = "linka.app-store-review.v1.last-automatic-request-at"
        static let lastAutomaticRequestVersion = "linka.app-store-review.v1.last-automatic-request-version"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// O histórico é a fonte de verdade para não contar resultados parciais,
    /// cancelados ou ainda não persistidos.
    func shouldRequestReview(
        completedMeasurementCount: Int,
        firstCompletedMeasurementAt: Date?,
        hasInteractedWithCurrentResult: Bool,
        now: Date = Date(),
        appVersion: String
    ) -> Bool {
        guard completedMeasurementCount >= Self.minimumCompletedMeasurements,
              let firstCompletedMeasurementAt,
              now.timeIntervalSince(firstCompletedMeasurementAt) >= TimeInterval(Self.minimumDaysSinceFirstMeasurement * 24 * 60 * 60),
              hasInteractedWithCurrentResult else {
            return false
        }

        if let lastRequestAt = defaults.object(forKey: Key.lastAutomaticRequestAt) as? Date,
           now.timeIntervalSince(lastRequestAt) < Self.cooldown {
            return false
        }

        return defaults.string(forKey: Key.lastAutomaticRequestVersion) != appVersion
    }

    /// O StoreKit não informa se o diálogo foi efetivamente mostrado, fechado
    /// ou convertido em nota. Registramos somente uma tentativa local e
    /// aplicamos uma pausa conservadora antes de tentar de novo.
    func recordAutomaticRequest(now: Date = Date(), appVersion: String) {
        defaults.set(now, forKey: Key.lastAutomaticRequestAt)
        defaults.set(appVersion, forKey: Key.lastAutomaticRequestVersion)
    }
}

/// Mantém o convite no contexto do resultado. A elegibilidade de uso não é
/// suficiente se a pessoa já saiu da tela onde o valor acabou de aparecer.
enum AppStoreReviewPromptPresentationPolicy {
    static func isSafe(
        sceneIsActive: Bool,
        resultIsVisible: Bool,
        hasBlockingPresentation: Bool
    ) -> Bool {
        sceneIsActive && resultIsVisible && !hasBlockingPresentation
    }
}
