import Foundation
import NetworkCore

public enum NetworkAssistDisposition: String, Codable, Equatable, Sendable {
    case answered
    case insufficientEvidence
    case requiresDiagnosis
    case unsupported
}

public enum NetworkAssistEvidenceKind: String, Codable, Equatable, Sendable {
    case metric
    case comparison
    case statistic
    case trend
    case context
}

public struct NetworkAssistEvidence: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: NetworkAssistEvidenceKind
    public let metricKey: String?
    public let value: Double?
    public let baselineValue: Double?
    public let percentChange: Double?
    public let unit: String?
    public let direction: String?
    public let sourceMeasurementIDs: [UUID]

    public init(
        id: String,
        kind: NetworkAssistEvidenceKind,
        metricKey: String? = nil,
        value: Double? = nil,
        baselineValue: Double? = nil,
        percentChange: Double? = nil,
        unit: String? = nil,
        direction: String? = nil,
        sourceMeasurementIDs: [UUID] = []
    ) {
        self.id = id
        self.kind = kind
        self.metricKey = metricKey
        self.value = value
        self.baselineValue = baselineValue
        self.percentChange = percentChange
        self.unit = unit
        self.direction = direction
        self.sourceMeasurementIDs = sourceMeasurementIDs
    }
}

public struct NetworkAssistPolicy: Codable, Equatable, Sendable {
    public let observationalOnly: Bool
    public let mayInferRootCause: Bool
    public let mayRecommendRepair: Bool
    public let mustGroundInProvidedData: Bool
    public let handoffWhenDiagnosisIsRequired: Bool

    public static let measurementUnderstanding = NetworkAssistPolicy(
        observationalOnly: true,
        mayInferRootCause: false,
        mayRecommendRepair: false,
        mustGroundInProvidedData: true,
        handoffWhenDiagnosisIsRequired: true
    )
}

public struct NetworkAssistContext: Codable, Equatable, Sendable {
    public let question: String
    public let currentMeasurement: NetworkMeasurement
    public let recentMeasurements: [NetworkMeasurement]
    public let evidence: [NetworkAssistEvidence]
    /// Contexto de uso informado pelo usuário, quando existir. Ausência é
    /// diferente de uma finalidade inferida pelo cliente.
    public let usageContext: String?
    public let diagnosticPayload: String?
    public let locale: String?
    /// Macro-grupo do problema escolhido pelo usuário no fluxo guiado
    /// (`AssistProblemSelectionView`), ex.: `"JOGOS_COM_LAG"`. `nil` no
    /// fluxo observacional puro — o Assist continua funcionando sem essa
    /// seleção, só sem o contrato v2 do NDS.
    public let objective: String?
    /// Subcategoria fechada dentro de `objective`, ex.: `"PING_ALTO"`.
    /// Só existe quando `objective` também existe — o fluxo guiado sempre
    /// coleta as duas etapas antes de invocar o Assist.
    public let subcategory: String?
    /// Texto livre digitado pelo usuário quando escolhe "Outro problema" na
    /// primeira tripleta (`AssistProblemSelectionView`), em vez de um
    /// `objective` fechado. Limitado a 200 caracteres (ver
    /// `NetworkAssistConfiguration.maximumReportedProblemLength`) — validado
    /// tanto no client (view) quanto aqui, no `NetworkAssistService`.
    /// IMPORTANTE: este texto NÃO influencia a priorização de regras do
    /// NDS — é usado só como contexto adicional pela IA na explicação
    /// (`context.reported_problem`, ortogonal a `objective`/`subcategory`).
    /// `nil` quando o usuário escolheu um `objective` fechado ou pulou a
    /// seleção.
    public let reportedProblem: String?

    public init(
        question: String,
        currentMeasurement: NetworkMeasurement,
        recentMeasurements: [NetworkMeasurement] = [],
        evidence: [NetworkAssistEvidence] = [],
        usageContext: String? = nil,
        diagnosticPayload: String? = nil,
        locale: String? = nil,
        objective: String? = nil,
        subcategory: String? = nil,
        reportedProblem: String? = nil
    ) {
        self.question = question
        self.currentMeasurement = currentMeasurement
        self.recentMeasurements = recentMeasurements
        self.evidence = evidence
        self.usageContext = usageContext
        self.diagnosticPayload = diagnosticPayload
        self.locale = locale
        self.objective = objective
        self.subcategory = subcategory
        self.reportedProblem = reportedProblem
    }
}

