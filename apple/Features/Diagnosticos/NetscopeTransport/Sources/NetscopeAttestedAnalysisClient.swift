import CryptoKit
import Foundation
import NetscopeEvidence

/// A plataforma que a composição do app observou. Não há fallback de macOS ou
/// simulador para uma chave local: esta primeira integração aceita somente
/// aparelhos iPhone e iPad físicos com App Attest disponível.
public enum NetscopeClientPlatform: Equatable, Sendable {
    case iPhonePhysical
    case iPadPhysical
    case simulator
    case macOS
    case unsupported

    fileprivate var acceptsAppAttest: Bool {
        self == .iPhonePhysical || self == .iPadPhysical
    }
}

/// Configuração entregue apenas pela composição futura do app. O pacote não
/// possui host, URL, segredo ou fallback embutido.
public struct NetscopeServiceConfiguration: Equatable, Sendable {
    public let baseURL: URL

    public init(baseURL: URL) throws {
        let pathIsOriginOnly = baseURL.path.isEmpty || baseURL.path == "/"
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              pathIsOriginOnly,
              baseURL.query == nil,
              baseURL.fragment == nil else {
            throw NetscopeServiceConfigurationError.invalidBaseURL
        }
        self.baseURL = baseURL
    }

    fileprivate var analysisURL: URL {
        baseURL.appending(path: "v1/linka/analysis")
    }
}

public enum NetscopeServiceConfigurationError: Error, Equatable, Sendable {
    case invalidBaseURL
}

/// Challenge opaco e de curta duração usado somente para registrar uma chave
/// App Attest. Ele não pode ser reaproveitado como challenge de assertion de
/// análise e nunca é persistido pelo cliente.
public struct NetscopeRegistrationChallenge: Equatable, Sendable {
    public let value: Data

    public init(value: Data) {
        self.value = value
    }

    fileprivate var isUsable: Bool { !value.isEmpty }
}

/// Binding imutável enviado ao servidor para obter um challenge de assertion.
/// Método e rota são fechados; o único dado variável é SHA-256 do body exato.
public struct NetscopeAnalysisAssertionBinding: Equatable, Sendable {
    public let method: String
    public let path: String
    public let payloadSHA256: Data

    public init(exactBody: Data) {
        method = "POST"
        path = "/v1/linka/analysis"
        payloadSHA256 = Data(SHA256.hash(data: exactBody))
    }

    public func binds(exactBody: Data) -> Bool {
        payloadSHA256 == Data(SHA256.hash(data: exactBody))
    }
}

/// Challenge de uso único emitido pelo servidor depois de receber o binding da
/// análise. O timestamp é Unix em milissegundos e usa inteiro decimal no wire.
public struct NetscopeAnalysisAssertionChallenge: Equatable, Sendable {
    public let nonce: String
    public let timestampUnixMilliseconds: Int64

    public init(nonce: String, timestampUnixMilliseconds: Int64) {
        self.nonce = nonce
        self.timestampUnixMilliseconds = timestampUnixMilliseconds
    }

    fileprivate var isUsable: Bool { !nonce.isEmpty && timestampUnixMilliseconds > 0 }
}

/// Material que a assertion deve assinar. O binding já foi aceito pelo
/// servidor e um segundo digest prende método, rota, body exato, nonce e
/// timestamp ao pedido. Os hashes usam campos UTF-8 prefixados por tamanho,
/// sem serialização JSON implícita. O payload bruto não é armazenado aqui.
public struct NetscopeAttestationAssertionInput: Equatable, Sendable {
    public let binding: NetscopeAnalysisAssertionBinding
    public let signedRequestSHA256: Data

    public init(
        binding: NetscopeAnalysisAssertionBinding,
        exactBody: Data,
        challenge: NetscopeAnalysisAssertionChallenge
    ) {
        self.binding = binding
        signedRequestSHA256 = Self.signedRequestSHA256(
            method: binding.method,
            path: binding.path,
            exactBody: exactBody,
            nonce: challenge.nonce,
            timestampUnixMilliseconds: challenge.timestampUnixMilliseconds
        )
    }

    /// Confere o material que a implementação App Attest recebeu contra o
    /// pedido que o transporte pretende enviar. Alterar corpo, nonce ou tempo
    /// depois da assertion invalida a ligação antes de I/O.
    public func binds(
        method: String,
        path: String,
        exactBody: Data,
        nonce: String,
        timestampUnixMilliseconds: Int64
    ) -> Bool {
        binding.method == method && binding.path == path && binding.binds(exactBody: exactBody) &&
            signedRequestSHA256 == Self.signedRequestSHA256(
                method: method,
                path: path,
                exactBody: exactBody,
                nonce: nonce,
                timestampUnixMilliseconds: timestampUnixMilliseconds
            )
    }

    private static func signedRequestSHA256(
        method: String,
        path: String,
        exactBody: Data,
        nonce: String,
        timestampUnixMilliseconds: Int64
    ) -> Data {
        var material = Data()
        [Data(method.utf8), Data(path.utf8), exactBody, Data(nonce.utf8), Data(String(timestampUnixMilliseconds).utf8)].forEach {
            var length = UInt64($0.count).bigEndian
            withUnsafeBytes(of: &length) { material.append(contentsOf: $0) }
            material.append($0)
        }
        return Data(SHA256.hash(data: material))
    }
}

/// Prova transitória de App Attest. A implementação real mantém a chave no
/// Keychain; este pacote não persiste chave, assertion, challenge ou payload.
public struct NetscopeAttestationProof: Equatable, Sendable {
    public let keyID: String
    public let assertion: Data

