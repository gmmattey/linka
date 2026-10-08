import Foundation

/// Representa somente o payload V1 documentado para o Netscope. Não abre
/// conexões, não conhece destinos e não toma decisões sobre quando enviar.
public enum NetscopeV1Codec {
    public static let schemaVersion = "1.0.0"

    public struct AppDescriptor: Equatable, Sendable {
        public enum Platform: String, Equatable, Sendable {
            case ios
            case ipados
            case macos
        }

        public let version: String
        public let platform: Platform

        public init(version: String, platform: Platform) {
            self.version = version
            self.platform = platform
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case missingUsageObjective
        case invalidLocale
        case invalidAppVersion
        case malformedResponse
        case responseDoesNotMatchRequest
    }

    /// Serializa os campos obrigatórios de `AnalysisRequest`. Métricas e
    /// detalhes Wi-Fi ausentes já chegam como `nil` na evidência e, portanto,
    /// são omitidos do JSON em vez de virar zeros ou `null`.
    public static func encodeRequest(
        input: NetscopeLocalAnalysisInput,
        locale: String,
        app: AppDescriptor
    ) throws -> Data {
        guard (2...35).contains(locale.count) else { throw Error.invalidLocale }
        guard (1...64).contains(app.version.count) else { throw Error.invalidAppVersion }
        guard let objective = input.declaredContext.objective else {
            throw Error.missingUsageObjective
        }

        let request = Request(
            schemaVersion: schemaVersion,
            measurement: Measurement(input.observedEvidence),
            usageContext: UsageContext(objective: objective.rawValue),
            locale: locale,
            app: WireAppDescriptor(version: app.version, platform: app.platform.rawValue),
            consent: Consent(diagnosticProcessing: true)
        )
        return try JSONEncoder().encode(request)
    }

    /// Decodifica a resposta V1 com objetos fechados. Um campo desconhecido,
    /// `null` onde o contrato não o permite ou combinação de estado inválida
    /// produz erro em vez de uma leitura possivelmente enganosa.
    public static func decodeResponse(_ data: Data) throws -> AnalysisResponse {
        do {
            try validateClosedResponseShape(data)
            return try JSONDecoder().decode(AnalysisResponse.self, from: data)
        } catch {
            throw Error.malformedResponse
        }
    }

    /// Confirma que uma resposta já decodificada só cita fatos que este cliente
    /// realmente colocaria no payload V1. A projeção é a mesma usada por
    /// `encodeRequest`, portanto nunca compara com a evidência local bruta.
    /// Esta validação não envia a resposta nem abre qualquer conexão.
    public static func validateResponse(
        _ response: AnalysisResponse,
        for input: NetscopeLocalAnalysisInput
    ) throws {
        if let declaredContext = response.declaredContext,
           declaredContext.objective != input.declaredContext.objective {
            throw Error.responseDoesNotMatchRequest
        }

        let measurement = Measurement(input.observedEvidence)
        for evidence in response.evidenceUsed ?? [] {
            guard measurement.value(for: evidence.metric) == evidence.value else {
                throw Error.responseDoesNotMatchRequest
            }
        }
    }

    private static func validateClosedResponseShape(_ data: Data) throws {
        let root = try object(
            JSONSerialization.jsonObject(with: data),
            allowed: ["schema_version", "request_id", "status", "declared_context", "assessment", "evidence_used", "limitations", "next_action", "provenance"]
        )
        if let value = root["declared_context"] {
            _ = try object(value, allowed: ["objective"])
        }
        if let value = root["assessment"] {
            _ = try object(value, allowed: ["title", "summary", "confidence"])
        }
        if let value = root["evidence_used"] {
            guard let values = value as? [Any] else { throw Error.malformedResponse }
            for item in values { _ = try object(item, allowed: ["metric", "value", "source"]) }
        }
        if let value = root["next_action"] {
            _ = try object(value, allowed: ["title", "steps"])
        }
        if let value = root["provenance"] {
            _ = try object(value, allowed: ["provider", "model", "policy_version"])
        }
    }

    private static func object(_ value: Any, allowed: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any], Set(object.keys).isSubset(of: allowed) else {
            throw Error.malformedResponse
        }
        return object
    }
}

public extension NetscopeV1Codec {
    struct AnalysisResponse: Equatable, Sendable {
        public enum Status: String, Decodable, Equatable, Sendable {
            case completed
            case inconclusive
            case unavailable
            case outOfScope = "out_of_scope"
        }

        public struct DeclaredContext: Equatable, Sendable {
            public let objective: NetscopeDeclaredContext.Objective
        }

        public struct Assessment: Equatable, Sendable {
            public enum Confidence: String, Decodable, Equatable, Sendable { case high, medium, low }
            public let title: String
            public let summary: String
            public let confidence: Confidence
        }

