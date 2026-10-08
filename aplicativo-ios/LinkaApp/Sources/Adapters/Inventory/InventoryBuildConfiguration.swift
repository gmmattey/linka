import Foundation

/// Archive configuration, not StoreKit or a remotely mutable preference, controls this beta.
enum InventoryBuildConfiguration {
    enum Channel: Equatable { case development, internalBeta, publicRelease }

    static var channel: Channel {
        #if LINKA_INTERNAL_BETA
        return .internalBeta
        #elseif DEBUG
        return .development
        #else
        return .publicRelease
        #endif
    }

    static var isEnabled: Bool { channel != .publicRelease }

    // Dedicated lookup deployment verified while disabled. Server activation is independent.
    // No provider credential belongs in this app. Keep the host allowlist explicit when activating.
    private static let internalBetaEndpointString: String? = "https://linka-device-spec-lookup.buildealabs.workers.dev/v1/device-specs/lookup"
    private static let internalBetaAllowedHosts: Set<String> = ["linka-device-spec-lookup.buildealabs.workers.dev"]
    private static let lookupPath = "/v1/device-specs/lookup"

    static var lookupEndpoint: URL? {
        switch channel {
        case .publicRelease:
            return nil
        case .internalBeta:
            guard let value = internalBetaEndpointString else { return nil }
            return validatedEndpoint(value, allowedHosts: internalBetaAllowedHosts, requiredPath: lookupPath)
        case .development:
            guard let value = ProcessInfo.processInfo.environment["LINKA_DEVICE_SPEC_ENDPOINT"] else { return nil }
            return validatedEndpoint(value)
        }
    }

    static func validatedEndpoint(_ value: String, allowedHosts: Set<String>? = nil, requiredPath: String? = nil) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port == nil || url.port == 443,
              allowedHosts == nil || allowedHosts!.contains(host.lowercased()),
              requiredPath == nil || url.path == requiredPath else { return nil }
        return url
    }
}
