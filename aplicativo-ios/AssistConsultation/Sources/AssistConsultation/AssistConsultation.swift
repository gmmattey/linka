import Foundation
import NetworkCore
import NetworkInventory

/// O contrato local do Assist V4. Este pacote não contém transporte, provider,
/// armazenamento remoto ou integração com o Assist legado.
public enum AssistConsultationContract {
    public static let schemaVersion = "assist.consultation/1.0"
    public static let maximumPayloadBytes = 256 * 1024

    public static func decode(_ data: Data, now: Date = Date()) throws -> ConsultationPayload {
        guard data.count <= maximumPayloadBytes else { throw ContractError.payloadTooLarge }
        let object = try JSONSerialization.jsonObject(with: data)
        try JSONSchemaValidator.validate(object, against: try schemaObject())

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ConsultationPayload.self, from: data)
        try payload.validate(at: now)
        return payload
    }

    public static func encode(_ payload: ConsultationPayload, now: Date = Date()) throws -> Data {
        try payload.validate(at: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        _ = try decode(data, now: now)
        return data
    }

    private static func schemaObject() throws -> Any {
        guard let url = Bundle.module.url(forResource: "assist.consultation-1.0.schema", withExtension: "json") else {
            throw ContractError.schemaUnavailable
        }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }
}

public enum ContractError: Error, Equatable, LocalizedError {
    case schemaUnavailable
    case payloadTooLarge
    case invalid(String)
    case consentNotGranted
    case contextNotAuthorized

    public var errorDescription: String? {
        switch self {
        case .schemaUnavailable: return "O schema local do contrato não está disponível."
        case .payloadTooLarge: return "O payload excede o limite do contrato."
        case .invalid(let message): return message
        case .consentNotGranted: return "O consentimento não permite envio desta consulta."
        case .contextNotAuthorized: return "O escopo de consentimento não permite anexar contexto."
        }
    }
}

public struct PseudonymousReference: Codable, Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard Self.isValid(value) else { throw ContractError.invalid("Referência pseudônima inválida.") }
        self.value = value
    }

    public static func isValid(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9]*-[A-Za-z0-9_-]{1,96}$", options: .regularExpression) != nil
    }

    private init(generatedValue: String) { self.value = generatedValue }

    fileprivate static func generated(prefix: String) -> Self {
        Self(generatedValue: "\(prefix)-\(UUID().uuidString.lowercased())")
    }
}

public enum ConsultationIntent: String, Codable, CaseIterable, Sendable {
    case openQuestion = "open_question"
    case slowConnection = "slow_connection"
    case routerAdequacy = "router_adequacy"
    case meshNeed = "mesh_need"
    case planValue = "plan_value"
}

public enum ConsentState: String, Codable, CaseIterable, Sendable {
    case granted
    case refused
    case revoked
}

public enum ConsentScope: String, Codable, CaseIterable, Sendable {
    case none
    case question
    case context
    case questionAndContext = "question_and_context"

    public var permitsQuestion: Bool { self == .question || self == .questionAndContext }
    public var permitsContext: Bool { self == .context || self == .questionAndContext }
}

public struct ConsentReceipt: Codable, Equatable, Sendable {
    public let ref: PseudonymousReference
    public let state: ConsentState
    public let scope: ConsentScope
    public let recordedAt: Date

    public init(ref: PseudonymousReference, state: ConsentState, scope: ConsentScope, recordedAt: Date) {
        self.ref = ref
        self.state = state
        self.scope = scope
        self.recordedAt = recordedAt
    }
}

public enum EvidenceSourceType: String, Codable, CaseIterable, Sendable {
    case userDeclared = "user_declared"
    case systemObserved = "system_observed"
    case manufacturerDocumented = "manufacturer_documented"
    case curatedKnowledge = "curated_knowledge"
    case derived
}

public enum ContextSourceKind: String, Codable, CaseIterable, Sendable {
    case userDeclaration = "user_declaration"
    case systemMeasurement = "system_measurement"
    case officialDocument = "official_document"
    case curatedReference = "curated_reference"
}

