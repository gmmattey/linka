#if os(macOS)
import Foundation
import SwiftUI
import os
import LinkaModules
import MeasurementHistory
import FirebaseCore
import FirebaseAnalytics

/// Nomes de tela do Mac. Todos começam com "macOS" para separar do iPhone e iPad
/// nos relatórios do Firebase.
enum MacScreenName {
    static let speedtest = "macOS Speedtest"
    static let measuring = "macOS Speedtest Measuring"
    static let result = "macOS Speedtest Result"
    static let error = "macOS Speedtest Error"
    static let history = "macOS History"
    static let myNetwork = "macOS My Network"
    static func settings(_ tab: String) -> String { "macOS Settings \(tab)" }
    static func sheet(_ name: String) -> String { "macOS Sheet \(name)" }
}

/// Eventos de produto do Mac. Cada evento vira `mac_<nome>` no Firebase.
/// Regra de privacidade: nunca enviar nome de rede, BSSID, IP, localização,
/// texto digitado ou conteúdo de medições além de números agregados.
enum MacAnalyticsEvent: Equatable {
    // Aquisição e retenção
    case firstLaunch
    case appOpen(launchCount: Int, daysSinceFirstLaunch: Int, historyCount: Int)
    case appUpdated(fromVersion: String)
    // Navegação
    case screenView(String)
    case navigate(to: String, method: String)
    case settingsOpened
    case inspectorToggled(visible: Bool)
    // Medição
    case speedtestStarted(connectionType: String, trigger: String)
    case speedtestCompleted(connectionType: String, durationSeconds: Int, hasUpload: Bool, hasPing: Bool,
                            downloadMbps: Double?, uploadMbps: Double?, pingMs: Double?)
    case speedtestFailed(reason: String, connectionType: String)
    case speedtestCancelled(phase: String)
    case resultViewed(source: String)
    case resultShared(method: String)
    // Histórico
    case historyFiltered(filter: String)
    case historySorted(column: String)
    case historySearched
    case historyExported(rows: Int, success: Bool)
    case measurementDeleted(scope: String)
    // Minha Rede e ferramentas
    case myNetworkAction(action: String)
    case diagnosticStarted(type: String)
    case diagnosticCompleted(type: String, outcome: String)
    case serviceStatusViewed
    case plusOfferViewed(entryPoint: String)
    // Ajustes, permissões e falhas
    case settingChanged(setting: String, value: String)
    case locationPermission(status: String)
    case error(area: String, kind: String)
}

/// Nome e parâmetros prontos para o Firebase. Puro, para ser testado sem SDK.
struct MacAnalyticsPayload: Equatable {
    static let prefix = "mac_"
    let name: String
    let parameters: [String: AnyHashable]

    init(_ event: MacAnalyticsEvent) {
        var p: [String: AnyHashable] = ["app_platform": "macos"]
        let n: String
        switch event {
        case .firstLaunch:
            n = "first_launch"
        case let .appOpen(count, days, history):
            n = "app_open"
            p["launch_count"] = Self.bucket(count)
            p["days_since_first_launch"] = max(0, days)
            p["history_count"] = Self.bucket(history)
        case let .appUpdated(from):
            n = "app_updated"
            p["from_version"] = Self.text(from)
        case let .screenView(name):
            // Evento padrão do Firebase: aparece em Engajamento > Páginas e telas.
            self.name = AnalyticsEventScreenView
            self.parameters = [AnalyticsParameterScreenName: Self.text(name),
                               AnalyticsParameterScreenClass: "LinkaMac", "app_platform": "macos"]
            return
        case let .navigate(to, method):
            n = "navigate"
            p["destination"] = Self.text(to)
            p["method"] = Self.text(method)
        case .settingsOpened:
            n = "settings_opened"
        case let .inspectorToggled(visible):
            n = "inspector_toggled"
            p["visible"] = visible
        case let .speedtestStarted(connection, trigger):
            n = "speedtest_started"
            p["connection_type"] = Self.text(connection)
            p["trigger"] = Self.text(trigger)
        case let .speedtestCompleted(connection, duration, hasUpload, hasPing, down, up, ping):
            n = "speedtest_completed"
            p["connection_type"] = Self.text(connection)
            p["duration_seconds"] = max(0, duration)
            p["has_upload"] = hasUpload
            p["has_ping"] = hasPing
            if let down { p["download_mbps"] = Self.rounded(down) }
            if let up { p["upload_mbps"] = Self.rounded(up) }
            if let ping { p["ping_ms"] = Self.rounded(ping) }
        case let .speedtestFailed(reason, connection):
            n = "speedtest_failed"
            p["failure_reason"] = Self.text(reason)
            p["connection_type"] = Self.text(connection)
        case let .speedtestCancelled(phase):
            n = "speedtest_cancelled"
            p["phase"] = Self.text(phase)
        case let .resultViewed(source):
            n = "result_viewed"
            p["source"] = Self.text(source)
        case let .resultShared(method):
            n = "result_shared"
            p["method"] = Self.text(method)
        case let .historyFiltered(filter):
            n = "history_filtered"
            p["filter"] = Self.text(filter)
        case let .historySorted(column):
            n = "history_sorted"
            p["column"] = Self.text(column)
        case .historySearched:
            n = "history_searched" // o texto buscado nunca é enviado
        case let .historyExported(rows, success):
            n = "history_exported"
            p["rows"] = Self.bucket(rows)
            p["success"] = success
        case let .measurementDeleted(scope):
            n = "measurement_deleted"
            p["scope"] = Self.text(scope)
        case let .myNetworkAction(action):
            n = "my_network_action"
            p["action"] = Self.text(action)
        case let .diagnosticStarted(type):
            n = "diagnostic_started"
            p["diagnostic_type"] = Self.text(type)
        case let .diagnosticCompleted(type, outcome):
            n = "diagnostic_completed"
            p["diagnostic_type"] = Self.text(type)
            p["outcome"] = Self.text(outcome)
        case .serviceStatusViewed:
            n = "service_status_viewed"
        case let .plusOfferViewed(entry):
            n = "plus_offer_viewed"
            p["entry_point"] = Self.text(entry)
        case let .settingChanged(setting, value):
            n = "setting_changed"
            p["setting"] = Self.text(setting)
            p["value"] = Self.text(value)
        case let .locationPermission(status):
            n = "location_permission"
            p["status"] = Self.text(status)
        case let .error(area, kind):
            n = "error"
            p["area"] = Self.text(area)
            p["kind"] = Self.text(kind)
        }
        name = Self.prefix + n
        parameters = p
    }

