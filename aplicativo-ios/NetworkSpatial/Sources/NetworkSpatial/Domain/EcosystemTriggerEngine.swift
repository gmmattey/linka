import Foundation

/// Aplicativos recomendados contextualmente a partir do diagnóstico de rede (Linka e Lagcheck).
public enum EcosystemTargetApp: Sendable, Equatable {
    case linka(gatewayIP: String)
    case lagcheck(isGamingRoom: Bool)

    public var appTitle: String {
        switch self {
        case .linka:
            return "Linka"
        case .lagcheck:
            return "Lagcheck"
        }
    }

    public var appSymbol: String {
        switch self {
        case .linka:
            return "speedometer"
        case .lagcheck:
            return "gamecontroller.fill"
        }
    }

    public var headline: String {
        switch self {
        case .linka:
            return "Seu Wi-Fi está perfeito. A lentidão é da sua operadora."
        case .lagcheck(let isGaming):
            return isGaming
                ? "Estabilidade Crítica para Jogos e Chamadas"
                : "Oscilação de Latência (Jitter) Detectada"
        }
    }

    public var message: String {
        switch self {
        case .linka:
            return "Seu sinal Wi-Fi local está excelente, mas a conexão externa com a internet apresenta perda ou lentidão. Teste a velocidade real e estabilidade com o Linka."
        case .lagcheck(let isGaming):
            return isGaming
                ? "Este cômodo requer baixa latência contínua. Meça a latência fina e perda em tempo real com o Lagcheck."
                : "Identificamos variações de jitter no tráfego local. Use o Lagcheck para diagnosticar picos de engasgo e rotas."
        }
    }

    public var actionTitle: String {
        switch self {
        case .linka:
            return "Testar Conexão no Linka"
        case .lagcheck:
            return "Verificar Jitter no Lagcheck"
        }
    }

    public var deepLinkURL: URL {
        switch self {
        case .linka(let gatewayIP):
            let encodedIP = gatewayIP.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? gatewayIP
            return URL(string: "linka://speedtest?referrer=linka_spatial&ip=\(encodedIP)")
                ?? URL(string: "linka://speedtest?referrer=linka_spatial")!
        case .lagcheck:
            return URL(string: "lagcheck://quicktest?referrer=linka_spatial")!
        }
    }

    public var appStoreURL: URL {
        switch self {
        case .linka:
            return URL(string: "https://apps.apple.com/app/linka/id673891234")!
        case .lagcheck:
            return URL(string: "https://apps.apple.com/app/lagcheck/id673891235")!
        }
    }
}

/// Motor de regras de negócio determinísticas para recomendação de aplicativos complementares (Linka e Lagcheck).
public enum EcosystemTriggerEngine {

    /// Avalia se o resultado da medição de um cômodo deve sugerir um aplicativo complementar
    public static func evaluateTrigger(
        for measurement: MeasurementResult,
        room: Room
    ) -> EcosystemTargetApp? {
        // Regra 1: Se a degradação for externa da operadora (ISP) e o Wi-Fi interno estiver bom
        if measurement.cause == .ispDegraded {
            return .linka(gatewayIP: measurement.metrics.gatewayIP)
        }

        // Regra 2: Se o Wi-Fi local estiver com problema ou offline, focar exclusivamente na resolução local (sem cross-sell)
        guard measurement.cause != .localWiFiDegraded,
              measurement.cause != .offline,
              measurement.cause != .bothDegraded else {
            return nil
        }

        let isGaming = isGamingOrWorkRoom(room)
        let isCriticalJitter = measurement.metrics.gatewayJitterMs > 15.0

        // Regra 3: Se a causa for allGood (ou rating fair) e (jitter > 15ms ou cômodo gamer/trabalho)
        if (measurement.cause == .allGood || measurement.rating == .fair) && (isCriticalJitter || isGaming) {
            return .lagcheck(isGamingRoom: isGaming)
        }

        return nil
    }

    /// Identifica se o cômodo é associado a games, trabalho remoto ou computadores
    public static func isGamingOrWorkRoom(_ room: Room) -> Bool {
        let nameLower = room.name.lowercased()
        if nameLower.contains("game") ||
            nameLower.contains("jogo") ||
            nameLower.contains("pc") ||
            nameLower.contains("escritório") ||
            nameLower.contains("escritorio") ||
            nameLower.contains("trabalho") ||
            nameLower.contains("office") ||
            nameLower.contains("setup") {
            return true
        }

        // Ícones representativos
        let gamingIcons: Set<String> = [
            "laptopcomputer",
            "tv",
            "gamecontroller",
            "gamecontroller.fill",
            "desktopcomputer",
            "display"
        ]
        return gamingIcons.contains(room.icon)
    }
}