/// Metadado de proveniência. A URL, quando houver, permanece dado não
/// confiável: este núcleo não a abre, não a busca e não a entrega a uma ferramenta.
public struct ContextSource: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let kind: ContextSourceKind
    public let url: String?
    public let retrievedAt: Date

    public init(id: PseudonymousReference, kind: ContextSourceKind, url: String? = nil, retrievedAt: Date) {
        self.id = id
        self.kind = kind
        self.url = url
        self.retrievedAt = retrievedAt
    }
}

public enum EvidenceQualityStatus: String, Codable, CaseIterable, Sendable {
    case usable
    case partial
    case stale
    case conflicted
    case unavailable
}

public enum EvidenceValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case boolean(Bool)
}

extension EvidenceValue: Codable {
    private enum CodingKeys: String, CodingKey { case kind, text, number, boolean }
    private enum Kind: String, Codable { case text, number, boolean }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text: self = .text(try container.decode(String.self, forKey: .text))
        case .number: self = .number(try container.decode(Double.self, forKey: .number))
        case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .number(let value):
            try container.encode(Kind.number, forKey: .kind)
            try container.encode(value, forKey: .number)
        case .boolean(let value):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(value, forKey: .boolean)
        }
    }
}

public struct EvidenceFact: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let subjectRef: PseudonymousReference
    public let property: String
    public let value: EvidenceValue
    public let unit: String?
    public let sourceType: EvidenceSourceType
    public let sourceRefs: [PseudonymousReference]
    public let observedAt: Date
    public let validUntil: Date?
    public let consentScope: ConsentScope
    public let qualityStatus: EvidenceQualityStatus
    public let derivedFrom: [PseudonymousReference]

    public init(
        id: PseudonymousReference,
        subjectRef: PseudonymousReference,
        property: String,
        value: EvidenceValue,
        unit: String? = nil,
        sourceType: EvidenceSourceType,
        sourceRefs: [PseudonymousReference],
        observedAt: Date,
        validUntil: Date? = nil,
        consentScope: ConsentScope,
        qualityStatus: EvidenceQualityStatus = .usable,
        derivedFrom: [PseudonymousReference] = []
    ) {
        self.id = id
        self.subjectRef = subjectRef
        self.property = property
        self.value = value
        self.unit = unit
        self.sourceType = sourceType
        self.sourceRefs = sourceRefs
        self.observedAt = observedAt
        self.validUntil = validUntil
        self.consentScope = consentScope
        self.qualityStatus = qualityStatus
        self.derivedFrom = derivedFrom
    }
}

public struct ConsultationHypothesis: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let text: String
    public let evidenceRefs: [PseudonymousReference]
    public let limitations: [String]

    public init(id: PseudonymousReference, text: String, evidenceRefs: [PseudonymousReference], limitations: [String]) {
        self.id = id
        self.text = text
        self.evidenceRefs = evidenceRefs
        self.limitations = limitations
    }
}

public enum AbsenceReason: String, Codable, CaseIterable, Sendable {
    case notCollected = "not_collected"
    case expired
    case conflicted
    case deleted
    case unavailable
    case ineligibleMeasurement = "ineligible_measurement"
    case consentNotGranted = "consent_not_granted"
}

/// Ausência é um estado explícito. Nunca carrega um valor que possa ser
/// confundido com zero, `false` ou uma lista vazia medida.
public struct KnownAbsence: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let subjectRef: PseudonymousReference
    public let property: String
    public let reason: AbsenceReason
    public let observedAt: Date
    public let sourceRefs: [PseudonymousReference]

    public init(id: PseudonymousReference, subjectRef: PseudonymousReference, property: String, reason: AbsenceReason, observedAt: Date, sourceRefs: [PseudonymousReference] = []) {
        self.id = id
        self.subjectRef = subjectRef
        self.property = property
        self.reason = reason
        self.observedAt = observedAt
        self.sourceRefs = sourceRefs
    }
}

public enum MeasurementMethod: String, Codable, CaseIterable, Sendable {
    case appMeasurement = "app_measurement"
}

public struct ConsultationMeasurement: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let profileRef: PseudonymousReference
    public let measuredAt: Date
    public let validUntil: Date
    public let method: MeasurementMethod
    public let values: [EvidenceFact]

    public init(id: PseudonymousReference, profileRef: PseudonymousReference, measuredAt: Date, validUntil: Date, method: MeasurementMethod, values: [EvidenceFact]) {
        self.id = id
        self.profileRef = profileRef
        self.measuredAt = measuredAt
        self.validUntil = validUntil
        self.method = method
        self.values = values
    }
}