    /// Texto curto e estável: o Firebase aceita até 100 caracteres por valor.
    static func text(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : String(trimmed.prefix(100))
    }

    static func rounded(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (max(0, value) * 10).rounded() / 10
    }

    /// Faixas evitam valores soltos e facilitam segmentar coortes.
    static func bucket(_ n: Int) -> String {
        switch n {
        case ..<1: return "0"
        case 1...5: return "1-5"
        case 6...20: return "6-20"
        case 21...100: return "21-100"
        default: return "100+"
        }
    }
}

/// Envio de telemetria do Mac ao Firebase. Só funciona se o app trouxer o
/// `GoogleService-Info-macOS.plist` do app macOS registrado no Firebase.
final class MacAnalytics: @unchecked Sendable {
    static let shared = MacAnalytics()
    static let plistName = "GoogleService-Info-macOS"
    private static let logger = Logger(subsystem: "com.linka.assist", category: "MacAnalytics")

    private enum Keys {
        static let firstLaunch = "linka.mac.analytics.firstLaunchDate"
        static let launchCount = "linka.mac.analytics.launchCount"
        static let lastVersion = "linka.mac.analytics.lastVersion"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var configured = false
    private var pendingTrigger: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Origem do próximo teste: "button", "menu", "history"… Lido uma única vez.
    func markNextTestTrigger(_ trigger: String) {
        lock.lock(); pendingTrigger = trigger; lock.unlock()
    }

    func consumeTestTrigger() -> String {
        lock.lock(); defer { lock.unlock() }
        let value = pendingTrigger ?? "button"
        pendingTrigger = nil
        return value
    }

    /// Configura o Firebase e registra o ciclo de vida (instalação, abertura, atualização).
    func configure(collectionEnabled: Bool) {
        if FirebaseApp.app() == nil {
            guard let path = Bundle.main.path(forResource: Self.plistName, ofType: "plist"),
                  let options = FirebaseOptions(contentsOfFile: path) else {
                Self.logger.warning("Telemetria do Mac desligada: \(Self.plistName, privacy: .public).plist ausente no app.")
                return
            }
            FirebaseApp.configure(options: options)
        }
        Analytics.setAnalyticsCollectionEnabled(collectionEnabled)
        configured = true
        guard collectionEnabled else { return }
        setUserProperties()
        recordLifecycle()
    }

    func setCollectionEnabled(_ enabled: Bool) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }

    func track(_ event: MacAnalyticsEvent) {
        guard configured, LinkaAnalytics.shared.preference.isCollectionEnabled else { return }
        let payload = MacAnalyticsPayload(event)
        Analytics.logEvent(payload.name, parameters: payload.parameters)
    }

    func setUserProperty(_ value: String, for key: String) {
        guard configured, LinkaAnalytics.shared.preference.isCollectionEnabled else { return }
        Analytics.setUserProperty(MacAnalyticsPayload.text(value), forName: key)
    }

    // MARK: Ciclo de vida

    private func setUserProperties() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        Analytics.setUserProperty("macos", forName: "app_platform")
        Analytics.setUserProperty(LinkaDistribution.isDirectDownload ? "direct" : "app_store", forName: "distribution")
        Analytics.setUserProperty("\(os.majorVersion)", forName: "macos_major")
        Analytics.setUserProperty(Locale.preferredLanguages.first.map { String($0.prefix(8)) } ?? "unknown", forName: "device_language")
    }

    private func recordLifecycle() {
        let now = Date()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let launches = defaults.integer(forKey: Keys.launchCount) + 1
        defaults.set(launches, forKey: Keys.launchCount)

        if let first = defaults.object(forKey: Keys.firstLaunch) as? Date {
            let days = Calendar.current.dateComponents([.day], from: first, to: now).day ?? 0
            Task { [weak self] in
                let history = await MacAnalytics.historyCount()
                self?.track(.appOpen(launchCount: launches, daysSinceFirstLaunch: days, historyCount: history))
            }
        } else {
            defaults.set(now, forKey: Keys.firstLaunch)
            track(.firstLaunch)
            track(.appOpen(launchCount: launches, daysSinceFirstLaunch: 0, historyCount: 0))
        }

        if let last = defaults.string(forKey: Keys.lastVersion), last != version {
            track(.appUpdated(fromVersion: last))
        }
        defaults.set(version, forKey: Keys.lastVersion)
    }

    private static func historyCount() async -> Int {
        let repo = LinkaMeasurementHistory.makeRepository()
        return (try? await repo.measurements(matching: MeasurementQuery(sortOrder: .newestFirst)).count) ?? 0
    }
}

extension View {
    /// Registra a visualização de tela (`screen_view`) com nome iniciado em "macOS".
    func macScreen(_ name: String) -> some View {
        onAppear { MacAnalytics.shared.track(.screenView(name)) }
    }
}
#endif
