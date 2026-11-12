import Foundation

/// Representa as informações descobertas sobre o roteador/gateway da rede local.
public struct GatewayInfo: Codable, Equatable, Hashable, Sendable {
    /// Endereço IPv4 do gateway (ex: "192.168.1.1").
    public let ip: String
    
    /// Indica se a interface web de administração respondeu via HTTP ou HTTPS.
    public let isAccessible: Bool
    
    /// URL direta para acessar a página de administração (ex: "http://192.168.1.1").
    public let adminURL: URL?
    
    public init(
        ip: String,
        isAccessible: Bool = false,
        adminURL: URL? = nil
    ) {
        self.ip = ip
        self.isAccessible = isAccessible
        self.adminURL = adminURL
    }
    
    /// Rótulo amigável para exibição na interface
    public var displayName: String {
        return "Roteador"
    }
}
