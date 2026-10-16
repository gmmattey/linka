import XCTest
@testable import LinkaApp
import NetworkCore
import NetworkInventory

final class LinkaGeniusTests: XCTestCase {

    // MARK: - 1. Testes de Resolução de Chave de API

    func testKeyProviderResolvesFromEnvironmentFirst() {
        let provider = DefaultLinkaGeniusKeyProvider(
            environmentLookup: { key in
                key == "GEMINI_API_KEY" ? "env_test_key_123" : nil
            },
            fileReader: { _ in "GEMINI_API_KEY=file_key_456" }
        )

        let resolved = provider.resolveKey()
        XCTAssertEqual(resolved, "env_test_key_123")
    }

    func testKeyProviderResolvesFromEnvLocalWhenEnvironmentMissing() {
        let provider = DefaultLinkaGeniusKeyProvider(
            environmentLookup: { _ in nil },
            fileReader: { path in
                if path.contains(".env.local") {
                    return "OTHER_VAR=abc\nGEMINI_API_KEY=parsed_from_env_local\nANOTHER=xyz"
                }
                return nil
            }
        )

        let resolved = provider.resolveKey()
        XCTAssertEqual(resolved, "parsed_from_env_local")
    }

    func testKeyProviderResolvesFromUserDocumentsWhenEnvLocalMissing() {
        let provider = DefaultLinkaGeniusKeyProvider(
            environmentLookup: { _ in nil },
            fileReader: { path in
                if path.contains("Gemini API KEY.md") {
                    return "Gemini API KEY\nmock-gemini-key-for-unit-testing\n"
                }
                return nil
            }
        )

        let resolved = provider.resolveKey()
        XCTAssertEqual(resolved, "mock-gemini-key-for-unit-testing")
    }

    func testKeyProviderReturnsNilWhenNoKeyAvailable() {
        let provider = DefaultLinkaGeniusKeyProvider(
            environmentLookup: { _ in nil },
            fileReader: { _ in nil }
        )

        XCTAssertNil(provider.resolveKey())
    }

    // MARK: - 2. Testes de Montagem de Contexto e Fatos

    func testContextAssemblerWithFullMeasurementAndPlan() async {
        let wifiContext = WiFiNetworkContext(
            ssid: "MinhaRede_5G",
            bandGHz: 5.0,
            rssiDbm: -55.0,
            linkSpeedMbps: 866.0,
            gatewayIP: "192.168.1.1",
            gatewayVendor: "TP-Link"
        )

        let measurement = NetworkMeasurement(
            downloadMbps: 450.5,
            uploadMbps: 150.2,
            latencyMs: 12.4,
            jitterMs: 1.8,
            packetLossPercent: 0.0,
            loadedLatencyMs: 25.0,
            loadedLatencyUploadMs: 30.0,
            connectionKind: .wifi,
            wifiBandGHz: 5.0,
            wifiContext: wifiContext
        )

        let plan = NetworkServicePlan(
            ispName: "Fibra Telecom",
            planName: "Super Fibra 500",
            nominalDownloadMbps: 500.0,
            nominalUploadMbps: 250.0,
            technology: .fiber,
            monthlyCostCents: 9990
        )

        let device = RegisteredNetworkDevice(
            identity: DeviceIdentity(brand: "TP-Link", model: "Archer AX50"),
            installation: DeviceInstallation(role: .mainRouter, ownership: .userOwned)
        )

        let context = LinkaGeniusContext(
            question: "Como está minha velocidade?",
            measurement: measurement,
            plan: plan,
            devices: [device],
            locale: "pt-BR"
        )

        let report = LinkaGeniusContextAssembler.buildFactualReport(for: context)
        XCTAssertTrue(report.contains("450.50 Mbps"))
        XCTAssertTrue(report.contains("150.20 Mbps"))
        XCTAssertTrue(report.contains("12.4 ms"))
        XCTAssertTrue(report.contains("MinhaRede_5G"))
        XCTAssertTrue(report.contains("TP-Link Archer AX50"))
        XCTAssertTrue(report.contains("Fibra Telecom"))
    }

    func testContextAssemblerWithoutMeasurementOrPlan() {
        let context = LinkaGeniusContext(
            question: "Minha internet está lenta?",
            measurement: nil,
            plan: nil,
            devices: [],
            locale: "pt-BR"
        )

        let report = LinkaGeniusContextAssembler.buildFactualReport(for: context)
        XCTAssertTrue(report.contains("Nenhuma medição de velocidade foi realizada recentemente."))
        XCTAssertTrue(report.contains("Nenhum plano residencial cadastrado no inventário."))
        XCTAssertTrue(report.contains("Nenhum equipamento cadastrado."))
    }