public struct NetworkAssistRequest: Codable, Equatable, Sendable {
    public let question: String
    public let currentMeasurement: NetworkMeasurement
    public let recentMeasurements: [NetworkMeasurement]
    public let evidence: [NetworkAssistEvidence]
    public let usageContext: String?
    public let locale: String?
    public let policy: NetworkAssistPolicy
    public let objective: String?
    public let subcategory: String?
    /// Ver `NetworkAssistContext.reportedProblem` — mesmo contrato, já
    /// aparado (trim) e validado quanto ao limite de 200 caracteres antes
    /// de chegar aqui (`NetworkAssistService.validate(context:)`).
    public let reportedProblem: String?

    init(validated context: NetworkAssistContext) {
        self.question = context.question.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentMeasurement = context.currentMeasurement
        self.recentMeasurements = context.recentMeasurements
        self.evidence = context.evidence
        self.usageContext = context.usageContext
        self.locale = context.locale
        self.policy = .measurementUnderstanding
        self.objective = context.objective
        self.subcategory = context.subcategory
        self.reportedProblem = context.reportedProblem?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    public var knownEvidenceIDs: Set<String> {
        var ids = Set(evidence.map(\.id))
        ids.insert(Self.currentMeasurementEvidenceID(currentMeasurement.id))
        for measurement in recentMeasurements {
            ids.insert(Self.recentMeasurementEvidenceID(measurement.id))
        }
        return ids
    }

    public static func currentMeasurementEvidenceID(_ id: UUID) -> String {
        "current:\(id.uuidString.lowercased())"
    }

    public static func recentMeasurementEvidenceID(_ id: UUID) -> String {
        "recent:\(id.uuidString.lowercased())"
    }
}

public struct NetworkAssistDimension: Codable, Equatable, Sendable {
    public let name: String
    public let status: String
    public init(name: String, status: String) {
        self.name = name
        self.status = status
    }
}

public struct NetworkAssistRecommendation: Codable, Equatable, Sendable {
    public let title: String
    public let description: String
    public let steps: [String]
    public let actionURL: URL?
    public let actionLabel: String?

    public init(
        title: String,
        description: String,
        steps: [String] = [],
        actionURL: URL? = nil,
        actionLabel: String? = nil
    ) {
        self.title = title
        self.description = description
        self.steps = steps
        self.actionURL = actionURL
        self.actionLabel = actionLabel
    }
}

public struct NetworkAssistResponse: Codable, Equatable, Sendable {
    public let text: String
    public let longText: String?
    public let disposition: NetworkAssistDisposition
    public let evidenceIDs: [String]
    public let suggestions: [String]?

    // Novos campos estruturados para o AssistViewModel
    public let headerStatus: String?
    public let title: String?
    public let summary: String?
    public let recommendation: NetworkAssistRecommendation?
    public let dimensions: [NetworkAssistDimension]?
    public let aiAttribution: String?

