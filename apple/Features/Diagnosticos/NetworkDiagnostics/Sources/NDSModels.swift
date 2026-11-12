import Foundation

public struct NDSRequest: Codable, Equatable, Sendable {
    public var schemaVersion: String?
    public var request_id: String?
    public var sessionId: String?
    public var platform: String?
    public var locale: String?
    public var profile: String?
    public var app: AppInfo?
    public var capabilities: [String]
    public var requestedOutputs: [String]?
    public var context: DiagnosticContext?
    public var connection: Connection?
    public var wifi: Wifi?
    public var speed: Speed?
    public var quality: Quality?
    public var historical: Historical?

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case request_id
        case sessionId = "session_id"
        case platform
        case locale
        case profile
        case app
        case capabilities
        case requestedOutputs = "requested_outputs"
        case context
        case connection
        case wifi
        case speed
        case quality
        case historical
    }

    public init(
        schemaVersion: String? = "1.0",
        request_id: String? = nil,
        sessionId: String? = nil,
        platform: String? = nil,
        locale: String? = nil,
        profile: String? = nil,
        app: AppInfo? = nil,
        capabilities: [String] = [],
        requestedOutputs: [String]? = nil,
        context: DiagnosticContext? = nil,
        connection: Connection? = nil,
        wifi: Wifi? = nil,
        speed: Speed? = nil,
        quality: Quality? = nil,
        historical: Historical? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.request_id = request_id
        self.sessionId = sessionId
        self.platform = platform
        self.locale = locale
        self.profile = profile
        self.app = app
        self.capabilities = capabilities
        self.requestedOutputs = requestedOutputs
        self.context = context
        self.connection = connection
        self.wifi = wifi
        self.speed = speed
        self.quality = quality
        self.historical = historical
    }

    public struct DiagnosticContext: Codable, Equatable, Sendable {
        public var reportedProblem: String?
        public var objective: String?
        /// Subcategoria fechada dentro de `objective`, coletada pelo fluxo
        /// guiado (`AssistProblemSelectionView`) no app. Opcional e
        /// compatível com v1: quando ausente, o NDS não vê diferença de
        /// payload em relação ao formato anterior a esta issue.
        public var subcategory: String?
        public var symptoms: [String]?
        public var answers: [String: String]?

        public enum CodingKeys: String, CodingKey {
            case reportedProblem = "reported_problem"
            case objective
            case subcategory
            case symptoms
            case answers
        }

        public init(
            reportedProblem: String? = nil,
            objective: String? = nil,
            subcategory: String? = nil,
            symptoms: [String]? = nil,
            answers: [String: String]? = nil
        ) {
            self.reportedProblem = reportedProblem
            self.objective = objective
            self.subcategory = subcategory
            self.symptoms = symptoms
            self.answers = answers
        }
    }

    public struct AppInfo: Codable, Equatable, Sendable {
        public var id: String?
        public var version: String?
        public init(id: String? = nil, version: String? = nil) {
            self.id = id
            self.version = version
        }
    }

    public struct Connection: Codable, Equatable, Sendable {
        public var type: String?
        public var hasInternet: Bool?
        public enum CodingKeys: String, CodingKey {
            case type
            case hasInternet = "has_internet"
        }

        public init(type: String? = nil, hasInternet: Bool? = nil) {
            self.type = type
            self.hasInternet = hasInternet
        }
    }

    public struct Wifi: Codable, Equatable, Sendable {
        public var rssiDbm: Double?
        public var linkSpeedMbps: Double?
        public var band: String?
        public var securityType: String?
        public var rxRateMbps: Double?
        public var txRateMbps: Double?
        public var noiseDbm: Double?
        public var snrDb: Double?
        public var channelNumber: Int?
        public var gatewayIP: String?
        public var gatewayVendor: String?
        public var gatewayAdminURL: String?

        public enum CodingKeys: String, CodingKey {
            case rssiDbm = "rssi_dbm"
            case linkSpeedMbps = "link_speed_mbps"
            case band
            case securityType = "security_type"
            case rxRateMbps = "rx_rate_mbps"
            case txRateMbps = "tx_rate_mbps"
            case noiseDbm = "noise_dbm"
            case snrDb = "snr_db"
            case channelNumber = "channel_number"
            case gatewayIP = "gateway_ip"
            case gatewayVendor = "gateway_vendor"
            case gatewayAdminURL = "gateway_admin_url"
        }

        public init(
            rssiDbm: Double? = nil,
            linkSpeedMbps: Double? = nil,
            band: String? = nil,
            securityType: String? = nil,
            rxRateMbps: Double? = nil,
            txRateMbps: Double? = nil,
            noiseDbm: Double? = nil,
            snrDb: Double? = nil,
            channelNumber: Int? = nil,
            gatewayIP: String? = nil,
            gatewayVendor: String? = nil,
            gatewayAdminURL: String? = nil
        ) {
            self.rssiDbm = rssiDbm
            self.linkSpeedMbps = linkSpeedMbps
            self.band = band
            self.securityType = securityType
            self.rxRateMbps = rxRateMbps
            self.txRateMbps = txRateMbps
            self.noiseDbm = noiseDbm
            self.snrDb = snrDb
            self.channelNumber = channelNumber
            self.gatewayIP = gatewayIP
            self.gatewayVendor = gatewayVendor
            self.gatewayAdminURL = gatewayAdminURL
        }
    }

    public struct Speed: Codable, Equatable, Sendable {
        public var downloadMbps: Double?
        public var uploadMbps: Double?
        public enum CodingKeys: String, CodingKey {
            case downloadMbps = "download_mbps"
            case uploadMbps = "upload_mbps"
        }

        public init(downloadMbps: Double? = nil, uploadMbps: Double? = nil) {
            self.downloadMbps = downloadMbps
            self.uploadMbps = uploadMbps
        }
    }

    public struct Quality: Codable, Equatable, Sendable {
        public var latencyMs: Double?
        public var loadedLatencyMs: Double?
        public var loadedLatencyUploadMs: Double?
        public var dnsResolutionMs: Double?
        public var jitterMs: Double?
        public var packetLossPercent: Double?
        public enum CodingKeys: String, CodingKey {
            case latencyMs = "latency_ms"
            case loadedLatencyMs = "loaded_latency_ms"
            case loadedLatencyUploadMs = "loaded_latency_upload_ms"
            case dnsResolutionMs = "dns_resolution_ms"
            case jitterMs = "jitter_ms"
            case packetLossPercent = "packet_loss_percent"
        }

        public init(
            latencyMs: Double? = nil,
            loadedLatencyMs: Double? = nil,
            loadedLatencyUploadMs: Double? = nil,
            dnsResolutionMs: Double? = nil,
            jitterMs: Double? = nil,
            packetLossPercent: Double? = nil
        ) {
            self.latencyMs = latencyMs
            self.loadedLatencyMs = loadedLatencyMs
            self.loadedLatencyUploadMs = loadedLatencyUploadMs
            self.dnsResolutionMs = dnsResolutionMs
            self.jitterMs = jitterMs
            self.packetLossPercent = packetLossPercent
        }
    }

    public struct Historical: Codable, Equatable, Sendable {
        public var avgDownload30d: Double?
        public var avgDownload7d: Double?
        public var avgUpload30d: Double?
        public var avgUpload7d: Double?
        public var avgPing30d: Double?
        public var avgPing7d: Double?
        public var tests30d: Int?
        public var tests7d: Int?

        public enum CodingKeys: String, CodingKey {
            case avgDownload30d = "avg_download_30d"
            case avgDownload7d = "avg_download_7d"
            case avgUpload30d = "avg_upload_30d"
            case avgUpload7d = "avg_upload_7d"
            case avgPing30d = "avg_ping_30d"
            case avgPing7d = "avg_ping_7d"
            case tests30d = "tests_30d"
            case tests7d = "tests_7d"
        }

        public init(
            avgDownload30d: Double? = nil,
            avgDownload7d: Double? = nil,
            avgUpload30d: Double? = nil,
            avgUpload7d: Double? = nil,
            avgPing30d: Double? = nil,
            avgPing7d: Double? = nil,
            tests30d: Int? = nil,
            tests7d: Int? = nil
        ) {
            self.avgDownload30d = avgDownload30d
            self.avgDownload7d = avgDownload7d
            self.avgUpload30d = avgUpload30d
            self.avgUpload7d = avgUpload7d
            self.avgPing30d = avgPing30d
            self.avgPing7d = avgPing7d
            self.tests30d = tests30d
            self.tests7d = tests7d
        }
    }
}

