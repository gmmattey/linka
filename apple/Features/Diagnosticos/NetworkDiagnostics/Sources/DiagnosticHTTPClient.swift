import Foundation

/// HTTP mínimo, injetável para testes. Não fazemos multi-part, streaming, nada.
/// Só POST JSON → JSON.
public protocol DiagnosticHTTPClient: Sendable {
    func postJSON(url: URL, body: Data, timeout: TimeInterval, bearerToken: String?) async throws -> (Data, Int)
}

public struct URLSessionDiagnosticHTTPClient: DiagnosticHTTPClient {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Cancelamento (issue #69): usa `withTaskCancellationHandler` +
    /// `URLSessionDataTask` explícito, em vez de confiar apenas no
    /// comportamento interno de `URLSession.data(for:)`. Quando a `Task`
    /// chamadora é cancelada — inclusive por cancelamento cooperativo
    /// propagado a partir de `NetworkAssistService.streamAnswer` — o
    /// `onCancel` chama `.cancel()` na `URLSessionDataTask` em voo,
    /// encerrando a requisição HTTP de verdade, não só parando de
    /// consumir o resultado no cliente.
    public func postJSON(url: URL, body: Data, timeout: TimeInterval, bearerToken: String? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        try Task.checkCancellation()

        let box = CancellableURLSessionTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Int), Error>) in
                let dataTask = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        continuation.resume(throwing: NetworkDiagnosticsError.transport("resposta inválida do servidor"))
                        return
                    }
                    continuation.resume(returning: (data ?? Data(), http.statusCode))
                }
                box.store(dataTask)
                dataTask.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Guarda uma `URLSessionTask` de forma thread-safe para que `onCancel`
/// (que pode disparar em qualquer thread, inclusive antes da task ser
/// criada) sempre consiga cancelá-la — sem essa guarda, um cancelamento
/// que chega entre o início da `Task` e a criação da `URLSessionDataTask`
/// seria perdido silenciosamente.
private final class CancellableURLSessionTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelledBeforeStore = false

    func store(_ task: URLSessionTask) {
        lock.lock()
        let shouldCancelImmediately = cancelledBeforeStore
        if !shouldCancelImmediately {
            self.task = task
        }
        lock.unlock()
        if shouldCancelImmediately {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelledBeforeStore = true
        let storedTask = task
        lock.unlock()
        storedTask?.cancel()
    }
}

public enum NetworkDiagnosticsError: Error, Equatable, Sendable {
    case notConfigured
    case transport(String)
    case httpStatus(Int)
    case nds(code: String, message: String, retryable: Bool, requestID: String?)
    case decoding(String)
    case emptyResult
}