    public init(
        text: String,
        longText: String? = nil,
        disposition: NetworkAssistDisposition = .answered,
        evidenceIDs: [String] = [],
        suggestions: [String]? = nil,
        headerStatus: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        recommendation: NetworkAssistRecommendation? = nil,
        dimensions: [NetworkAssistDimension]? = nil,
        aiAttribution: String? = nil
    ) {
        self.text = text
        self.longText = longText
        self.disposition = disposition
        self.evidenceIDs = evidenceIDs
        self.suggestions = suggestions
        self.headerStatus = headerStatus
        self.title = title
        self.summary = summary
        self.recommendation = recommendation
        self.dimensions = dimensions
        self.aiAttribution = aiAttribution
    }
}

/// Etapa de progresso que um transporte de streaming pode sinalizar
/// enquanto monta a resposta (issue #69). Enum tipado e fechado — o motor
/// só emite a etapa que o transporte de fato conhece, nunca inventa uma
/// (`NetworkAssistService.streamAnswer` nunca gera `.progress` sozinho).
/// Sem copy aqui: texto de apresentação vive na UI, mesmo padrão de
/// `investigationShortText` em `AssistSheet`.
public enum NetworkAssistProgressStep: String, Codable, Equatable, Sendable, CaseIterable {
    /// Lendo a medição atual/histórico recente antes de responder.
    case readingMeasurement
    /// Comparando a medição atual com o histórico.
    case comparingHistory
    /// Montando o texto final da resposta.
    case composingAnswer
}

/// Evento emitido por um caminho de streaming do Assist (issue #69).
/// `.progress` só existe quando o transporte real sinaliza aquela etapa —
/// nunca fabricado client-side. `.textDelta` é um fragmento de texto que
/// chegou de verdade (ex.: token de um SSE real), nunca um recorte
/// artificial de uma resposta que já chegou inteira. `.completed` carrega
/// a resposta final, já validada contra a política de evidência do Assist
/// (mesma validação de `NetworkAssistService.answer(_:)`).
public enum NetworkAssistStreamEvent: Equatable, Sendable {
    case progress(NetworkAssistProgressStep)
    case textDelta(String)
    case completed(NetworkAssistResponse)
}

public struct NetworkAssistConfiguration: Equatable, Sendable {
    public let maximumQuestionLength: Int
    public let maximumRecentMeasurements: Int
    public let maximumEvidenceItems: Int
    /// Limite de caracteres para `NetworkAssistContext.reportedProblem`
    /// ("Outro problema" em `AssistProblemSelectionView`). Espelha o limite
    /// já validado no client (contador de 200 caracteres na tela) — server
    /// e client concordam no mesmo número, o client só evita a viagem de
    /// rede que já sabe que vai falhar aqui.
    public let maximumReportedProblemLength: Int

    public init(
        maximumQuestionLength: Int = 500,
        maximumRecentMeasurements: Int = 20,
        maximumEvidenceItems: Int = 50,
        maximumReportedProblemLength: Int = 200
    ) {
        self.maximumQuestionLength = max(1, maximumQuestionLength)
        self.maximumRecentMeasurements = max(0, maximumRecentMeasurements)
        self.maximumEvidenceItems = max(0, maximumEvidenceItems)
        self.maximumReportedProblemLength = max(1, maximumReportedProblemLength)
    }
}

public enum NetworkAssistError: Error, Equatable, Sendable {
    case notConfigured
    case emptyQuestion
    case questionTooLong(maximum: Int)
    case invalidMeasurement(UUID)
    case tooManyRecentMeasurements(maximum: Int)
    case tooManyEvidenceItems(maximum: Int)
    case invalidEvidenceID(String)
    case duplicateEvidenceID(String)
    case unknownEvidenceSource(UUID)
    case emptyResponse
    case unknownResponseEvidenceID(String)
    case answeredWithoutEvidence
    /// `reportedProblem` (texto livre de "Outro problema") ultrapassou
    /// `NetworkAssistConfiguration.maximumReportedProblemLength` mesmo após
    /// trim — o client já valida isso na tela, mas o service não confia
    /// cegamente em quem chama `answer(_:)`/`streamAnswer(_:)`.
    case reportedProblemTooLong(maximum: Int)

    /// Não é lançado por `NetworkAssistService` — este pacote não conhece
    /// entitlement. Reservado para consumidores que envolvem
    /// `NetworkAssistProviding` com uma checagem de acesso (ver
    /// `LinkaModules.EntitlementGatedNetworkAssistProvider`). Ortogonal a
    /// `.notConfigured`, que representa transport ausente, não falta de direito.
    case notEntitled
}

public protocol NetworkAssistProviding: Sendable {
    func answer(_ context: NetworkAssistContext) async throws -> NetworkAssistResponse