public struct NDSResponse: Codable, Equatable, Sendable {
    public var results: [NDSResult]?
    public var traces: [NDSTrace]?
    public var recommendation: NDSRecommendation?
    /// Bloco `raw` do contrato `/v2/diagnostics/evaluate` — a mesma análise
    /// crua determinística do v1 (`results`/`traces`/`recommendation`),
    /// só que aninhada. Ausente numa resposta v1 pura.
    public var raw: NDSRawPayload?
    /// Bloco `explanation` do contrato v2 — texto tratado (`titulo`,
    /// `descricao`, `dados`, `acao_usuario`) ou `sem_causa_identificada`.
    /// Ausente numa resposta v1 pura.
    public var explanation: NDSV2Explanation?

    public init(
        results: [NDSResult]? = nil,
        traces: [NDSTrace]? = nil,
        recommendation: NDSRecommendation? = nil,
        raw: NDSRawPayload? = nil,
        explanation: NDSV2Explanation? = nil
    ) {
        self.results = results
        self.traces = traces
        self.recommendation = recommendation
        self.raw = raw
        self.explanation = explanation
    }

    /// `results` do v2 (`raw.results`) quando presente, senão o `results`
    /// de topo do v1 — único ponto de leitura para quem consome achados
    /// independente da versão de contrato que respondeu.
    public var effectiveResults: [NDSResult]? {
        raw?.results ?? results
    }

