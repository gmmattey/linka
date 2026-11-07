#if os(macOS)
import Foundation

/// Chave central de recursos do Linka para Mac. Um recurso fica oculto
/// (barra lateral, barra de ferramentas, menus e links) até estar funcional e
/// revisado no layout nativo do Mac. Para liberar, troque para `true`.
enum MacFeatures {
    /// Conversa do Assist (Linka Plus).
    static let assist = false
    /// Otimização e comparação de DNS (Linka Plus).
    static let optimization = false
    /// Compra e gestão da assinatura do Linka Plus dentro do app.
    static let plusPurchase = false
    /// Painel do roteador (abrir o painel de administração).
    static let routerPanel = false
    /// Cobertura residencial (mapa de cômodos).
    static let homeCoverage = false
    /// Análise detalhada Netscope (leitura ainda desligada).
    static let netscopeAnalysis = false
}
#endif
