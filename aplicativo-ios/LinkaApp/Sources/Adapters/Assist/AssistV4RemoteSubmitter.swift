#if os(iOS)
import AssistConsultation
import AssistConsultationTransport
import Foundation

/// Composition root for the V4-only remote boundary. It owns ephemeral HTTP,
/// App Attest bootstrap and the conversion to presentation states; it never
/// imports NetworkAssist or exposes a configurable host.
@available(iOS 16.0, *)
final class AssistV4EphemeralHTTPClient: NSObject, AssistConsultationHTTPTransporting, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func perform(_ request: AssistConsultationHTTPRequest) async throws -> AssistConsultationHTTPResponse {
        let response = try await send(url: request.url, headers: request.headers, body: request.body)
        return .init(statusCode: response.statusCode, body: response.body, finalURL: response.finalURL)
    }

    func send(url: URL, headers: [String: String], body: Data) async throws -> (statusCode: Int, body: Data, finalURL: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, let finalURL = http.url else { throw AssistV4RemoteError.invalidResponse }
        return (http.statusCode, data, finalURL)
    }

    // URLSession's async API does not surface a redirect body as a completed
    // request when the delegate refuses it. The final-URL check remains in
    // the V4 client as a second, explicit boundary.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@available(iOS 16.0, *)
private final class AssistV4AttestationExchange: AssistConsultationAttestationExchanging, @unchecked Sendable {
    private let http: AssistV4EphemeralHTTPClient
    private let endpoint: URL

    init(http: AssistV4EphemeralHTTPClient, endpoint: URL) {
        self.http = http
        self.endpoint = endpoint
    }

    func requestRegistrationChallenge() async throws -> AssistConsultationRegistrationChallenge {
        try await decode(path: "registration-challenge", body: EmptyBody())
    }

    func register(_ proof: AssistConsultationRegistrationProof) async throws {
        let response = try await post(path: "register", body: proof)
        guard response.statusCode == 201 else { throw AssistV4RemoteError.rejectedStatus(response.statusCode) }
    }

    func requestAssertionChallenge(for binding: AssistConsultationAssertionBinding, keyID: String) async throws -> AssistConsultationAssertionChallenge {
        struct Request: Encodable { let keyID: String; let requestSHA256: String }
        return try await decode(path: "assertion-challenge", body: Request(keyID: keyID, requestSHA256: binding.requestSHA256))
    }

    private func decode<Value: Decodable, Body: Encodable>(path: String, body: Body) async throws -> Value {
        let response = try await post(path: path, body: body)
        guard response.statusCode == 201, response.finalURL == attestationURL(path) else { throw AssistV4RemoteError.invalidResponse }
        return try JSONDecoder().decode(Value.self, from: response.body)
    }

    private func post<Body: Encodable>(path: String, body: Body) async throws -> (statusCode: Int, body: Data, finalURL: URL) {
        let data = try JSONEncoder().encode(body)
        return try await http.send(url: attestationURL(path), headers: [
            "Accept": "application/json", "Cache-Control": "no-store", "Content-Type": "application/json"
        ], body: data)
    }

    private func attestationURL(_ path: String) -> URL {
        endpoint.appendingPathComponent("attestation").appendingPathComponent(path)
    }

    private struct EmptyBody: Encodable {}
}

@available(iOS 16.0, *)
private final class AssistV4RemoteSubmitter: @unchecked Sendable {
    private let configuration: AssistConsultationTransportConfiguration
    private let http: AssistV4EphemeralHTTPClient
    private let authorizer: AssistConsultationAppAttestAuthorizer

    init(configuration: AssistConsultationTransportConfiguration) {
        self.configuration = configuration
        let http = AssistV4EphemeralHTTPClient()
        self.http = http
        self.authorizer = .init(
            appAttest: AssistConsultationSystemAppAttestProvider(),
            keyIDStore: AssistConsultationKeychainAppAttestKeyIDStore(),
            exchange: AssistV4AttestationExchange(http: http, endpoint: configuration.endpoint)
        )
    }

    func submit(_ payload: ConsultationPayload) async -> AssistV4OpenQuestionSubmission {
        let client = AssistConsultationTransportClient(configuration: configuration, transport: http)
        let request: AssistConsultationHTTPRequest
        do { request = try client.makeRequest(for: payload) } catch { return .recoverableFailure("A consulta não pôde ser preparada neste aparelho.") }
        guard case let .authorized(attestation) = await authorizer.authorize(exactBody: request.body) else {
            return .recoverableFailure("Não foi possível proteger esta consulta neste aparelho.")
        }
        var headers = request.headers
        headers["X-Linka-Consultation-Key-Id"] = attestation.keyID
        headers["X-Linka-Consultation-Assertion"] = attestation.assertion
        headers["X-Linka-Consultation-Nonce"] = attestation.nonce
        headers["X-Linka-Consultation-Timestamp-Ms"] = attestation.timestampUnixMilliseconds
        headers["X-Linka-Consultation-Request-Sha256"] = attestation.requestSHA256
        do {
            let response = try await http.send(url: request.url, headers: headers, body: request.body)
            guard response.finalURL == configuration.endpoint else { return .recoverableFailure("A consulta recusou um redirecionamento inesperado.") }
            guard (200...299).contains(response.statusCode) else { return .recoverableFailure("A consulta está indisponível agora. Tente novamente mais tarde.") }
            let decoded = try AssistConsultationContract.decodeResponse(response.body, for: payload)
            return .response(decoded)
        } catch {
            return .recoverableFailure("Não foi possível concluir a consulta agora. Sua pergunta continua neste aparelho.")
        }
    }
}

enum AssistV4RemoteComposition {
    static func submitter() -> @Sendable (ConsultationPayload) async -> AssistV4OpenQuestionSubmission {
        guard #available(iOS 16.0, *) else { return { _ in .disabled } }
        do {
            let configuration = try AssistConsultationTransportConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
            guard configuration.isEnabled else { return { _ in .disabled } }
            let remote = AssistV4RemoteSubmitter(configuration: configuration)
            return { payload in await remote.submit(payload) }
        } catch {
            return { _ in .disabled }
        }
    }
}

private enum AssistV4RemoteError: Error { case invalidResponse, rejectedStatus(Int) }
#endif
