import Foundation

/// Camada de "próxima ação" (issue #58) — deliberadamente separada da
/// investigação local de falha (`NetworkAssistInvestigationEngine`, issue
/// #56), mesmo padrão de separação documentado no cabeçalho de
/// `NetworkAssistInvestigation.swift`: cada capacidade do `NetworkAssist` é
/// um motor próprio, puro, síncrono, sem I/O, sem `async`, sem depender de
/// `LinkaEngine` nem de UIKit/SwiftUI.
///
/// Este motor só decide O QUÊ sugerir — um `NetworkAssistActionSuggestion`
/// tipado, fechado. Nunca decide COMO apresentar (nenhuma string de copy
/// aqui) nem COMO executar (isso é responsabilidade exclusiva de
/// `AssistContainer`/`AssistSheet` em `LinkaApp`, o único lugar do app que
/// fala com `UIApplication`/SwiftUI). Mesma disciplina de
/// `NetworkAssistInvestigationResult`: "motor expõe fato, apresentação
/// expõe linguagem" (AGENTS.md §8).

// MARK: - Tópico de orientação manual

/// Tópico de orientação manual para quando não existe API pública da Apple
/// que automatize o próximo passo — o app não pode abrir diretamente a
/// tela de Wi-Fi ou de DNS do sistema, então o máximo honesto é descrever
/// os passos em texto, sem prometer automação com um botão.
public enum NetworkAssistManualGuidanceTopic: String, Codable, Equatable, Sendable {
    /// Verificar conectividade do aparelho (Wi-Fi/dados móveis ligados,
    /// modo avião desligado) — usado quando a investigação aponta que
    /// nenhuma rede foi detectada antes mesmo de o teste começar
    /// (`NetworkAssistFailureSignal.offline`). Não existe API pública para
    /// abrir a tela de Wi-Fi diretamente a partir de um app de terceiros.
    case wifiConnectivity
    /// Verificar/restaurar configuração de DNS. Não existe API pública para
    /// ler, mudar ou abrir a tela de DNS a partir de um app de terceiros —
    /// por isso este caso nunca tem uma ação automática correspondente.
    /// Reservado para quando a investigação (#56) ganhar um sinal
    /// específico de DNS; `NetworkAssistActionEngine.suggest(for:)` não
    /// produz este caso hoje porque a investigação atual não coleta
    /// evidência de DNS — existe para o tipo já estar pronto sem exigir
    /// uma mudança de contrato incompatível quando esse sinal existir.
    case dnsConnectivity
}

// MARK: - Sugestão

/// Sugestão de próxima ação — no máximo uma por resultado de investigação
/// (ver `NetworkAssistActionEngine.suggest(for:)`). Enum fechado: uma nova
/// forma de ação precisa passar pela curadoria de minimalismo do §1 do
/// AGENTS.md antes de virar um novo caso aqui.
public enum NetworkAssistActionSuggestion: Equatable, Sendable {
    /// Reexecutar a medição. Este pacote nunca dispara uma medição
    /// sozinho — o chamador (`AssistContainer`/`AssistSheet`) reusa o
    /// caminho de início de teste já existente do app via closure.
    case retryMeasurement
    /// Abrir a página do próprio app em Ajustes, via
    /// `UIApplication.openSettingsURLString` — a única forma pública e
    /// documentada pela Apple de deep-linkar em Ajustes a partir de um app
    /// iOS/iPadOS. Não existe equivalente que abra uma tela específica de
    /// Wi-Fi ou DNS; por isso este caso só é sugerido quando a evidência
    /// de `connectionKind` da investigação aponta Wi-Fi como conexão
    /// recente predominante — é o único cenário em que abrir a página do
    /// app em Ajustes tem relação objetiva com o que foi observado.
    case openAppSettings
    /// Orientação manual em poucos passos — sem botão de automação, porque
    /// não existe API pública da Apple para o caso.
    case manualGuidance(topic: NetworkAssistManualGuidanceTopic)
}

