import Foundation

public enum NetworkDiagnosticsTransportAuth: Equatable, Sendable {
    case bearer
    case relay
}

public struct NetworkDiagnosticsConfiguration: Sendable {
    public let rulesEndpoint: URL
    /// Endpoint do contrato `/v2/diagnostics/evaluate` (`raw`/`explanation`).
    /// Todo diagnóstico usa V2. Derivado de `rulesEndpoint` por padrão
    /// (troca `/v1/` por `/v2/`), com override explícito quando fornecido —
    /// o servidor v2 ainda pode não estar deployado (ver AGENTS.md deste
    /// repositório e o contrato documentado na issue), então este valor é
    /// só endereço, não confirmação de disponibilidade.
    public let v2RulesEndpoint: URL
    public let bearerToken: String?
    public let transportAuth: NetworkDiagnosticsTransportAuth
    public let requestTimeout: TimeInterval
    public let appVersion: String?
    public let platformIdentifier: String
    public let historyLookbackDays: Int
    public let recentMeasurementsLimit: Int

    public init(
        rulesEndpoint: URL,
        v2RulesEndpoint: URL? = nil,
        bearerToken: String? = nil,
        transportAuth: NetworkDiagnosticsTransportAuth = .bearer,
        requestTimeout: TimeInterval = 55,
        appVersion: String? = nil,
        platformIdentifier: String,
        historyLookbackDays: Int = 30,
        recentMeasurementsLimit: Int = 20
    ) {
        self.rulesEndpoint = rulesEndpoint
        self.v2RulesEndpoint = v2RulesEndpoint ?? Self.derivedV2Endpoint(from: rulesEndpoint)
        self.bearerToken = bearerToken
        self.transportAuth = transportAuth
        self.requestTimeout = max(1, requestTimeout)
        self.appVersion = appVersion
        self.platformIdentifier = platformIdentifier
        self.historyLookbackDays = max(1, historyLookbackDays)
        self.recentMeasurementsLimit = max(0, recentMeasurementsLimit)
    }

    public static let defaultRulesEndpoint = URL(string: "https://network-diagnostics-service.buildealabs.workers.dev/v1/diagnostics/evaluate")!
    public static let defaultV2RulesEndpoint = URL(string: "https://network-diagnostics-service.buildealabs.workers.dev/v2/diagnostics/evaluate")!
    public static let defaultAssistRelayEndpoint = URL(string: "https://linka-assist-relay.buildealabs.workers.dev/v2/assist")!

    /// `.../v1/diagnostics/evaluate` → `.../v2/diagnostics/evaluate`.
    /// Para endpoints que não têm `/v1/`, preserva o endereço informado.
    static func derivedV2Endpoint(from v1: URL) -> URL {
        let absolute = v1.absoluteString
        guard absolute.contains("/v1/") else { return v1 }
        let replaced = absolute.replacingOccurrences(of: "/v1/", with: "/v2/")
        return URL(string: replaced) ?? v1
    }
}