    /// Caminho único de streaming (issue #69) — a UI chama só este método,
    /// independente de o provider por baixo saber streamar de verdade ou
    /// não. Ver extensão abaixo para o bridge default. Aditivo: nenhum
    /// conformer existente precisa implementar isto para continuar
    /// compilando.
    func streamAnswer(_ context: NetworkAssistContext) -> AsyncThrowingStream<NetworkAssistStreamEvent, Error>
}

public extension NetworkAssistProviding {
    /// Bridge default usado por qualquer conformer que não sobrescreve este
    /// método (ou seja, que não sabe streamar de verdade): chama
    /// `answer(_:)` uma única vez e emite um único `.completed` — sem
    /// `.textDelta`, sem `.progress` fabricado. É assim que uma resposta
    /// que já chegou inteira (caminho local instantâneo, ou transporte
    /// remoto não-streaming) revela de uma vez, sem reveal artificial
    /// (AGENTS.md — não invente espetáculo sobre uma resposta que já
    /// chegou pronta).
    ///
    /// Cancelamento: `continuation.onTermination` cancela a `Task` interna
    /// assim que o consumidor para de iterar o stream (inclusive quando a
    /// `Task` do chamador é cancelada) — propaga cancelamento cooperativo
    /// até `answer(_:)`.
    func streamAnswer(_ context: NetworkAssistContext) -> AsyncThrowingStream<NetworkAssistStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await self.answer(context)
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public protocol NetworkAssistTransport: Sendable {
    func answer(_ request: NetworkAssistRequest) async throws -> NetworkAssistResponse
}

/// Transporte que expõe eventos reais de streaming (issue #69) — chunks de
/// texto ou etapas de progresso que o backend de fato sinaliza, nunca
/// fabricados client-side. Estritamente aditivo a `NetworkAssistTransport`:
/// nenhum transporte hoje conforma a este protocolo, incluindo
/// `SignallqAiDiagnosticTransport` (`NetworkDiagnostics`) — o
/// `ai-diagnosis-worker` ainda responde em um único round-trip HTTP, não em
/// SSE/chunked/NDJSON. `NetworkAssistService.streamAnswer` cai no bridge
/// não-streaming (`NetworkAssistProviding.streamAnswer` default) para
/// qualquer transporte que não conforme a este protocolo.
public protocol NetworkAssistStreamingTransport: NetworkAssistTransport {
    func streamAnswer(_ request: NetworkAssistRequest) -> AsyncThrowingStream<NetworkAssistStreamEvent, Error>
}

public struct NetworkAssistService<Transport: NetworkAssistTransport>: NetworkAssistProviding {
    private let transport: Transport
    public let configuration: NetworkAssistConfiguration

    public init(
        transport: Transport,
        configuration: NetworkAssistConfiguration = .init()
    ) {
        self.transport = transport
        self.configuration = configuration
    }

    public func answer(_ context: NetworkAssistContext) async throws -> NetworkAssistResponse {
        try validate(context)
        let request = NetworkAssistRequest(validated: context)
        let response = try await transport.answer(request)
        try validate(response, against: request)
        return normalized(response)
    }

    /// Consome o transporte via streaming quando ele expõe eventos reais
    /// (`Transport: NetworkAssistStreamingTransport`); caso contrário, cai
    /// no bridge default de `NetworkAssistProviding` — um único round-trip
    /// via `answer(_:)`, emitido como `.completed` sem `.progress`/
    /// `.textDelta` fabricados. Isso dá à UI um único call-site
    /// (`streamAnswer`) independente da capacidade do transporte injetado
    /// (issue #69).
    ///
    /// Aplica a MESMA validação de entrada (`validate(context)`) e de
    /// resposta final (`validate(response:against:)`) usada por
    /// `answer(_:)` — a política de evidência do Assist vale também para o
    /// caminho streaming, inclusive quando o transporte é não-streaming.
    ///
    /// Cancelamento: `continuation.onTermination` cancela a `Task` interna
    /// assim que o consumidor para de iterar o stream — isso propaga
    /// cancelamento cooperativo até `transport.answer`/
    /// `transport.streamAnswer`, que por sua vez propaga até a requisição
    /// HTTP em voo quando o transporte é cancellation-aware (ver
    /// `URLSessionDiagnosticHTTPClient` em `NetworkDiagnostics`).
    public func streamAnswer(_ context: NetworkAssistContext) -> AsyncThrowingStream<NetworkAssistStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try validate(context)
                    let request = NetworkAssistRequest(validated: context)