        public struct EvidenceUsed: Equatable, Sendable {
            public enum Metric: String, Decodable, Equatable, Sendable {
                case downloadMbps = "download_mbps"
                case uploadMbps = "upload_mbps"
                case latencyMs = "latency_ms"
                case jitterMs = "jitter_ms"
                case packetLossPercent = "packet_loss_percent"
                case loadedLatencyDownloadMs = "loaded_latency_download_ms"
                case loadedLatencyUploadMs = "loaded_latency_upload_ms"
                case dnsResolutionMs = "dns_resolution_ms"
                case connectionKind = "connection_kind"
                case wifiFrequencyMHz = "wifi_details.frequency_mhz"
                case wifiBand = "wifi_details.band"
                case wifiChannel = "wifi_details.channel"
                case wifiLinkSpeedMbps = "wifi_details.link_speed_mbps"
            }

            public enum Value: Equatable, Sendable { case number(Double), string(String) }
            public let metric: Metric
            public let value: Value
        }

        public struct NextAction: Equatable, Sendable {
            public let title: String
            public let steps: [String]
        }

        public struct Provenance: Equatable, Sendable {
            public let provider: String
            public let model: String
            public let policyVersion: String
        }

        public let requestID: String
        public let status: Status
        public let declaredContext: DeclaredContext?
        public let assessment: Assessment?
        public let evidenceUsed: [EvidenceUsed]?
        public let limitations: [String]
        public let nextAction: NextAction?
        public let provenance: Provenance?
    }
}

private extension NetscopeV1Codec {
    struct Request: Encodable {
        let schemaVersion: String
        let measurement: Measurement
        let usageContext: UsageContext
        let locale: String
        let app: WireAppDescriptor
        let consent: Consent

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", measurement
            case usageContext = "usage_context", locale, app, consent
        }
    }

    struct Measurement: Encodable {
        let downloadMbps: Double?
        let uploadMbps: Double?
        let latencyMs: Double?
        let jitterMs: Double?
        let packetLossPercent: Double?
        let connectionKind: String
        let wifiDetails: WiFiDetails?

        init(_ evidence: NetscopeMeasurementEvidence) {
            downloadMbps = Self.nonNegative(evidence.downloadMbps)
            uploadMbps = Self.nonNegative(evidence.uploadMbps)
            latencyMs = Self.nonNegative(evidence.latencyMs)
            jitterMs = Self.nonNegative(evidence.jitterMs)
            packetLossPercent = Self.percentage(evidence.packetLossPercent)
            connectionKind = evidence.connectionKind.rawValue
            wifiDetails = evidence.connectionKind == .wifi
                ? evidence.wifiDetails.flatMap(WiFiDetails.init)
                : nil
        }

        private static func nonNegative(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }

        private static func percentage(_ value: Double?) -> Double? {
            guard let value, value.isFinite, (0...100).contains(value) else { return nil }
            return value
        }

        enum CodingKeys: String, CodingKey {
            case downloadMbps = "download_mbps", uploadMbps = "upload_mbps"
            case latencyMs = "latency_ms", jitterMs = "jitter_ms"
            case packetLossPercent = "packet_loss_percent"
            case connectionKind = "connection_kind", wifiDetails = "wifi_details"
        }

        func value(for metric: AnalysisResponse.EvidenceUsed.Metric) -> AnalysisResponse.EvidenceUsed.Value? {
            switch metric {
            case .downloadMbps:
                downloadMbps.map(AnalysisResponse.EvidenceUsed.Value.number)
            case .uploadMbps:
                uploadMbps.map(AnalysisResponse.EvidenceUsed.Value.number)
            case .latencyMs:
                latencyMs.map(AnalysisResponse.EvidenceUsed.Value.number)
            case .jitterMs:
                jitterMs.map(AnalysisResponse.EvidenceUsed.Value.number)
            case .packetLossPercent:
                packetLossPercent.map(AnalysisResponse.EvidenceUsed.Value.number)
            case .connectionKind:
                .string(connectionKind)
            case .wifiBand:
                wifiDetails?.band.map(AnalysisResponse.EvidenceUsed.Value.string)
            case .wifiLinkSpeedMbps:
                wifiDetails?.linkSpeedMbps.map(AnalysisResponse.EvidenceUsed.Value.number)
            case .loadedLatencyDownloadMs, .loadedLatencyUploadMs, .dnsResolutionMs,
                 .wifiFrequencyMHz, .wifiChannel:
                nil
            }
        }
    }

    struct WiFiDetails: Encodable {
        let band: String?
        let linkSpeedMbps: Double?

        init?(_ details: NetscopeMeasurementEvidence.WiFiDetails) {
            band = details.band?.rawValue
            guard let speed = details.linkSpeedMbps, speed.isFinite, speed > 0 else {
                linkSpeedMbps = nil
                guard band != nil else { return nil }
                return
            }
            linkSpeedMbps = speed
        }

        enum CodingKeys: String, CodingKey {
            case band
            case linkSpeedMbps = "link_speed_mbps"
        }
    }

    struct UsageContext: Encodable {
        let objective: String
    }

    struct WireAppDescriptor: Encodable {
        let version: String
        let platform: String
    }

    struct Consent: Encodable {
        let diagnosticProcessing: Bool
        enum CodingKeys: String, CodingKey { case diagnosticProcessing = "diagnostic_processing" }
    }
}

