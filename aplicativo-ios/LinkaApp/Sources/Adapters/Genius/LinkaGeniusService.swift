import Foundation

/// Protocolo de transporte HTTP para o Gemini, permitindo injeção de mocks determinísticos.
public protocol LinkaGeniusHTTPTransporting: Sendable {
    func execute(request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Implementação padrão com URLSession.
public struct DefaultLinkaGeniusHTTPTransport: LinkaGeniusHTTPTransporting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func execute(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LinkaGeniusError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as LinkaGeniusError {
            throw error
        } catch let urlError as URLError {
            if urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                throw LinkaGeniusError.networkOffline
            } else if urlError.code == .timedOut {
                throw LinkaGeniusError.serviceBusy("A consulta ao Genius excedeu o tempo limite. Tente novamente.")
            } else {
                throw LinkaGeniusError.generic(urlError.localizedDescription)
            }
        } catch {
            throw LinkaGeniusError.generic(error.localizedDescription)
        }
    }
}

/// Protocolo principal do serviço Linka Genius.
public protocol LinkaGeniusServicing: Sendable {
    func analyze(context: LinkaGeniusContext) async throws -> LinkaGeniusAnalysis
}

/// Serviço de produção do Linka Genius com integração à API do Google AI (Gemini 3.8 Flash).
public struct LinkaGeniusService: LinkaGeniusServicing {
    private let configuration: LinkaGeniusConfiguration
    private let keyProvider: any LinkaGeniusKeyProviding
    private let transport: any LinkaGeniusHTTPTransporting

    public init(
        configuration: LinkaGeniusConfiguration = LinkaGeniusConfiguration(),
        keyProvider: any LinkaGeniusKeyProviding = DefaultLinkaGeniusKeyProvider(),
        transport: any LinkaGeniusHTTPTransporting = DefaultLinkaGeniusHTTPTransport()
    ) {
        self.configuration = configuration
        self.keyProvider = keyProvider
        self.transport = transport
    }

    public func analyze(context: LinkaGeniusContext) async throws -> LinkaGeniusAnalysis {
        // 1. Resolver API Key
        guard let apiKey = keyProvider.resolveKey(), !apiKey.isEmpty else {
            throw LinkaGeniusError.missingAPIKey
        }

        // 2. Montar URL
        guard let url = configuration.endpointURL(apiKey: apiKey) else {
            throw LinkaGeniusError.generic("URL do endpoint Gemini inválida.")
        }

        // 3. Montar payload do request
        let requestPayload = LinkaGeniusPromptBuilder.buildRequest(for: context)
        let encoder = JSONEncoder()
        guard let httpBody = try? encoder.encode(requestPayload) else {
            throw LinkaGeniusError.generic("Falha ao codificar requisição para a API Gemini.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.httpBody = httpBody

        // 4. Executar transporte
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.execute(request: urlRequest)
        } catch let geniusError as LinkaGeniusError {
            throw geniusError
        } catch let urlError as URLError {
            if urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                throw LinkaGeniusError.networkOffline
            } else if urlError.code == .timedOut {
                throw LinkaGeniusError.serviceBusy("A consulta ao Genius excedeu o tempo limite. Tente novamente.")
            } else {
                throw LinkaGeniusError.generic(urlError.localizedDescription)
            }
        } catch {
            throw LinkaGeniusError.generic(error.localizedDescription)
        }

        // 5. Tratar código de resposta HTTP
        switch response.statusCode {
        case 200...299:
            return try parseSuccessResponse(data: data)

        case 401, 403:
            throw LinkaGeniusError.unauthorized

        case 429:
            throw LinkaGeniusError.quotaExceeded

        case 503:
            // Caso documentado de alta demanda no Gemini 3.8 Flash
            throw LinkaGeniusError.serviceBusy("O modelo Gemini 3.8 Flash está com alta demanda no momento. Toque para tentar novamente em instantes.")

        case 500, 502, 504:
            throw LinkaGeniusError.serviceBusy("Serviço temporariamente indisponível. Tente novamente em instantes.")

        default:
            // Tenta extrair mensagem de erro detalhada da API do Google se disponível
            if let errorEnvelope = try? JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data),
               let msg = errorEnvelope.error?.message {
                throw LinkaGeniusError.generic(msg)
            }
            throw LinkaGeniusError.generic("A API Gemini retornou código HTTP \(response.statusCode).")
        }
    }

    private func parseSuccessResponse(data: Data) throws -> LinkaGeniusAnalysis {
        let decoder = JSONDecoder()
        guard let geminiResponse = try? decoder.decode(GeminiGenerateContentResponse.self, from: data) else {
            throw LinkaGeniusError.invalidResponse
        }

        guard let jsonString = geminiResponse.firstOutputText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !jsonString.isEmpty else {
            throw LinkaGeniusError.invalidResponse
        }

        // Limpeza de possíveis blocos de markdown ```json ... ``` caso venham na string
        let cleanedJSON = Self.sanitizeJSONString(jsonString)

        guard let jsonData = cleanedJSON.data(using: .utf8),
              let analysis = try? decoder.decode(LinkaGeniusAnalysis.self, from: jsonData) else {
            throw LinkaGeniusError.invalidResponse
        }

        return analysis
    }

    /// Remove cercas de código markdown ```json se o modelo tiver envelopado.
    public static func sanitizeJSONString(_ raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("```json") {
            str = String(str.dropFirst(7))
        } else if str.hasPrefix("```") {
            str = String(str.dropFirst(3))
        }
        if str.hasSuffix("```") {
            str = String(str.dropLast(3))
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
