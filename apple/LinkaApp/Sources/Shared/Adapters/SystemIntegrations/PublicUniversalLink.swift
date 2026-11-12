import Foundation

/// Rotas públicas que o site Linka pode entregar ao app por Universal Link.
///
/// Esta superfície é deliberadamente pequena: não aceita payload, não inicia
/// medição e não reutiliza o esquema privado `linka://wifi-advanced`.
enum PublicUniversalLink: Equatable {
    case home
    case history
    case myNetwork
}

enum PublicUniversalLinkParser {
    private static let canonicalHost = "linka.signallq.com"

    static func parse(_ url: URL) -> PublicUniversalLink? {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == canonicalHost else {
            return nil
        }

        switch url.path.lowercased() {
        case "/abrir/teste", "/abrir/teste/":
            return .home
        case "/abrir/historico", "/abrir/historico/":
            return .history
        case "/abrir/minha-rede", "/abrir/minha-rede/":
            return .myNetwork
        default:
            return nil
        }
    }
}
