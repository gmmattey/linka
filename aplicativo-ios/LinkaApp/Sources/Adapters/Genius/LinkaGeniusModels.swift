import Foundation
import NetworkCore
import NetworkInventory

/// Diagnóstico estruturado retornado pelo Linka Genius.
public struct LinkaGeniusAnalysis: Codable, Equatable, Sendable {
    /// Resumo humano e claro do sintoma observado.
    public let symptom: String
    /// Causa raiz técnica mais provável fundamentada nos dados reais.
    public let cause: String
    /// Lista de passos práticos imediatos em ordem de eficácia.
    public let actions: [String]
    /// Texto pronto para suporte técnico do provedor/operadora.
    public let operatorScript: String
    /// Indica se novo teste de rede é recomendado após executar as ações.
    public let needsRetest: Bool

    public init(
        symptom: String,
        cause: String,
        actions: [String],
        operatorScript: String,
        needsRetest: Bool
    ) {
        self.symptom = symptom
        self.cause = cause
        self.actions = actions
        self.operatorScript = operatorScript
        self.needsRetest = needsRetest
    }
}

/// Atalhos rápidos inteligentes apresentados na UI para os principais gargalos residenciais.
public enum LinkaGeniusShortcut: String, CaseIterable, Identifiable, Sendable {
    case slowCalls = "slow_calls"
    case routerAdequacy = "router_adequacy"
    case operatorScript = "operator_script"
    case meshNeed = "mesh_need"

    public var id: String { rawValue }

    public func title(for locale: String = "pt-BR") -> String {
        switch self {
        case .slowCalls:
            if locale.starts(with: "es") { return "Llamadas trabándose" }
            if locale.starts(with: "en") { return "Calls lagging" }
            return "Chamadas travando"
        case .routerAdequacy:
            if locale.starts(with: "es") { return "¿Mi router aguanta?" }
            if locale.starts(with: "en") { return "Is my router adequate?" }
            return "Meu roteador aguenta?"
        case .operatorScript:
            if locale.starts(with: "es") { return "Guión para el proveedor" }
            if locale.starts(with: "en") { return "Script for provider" }
            return "Script para o provedor"
        case .meshNeed:
            if locale.starts(with: "es") { return "¿Vale la pena Mesh?" }
            if locale.starts(with: "en") { return "Do I need Mesh?" }
            return "Vale a pena Mesh?"
        }
    }

    public func promptText(for locale: String = "pt-BR") -> String {
        switch self {
        case .slowCalls:
            if locale.starts(with: "es") { return "Mis videollamadas o reuniones se traban o se corta el audio. ¿Por qué ocurre y cómo lo soluciono?" }
            if locale.starts(with: "en") { return "My video calls or meetings lag and cut audio. Why is this happening and how do I fix it?" }
            return "Minhas videochamadas e reuniões travam ou engasgam o áudio. Por que isso acontece e como resolvo?"
        case .routerAdequacy:
            if locale.starts(with: "es") { return "¿Mi router actual es adecuado para mi velocidad contratada y los dispositivos de mi casa?" }
            if locale.starts(with: "en") { return "Is my current router adequate for my contracted plan speed and home devices?" }
            return "Meu roteador atual é adequado para a velocidade contratada e os dispositivos da minha casa?"
        case .operatorScript:
            if locale.starts(with: "es") { return "Genera un texto técnico preciso para que yo pueda reclamar al soporte de mi proveedor de internet." }
            if locale.starts(with: "en") { return "Generate a precise technical script for me to send to my internet provider's support team." }
            return "Gere um texto técnico preciso para eu acionar o suporte da minha operadora de internet."
        case .meshNeed:
            if locale.starts(with: "es") { return "Considerando el tamaño de mi hogar y las mediciones de señal, ¿vale la pena instalar una red Wi-Fi Mesh?" }
            if locale.starts(with: "en") { return "Considering my home size and Wi-Fi signal measurements, is it worth upgrading to a Mesh network?" }
            return "Considerando o tamanho da minha casa e as medições de sinal, vale a pena colocar uma rede Wi-Fi Mesh?"
        }
    }
}

/// Erros tipados e amigáveis de comunicação e execução do Linka Genius.
public enum LinkaGeniusError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey
    case networkOffline
    case serviceBusy(String)
    case unauthorized
    case invalidResponse
    case quotaExceeded
    case generic(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Chave da API Gemini não configurada. Configure GEMINI_API_KEY no ambiente ou nos arquivos de configuração."
        case .networkOffline:
            return "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .serviceBusy(let message):
            return message
        case .unauthorized:
            return "Chave de API Gemini inválida ou não autorizada."
        case .invalidResponse:
            return "Não foi possível interpretar o diagnóstico do Genius. Tente novamente."
        case .quotaExceeded:
            return "Limite de requisições da API Gemini atingido. Aguarde alguns instantes."
        case .generic(let message):
            return message
        }
    }
}

/// Máquina de estados reativa para a UI do Linka Genius.
public enum LinkaGeniusState: Equatable, Sendable {
    case idle
    case readingTelemetry
    case consultingGenius
    case finalizing
    case success(LinkaGeniusAnalysis)
    case failure(LinkaGeniusError)

    public var isLoading: Bool {
        switch self {
        case .readingTelemetry, .consultingGenius, .finalizing:
            return true
        case .idle, .success, .failure:
            return false
        }
    }

    public var loadingStepText: String? {
        switch self {
        case .readingTelemetry:
            return "Lendo telemetria da rede..."
        case .consultingGenius:
            return "Consultando o Genius..."
        case .finalizing:
            return "Finalizando diagnóstico..."
        case .idle, .success, .failure:
            return nil
        }
    }
}

/// Contexto consolidado para o Genius (telemetria + plano/equipamentos + pergunta).
public struct LinkaGeniusContext: Equatable, Sendable {
    public let question: String
    public let measurement: NetworkMeasurement?
    public let plan: NetworkServicePlan?
    public let devices: [RegisteredNetworkDevice]
    public let locale: String

    public init(
        question: String,
        measurement: NetworkMeasurement?,
        plan: NetworkServicePlan?,
        devices: [RegisteredNetworkDevice] = [],
        locale: String = "pt-BR"
    ) {
        self.question = question
        self.measurement = measurement
        self.plan = plan
        self.devices = devices
        self.locale = locale
    }
}