    /// Mesma ideia de `effectiveResults`, para `recommendation`.
    public var effectiveRecommendation: NDSRecommendation? {
        raw?.recommendation ?? recommendation
    }
}

/// Análise crua determinística devolvida no bloco `raw` do contrato v2 —
/// mesma forma de `results`/`traces`/`recommendation` do v1, só aninhada
/// sob a chave `raw` em vez de ficar no nível raiz da resposta.
public struct NDSRawPayload: Codable, Equatable, Sendable {
    public var results: [NDSResult]?
    public var traces: [NDSTrace]?
    public var recommendation: NDSRecommendation?

    public init(results: [NDSResult]? = nil, traces: [NDSTrace]? = nil, recommendation: NDSRecommendation? = nil) {
        self.results = results
        self.traces = traces
        self.recommendation = recommendation
    }
}

public struct NDSExplanationProvenance: Codable, Equatable, Sendable {
    public var source: String?
    public var modelLabel: String?

    enum CodingKeys: String, CodingKey {
        case source
        case modelLabel = "model_label"
    }

    public init(source: String? = nil, modelLabel: String? = nil) {
        self.source = source
        self.modelLabel = modelLabel
    }
}

/// Texto tratado do bloco `explanation` do contrato v2. Quando
/// `semCausaIdentificada == true`, nenhuma regra disparou — `titulo`/
/// `descricao`/`dados`/`acaoUsuario` podem vir ausentes nesse caso, e o
/// consumidor deve mostrar uma mensagem transparente em vez de inventar
/// uma causa (AGENTS.md §9 — nada de opinião fabricada).
public struct NDSV2Explanation: Codable, Equatable, Sendable {
    public var titulo: String?
    public var descricao: String?
    public var dados: [String]?
    public var acaoUsuario: String?
    public var semCausaIdentificada: Bool?
    public var provenance: NDSExplanationProvenance?

    public enum CodingKeys: String, CodingKey {
        case titulo
        case descricao
        case dados
        case acaoUsuario = "acao_usuario"
        case semCausaIdentificada = "sem_causa_identificada"
        case provenance
    }

    public init(
        titulo: String? = nil,
        descricao: String? = nil,
        dados: [String]? = nil,
        acaoUsuario: String? = nil,
        semCausaIdentificada: Bool? = nil,
        provenance: NDSExplanationProvenance? = nil
    ) {
        self.titulo = titulo
        self.descricao = descricao
        self.dados = dados
        self.acaoUsuario = acaoUsuario
        self.semCausaIdentificada = semCausaIdentificada
        self.provenance = provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.titulo = try container.decodeIfPresent(String.self, forKey: .titulo)
        self.descricao = try container.decodeIfPresent(String.self, forKey: .descricao)
        self.acaoUsuario = try container.decodeIfPresent(String.self, forKey: .acaoUsuario)
        self.semCausaIdentificada = try container.decodeIfPresent(Bool.self, forKey: .semCausaIdentificada)
        self.provenance = try container.decodeIfPresent(NDSExplanationProvenance.self, forKey: .provenance)
        
        if let stringArray = try? container.decodeIfPresent([String].self, forKey: .dados) {
            self.dados = stringArray
        } else if let singleString = try? container.decodeIfPresent(String.self, forKey: .dados) {
            self.dados = [singleString]
        } else {
            self.dados = nil
        }
    }
}

public struct NDSErrorEnvelope: Codable, Equatable, Sendable {
    public struct Detail: Codable, Equatable, Sendable {
        public let code: String
        public let message: String
        public let retryable: Bool
    }

    public let error: Detail
    public let requestID: String?

    enum CodingKeys: String, CodingKey {
        case error
        case requestID = "request_id"
    }
}

public struct NDSTrace: Codable, Equatable, Sendable {
    public var module: String
    public var durationMs: Int?
    public var status: String?
    public var error: String?
    public var source: String?

