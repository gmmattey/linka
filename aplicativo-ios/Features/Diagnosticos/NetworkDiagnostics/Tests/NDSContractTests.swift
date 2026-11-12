import XCTest
@testable import NetworkDiagnostics
import NetworkCore
import NetworkAssist

final class NDSContractTests: XCTestCase {
    func testDecodeNDSResponse() throws {
        let json = """
        {
          "recommendation": {
            "id": "REC_WIFI_FAR",
            "type": "wifi_issue",
            "title": "Sinal Wi-Fi fraco",
            "description": "Aproxime-se do roteador...",
            "steps": ["Aproxime-se do roteador.", "Repita a medição."],
            "source_finding_ids": ["wifi_signal_critical"]
          },
          "traces": [
            { "module": "scoring", "duration_ms": 3, "status": "ok" }
          ],
          "results": [
            {
              "module": "diagnostics.wifi",
              "result": {},
              "cards": [
                {
                  "id": "wifi_far",
                  "titulo": "Sinal Fraco",
                  "status": "attention",
                  "evidencia": null,
                  "mensagemUsuario": "Latência elevada",
                  "recomendacao": null,
                  "categoria": "wifi",
                  "podeConcluir": false,
                  "categoriaOrigem": null
                }
              ]
            },
            {
              "module": "scoring",
              "result": {
                "score": 85,
                "veredicto": "bom",
                "observed_dimensions": 2
              }
            },
            {
              "module": "ai",
              "result": {
                "explanation": {
                  "titulo_amigavel": "Tudo certo",
                  "resumo_tecnico_traduzido": "Sua conexão está boa."
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(NDSResponse.self, from: json)
        
        XCTAssertEqual(response.recommendation?.id, "REC_WIFI_FAR")
        XCTAssertEqual(response.recommendation?.steps, ["Aproxime-se do roteador.", "Repita a medição."])
        XCTAssertEqual(response.traces?.first?.durationMs, 3)
        XCTAssertEqual(response.results?.first(where: { $0.module == "scoring" })?.result?.score, 85)
        XCTAssertEqual(response.results?.first(where: { $0.module == "scoring" })?.result?.veredicto, "bom")
        XCTAssertEqual(response.results?.first(where: { $0.module == "diagnostics.wifi" })?.cards?.first?.mensagemUsuario, "Latência elevada")
    }

    /// Contrato v2 (`raw` + `explanation`): `explanation.titulo`/`descricao`
    /// mapeiam para title/summary, e o `raw` carrega a mesma análise crua
    /// do v1 (`results`/`recommendation`), só aninhada.
    func testDecodeNDSV2Response() throws {
        let json = """
        {
          "raw": {
            "results": [
              { "module": "scoring", "result": { "score": 40, "veredicto": "ruim" } }
            ],
            "recommendation": { "id": "REC_X", "type": "x", "title": "t", "description": "d", "steps": [] }
          },
          "explanation": {
            "titulo": "Ping alto identificado",
            "descricao": "Seu ping está bem acima do esperado para jogos.",
            "dados": "Ping médio de 180ms nos últimos testes.",
            "acao_usuario": "Conecte o console por cabo em vez de Wi-Fi.",
            "provenance": {
              "source": "ai",
              "model_label": "gpt-5.6-luna"
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NDSResponse.self, from: json)

        XCTAssertEqual(response.explanation?.titulo, "Ping alto identificado")
        XCTAssertEqual(response.explanation?.descricao, "Seu ping está bem acima do esperado para jogos.")
        XCTAssertEqual(response.explanation?.dados, ["Ping médio de 180ms nos últimos testes."])
        XCTAssertEqual(response.explanation?.acaoUsuario, "Conecte o console por cabo em vez de Wi-Fi.")
        XCTAssertNil(response.explanation?.semCausaIdentificada)
        XCTAssertEqual(response.explanation?.provenance?.source, "ai")
        XCTAssertEqual(response.explanation?.provenance?.modelLabel, "gpt-5.6-luna")
        XCTAssertEqual(BuildeaDiagnosticTransport.formatProvenance(response.explanation?.provenance), "ChatGPT – Luna")
        XCTAssertEqual(response.effectiveResults?.first?.result?.score, 40)
        XCTAssertEqual(response.effectiveRecommendation?.id, "REC_X")
    }

    /// `sem_causa_identificada == true`: nenhuma regra disparou. O
    /// decoder precisa expor isso sem exigir `titulo`/`descricao`.
    func testDecodeNDSV2ResponseSemCausaIdentificada() throws {
        let json = """
        {
          "raw": { "results": [], "recommendation": null },
          "explanation": { "sem_causa_identificada": true }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NDSResponse.self, from: json)

        XCTAssertEqual(response.explanation?.semCausaIdentificada, true)
        XCTAssertNil(response.explanation?.titulo)
    }

    /// Regressão: uma resposta v1 pura (sem `raw`/`explanation`) continua
    /// decodificando e `effectiveResults`/`effectiveRecommendation` caem
    /// para os campos de topo, exatamente como antes desta issue.
    func testDecodeNDSV1ResponseStillWorksAndEffectiveFieldsFallBackToTopLevel() throws {
        let json = """
        {
          "recommendation": { "id": "REC_V1", "type": "x", "title": "t", "description": "d", "steps": [] },
          "results": [
            { "module": "scoring", "result": { "score": 90, "veredicto": "bom" } }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NDSResponse.self, from: json)

        XCTAssertNil(response.raw)
        XCTAssertNil(response.explanation)
        XCTAssertEqual(response.effectiveRecommendation?.id, "REC_V1")
        XCTAssertEqual(response.effectiveResults?.first?.result?.score, 90)
    }

    func testDecodeCanonicalErrorEnvelope() throws {
        let json = """
        {
          "error": {
            "code": "NDS_TIMEOUT",
            "message": "A análise demorou mais que o limite do serviço. Tente novamente.",
            "retryable": true
          },
          "request_id": "req-123"
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(NDSErrorEnvelope.self, from: json)

        XCTAssertEqual(envelope.error.code, "NDS_TIMEOUT")
        XCTAssertTrue(envelope.error.retryable)
        XCTAssertEqual(envelope.requestID, "req-123")
    }

    func testDecodeResponseWithoutRecommendation() throws {
        let response = try JSONDecoder().decode(
            NDSResponse.self,
            from: Data("{\"results\":[],\"traces\":[],\"recommendation\":null}".utf8)
        )

        XCTAssertNil(response.recommendation)
        XCTAssertEqual(response.results, [])
    }

    func testAPIPropagatesCanonicalNDSFailure() async throws {
        let client = StubDiagnosticHTTPClient(
            data: Data("""
            {
              "error": {
                "code": "NDS_TIMEOUT",
                "message": "Tente novamente.",
                "retryable": true
              },
              "request_id": "req-456"
            }
            """.utf8),
            status: 504
        )
        let configuration = NetworkDiagnosticsConfiguration(
            rulesEndpoint: URL(string: "https://example.com/v1/diagnostics/evaluate")!,
            bearerToken: "test-token",
            platformIdentifier: "ios"
        )
        let api = BuildeaDiagnosticAPI(configuration: configuration, httpClient: client)
        let measurement = NetworkMeasurement(
            id: UUID(),
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20,
            connectionKind: .wifi
        )

        do {
            _ = try await api.evaluate(measurement, requestAI: true)
            XCTFail("A falha canônica do NDS deveria ser propagada")
        } catch let error as NetworkDiagnosticsError {
            XCTAssertEqual(
                error,
                .nds(code: "NDS_TIMEOUT", message: "Tente novamente.", retryable: true, requestID: "req-456")
            )
        }
    }

    func testAPIFailsClosedWithoutCredential() async throws {
        let configuration = NetworkDiagnosticsConfiguration(
            rulesEndpoint: URL(string: "https://example.com/v1/diagnostics/evaluate")!,
            platformIdentifier: "ios"
        )
        let api = BuildeaDiagnosticAPI(
            configuration: configuration,
            httpClient: StubDiagnosticHTTPClient(data: Data(), status: 200)
        )
        let measurement = NetworkMeasurement(
            id: UUID(),
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20,
            connectionKind: .wifi
        )

        do {
            _ = try await api.evaluate(measurement, requestAI: false)
            XCTFail("A API deveria falhar fechada sem credencial")
        } catch let error as NetworkDiagnosticsError {
            XCTAssertEqual(error, .notConfigured)
        }
    }

    func testConfiguredRelayDoesNotSendBearerCredential() async throws {
        let client = RecordingDiagnosticHTTPClient(
            data: try JSONEncoder().encode(NDSResponse(results: [], traces: [], recommendation: nil)),
            status: 200
        )
        let api = BuildeaDiagnosticAPI(
            configuration: NetworkDiagnosticsConfiguration(
                rulesEndpoint: URL(string: "https://relay.example/v1/assist")!,
                transportAuth: .relay,
                platformIdentifier: "ios"
            ),
            httpClient: client
        )

        let measurement = NetworkMeasurement(
            id: UUID(), outcome: .complete, downloadMbps: 100, uploadMbps: 50,
            latencyMs: 20, connectionKind: .wifi
        )
        _ = try await api.evaluate(measurement, requestAI: true)

        let bearerToken = await client.bearerToken
        XCTAssertNil(bearerToken)
    }

    func testEvaluateAlwaysUsesV2Endpoint() async throws {
        let client = URLRecordingDiagnosticHTTPClient(
            data: try JSONEncoder().encode(NDSResponse()),
            status: 200
        )
        let configuration = NetworkDiagnosticsConfiguration(
            rulesEndpoint: URL(string: "https://example.com/v1/diagnostics/evaluate")!,
            transportAuth: .relay,
            platformIdentifier: "ios"
        )
        let api = BuildeaDiagnosticAPI(configuration: configuration, httpClient: client)
        let measurement = NetworkMeasurement(
            id: UUID(), outcome: .complete, downloadMbps: 100, uploadMbps: 50,
            latencyMs: 20, connectionKind: .wifi
        )

        _ = try await api.evaluate(measurement, requestAI: true)
        let calledURL = await client.calledURL
        XCTAssertEqual(calledURL, URL(string: "https://example.com/v2/diagnostics/evaluate")!)
    }

}

private struct StubDiagnosticHTTPClient: DiagnosticHTTPClient {
    let data: Data
    let status: Int

    func postJSON(url: URL, body: Data, timeout: TimeInterval, bearerToken: String?) async throws -> (Data, Int) {
        (data, status)
    }
}

private actor URLRecordingDiagnosticHTTPClient: DiagnosticHTTPClient {
    let data: Data
    let status: Int
    private(set) var calledURL: URL?

    init(data: Data, status: Int) {
        self.data = data
        self.status = status
    }

    func postJSON(url: URL, body: Data, timeout: TimeInterval, bearerToken: String?) async throws -> (Data, Int) {
        self.calledURL = url
        return (data, status)
    }
}

private actor RecordingDiagnosticHTTPClient: DiagnosticHTTPClient {
    let data: Data
    let status: Int
    private(set) var bearerToken: String?

    init(data: Data, status: Int) {
        self.data = data
        self.status = status
    }

    func postJSON(url: URL, body: Data, timeout: TimeInterval, bearerToken: String?) async throws -> (Data, Int) {
        self.bearerToken = bearerToken
        return (data, status)
    }
}