    // MARK: - 3. Testes do Prompt Builder e Idiomas

    func testPromptBuilderGeneratesCorrectLanguageInstruction() {
        let ptSystem = LinkaGeniusPromptBuilder.buildSystemInstruction(locale: "pt-BR")
        XCTAssertTrue(ptSystem.contains("Português do Brasil (pt-BR)"))

        let enSystem = LinkaGeniusPromptBuilder.buildSystemInstruction(locale: "en")
        XCTAssertTrue(enSystem.contains("strictly in English (en)"))

        let esSystem = LinkaGeniusPromptBuilder.buildSystemInstruction(locale: "es-419")
        XCTAssertTrue(esSystem.contains("Español Latinoamericano (es-419)"))
    }

    func testPromptBuilderBuildsValidGeminiRequest() {
        let context = LinkaGeniusContext(
            question: "Chamadas travando",
            measurement: nil,
            plan: nil,
            locale: "pt-BR"
        )

        let request = LinkaGeniusPromptBuilder.buildRequest(for: context)
        XCTAssertEqual(request.contents.count, 1)
        XCTAssertEqual(request.contents.first?.role, "user")
        XCTAssertEqual(request.systemInstruction?.role, "system")
        XCTAssertEqual(request.generationConfig?.responseMimeType, "application/json")
        XCTAssertEqual(request.generationConfig?.responseSchema?.properties?.count, 5)
    }

    // MARK: - 4. Testes de Serviço e Transporte com Mocks

    func testServiceSuccessfulJSONResponseParsing() async throws {
        let sampleAnalysisJSON = """
        {
          "symptom": "Chamadas de vídeo congelando e áudio picotado",
          "cause": "Bufferbloat severo sob tráfego na frequência de 2.4 GHz",
          "actions": [
            "Conectar na rede Wi-Fi de 5 GHz",
            "Reiniciar o roteador para limpar as tabelas de NAT",
            "Se possível, utilizar cabo de rede para chamadas críticas"
          ],
          "operatorScript": "Prezados, realizo medições com 320ms de latência sob carga e peço revisão do perfil de fila.",
          "needsRetest": true
        }
        """

        let geminiResponseEnvelope = """
        {
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": \(sampleAnalysisJSON.debugDescription)
                  }
                ]
              },
              "finishReason": "STOP"
            }
          ]
        }
        """

        let mockTransport = MockGeniusHTTPTransport(
            statusCode: 200,
            responseData: geminiResponseEnvelope.data(using: .utf8)!
        )

        let service = LinkaGeniusService(
            configuration: LinkaGeniusConfiguration(model: "gemini-3.8-flash"),
            keyProvider: MockKeyProvider(key: "test_key"),
            transport: mockTransport
        )

        let context = LinkaGeniusContext(question: "Chamadas travando", measurement: nil, plan: nil)
        let analysis = try await service.analyze(context: context)

        XCTAssertEqual(analysis.symptom, "Chamadas de vídeo congelando e áudio picotado")
        XCTAssertEqual(analysis.cause, "Bufferbloat severo sob tráfego na frequência de 2.4 GHz")
        XCTAssertEqual(analysis.actions.count, 3)
        XCTAssertEqual(analysis.operatorScript, "Prezados, realizo medições com 320ms de latência sob carga e peço revisão do perfil de fila.")
        XCTAssertTrue(analysis.needsRetest)
    }

