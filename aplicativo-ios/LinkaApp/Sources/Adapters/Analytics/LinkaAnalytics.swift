import Foundation
import os
#if os(iOS)
import FirebaseCore
import FirebaseAnalytics
#endif

public enum LinkaAnalyticsEvent: Sendable {
    case speedtestStarted(connectionType: String)
    case speedtestCompleted(connectionType: String, durationSeconds: Int, hasUpload: Bool, hasPing: Bool)
    case speedtestFailed(reason: String, connectionType: String)
    case diagnosticStarted(diagnosticType: String)
    case diagnosticCompleted(diagnosticType: String, outcome: String)
    case resultViewed(source: String)
    case plusOfferViewed(entryPoint: String)
    // Rotas de valor adicional avaliadas
    case myNetworkViewed
    case serviceStatusViewed
    case resultShared
}

public final class LinkaAnalytics: @unchecked Sendable {
    public static let shared = LinkaAnalytics()
    private static let logger = Logger(subsystem: "com.linka.assist", category: "Analytics")

    public let preference: AnalyticsCollectionPreference

    public init(preference: AnalyticsCollectionPreference = AnalyticsCollectionPreference()) {
        self.preference = preference
    }

    public func configure() {
        #if os(iOS)
        let collectionEnabled = preference.isCollectionEnabled

        guard FirebaseApp.app() == nil else {
            Analytics.setAnalyticsCollectionEnabled(collectionEnabled)
            Self.logger.info("Firebase já configurado. Coleta definida para: \(collectionEnabled, privacy: .public)")
            return
        }

        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            Self.logger.warning("Firebase não configurado: GoogleService-Info.plist não encontrado no bundle principal.")
            return
        }

        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(collectionEnabled)
        Self.logger.info("Firebase configurado com sucesso. Coleta ativa: \(collectionEnabled, privacy: .public)")
        #endif
    }

    public func setCollectionEnabled(_ enabled: Bool) {
        #if os(iOS)
        guard FirebaseApp.app() != nil else { return }
        Analytics.setAnalyticsCollectionEnabled(enabled)
        Self.logger.info("Coleta do Firebase atualizada em tempo de execução: \(enabled, privacy: .public)")
        #endif
    }

    public func track(_ event: LinkaAnalyticsEvent) {
        #if os(iOS)
        guard preference.isCollectionEnabled else { return }
        guard let payload = FirebaseAnalyticsPayload(event: event) else { return }
        Analytics.logEvent(payload.name, parameters: payload.parameters)
        Self.logger.debug("Evento registrado: \(payload.name, privacy: .public)")
        #endif
    }
}

#if os(iOS)
private struct FirebaseAnalyticsPayload {
    let name: String
    let parameters: [String: Any]?

    init?(event: LinkaAnalyticsEvent) {
        switch event {
        case let .speedtestStarted(connectionType):
            name = "speedtest_started"
            parameters = [
                "connection_type": Self.sanitize(connectionType)
            ]

        case let .speedtestCompleted(connectionType, durationSeconds, hasUpload, hasPing):
            name = "speedtest_completed"
            parameters = [
                "connection_type": Self.sanitize(connectionType),
                "duration_seconds": max(0, durationSeconds),
                "has_upload": hasUpload,
                "has_ping": hasPing
            ]

        case let .speedtestFailed(reason, connectionType):
            name = "speedtest_failed"
            parameters = [
                "failure_reason": Self.sanitize(reason),
                "connection_type": Self.sanitize(connectionType)
            ]

        case let .diagnosticStarted(diagnosticType):
            name = "diagnostic_started"
            parameters = [
                "diagnostic_type": Self.sanitize(diagnosticType)
            ]

        case let .diagnosticCompleted(diagnosticType, outcome):
            name = "diagnostic_completed"
            parameters = [
                "diagnostic_type": Self.sanitize(diagnosticType),
                "outcome": Self.sanitize(outcome)
            ]

        case let .resultViewed(source):
            name = "result_viewed"
            parameters = [
                "source": Self.sanitize(source)
            ]

        case let .plusOfferViewed(entryPoint):
            name = "plus_offer_viewed"
            parameters = [
                "entry_point": Self.sanitize(entryPoint)
            ]

        case .myNetworkViewed:
            name = "my_network_viewed"
            parameters = nil

        case .serviceStatusViewed:
            name = "service_status_viewed"
            parameters = nil

        case .resultShared:
            name = "result_shared"
            parameters = nil
        }
    }

    /// Garante que nenhuma string contenha identificadores potencialmente sensíveis
    private static func sanitize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }
}
#endif
