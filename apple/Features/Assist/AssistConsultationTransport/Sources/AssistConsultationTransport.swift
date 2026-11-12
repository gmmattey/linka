import AssistConsultation
import Foundation

/// Configuração fechada da consulta remota V4.
///
/// Não aceita hosts, caminhos, redirecionamentos ou fallback configuráveis pelo
/// cliente. A flag nasce desligada: instalar este pacote não cria tráfego.
public struct AssistConsultationTransportConfiguration: Equatable, Sendable {
    public static let fixedEndpoint = URL(string: "https://linka-assist-relay.buildealabs.workers.dev/v1/assist/consultations")!

    public let isEnabled: Bool
    public let endpoint: URL

    public init(isEnabled: Bool = false, endpoint: URL = Self.fixedEndpoint) throws {
        guard endpoint == Self.fixedEndpoint,
              endpoint.scheme?.lowercased() == "https",
              endpoint.user == nil,
              endpoint.password == nil,
              endpoint.query == nil,
              endpoint.fragment == nil else {
            throw AssistConsultationTransportConfigurationError.invalidEndpoint
        }
        self.isEnabled = isEnabled
        self.endpoint = endpoint
    }

    /// Lê somente a chave V4 do Info.plist. Ausência ou qualquer valor que não
    /// seja `YES` mantém o recurso desligado; URL diferente nunca é aceita.
    public init(infoDictionary: [String: Any]) throws {
        let enabled = (infoDictionary["LinkaAssistConsultationEnabled"] as? String) == "YES"
        let declaredEndpoint = infoDictionary["LinkaAssistConsultationEndpoint"] as? String
        guard let declaredEndpoint, let endpoint = URL(string: declaredEndpoint) else {
            if enabled { throw AssistConsultationTransportConfigurationError.invalidEndpoint }
            try self.init(isEnabled: false)
            return
        }
        try self.init(isEnabled: enabled, endpoint: endpoint)
    }
}

public enum AssistConsultationTransportConfigurationError: Error, Equatable, Sendable {
    case invalidEndpoint
}

/// O limite de I/O é injetado pelo composition root iOS. Este pacote não cria
/// URLSession e, por isso, não tem egress implícito ou caminho de legado.
public protocol AssistConsultationHTTPTransporting: Sendable {
    func perform(_ request: AssistConsultationHTTPRequest) async throws -> AssistConsultationHTTPResponse
}

/// Request já serializado. `body` é o mesmo conjunto de bytes validado pelo
/// contrato e enviado ao adaptador; nenhuma reserialização é permitida aqui.
public struct AssistConsultationHTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data

    fileprivate init(url: URL, body: Data, idempotencyKey: String) {
        self.url = url
        method = "POST"
        headers = [
            "Accept": "application/json",
            "Cache-Control": "no-store",
            "Content-Type": "application/json",
            "Idempotency-Key": idempotencyKey
        ]
        self.body = body
    }
}

/// O adaptador concreto deve reportar a URL final observada. Mesmo um redirect
/// HTTPS para outro caminho é rejeitado antes de decodificar qualquer dado.
public struct AssistConsultationHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data
    public let finalURL: URL

    public init(statusCode: Int, body: Data, finalURL: URL) {
        self.statusCode = statusCode
        self.body = body
        self.finalURL = finalURL
    }
}

public enum AssistConsultationTransportFailure: Equatable, Sendable {
    case disabled
    case invalidRequest
    case transportUnavailable
    case redirected
    case rejectedStatus(Int)
    case invalidResponse
}

public enum AssistConsultationTransportOutcome: Equatable, Sendable {
    case response(ConsultationResponse)
    case unavailable(AssistConsultationTransportFailure)
}

/// Cliente V4 de uma única rota. Ele não conhece `/v2/assist`, NetworkAssist,
/// provider, UI ou estado local. A camada atestada futura pode implementar o
/// protocolo HTTP injetado, recebendo exatamente os bytes deste request.
public struct AssistConsultationTransportClient: Sendable {
    private let configuration: AssistConsultationTransportConfiguration
    private let transport: any AssistConsultationHTTPTransporting

    public init(
        configuration: AssistConsultationTransportConfiguration,
        transport: any AssistConsultationHTTPTransporting
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Prepara bytes canônicos para um único POST V4 sem realizar I/O.
    public func makeRequest(
        for payload: ConsultationPayload,
        now: Date = Date()
    ) throws -> AssistConsultationHTTPRequest {
        let exactBody = try AssistConsultationContract.encode(payload, now: now)
        return AssistConsultationHTTPRequest(
            url: configuration.endpoint,
            body: exactBody,
            idempotencyKey: payload.requestID.value
        )
    }

    /// Não faz retry automático, não segue redirects e sempre confere a
    /// resposta contra o payload correspondente antes de expô-la ao app.
    public func send(
        _ payload: ConsultationPayload,
        now: Date = Date()
    ) async -> AssistConsultationTransportOutcome {
        guard configuration.isEnabled else { return .unavailable(.disabled) }

        let request: AssistConsultationHTTPRequest
        do {
            request = try makeRequest(for: payload, now: now)
        } catch {
            return .unavailable(.invalidRequest)
        }

        do {
            let response = try await transport.perform(request)
            guard response.finalURL == configuration.endpoint else {
                return .unavailable(.redirected)
            }
            guard (200...299).contains(response.statusCode) else {
                return .unavailable(.rejectedStatus(response.statusCode))
            }
            do {
                let decoded = try AssistConsultationContract.decodeResponse(response.body, for: payload, now: now)
                return .response(decoded)
            } catch {
                return .unavailable(.invalidResponse)
            }
        } catch {
            return .unavailable(.transportUnavailable)
        }
    }
}
