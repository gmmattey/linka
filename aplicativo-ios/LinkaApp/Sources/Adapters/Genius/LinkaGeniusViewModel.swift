import Foundation
import Combine
import NetworkCore
import NetworkInventory

/// ViewModel responsável pelo fluxo conversacional inteligente do Linka Genius.
@MainActor
public final class LinkaGeniusViewModel: ObservableObject {
    @Published public private(set) var state: LinkaGeniusState = .idle
    @Published public var draft: String = ""
    @Published public private(set) var activeAnalysis: LinkaGeniusAnalysis?
    @Published public private(set) var activeContext: LinkaGeniusContext?
    @Published public private(set) var selectedShortcut: LinkaGeniusShortcut?

    private let geniusService: any LinkaGeniusServicing
    private let contextAssembler: LinkaGeniusContextAssembler
    private let measurementProvider: @Sendable () -> NetworkMeasurement?
    private var lastQuestion: String?

    public init(
        geniusService: any LinkaGeniusServicing = LinkaGeniusService(),
        contextAssembler: LinkaGeniusContextAssembler = LinkaGeniusContextAssembler(),
        measurementProvider: @escaping @Sendable () -> NetworkMeasurement? = { nil }
    ) {
        self.geniusService = geniusService
        self.contextAssembler = contextAssembler
        self.measurementProvider = measurementProvider
    }

    /// Executa um diagnóstico a partir de um dos atalhos pré-configurados.
    public func ask(shortcut: LinkaGeniusShortcut) {
        selectedShortcut = shortcut
        let prompt = shortcut.promptText()
        draft = prompt
        executeAnalysis(for: prompt)
    }

    /// Executa um diagnóstico com o texto digitado livremente pelo usuário.
    public func submitDraft() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        selectedShortcut = nil
        executeAnalysis(for: question)
    }

    /// Retenta a última pergunta submetida mantendo o contexto.
    public func retry() {
        guard let question = lastQuestion else { return }
        executeAnalysis(for: question)
    }

    /// Retorna a tela ao estado inicial (idle) para novas consultas.
    public func reset() {
        state = .idle
        activeAnalysis = nil
        activeContext = nil
        selectedShortcut = nil
        draft = ""
        lastQuestion = nil
    }

    // MARK: - Private Execution Pipeline

    private func executeAnalysis(for question: String) {
        lastQuestion = question
        state = .readingTelemetry

        Task {
            // 1. Fase de leitura de telemetria
            let currentMeasurement = measurementProvider()
            let context = await contextAssembler.assemble(
                question: question,
                measurement: currentMeasurement
            )
            self.activeContext = context

            // 2. Transição sequencial para consulta do Genius
            self.state = .consultingGenius

            do {
                // 3. Chamada de rede ao serviço Gemini 3.8 Flash
                let analysis = try await geniusService.analyze(context: context)

                // 4. Transição suave de finalização e sucesso
                self.state = .finalizing
                // Pequena pausa assíncrona cooperativa para a transição fluida na UI
                try? await Task.sleep(nanoseconds: 200_000_000)

                self.activeAnalysis = analysis
                self.state = .success(analysis)
            } catch let geniusError as LinkaGeniusError {
                self.state = .failure(geniusError)
            } catch {
                self.state = .failure(.generic(error.localizedDescription))
            }
        }
    }
}