    enum CodingKeys: String, CodingKey {
        case module
        case durationMs = "duration_ms"
        case status
        case error
        case source
    }

    public init(module: String, durationMs: Int? = nil, status: String? = nil, error: String? = nil, source: String? = nil) {
        self.module = module
        self.durationMs = durationMs
        self.status = status
        self.error = error
        self.source = source
    }
}

public struct NDSDimensao: Codable, Equatable, Sendable {
    public var nome: String
    public var status: String

    public init(nome: String, status: String) {
        self.nome = nome
        self.status = status
    }
}

public struct NDSModuleData: Codable, Equatable, Sendable {
    public var score: Int?
    public var explanation: NDSExplanation?
    public var veredicto: String?
    public var observedDimensions: Int?
    public var dimensoes: [NDSDimensao]?
    /// IDs dos achados que sustentam `explanation`, quando o módulo é `ai`
    /// (issue #129). Antes deste campo, o Codable descartava
    /// `source_finding_ids` do módulo `ai` silenciosamente — o Linka não
    /// tinha como saber se uma explicação de IA tinha evidência por trás.
    public var sourceFindingIds: [String]?
    public var aiModelUsed: String?

    enum CodingKeys: String, CodingKey {
        case score
        case explanation
        case veredicto
        case observedDimensions = "observed_dimensions"
        case dimensoes
        case sourceFindingIds = "source_finding_ids"
        case aiModelUsed = "ai_model_used"
    }

    public init(score: Int? = nil, explanation: NDSExplanation? = nil, veredicto: String? = nil, observedDimensions: Int? = nil, dimensoes: [NDSDimensao]? = nil, sourceFindingIds: [String]? = nil, aiModelUsed: String? = nil) {
        self.score = score
        self.explanation = explanation
        self.veredicto = veredicto
        self.observedDimensions = observedDimensions
        self.dimensoes = dimensoes
        self.sourceFindingIds = sourceFindingIds
        self.aiModelUsed = aiModelUsed
    }
}

public struct NDSResult: Codable, Equatable, Sendable {
    public var module: String?
    public var result: NDSModuleData?
    public var cards: [NDSCard]?
    public var warnings: [String]?
    public var missingInputs: [String]?

    enum CodingKeys: String, CodingKey {
        case module
        case result
        case cards
        case warnings
        case missingInputs = "missing_inputs"
    }

    public init(module: String? = nil, result: NDSModuleData? = nil, cards: [NDSCard]? = nil, warnings: [String]? = nil, missingInputs: [String]? = nil) {
        self.module = module
        self.result = result
        self.cards = cards
        self.warnings = warnings
        self.missingInputs = missingInputs
    }
}

public struct NDSRecommendation: Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var title: String
    public var description: String
    public var steps: [String]
    public var sourceFindingIds: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case description
        case steps
        case sourceFindingIds = "source_finding_ids"
    }

    public init(id: String, type: String, title: String, description: String, steps: [String] = [], sourceFindingIds: [String]? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.steps = steps
        self.sourceFindingIds = sourceFindingIds
    }
}

public struct NDSCard: Codable, Equatable, Sendable {
    public var id: String
    public var titulo: String
    public var status: String
    public var evidencia: String?
    public var mensagemUsuario: String
    public var recomendacao: String?
    public var categoria: String
    public var podeConcluir: Bool
    public var categoriaOrigem: String?

    public init(id: String, titulo: String, status: String, evidencia: String? = nil, mensagemUsuario: String, recomendacao: String? = nil, categoria: String, podeConcluir: Bool, categoriaOrigem: String? = nil) {
        self.id = id
        self.titulo = titulo
        self.status = status
        self.evidencia = evidencia
        self.mensagemUsuario = mensagemUsuario
        self.recomendacao = recomendacao
        self.categoria = categoria
        self.podeConcluir = podeConcluir
        self.categoriaOrigem = categoriaOrigem
    }
}


public struct NDSExplanation: Codable, Equatable, Sendable {
    public var summary: String?
    public var audience: String?
    public var tituloAmigavel: String?
    public var resumoTecnicoTraduzido: String?

    public enum CodingKeys: String, CodingKey {
        case summary
        case audience
        case tituloAmigavel = "titulo_amigavel"
        case resumoTecnicoTraduzido = "resumo_tecnico_traduzido"
    }

    public init(summary: String? = nil, audience: String? = nil, tituloAmigavel: String? = nil, resumoTecnicoTraduzido: String? = nil) {
        self.summary = summary
        self.audience = audience
        self.tituloAmigavel = tituloAmigavel
        self.resumoTecnicoTraduzido = resumoTecnicoTraduzido
    }
}
