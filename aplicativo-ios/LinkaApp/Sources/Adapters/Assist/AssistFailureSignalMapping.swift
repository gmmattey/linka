import Foundation
import LinkaEngine
import NetworkAssist

/// Ponte entre o fato tipado do motor (`EngineFailureReason`, issue #66) e o
/// sinal de falha próprio do `NetworkAssist` (`NetworkAssistFailureSignal`,
/// issue #56).
///
/// Essa é a única peça do app que conhece os dois lados: `NetworkAssist`
/// continua sem importar `LinkaEngine` (AGENTS.md §8), e `LinkaEngine`
/// continua sem saber que o Assist existe. Mapeamento puro, sem copy —
/// texto para o usuário vive só na UI (`AssistSheet`), nunca aqui.
enum AssistFailureSignalMapping {
    static func map(_ reason: EngineFailureReason?) -> NetworkAssistFailureSignal? {
        guard let reason else { return nil }
        switch reason {
        case .offline:
            return .offline
        case .connectionLost(let phase):
            return .connectionLost(phase: map(phase))
        }
    }

    private static func map(_ phase: Phase) -> NetworkAssistFailurePhaseSignal {
        switch phase {
        case .ping:
            return .ping
        case .download:
            return .download
        case .upload:
            return .upload
        case .result:
            return .result
        case .idle, .error:
            // Não deveria ocorrer na prática (`connectionLost` sempre
            // carrega uma fase de medição real), mas mantém o mapeamento
            // exaustivo em vez de forçar um valor.
            return .unspecified
        }
    }
}
