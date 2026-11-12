import Foundation

enum PurchaseEntryPoint: Equatable {
    case settings
    case assist
    case historyInsights
    case advancedWiFi
    case optimization
    case shortcut
    case appIntent

    var title: String {
        switch self {
        case .settings: LinkaCopy.value("purchase.entry.settings.title", defaultValue: "Linka Plus")
        case .assist: LinkaCopy.value("purchase.entry.assist.title", defaultValue: "Entenda esta medição")
        case .historyInsights: LinkaCopy.value("purchase.entry.history.title", defaultValue: "Veja o que se repete")
        case .advancedWiFi: LinkaCopy.value("purchase.entry.wifi.title", defaultValue: "Veja além da velocidade")
        case .optimization: LinkaCopy.value("purchase.entry.optimization.title", defaultValue: "Encontre oportunidades reais")
        case .shortcut, .appIntent: LinkaCopy.value("purchase.entry.shortcuts.title", defaultValue: "Automação e Atalhos")
        }
    }

    var subtitle: String {
        switch self {
        case .settings:
            LinkaCopy.value("purchase.entry.settings.subtitle", defaultValue: "Entenda sua conexão, não apenas a velocidade.")
        case .assist:
            LinkaCopy.value("purchase.entry.assist.subtitle", defaultValue: "O Linka Plus interpreta o resultado e mostra o que merece atenção.")
        case .historyInsights:
            LinkaCopy.value("purchase.entry.history.subtitle", defaultValue: "Compare suas medições e descubra padrões por rede e horário.")
        case .advancedWiFi:
            LinkaCopy.value("purchase.entry.wifi.subtitle", defaultValue: "Use informações extras do Wi-Fi para entender melhor a conexão.")
        case .optimization:
            LinkaCopy.value("purchase.entry.optimization.subtitle", defaultValue: "O Linka Plus encontra ajustes possíveis e mede novamente para comparar.")
        case .shortcut, .appIntent:
            LinkaCopy.value("purchase.entry.shortcuts.subtitle", defaultValue: "Automatize testes e acompanhe resultados usando a Siri e os Atalhos.")
        }
    }

    var analyticsIdentifier: String {
        switch self {
        case .settings: return "settings"
        case .assist: return "assist"
        case .historyInsights: return "history_insights"
        case .advancedWiFi: return "advanced_wifi"
        case .optimization: return "optimization"
        case .shortcut: return "shortcut"
        case .appIntent: return "app_intent"
        }
    }
}
