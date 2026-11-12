import XCTest
@testable import NetworkDiagnostics
import NetworkAssist
import NetworkCore

/// Cobertura do parsing do contrato v2 (`raw`+`explanation`) dentro de
/// `BuildeaDiagnosticTransport.answer(_:)` — mapeamento
/// titulo/descricao/dados/acao_usuario → title/summary/recommendation, o
/// caminho `sem_causa_identificada`, e regressão do formato v1 puro.
final class BuildeaDiagnosticTransportV2Tests: XCTestCase {
    /// `NetworkAssistRequest.init(validated:)` é `internal` ao pacote
    /// `NetworkAssist` — este teste vive em `NetworkDiagnostics`, então
    /// monta o mesmo valor via `Codable` (todos os campos são públicos e
    /// `Codable`), sem depender de um initializer não exposto.
    private func makeRequest(
        objective: String? = nil,
        subcategory: String? = nil,
        reportedProblem: String? = nil,
        locale: String? = nil
    ) throws -> NetworkAssistRequest {
        let measurement = NetworkMeasurement(
            id: UUID(), outcome: .complete, downloadMbps: 100, uploadMbps: 50,
            latencyMs: 20, connectionKind: .wifi
        )
        let evidence = NetworkAssistEvidence(
            id: NetworkAssistRequest.currentMeasurementEvidenceID(measurement.id),
            kind: .metric,
            sourceMeasurementIDs: [measurement.id]
        )
        let requestLike = RequestLike(
            question: "Interprete esta medição com os dados disponíveis.",
            currentMeasurement: measurement,
            recentMeasurements: [],
            evidence: [evidence],
            usageContext: nil,
            locale: locale,
            policy: .measurementUnderstanding,
            objective: objective,
            subcategory: subcategory,
            reportedProblem: reportedProblem
        )
        let data = try JSONEncoder().encode(requestLike)
        return try JSONDecoder().decode(NetworkAssistRequest.self, from: data)
    }

    /// Mesmo shape/`CodingKeys` de `NetworkAssistRequest` (Codable
    /// sintetizado), usado só para produzir o JSON que o decoder real de
    /// `NetworkAssistRequest` sabe ler.
    private struct RequestLike: Codable {
        let question: String
        let currentMeasurement: NetworkMeasurement
        let recentMeasurements: [NetworkMeasurement]
        let evidence: [NetworkAssistEvidence]
        let usageContext: String?
        let locale: String?
        let policy: NetworkAssistPolicy
        let objective: String?
        let subcategory: String?
        let reportedProblem: String?
    }

    func testAnswerMapsV2ExplanationToTitleSummaryAndRecommendation() async throws {
        let json = """
        {
          "raw": { "results": [], "recommendation": null },
          "explanation": {
            "titulo": "Ping alto identificado",
            "descricao": "Seu ping está bem acima do esperado para jogos.",
            "dados": "Ping médio de 180ms nos últimos testes.",
            "acao_usuario": "Conecte o console por cabo em vez de Wi-Fi."
          }
        }
        """.data(using: .utf8)!
        let client = StubHTTPClient(data: json, status: 200)
        let configuration = NetworkDiagnosticsConfiguration(
            rulesEndpoint: URL(string: "https://example.com/v1/diagnostics/evaluate")!,
            transportAuth: .relay,
            platformIdentifier: "ios"
        )
        let api = BuildeaDiagnosticAPI(configuration: configuration, httpClient: client)
        let transport = BuildeaDiagnosticTransport(api: api)

        let request = try makeRequest(objective: "JOGOS_COM_LAG", subcategory: "PING_ALTO")
        let response = try await transport.answer(request)

        XCTAssertEqual(response.title, "Ping alto identificado")
        XCTAssertEqual(response.summary, "Seu ping está bem acima do esperado para jogos.")
        XCTAssertEqual(response.recommendation?.title, "Conecte o console por cabo em vez de Wi-Fi.")
        XCTAssertEqual(response.recommendation?.description, "Ping médio de 180ms nos últimos testes.")
    }

    func testAnswerShowsTransparentMessageWhenSemCausaIdentificada() async throws {
        let json = """
        {
          "raw": { "results": [], "recommendation": null },
          "explanation": { "sem_causa_identificada": true }
        }
        """.data(using: .utf8)!
        let client = StubHTTPClient(data: json, status: 200)
        let configuration = NetworkDiagnosticsConfiguration(
            rulesEndpoint: URL(string: "https://example.com/v1/diagnostics/evaluate")!,
            transportAuth: .relay,
            platformIdentifier: "ios"
        )
        let api = BuildeaDiagnosticAPI(configuration: configuration, httpClient: client)
        let transport = BuildeaDiagnosticTransport(api: api)

        let request = try makeRequest(objective: "JOGOS_COM_LAG", subcategory: "PING_ALTO")
        let response = try await transport.answer(request)

        XCTAssertEqual(response.title, "Tudo funcionando normalmente")
        XCTAssertEqual(
            response.summary,
            "Não há problemas identificados na sua conexão. Tudo parece normal."
        )
        XCTAssertNil(response.recommendation)
    }