public struct ContextSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let snapshotID: PseudonymousReference
    public let revision: Int
    public let intent: ConsultationIntent
    public let consent: ConsentReceipt
    public let createdAt: Date
    public let sources: [ContextSource]
    public let facts: [EvidenceFact]
    public let hypotheses: [ConsultationHypothesis]
    public let absences: [KnownAbsence]
    public let measurements: [ConsultationMeasurement]

    public init(
        schemaVersion: String = AssistConsultationContract.schemaVersion,
        snapshotID: PseudonymousReference,
        revision: Int,
        intent: ConsultationIntent,
        consent: ConsentReceipt,
        createdAt: Date,
        sources: [ContextSource] = [],
        facts: [EvidenceFact] = [],
        hypotheses: [ConsultationHypothesis] = [],
        absences: [KnownAbsence] = [],
        measurements: [ConsultationMeasurement] = []
    ) {
        self.schemaVersion = schemaVersion
        self.snapshotID = snapshotID
        self.revision = revision
        self.intent = intent
        self.consent = consent
        self.createdAt = createdAt
        self.sources = sources
        self.facts = facts
        self.hypotheses = hypotheses
        self.absences = absences
        self.measurements = measurements
    }

    public func validate(at now: Date) throws {
        guard schemaVersion == AssistConsultationContract.schemaVersion, revision > 0 else {
            throw ContractError.invalid("A versão ou revisão do ContextSnapshot é incompatível.")
        }
        let hasContext = !sources.isEmpty || !facts.isEmpty || !hypotheses.isEmpty || !absences.isEmpty || !measurements.isEmpty
        if hasContext && !consent.scope.permitsContext { throw ContractError.contextNotAuthorized }
        if consent.state != .granted && hasContext { throw ContractError.consentNotGranted }

        for measurement in measurements {
            guard measurement.validUntil > now, measurement.measuredAt <= measurement.validUntil, !measurement.values.isEmpty else {
                throw ContractError.invalid("Medição sem validade, vazia ou expirada.")
            }
        }
        let allFacts = facts + measurements.flatMap(\.values)
        let factRefs = Set(allFacts.map(\.id))
        guard factRefs.count == allFacts.count else { throw ContractError.invalid("Há fatos com referências repetidas.") }
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        guard sourcesByID.count == sources.count else { throw ContractError.invalid("Há fontes com referências repetidas.") }
        for source in sources { try validateSource(source) }
        for fact in allFacts { try validateFact(fact, knownSources: sourcesByID, at: now) }
        let availableEvidence = factRefs.union(measurements.flatMap { $0.values.map(\.id) })
        for hypothesis in hypotheses {
            guard !hypothesis.text.isEmpty, !hypothesis.evidenceRefs.isEmpty,
                  Set(hypothesis.evidenceRefs).isSubset(of: availableEvidence) else {
                throw ContractError.invalid("Hipótese sem evidência disponível.")
            }
        }
    }

    private func validateFact(_ fact: EvidenceFact, knownSources: [PseudonymousReference: ContextSource], at now: Date) throws {
        guard !fact.property.isEmpty, !fact.sourceRefs.isEmpty, fact.consentScope.permitsContext else {
            throw ContractError.invalid("Fato sem procedência ou escopo de contexto.")
        }
        let factSources = fact.sourceRefs.compactMap { knownSources[$0] }
        guard factSources.count == fact.sourceRefs.count else { throw ContractError.invalid("Fato referencia fonte ausente.") }
        if fact.sourceType == .manufacturerDocumented,
           !factSources.contains(where: { $0.kind == .officialDocument }) {
            throw ContractError.invalid("Especificação documentada exige fonte oficial.")
        }
        guard fact.qualityStatus == .usable || fact.qualityStatus == .partial else {
            throw ContractError.invalid("Fato não utilizável deve ser representado como ausência.")
        }
        if let validUntil = fact.validUntil, validUntil <= fact.observedAt || validUntil <= now {
            throw ContractError.invalid("Fato expirado não entra no snapshot.")
        }
    }

    private func validateSource(_ source: ContextSource) throws {
        guard source.kind != .officialDocument || isPublicHTTPSURL(source.url) else {
            throw ContractError.invalid("Fonte oficial exige URL HTTPS pública.")
        }
    }

    private func isPublicHTTPSURL(_ value: String?) -> Bool {
        guard let value, let url = URL(string: value), url.scheme == "https", let host = url.host,
              url.user == nil, url.password == nil else {
            return false
        }
        let normalizedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalizedHost.isEmpty,
              normalizedHost.contains("."),
              normalizedHost != "localhost",
              !normalizedHost.hasSuffix(".localhost"),
              !normalizedHost.hasSuffix(".local"),
              !isIPLiteral(normalizedHost) else {
            return false
        }
        return true
    }

    /// Este contrato não resolve nem acessa a URL. Ele recusa literais de IP,
    /// notação numérica ambígua e hosts locais no payload; a validação de DNS,
    /// redirects e destino público pertence à ferramenta que vier a buscar a
    /// fonte em um bloco posterior.
    private func isIPLiteral(_ host: String) -> Bool {
        if host.contains(":") { return true }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return !labels.isEmpty && labels.allSatisfy(isNumericAddressLabel)
    }

    private func isNumericAddressLabel(_ label: Substring) -> Bool {
        guard !label.isEmpty else { return false }
        if label.lowercased().hasPrefix("0x") {
            return UInt64(label.dropFirst(2), radix: 16) != nil
        }
        return UInt64(label) != nil
    }
}

