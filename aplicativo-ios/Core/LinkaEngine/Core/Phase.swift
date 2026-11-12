import Foundation

public enum Phase: Sendable, Equatable {
    case idle
    case ping
    case download
    case upload
    case result
    /// Falha fatal do motor (issue #66): a fase foi abortada porque perdeu
    /// conectividade de transporte de forma não recuperável, ou porque não
    /// havia rede desde o início. Distinto de uma falha transitória isolada
    /// (timeout, 429, 5xx), que o motor tenta recuperar sozinho sem chegar
    /// a este estado. Detalhe do motivo vive em `MeasurementState.failureReason`.
    case error
}