    public init(keyID: String, assertion: Data) {
        self.keyID = keyID
        self.assertion = assertion
    }
}

/// Abstrai App Attest para que hardware, indisponibilidade e assinaturas sejam
/// testáveis sem rede. A implementação concreta ainda será habilitada somente
/// depois do provisionamento Apple e da prova física em iPhone e iPad.
public protocol NetscopeAttestationProviding: Sendable {
    func requestRegistrationChallenge() async throws -> NetscopeRegistrationChallenge
    func registerIfNeeded(for challenge: NetscopeRegistrationChallenge) async throws
    func requestAnalysisAssertionChallenge(
        for binding: NetscopeAnalysisAssertionBinding
    ) async throws -> NetscopeAnalysisAssertionChallenge
    func makeAssertion(
        for input: NetscopeAttestationAssertionInput,
        using challenge: NetscopeAnalysisAssertionChallenge
    ) async throws -> NetscopeAttestationProof
}

/// Limite de I/O injetado. Esta PR deliberadamente não fornece URLSession nem
/// outro transporte concreto, portanto instalar o pacote não cria egress.
public protocol NetscopeHTTPTransporting: Sendable {
    func perform(_ request: NetscopeAuthenticatedHTTPRequest) async throws -> NetscopeHTTPResponse
}

/// Pedido autenticado construído internamente. Não oferece rota ou método
/// configuráveis pelo cliente e não inclui URL de redirect.
public struct NetscopeAuthenticatedHTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: String
    public let body: Data
    public let nonce: String
    public let timestampUnixMilliseconds: Int64
    public let signedRequestSHA256: Data
    public let attestation: NetscopeAttestationProof

    fileprivate init(
        url: URL,
        body: Data,
        assertionInput: NetscopeAttestationAssertionInput,
        analysisChallenge: NetscopeAnalysisAssertionChallenge,
        attestation: NetscopeAttestationProof
    ) {
        self.url = url
        method = assertionInput.binding.method
        self.body = body
        nonce = analysisChallenge.nonce
        timestampUnixMilliseconds = analysisChallenge.timestampUnixMilliseconds
        signedRequestSHA256 = assertionInput.signedRequestSHA256
        self.attestation = attestation
    }
}

/// O transporte concreto futuro deve devolver a URL final observada. O cliente
/// rejeita qualquer mudança de URL, inclusive redirect cross-host.
public struct NetscopeHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data
    public let finalURL: URL

    public init(statusCode: Int, body: Data, finalURL: URL) {
        self.statusCode = statusCode
        self.body = body
        self.finalURL = finalURL
    }
}

public enum NetscopeAttestedAnalysisOutcome: Equatable, Sendable {
    case response(NetscopeV1Codec.AnalysisResponse)
    case unavailable
}

/// Cliente fechado e sem retry para uma leitura de análise. Qualquer erro de
/// atestação, transporte, timeout, cancelamento, HTTP não-2xx, redirect ou
/// JSON inválido converge para `unavailable`; a medição local não é alterada.
public struct NetscopeAttestedAnalysisClient: Sendable {
    private let platform: NetscopeClientPlatform
    private let attestation: any NetscopeAttestationProviding
    private let transport: any NetscopeHTTPTransporting

    public init(
        platform: NetscopeClientPlatform,
        attestation: any NetscopeAttestationProviding,
        transport: any NetscopeHTTPTransporting
    ) {
        self.platform = platform
        self.attestation = attestation
        self.transport = transport
    }

    public func analyze(
        input: NetscopeLocalAnalysisInput,
        locale: String,
        app: NetscopeV1Codec.AppDescriptor,
        configuration: NetscopeServiceConfiguration
    ) async -> NetscopeAttestedAnalysisOutcome {
        guard platform.acceptsAppAttest else { return .unavailable }

        do {
            let registrationChallenge = try await attestation.requestRegistrationChallenge()
            guard registrationChallenge.isUsable else { return .unavailable }
            try await attestation.registerIfNeeded(for: registrationChallenge)
            let exactBody = try NetscopeV1Codec.encodeRequest(input: input, locale: locale, app: app)
            let binding = NetscopeAnalysisAssertionBinding(exactBody: exactBody)
            let analysisChallenge = try await attestation.requestAnalysisAssertionChallenge(for: binding)
            guard analysisChallenge.isUsable else { return .unavailable }
            let assertionInput = NetscopeAttestationAssertionInput(
                binding: binding,
                exactBody: exactBody,
                challenge: analysisChallenge
            )
            guard assertionInput.binds(
                method: binding.method,
                path: binding.path,
                exactBody: exactBody,
                nonce: analysisChallenge.nonce,
                timestampUnixMilliseconds: analysisChallenge.timestampUnixMilliseconds
            ) else { return .unavailable }
            let proof = try await attestation.makeAssertion(for: assertionInput, using: analysisChallenge)
            guard !proof.keyID.isEmpty, !proof.assertion.isEmpty else { return .unavailable }

            let expectedURL = configuration.analysisURL
            let response = try await transport.perform(
                NetscopeAuthenticatedHTTPRequest(
                    url: expectedURL,
                    body: exactBody,
                    assertionInput: assertionInput,
                    analysisChallenge: analysisChallenge,
                    attestation: proof
                )
            )
            guard response.finalURL == expectedURL, (200...299).contains(response.statusCode) else {
                return .unavailable
            }

            let decoded = try NetscopeV1Codec.decodeResponse(response.body)
            try NetscopeV1Codec.validateResponse(decoded, for: input)
            return .response(decoded)
        } catch {
            return .unavailable
        }
    }
}