public enum ConsultationInput: Equatable, Sendable {
    case userMessage(String)
}

extension ConsultationInput: Codable {
    private enum CodingKeys: String, CodingKey { case kind, text }
    private enum Kind: String, Codable { case userMessage = "user_message" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Kind.self, forKey: .kind) == .userMessage else {
            throw ContractError.invalid("Tipo de entrada não suportado pelo núcleo local.")
        }
        self = .userMessage(try container.decode(String.self, forKey: .text))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Kind.userMessage, forKey: .kind)
        if case .userMessage(let text) = self { try container.encode(text, forKey: .text) }
    }

    var text: String {
        switch self {
        case .userMessage(let text): return text
        }
    }
}

/// Payload local serializável. Carrega somente uma referência de sessão, sem URL,
/// provider ou operação de rede; a etapa remota será outro bloco, com autorização própria.
public struct ConsultationPayload: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestID: PseudonymousReference
    public let transportSessionID: PseudonymousReference
    public let turnID: PseudonymousReference
    public let expectedRevision: Int
    public let locale: String
    public let input: ConsultationInput
    public let contextSnapshot: ContextSnapshot
    public let consentReceiptRef: PseudonymousReference

    public init(schemaVersion: String = AssistConsultationContract.schemaVersion, requestID: PseudonymousReference, transportSessionID: PseudonymousReference, turnID: PseudonymousReference, expectedRevision: Int, locale: String, input: ConsultationInput, contextSnapshot: ContextSnapshot, consentReceiptRef: PseudonymousReference) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.transportSessionID = transportSessionID
        self.turnID = turnID
        self.expectedRevision = expectedRevision
        self.locale = locale
        self.input = input
        self.contextSnapshot = contextSnapshot
        self.consentReceiptRef = consentReceiptRef
    }

    public func validate(at now: Date) throws {
        guard schemaVersion == AssistConsultationContract.schemaVersion, expectedRevision > 0 else {
            throw ContractError.invalid("Schema de consulta incompatível.")
        }
        guard locale.range(of: "^[a-z]{2,3}(-[A-Z]{2})?$", options: .regularExpression) != nil,
              !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.text.unicodeScalars.count <= 2_000 else {
            throw ContractError.invalid("Entrada ou locale inválido.")
        }
        guard consentReceiptRef == contextSnapshot.consent.ref else {
            throw ContractError.invalid("Recibo do payload diverge do ContextSnapshot.")
        }
        guard contextSnapshot.consent.state == .granted, contextSnapshot.consent.scope.permitsQuestion else {
            throw ContractError.consentNotGranted
        }
        try contextSnapshot.validate(at: now)
    }
}

