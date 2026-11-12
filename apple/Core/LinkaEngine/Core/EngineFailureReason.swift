import Foundation

/// Motivo tipado de uma falha fatal do motor (issue #66).
///
/// Deliberadamente sem string de copy: o motor relata só o fato, nunca o
/// texto que o usuário vê. Mensagem amigável é responsabilidade exclusiva
/// da camada de apresentação (ver `MainView` no app) — mapear
/// `EngineFailureReason` para copy ali, nunca aqui, mantém o motor livre de
/// acoplamento com decisão de produto/idioma e evita duplicar lógica de
/// interpretação entre motor e UI (AGENTS.md §8).
public enum EngineFailureReason: Sendable, Equatable {
    /// Nenhuma conectividade de rede detectada antes de iniciar a medição
    /// (checagem prévia ao ping).
    case offline

    /// Conexão de transporte perdida de forma não recuperável durante a
    /// fase indicada — ex.: `cannotConnectToHost`, `networkConnectionLost`,
    /// `notConnectedToInternet`. Distinto de falha transitória isolada
    /// (timeout, 429, 5xx), que o motor tenta recuperar sozinho sem abortar
    /// (ver `SpeedTestCore.isFatalTransportError` e `shouldAbortPhase`).
    case connectionLost(phase: Phase)
}