    func testServiceHandles503HighDemandGracefully() async {
        let mockTransport = MockGeniusHTTPTransport(
            statusCode: 503,
            responseData: "{\"error\":{\"code\":503,\"message\":\"High demand\"}}".data(using: .utf8)!
        )

        let service = LinkaGeniusService(
            keyProvider: MockKeyProvider(key: "test_key"),
            transport: mockTransport
        )

        let context = LinkaGeniusContext(question: "Teste", measurement: nil, plan: nil)
        do {
            _ = try await service.analyze(context: context)
            XCTFail("Deveria ter lançado LinkaGeniusError.serviceBusy")
        } catch let error as LinkaGeniusError {
            guard case .serviceBusy(let message) = error else {
                return XCTFail("Esperado .serviceBusy, recebido \(error)")
            }
            XCTAssertTrue(message.contains("alta demanda"))
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    func testServiceHandles429QuotaExceeded() async {
        let mockTransport = MockGeniusHTTPTransport(
            statusCode: 429,
            responseData: Data()
        )

        let service = LinkaGeniusService(
            keyProvider: MockKeyProvider(key: "test_key"),
            transport: mockTransport
        )

        let context = LinkaGeniusContext(question: "Teste", measurement: nil, plan: nil)
        do {
            _ = try await service.analyze(context: context)
            XCTFail("Deveria ter lançado .quotaExceeded")
        } catch let error as LinkaGeniusError {
            XCTAssertEqual(error, .quotaExceeded)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    func testServiceHandlesMissingAPIKey() async {
        let service = LinkaGeniusService(
            keyProvider: MockKeyProvider(key: nil),
            transport: MockGeniusHTTPTransport(statusCode: 200, responseData: Data())
        )

        let context = LinkaGeniusContext(question: "Teste", measurement: nil, plan: nil)
        do {
            _ = try await service.analyze(context: context)
            XCTFail("Deveria ter lançado .missingAPIKey")
        } catch let error as LinkaGeniusError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    func testServiceHandlesOfflineNetwork() async {
        let mockTransport = MockGeniusHTTPTransport(
            error: URLError(.notConnectedToInternet)
        )

        let service = LinkaGeniusService(
            keyProvider: MockKeyProvider(key: "test_key"),
            transport: mockTransport
        )

        let context = LinkaGeniusContext(question: "Teste", measurement: nil, plan: nil)
        do {
            _ = try await service.analyze(context: context)
            XCTFail("Deveria ter lançado .networkOffline")
        } catch let error as LinkaGeniusError {
            XCTAssertEqual(error, .networkOffline)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    // MARK: - 5. Testes da Máquina de Estados do ViewModel

    @MainActor
    func testViewModelTransitionsFromIdleToSuccess() async {
        let expectedAnalysis = LinkaGeniusAnalysis(
            symptom: "Sintoma de teste",
            cause: "Causa de teste",
            actions: ["Passo 1"],
            operatorScript: "Script para o provedor",
            needsRetest: false
        )

        let mockService = MockGeniusService(result: .success(expectedAnalysis))
        let viewModel = LinkaGeniusViewModel(
            geniusService: mockService,
            contextAssembler: LinkaGeniusContextAssembler(),
            measurementProvider: { nil }
        )

        XCTAssertEqual(viewModel.state, LinkaGeniusState.idle)

        viewModel.ask(shortcut: .slowCalls)
        XCTAssertEqual(viewModel.state, LinkaGeniusState.readingTelemetry)

        // Aguarda execução da Task assíncrona
        for _ in 0..<15 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 30_000_000)
        }

        XCTAssertEqual(viewModel.state, LinkaGeniusState.success(expectedAnalysis))
        XCTAssertEqual(viewModel.activeAnalysis, expectedAnalysis)
    }

    @MainActor
    func testViewModelTransitionsToFailureAndSupportsRetry() async {
        let mockService = MockGeniusService(result: .failure(LinkaGeniusError.serviceBusy("Alta demanda")))
        let viewModel = LinkaGeniusViewModel(
            geniusService: mockService,
            contextAssembler: LinkaGeniusContextAssembler(),
            measurementProvider: { nil }
        )

        viewModel.draft = "Por que meu ping está alto?"
        viewModel.submitDraft()

        for _ in 0..<10 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(viewModel.state, LinkaGeniusState.failure(.serviceBusy("Alta demanda")))

        // Testar reset
        viewModel.reset()
        XCTAssertEqual(viewModel.state, LinkaGeniusState.idle)
        XCTAssertNil(viewModel.activeAnalysis)
        XCTAssertEqual(viewModel.draft, "")
    }
}

// MARK: - Mocks para Testes

private struct MockKeyProvider: LinkaGeniusKeyProviding {
    let key: String?
    func resolveKey() -> String? { key }
}

private struct MockGeniusHTTPTransport: LinkaGeniusHTTPTransporting {
    let statusCode: Int
    let responseData: Data
    let error: Error?

    init(statusCode: Int = 200, responseData: Data = Data(), error: Error? = nil) {
        self.statusCode = statusCode
        self.responseData = responseData
        self.error = error
    }

    func execute(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let error {
            throw error
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

private struct MockGeniusService: LinkaGeniusServicing {
    let result: Result<LinkaGeniusAnalysis, Error>

    func analyze(context: LinkaGeniusContext) async throws -> LinkaGeniusAnalysis {
        try result.get()
    }
}