extension NetscopeV1Codec.AnalysisResponse: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version", requestID = "request_id", status
        case declaredContext = "declared_context", assessment
        case evidenceUsed = "evidence_used", limitations
        case nextAction = "next_action", provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.requireOnly(CodingKeys.self)
        guard try container.decode(String.self, forKey: .schemaVersion) == NetscopeV1Codec.schemaVersion else {
            throw NetscopeV1Codec.Error.malformedResponse
        }
        requestID = try container.nonEmptyString(.requestID, maximum: 128)
        status = try container.decode(Status.self, forKey: .status)
        declaredContext = try container.optional(DeclaredContext.self, forKey: .declaredContext)
        assessment = try container.optional(Assessment.self, forKey: .assessment)
        evidenceUsed = try container.optional([EvidenceUsed].self, forKey: .evidenceUsed)
        limitations = try container.nonEmptyStrings(.limitations, maximumItems: 10, maximumLength: 300)
        nextAction = try container.optional(NextAction.self, forKey: .nextAction)
        provenance = try container.optional(Provenance.self, forKey: .provenance)
        if let evidenceUsed, evidenceUsed.isEmpty { throw NetscopeV1Codec.Error.malformedResponse }

        switch status {
        case .completed:
            guard assessment != nil, !(evidenceUsed?.isEmpty ?? true) else { throw NetscopeV1Codec.Error.malformedResponse }
        case .inconclusive:
            guard assessment == nil else { throw NetscopeV1Codec.Error.malformedResponse }
        case .unavailable, .outOfScope:
            guard assessment == nil, evidenceUsed == nil else { throw NetscopeV1Codec.Error.malformedResponse }
        }
    }
}

extension NetscopeV1Codec.AnalysisResponse.DeclaredContext: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case objective }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.requireOnly(CodingKeys.self)
        objective = try c.decode(NetscopeDeclaredContext.Objective.self, forKey: .objective)
    }
}

extension NetscopeV1Codec.AnalysisResponse.Assessment: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case title, summary, confidence }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.requireOnly(CodingKeys.self)
        title = try c.nonEmptyString(.title, maximum: 160)
        summary = try c.nonEmptyString(.summary, maximum: 1_000)
        confidence = try c.decode(Confidence.self, forKey: .confidence)
    }
}

extension NetscopeV1Codec.AnalysisResponse.EvidenceUsed: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case metric, value, source }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.requireOnly(CodingKeys.self)
        metric = try c.decode(Metric.self, forKey: .metric)
        guard try c.decode(String.self, forKey: .source) == "system_observed" else { throw NetscopeV1Codec.Error.malformedResponse }
        if let number = try? c.decode(Double.self, forKey: .value) { value = .number(number) }
        else { value = .string(try c.decode(String.self, forKey: .value)) }
    }
}

extension NetscopeV1Codec.AnalysisResponse.NextAction: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case title, steps }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.requireOnly(CodingKeys.self)
        title = try c.nonEmptyString(.title, maximum: 160)
        steps = try c.nonEmptyStrings(.steps, maximumItems: 5, maximumLength: 240)
    }
}

extension NetscopeV1Codec.AnalysisResponse.Provenance: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case provider, model, policyVersion = "policy_version" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.requireOnly(CodingKeys.self)
        provider = try c.nonEmptyString(.provider, maximum: 64)
        model = try c.nonEmptyString(.model, maximum: 128)
        policyVersion = try c.nonEmptyString(.policyVersion, maximum: 64)
    }
}

private extension KeyedDecodingContainer {
    func requireOnly<AllowedKey: CodingKey & CaseIterable>(_ keys: AllowedKey.Type) throws where AllowedKey.AllCases: Collection, AllowedKey.AllCases.Element == AllowedKey {
        guard Set(allKeys.map(\.stringValue)).isSubset(of: Set(keys.allCases.map(\.stringValue))) else {
            throw NetscopeV1Codec.Error.malformedResponse
        }
    }

    func optional<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key) else { return nil }
        guard !(try decodeNil(forKey: key)) else { throw NetscopeV1Codec.Error.malformedResponse }
        return try decode(T.self, forKey: key)
    }

    func nonEmptyString(_ key: Key, maximum: Int) throws -> String {
        let value = try decode(String.self, forKey: key)
        guard !value.isEmpty, value.count <= maximum else { throw NetscopeV1Codec.Error.malformedResponse }
        return value
    }

    func nonEmptyStrings(_ key: Key, maximumItems: Int, maximumLength: Int) throws -> [String] {
        let values = try decode([String].self, forKey: key)
        guard !values.isEmpty, values.count <= maximumItems,
              values.allSatisfy({ !$0.isEmpty && $0.count <= maximumLength }) else {
            throw NetscopeV1Codec.Error.malformedResponse
        }
        return values
    }
}