                    if let streamingTransport = transport as? NetworkAssistStreamingTransport {
                        for try await event in streamingTransport.streamAnswer(request) {
                            try Task.checkCancellation()
                            switch event {
                            case .progress(let step):
                                continuation.yield(.progress(step))
                            case .textDelta(let delta):
                                continuation.yield(.textDelta(delta))
                            case .completed(let response):
                                try validate(response, against: request)
                                continuation.yield(.completed(normalized(response)))
                            }
                        }
                    } else {
                        let response = try await transport.answer(request)
                        try validate(response, against: request)
                        continuation.yield(.completed(normalized(response)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func normalized(_ response: NetworkAssistResponse) -> NetworkAssistResponse {
        let trimmedLong = response.longText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NetworkAssistResponse(
            text: response.text.trimmingCharacters(in: .whitespacesAndNewlines),
            longText: (trimmedLong?.isEmpty == false) ? trimmedLong : nil,
            disposition: response.disposition,
            evidenceIDs: response.evidenceIDs,
            suggestions: response.suggestions,
            headerStatus: response.headerStatus,
            title: response.title,
            summary: response.summary,
            recommendation: response.recommendation,
            dimensions: response.dimensions
        )
    }

    private func validate(_ context: NetworkAssistContext) throws {
        let question = context.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            throw NetworkAssistError.emptyQuestion
        }
        guard question.count <= configuration.maximumQuestionLength else {
            throw NetworkAssistError.questionTooLong(maximum: configuration.maximumQuestionLength)
        }
        guard NetworkMeasurementContract.isValid(context.currentMeasurement) else {
            throw NetworkAssistError.invalidMeasurement(context.currentMeasurement.id)
        }
        guard context.recentMeasurements.count <= configuration.maximumRecentMeasurements else {
            throw NetworkAssistError.tooManyRecentMeasurements(maximum: configuration.maximumRecentMeasurements)
        }
        for measurement in context.recentMeasurements where !NetworkMeasurementContract.isValid(measurement) {
            throw NetworkAssistError.invalidMeasurement(measurement.id)
        }
        guard context.evidence.count <= configuration.maximumEvidenceItems else {
            throw NetworkAssistError.tooManyEvidenceItems(maximum: configuration.maximumEvidenceItems)
        }
        if let reportedProblem = context.reportedProblem?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reportedProblem.isEmpty,
           reportedProblem.count > configuration.maximumReportedProblemLength {
            throw NetworkAssistError.reportedProblemTooLong(maximum: configuration.maximumReportedProblemLength)
        }

        let knownMeasurementIDs = Set([context.currentMeasurement.id] + context.recentMeasurements.map(\.id))
        var evidenceIDs = Set<String>()
        for evidence in context.evidence {
            let normalizedID = evidence.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty else {
                throw NetworkAssistError.invalidEvidenceID(evidence.id)
            }
            guard evidenceIDs.insert(normalizedID).inserted else {
                throw NetworkAssistError.duplicateEvidenceID(normalizedID)
            }
            for sourceID in evidence.sourceMeasurementIDs where !knownMeasurementIDs.contains(sourceID) {
                throw NetworkAssistError.unknownEvidenceSource(sourceID)
            }
            let numericValues = [evidence.value, evidence.baselineValue, evidence.percentChange]
            if numericValues.contains(where: { value in
                guard let value else { return false }
                return !value.isFinite
            }) {
                throw NetworkAssistError.invalidEvidenceID(normalizedID)
            }
        }
    }

    private func validate(
        _ response: NetworkAssistResponse,
        against request: NetworkAssistRequest
    ) throws {
        guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkAssistError.emptyResponse
        }

        let knownIDs = request.knownEvidenceIDs
        for evidenceID in response.evidenceIDs where !knownIDs.contains(evidenceID) {
            throw NetworkAssistError.unknownResponseEvidenceID(evidenceID)
        }

        if response.disposition == .answered && response.evidenceIDs.isEmpty {
            throw NetworkAssistError.answeredWithoutEvidence
        }
    }
}

public struct UnconfiguredNetworkAssistTransport: NetworkAssistTransport {
    public init() {}

    public func answer(_ request: NetworkAssistRequest) async throws -> NetworkAssistResponse {
        throw NetworkAssistError.notConfigured
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