// MARK: - Motor

/// Motor de regras determinístico e puro — mesma disciplina de
/// `NetworkAssistInvestigationEngine`: mesma entrada sempre produz a mesma
/// saída, sem I/O, sem `async`, sem depender de nenhum transport remoto.
public enum NetworkAssistActionEngine {
    private static let connectionKindMetricKey = "connectionKind"
    private static let wifiDirection = "wifi"
    private static let recentOutcomeStabilityMetricKey = "recentOutcomeStability"
    private static let stableDirection = "stable"

    /// Decide a próxima ação sugerida a partir do resultado da investigação
    /// local de falha (issue #56). Regras (AGENTS.md §1/§9, plano #58):
    ///
    /// - nunca sugere nada quando `result` é `nil` ou `disposition ==
    ///   .inconclusive` — sem evidência suficiente para diferenciar local
    ///   de externo, nenhuma ação tem gatilho objetivo;
    /// - nunca sugere nada sem a evidência mínima daquele tipo de ação —
    ///   cada branch abaixo checa a evidência específica antes de decidir,
    ///   nunca infere a partir da disposição sozinha;
    /// - `.openAppSettings` só quando a evidência de `connectionKind`
    ///   aponta Wi-Fi;
    /// - nenhuma automação para DNS ou troca de rede Wi-Fi — quando o
    ///   único passo honesto é textual, retorna `.manualGuidance`, nunca
    ///   um caso com execução automática.
    public static func suggest(
        for result: NetworkAssistInvestigationResult?
    ) -> NetworkAssistActionSuggestion? {
        guard let result else { return nil }

        switch result.disposition {
        case .inconclusive:
            return nil
        case .localSignalLikely:
            return suggestForLocalSignal(result)
        case .externalSignalLikely:
            return suggestForExternalSignal(result)
        }
    }

    /// Indício local. Dois cenários com evidência suficiente para agir:
    ///
    /// A falha foi `.connectionLost` e a evidência de `connectionKind`
    ///    aponta Wi-Fi como conexão recente predominante — abrir a página
    ///    do app em Ajustes é uma ação real e pública com relação objetiva
    ///    ao que foi observado.
    ///
    /// Fora desses dois casos (ex.: `.connectionLost` sem `connectionKind`
    /// evidenciado, ou com conexão recente não-Wi-Fi) não há evidência que
    /// diferencie a causa o suficiente para sugerir algo sem fabricar uma
    /// hipótese — retorna `nil`.
    private static func suggestForLocalSignal(
        _ result: NetworkAssistInvestigationResult
    ) -> NetworkAssistActionSuggestion? {
        if hasWifiConnectionKindEvidence(result) {
            return .openAppSettings
        }
        return nil
    }

    /// Indício externo (além do acesso do usuário). A única ação com
    /// gatilho objetivo é reteste, e só quando o histórico recente
    /// (`recentOutcomeStability`) sustenta que os testes recentes
    /// completaram normalmente — isso é o que torna esta queda mais
    /// consistente com um evento pontual do que com um padrão, tornando o
    /// reteste uma sugestão fundamentada, não um "tente de novo" genérico.
    private static func suggestForExternalSignal(
        _ result: NetworkAssistInvestigationResult
    ) -> NetworkAssistActionSuggestion? {
        guard hasStableRecentHistoryEvidence(result) else { return nil }
        return .retryMeasurement
    }

    private static func hasWifiConnectionKindEvidence(_ result: NetworkAssistInvestigationResult) -> Bool {
        result.evidence.contains {
            $0.metricKey == connectionKindMetricKey && $0.direction == wifiDirection
        }
    }

    private static func hasStableRecentHistoryEvidence(_ result: NetworkAssistInvestigationResult) -> Bool {
        result.evidence.contains {
            $0.metricKey == recentOutcomeStabilityMetricKey && $0.direction == stableDirection
        }
    }
}
