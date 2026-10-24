import Foundation
import SwiftUI
import UserNotifications
import Security
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Catálogo remoto. A curadoria e a elegibilidade de alerta pertencem ao relay,
/// nunca ao binário — assim um serviço desativado não parece operacional.
struct LinkaService: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let officialStatusURL: URL?
    let sfSymbolName: String
    let notificationEligible: Bool
    let monitoringEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, category
        case officialStatusURL = "official_status_url"
        case sfSymbolName = "sf_symbol_name"
        case notificationEligible = "notification_eligible"
        case monitoringEnabled = "monitoring_enabled"
    }
}

struct LinkaServiceIncident: Codable, Identifiable, Hashable {
    let id: String
    let serviceID: String
    let state: String
    let severity: String
    let confidence: String
    let title: String
    let summary: String
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, state, severity, confidence, title, summary
        case serviceID = "service_id"
        case updatedAt = "updated_at"
    }
}

private struct CatalogResponse: Decodable { let services: [LinkaService] }
private struct IncidentsResponse: Decodable { let incidents: [LinkaServiceIncident] }

private enum ServiceStatusDeviceIdentity {
    private static let service = "com.linka.assist.service-status"
    private static let account = "installation-id"

    static func installationID() -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecReturnData: true,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let id = String(data: data, encoding: .utf8), UUID(uuidString: id) != nil {
            return id
        }
        let id = UUID().uuidString.lowercased()
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecValueData: Data(id.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        _ = SecItemAdd(item as CFDictionary, nil)
        return id
    }
}

@MainActor
final class ServiceStatusStore: ObservableObject {
    @Published private(set) var services: [LinkaService] = []
    @Published private(set) var incidents: [LinkaServiceIncident] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let defaults: UserDefaults
    private let session: URLSession
    private let endpoint: URL?
    private let installationID: String
    private var pushToken: String?
    private static let subscriptionsKey = "linka.serviceStatus.subscriptions"
    private static let pushTokenKey = "linka.serviceStatus.pushToken"

    init(defaults: UserDefaults = .standard, session: URLSession = .shared, bundle: Bundle = .main) {
        self.defaults = defaults
        self.session = session
        self.endpoint = bundle.object(forInfoDictionaryKey: "LinkaServiceStatusEndpoint")
            .flatMap { $0 as? String }
            .flatMap(URL.init(string:))
        self.installationID = ServiceStatusDeviceIdentity.installationID()
        self.pushToken = defaults.string(forKey: Self.pushTokenKey)
        NotificationCenter.default.addObserver(forName: .linkaDidRegisterPushToken, object: nil, queue: .main) { [weak self] notification in
            guard let token = notification.object as? Data else { return }
            Task { @MainActor [weak self] in await self?.didRegisterPushToken(token) }
        }
        NotificationCenter.default.addObserver(forName: .linkaDidFailPushRegistration, object: nil, queue: .main) { [weak self] notification in
            guard let error = notification.object as? Error else { return }
            Task { @MainActor [weak self] in self?.didFailToRegisterPush(error) }
        }
    }

    func isFollowing(_ service: LinkaService) -> Bool {
        (defaults.stringArray(forKey: Self.subscriptionsKey) ?? []).contains(service.id)
    }

    func setFollowing(_ service: LinkaService, enabled: Bool) async {
        guard service.notificationEligible && service.monitoringEnabled else { return }
        var subscriptions = Set(defaults.stringArray(forKey: Self.subscriptionsKey) ?? [])
        if enabled { subscriptions.insert(service.id) } else { subscriptions.remove(service.id) }
        defaults.set(Array(subscriptions).sorted(), forKey: Self.subscriptionsKey)
        if enabled { await requestPushPermissionIfNeeded() }
        await synchronizeInstallation()
    }

    func didRegisterPushToken(_ token: Data) async {
        pushToken = token.map { String(format: "%02x", $0) }.joined()
        defaults.set(pushToken, forKey: Self.pushTokenKey)
        await synchronizeInstallation()
    }

    func didFailToRegisterPush(_ error: Error) {
        // A pessoa continua vendo os avisos dentro do app. Não expomos erro
        // técnico nem apagamos a intenção de receber alertas.
        pushToken = nil
        defaults.removeObject(forKey: Self.pushTokenKey)
        Task { await synchronizeInstallation() }
    }

    func refresh() async {
        guard let endpoint else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let catalog: CatalogResponse = fetch("catalog", from: endpoint)
            async let active: IncidentsResponse = fetch("incidents", from: endpoint)
            services = try await catalog.services
            incidents = try await active.incidents
            lastError = nil
            await synchronizeInstallation()
        } catch {
            lastError = LinkaCopy.value("Não foi possível atualizar o status agora.")
        }
    }

    func incident(for service: LinkaService) -> LinkaServiceIncident? {
        incidents.first { $0.serviceID == service.id && $0.state != "resolved" }
    }

    private func requestPushPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        let updated = await center.notificationSettings()
        guard updated.authorizationStatus == .authorized || updated.authorizationStatus == .provisional else { return }
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    private func synchronizeInstallation() async {
        guard let endpoint else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let payload = InstallationPayload(
            platform: platform, appVersion: version, locale: Locale.current.identifier,
            pushToken: pushToken, pushEnvironment: pushToken.map { _ in pushEnvironment }
        )
        do {
            try await put("installations/\(installationID)", body: payload, to: endpoint)
            let subscriptions = (defaults.stringArray(forKey: Self.subscriptionsKey) ?? []).sorted()
            try await put("installations/\(installationID)/subscriptions", body: SubscriptionsPayload(serviceIDs: subscriptions), to: endpoint)
        } catch {
            // Preferências ficam locais e a próxima abertura/troca de token tenta
            // conciliá-las; falha de rede jamais desmarca a escolha da pessoa.
        }
    }

    private var platform: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }

    private var pushEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private func fetch<T: Decodable>(_ path: String, from endpoint: URL) async throws -> T {
        let url = endpoint.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder.serviceStatus.decode(T.self, from: data)
    }

    private func put<T: Encodable>(_ path: String, body: T, to endpoint: URL) async throws {
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }
}

private struct InstallationPayload: Encodable {
    let platform: String
    let appVersion: String
    let locale: String
    let pushToken: String?
    let pushEnvironment: String?
    enum CodingKeys: String, CodingKey { case platform, locale; case appVersion = "app_version"; case pushToken = "push_token"; case pushEnvironment = "push_environment" }
}

private struct SubscriptionsPayload: Encodable {
    let serviceIDs: [String]
    enum CodingKeys: String, CodingKey { case serviceIDs = "service_ids" }
}

private extension JSONDecoder {
    static let serviceStatus: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
