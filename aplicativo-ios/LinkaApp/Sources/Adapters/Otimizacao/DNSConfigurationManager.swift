import Foundation
import NetworkDNSBenchmark
import NetworkExtension

enum DNSConfigurationStatus: Equatable {
    case unavailable
    case none
    case awaitingActivation(providerName: String)
    case active(providerName: String)
    case failed
}

enum DNSConfigurationError: Error { case removalNotConfirmed }

protocol DNSConfigurationManaging {
    func create(provider: DNSProvider) async throws
    func status() async throws -> DNSConfigurationStatus
    func remove() async throws
}

/// Adaptador exclusivo da configuração pertencente ao processo do Linka. A API
/// não enumera nem modifica perfis de VPN, MDM ou de outros apps.
struct SystemDNSConfigurationManager: DNSConfigurationManaging {
    func create(provider: DNSProvider) async throws {
        let manager = NEDNSSettingsManager.shared()
        try await load(manager)
        guard manager.dnsSettings == nil else { throw DNSConfigurationError.removalNotConfirmed }
        let settings = NEDNSOverHTTPSSettings(servers: provider.bootstrapIPs)
        settings.serverURL = provider.dohURL
        settings.matchDomains = [""]
        settings.matchDomainsNoSearch = true
        manager.localizedDescription = "\(provider.name) via DNS sobre HTTPS"
        manager.dnsSettings = settings
        try await save(manager)
    }

    func status() async throws -> DNSConfigurationStatus {
        let manager = NEDNSSettingsManager.shared()
        try await load(manager)
        guard let settings = manager.dnsSettings as? NEDNSOverHTTPSSettings,
              let serverURL = settings.serverURL,
              let provider = DNSProviderCatalog.all.first(where: { $0.dohURL == serverURL }) else { return .none }
        return manager.isEnabled ? .active(providerName: provider.name) : .awaitingActivation(providerName: provider.name)
    }

    func remove() async throws {
        let manager = NEDNSSettingsManager.shared()
        try await load(manager)
        guard manager.dnsSettings != nil else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        try await load(manager)
        guard manager.dnsSettings == nil else { throw DNSConfigurationError.removalNotConfirmed }
    }

    private func load(_ manager: NEDNSSettingsManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func save(_ manager: NEDNSSettingsManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}

@MainActor
final class DNSConfigurationCoordinator: ObservableObject {
    @Published private(set) var status: DNSConfigurationStatus = .unavailable
    @Published private(set) var isWorking = false
    private let manager: any DNSConfigurationManaging

    init(manager: any DNSConfigurationManaging = SystemDNSConfigurationManager()) { self.manager = manager }

    func refresh() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do { status = try await manager.status() } catch { status = .unavailable }
    }

    func create(provider: DNSProvider) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await manager.create(provider: provider)
            status = try await manager.status()
        } catch { status = .failed }
    }

    func remove() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await manager.remove()
            status = try await manager.status()
        } catch { status = .failed }
    }
}