    /// Regressão: resposta v1 pura (sem `raw`/`explanation`) continua
    /// passando pelo caminho de copy existente (IA do módulo `ai` ou
    /// fallback determinístico), sem quebrar.
    func testAnswerStillHandlesV1ResponseFormat() async throws {
        let json = """
        {
          "recommendation": {
            "id": "REC_WIFI_FAR",
            "type": "wifi_issue",
            "title": "Sinal Wi-Fi fraco",
            "description": "Aproxime-se do roteador.",
            "steps": []
          },
          "results": [
            { "module": "scoring", "result": { "score": 60, "veredicto": "regular" } }
          ]
        }
        """.data(using: .utf8)!
        let client = StubHTTPClient(data: json, status: 200)
        let configuration = NetworkDiagnosticsConfiguration(
            rulesEndpoint: URL(string: "https://example.com/v1/diagnostics/evaluate")!,
            transportAuth: .relay,
            platformIdentifier: "ios"
        )
        let api = BuildeaDiagnosticAPI(configuration: configuration, httpClient: client)
        let transport = BuildeaDiagnosticTransport(api: api)

        // Fluxo observacional puro: sem objective/subcategory guiados.
        let request = try makeRequest()
        let response = try await transport.answer(request)

        XCTAssertEqual(response.title, "Sinal Wi-Fi fraco")
        XCTAssertEqual(response.summary, "Aproxime-se do roteador.")
        XCTAssertEqual(response.recommendation?.title, "Sinal Wi-Fi fraco")
    }

    /// "Outro problema": só `reportedProblem` chega ao transporte (sem
    /// objective/subcategory) — precisa virar `context.reported_problem` no
    /// payload do NDS e ainda seguir pela V2, que aceita a medição sem contexto
    /// guiado completo.
    func testAnswerSendsReportedProblemWithoutObjectiveThroughV2() async throws {
        let json = """
        {
          "recommendation": null,
          "results": [
            { "module": "scoring", "result": { "score": 80, "veredicto": "boa" } }
          ]
        }
        """.data(using: .utf8)!
        let client = CapturingHTTPClient(data: json, status: 200)
        let configuration = NetworkDiagnosticsConfiguration(
            rulesEndpoint: URL(string: "https://example.com/v1/diagnostics/evaluate")!,
            transportAuth: .relay,
            platformIdentifier: "ios"
        )
        let api = BuildeaDiagnosticAPI(configuration: configuration, httpClient: client)
        let transport = BuildeaDiagnosticTransport(api: api)

        let request = try makeRequest(
            reportedProblem: "Minha internet cai só quando chove.",
            locale: "en"
        )
        _ = try await transport.answer(request)

        let capturedURL = await client.capturedURL
        XCTAssertEqual(capturedURL, configuration.v2RulesEndpoint)

        let capturedBody = await client.capturedBody
        let payload = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: Any]
        let context = payload?["context"] as? [String: Any]
        XCTAssertEqual(context?["reported_problem"] as? String, "Minha internet cai só quando chove.")
        XCTAssertNil(context?["objective"])
        XCTAssertNil(context?["subcategory"])
        XCTAssertNil(payload?["historical"])
        XCTAssertEqual(payload?["locale"] as? String, "en")
    }

    func testAnswerUsesLocalSpanishFallbackOnlyWhenV2ExplanationIsIncomplete() async throws {
        let json = """
        { "raw": { "results": [] }, "explanation": {} }
        """.data(using: .utf8)!
        let api = BuildeaDiagnosticAPI(
            configuration: NetworkDiagnosticsConfiguration(
                rulesEndpoint: URL(string: "https://example.com/v1/diagnostics/evaluate")!,
                transportAuth: .relay,
                platformIdentifier: "ios"
            ),
            httpClient: StubHTTPClient(data: json, status: 200)
        )

        let response = try await BuildeaDiagnosticTransport(api: api).answer(
            try makeRequest(locale: "es-419")
        )

        XCTAssertEqual(response.title, "No se identificó una causa específica")
        XCTAssertEqual(response.summary, "No encontramos una causa específica. Inténtalo de nuevo más tarde.")
    }
}

private actor CapturingHTTPClient: DiagnosticHTTPClient {
    let data: Data
    let status: Int
    private(set) var capturedURL: URL?
    private(set) var capturedBody: Data?

    init(data: Data, status: Int) {
        self.data = data
        self.status = status
    }

    func postJSON(url: URL, body: Data, timeout: TimeInterval, bearerToken: String?) async throws -> (Data, Int) {
        capturedURL = url
        capturedBody = body
        return (data, status)
    }
}

private struct StubHTTPClient: DiagnosticHTTPClient {
    let data: Data
    let status: Int

    func postJSON(url: URL, body: Data, timeout: TimeInterval, bearerToken: String?) async throws -> (Data, Int) {
        (data, status)
    }
}
