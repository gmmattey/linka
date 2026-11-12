import Foundation

/// Pequenas guardas internas, injetáveis nos testes do host. Não expõem rede
/// nem estado do dispositivo como API do pacote.
public final class DNSConnectionCompletionGate: @unchecked Sendable {
    private let lock = NSLock(); private var resolved = false
    public init() {}
    public func resolveOnce(_ action: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !resolved else { return }; resolved = true; action()
    }
}

public final class DNSPathSessionGate: @unchecked Sendable {
    private var captured = false
    public init() {}
    public func reset() { captured = false }
    /// A segunda atualização, mesmo com a mesma interface, invalida a sessão.
    public func receiveUpdate(onChange: () -> Void) {
        if captured { onChange() } else { captured = true }
    }
}