public struct EvidenceCandidate: Sendable {
    public let fact: EvidenceFact
    public init(fact: EvidenceFact) { self.fact = fact }
}

public enum EvidenceProjection: Equatable, Sendable {
    case evidence(EvidenceFact)
    case absence(KnownAbsence)
}

public enum EvidenceProjector {
    public static func project(_ candidate: EvidenceCandidate, at now: Date) -> EvidenceProjection {
        let fact = candidate.fact
        let reason: AbsenceReason?
        switch fact.qualityStatus {
        case .usable, .partial:
            reason = fact.validUntil.map { $0 <= now ? .expired : nil } ?? nil
        case .stale: reason = .expired
        case .conflicted: reason = .conflicted
        case .unavailable: reason = .unavailable
        }
        if let reason {
            return .absence(KnownAbsence(
                id: .generated(prefix: "absence"),
                subjectRef: fact.subjectRef,
                property: fact.property,
                reason: reason,
                observedAt: now,
                sourceRefs: fact.sourceRefs
            ))
        }
        return .evidence(fact)
    }
}

public struct MeasurementCandidate: Sendable {
    public let reference: PseudonymousReference
    public let measurement: NetworkMeasurement
    public let profileRef: PseudonymousReference?
    public let validUntil: Date?
    public let isExpensive: Bool
    public let isPersonalHotspot: Bool
    public let isDeleted: Bool
    public let consent: ConsentReceipt

    public init(reference: PseudonymousReference, measurement: NetworkMeasurement, profileRef: PseudonymousReference?, validUntil: Date?, isExpensive: Bool = false, isPersonalHotspot: Bool = false, isDeleted: Bool = false, consent: ConsentReceipt) {
        self.reference = reference
        self.measurement = measurement
        self.profileRef = profileRef
        self.validUntil = validUntil
        self.isExpensive = isExpensive
        self.isPersonalHotspot = isPersonalHotspot
        self.isDeleted = isDeleted
        self.consent = consent
    }
}

public enum MeasurementProjection: Equatable, Sendable {
    case measurement(ConsultationMeasurement)
    case absence(KnownAbsence)
}

/// Único ponto do contrato V4 que projeta uma medição. A decisão residencial
/// delega a B1; este pacote não possui uma lista alternativa de interfaces.
public enum MeasurementProjector {
    public static func project(_ candidate: MeasurementCandidate, at now: Date) -> MeasurementProjection {
        let absence: (AbsenceReason) -> MeasurementProjection = { reason in
            .absence(KnownAbsence(
                id: .generated(prefix: "absence"),
                subjectRef: candidate.reference,
                property: "measurement",
                reason: reason,
                observedAt: now,
                sourceRefs: [candidate.reference]
            ))
        }
        guard candidate.consent.state == .granted, candidate.consent.scope.permitsContext else {
            return absence(.consentNotGranted)
        }
        guard !candidate.isDeleted else { return absence(.deleted) }
        guard let profileRef = candidate.profileRef,
              let validUntil = candidate.validUntil,
              validUntil > now,
              candidate.measurement.outcome == .complete else {
            return absence(.notCollected)
        }
        guard ResidentialPlanEligibility.evaluate(
            measurement: candidate.measurement,
            isExpensive: candidate.isExpensive,
            isPersonalHotspot: candidate.isPersonalHotspot
        ).isEligible else {
            return absence(.ineligibleMeasurement)
        }

        var values: [EvidenceFact] = []
        if let download = candidate.measurement.downloadMbps {
            values.append(metric("download_mbps", value: download, candidate: candidate, validUntil: validUntil))
        }
        if let upload = candidate.measurement.uploadMbps {
            values.append(metric("upload_mbps", value: upload, candidate: candidate, validUntil: validUntil))
        }
        guard !values.isEmpty else { return absence(.notCollected) }
        return .measurement(ConsultationMeasurement(
            id: candidate.reference,
            profileRef: profileRef,
            measuredAt: candidate.measurement.measuredAt,
            validUntil: validUntil,
            method: .appMeasurement,
            values: values
        ))
    }

    private static func metric(_ property: String, value: Double, candidate: MeasurementCandidate, validUntil: Date) -> EvidenceFact {
        EvidenceFact(
            id: .generated(prefix: "evidence"),
            subjectRef: candidate.reference,
            property: property,
            value: .number(value),
            unit: "Mbps",
            sourceType: .systemObserved,
            sourceRefs: [candidate.reference],
            observedAt: candidate.measurement.measuredAt,
            validUntil: validUntil,
            consentScope: candidate.consent.scope,
            qualityStatus: .usable
        )
    }
}

private enum JSONSchemaValidator {
    static func validate(_ value: Any, against schema: Any, root: Any? = nil, path: String = "$") throws {
        let root = root ?? schema
        guard let schema = schema as? [String: Any] else { throw ContractError.invalid("Schema inválido em \(path).") }
        if let reference = schema["$ref"] as? String {
            try validate(value, against: try resolve(reference, from: root), root: root, path: path)
            return
        }
        if let constant = schema["const"], !isEqual(value, constant) {
            throw ContractError.invalid("Valor incompatível em \(path).")
        }
        if let options = schema["oneOf"] as? [Any] {
            let valid = options.filter { (try? validate(value, against: $0, root: root, path: path)) != nil }
            guard valid.count == 1 else { throw ContractError.invalid("União inválida em \(path).") }
            return
        }
        if let types = schema["type"] as? [String] {
            guard types.contains(where: { matches(value, type: $0) }) else { throw ContractError.invalid("Tipo incompatível em \(path).") }
        } else if let type = schema["type"] as? String, !matches(value, type: type) {
            throw ContractError.invalid("Tipo incompatível em \(path).")
        }
        if let allowed = schema["enum"] as? [Any], !allowed.contains(where: { isEqual(value, $0) }) {
            throw ContractError.invalid("Enum incompatível em \(path).")
        }
        if let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: Any] ?? [:]
            for required in schema["required"] as? [String] ?? [] where object[required] == nil {
                throw ContractError.invalid("Campo obrigatório ausente em \(path): \(required).")
            }
            if (schema["additionalProperties"] as? Bool) == false,
               object.keys.contains(where: { properties[$0] == nil }) {
                throw ContractError.invalid("Campo não permitido em \(path).")
            }
            for (key, child) in object {
                if let childSchema = properties[key] { try validate(child, against: childSchema, root: root, path: "\(path).\(key)") }
            }
        }
        if let array = value as? [Any] {
            if let minimum = schema["minItems"] as? Int, array.count < minimum { throw ContractError.invalid("Lista curta em \(path).") }
            if let maximum = schema["maxItems"] as? Int, array.count > maximum { throw ContractError.invalid("Lista longa em \(path).") }
            if let itemSchema = schema["items"] { for (index, child) in array.enumerated() { try validate(child, against: itemSchema, root: root, path: "\(path)[\(index)]") } }
        }
        if let string = value as? String {
            if let minimum = schema["minLength"] as? Int, string.count < minimum { throw ContractError.invalid("Texto curto em \(path).") }
            if let maximum = schema["maxLength"] as? Int, string.count > maximum { throw ContractError.invalid("Texto longo em \(path).") }
            if let pattern = schema["pattern"] as? String, string.range(of: pattern, options: .regularExpression) == nil { throw ContractError.invalid("Formato incompatível em \(path).") }
        }
    }

    private static func resolve(_ reference: String, from root: Any) throws -> Any {
        guard reference.hasPrefix("#/") else { throw ContractError.invalid("Referência de schema externa não permitida.") }
        return try reference.dropFirst(2).split(separator: "/").reduce(root) { partial, component in
            guard let object = partial as? [String: Any], let next = object[String(component)] else { throw ContractError.invalid("Referência de schema ausente.") }
            return next
        }
    }

    private static func matches(_ value: Any, type: String) -> Bool {
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "boolean": return (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        case "number": return (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() } ?? false
        case "integer": return (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.rounded() == $0.doubleValue } ?? false
        case "null": return value is NSNull
        default: return false
        }
    }

    private static func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let lhs = lhs as? String, let rhs = rhs as? String { return lhs == rhs }
        if let lhs = lhs as? NSNumber, let rhs = rhs as? NSNumber { return lhs == rhs }
        return false
    }
}
