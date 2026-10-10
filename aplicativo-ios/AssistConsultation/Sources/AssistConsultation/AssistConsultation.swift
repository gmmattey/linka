import Foundation
import NetworkCore
import NetworkInventory

/// O contrato local do Assist V4. Este pacote não contém transporte, provider,
/// armazenamento remoto ou integração com o Assist legado.
public enum AssistConsultationContract {
    public static let schemaVersion = "assist.consultation/1.0"
    public static let maximumPayloadBytes = 256 * 1024
    public static let maximumResponseBytes = 64 * 1024

    public static func decode(_ data: Data, now: Date = Date()) throws -> ConsultationPayload {
        guard data.count <= maximumPayloadBytes else { throw ContractError.payloadTooLarge }
        let object = try JSONSerialization.jsonObject(with: data)
        try JSONSchemaValidator.validate(object, against: try schemaObject(named: "assist.consultation-1.0.schema"))

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

    public static func decodeResponse(_ data: Data, for payload: ConsultationPayload, now: Date = Date()) throws -> ConsultationResponse {
        guard data.count <= maximumResponseBytes else { throw ContractError.payloadTooLarge }
        let object = try JSONSerialization.jsonObject(with: data)
        try JSONSchemaValidator.validate(object, against: try schemaObject(named: "assist.consultation-1.0.response.schema"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ConsultationResponse.self, from: data)
        try response.validate(for: payload, at: now)
        return response
    }

    public static func encodeResponse(_ response: ConsultationResponse, for payload: ConsultationPayload, now: Date = Date()) throws -> Data {
        try response.validate(for: payload, at: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        _ = try decodeResponse(data, for: payload, now: now)
        return data
    }

    private static func schemaObject(named name: String) throws -> Any {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
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

public enum ConsultationPurpose: String, Codable, CaseIterable, Sendable {
    case consultation
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
    public let revision: String?
    public let retrievedAt: Date

    public init(id: PseudonymousReference, kind: ContextSourceKind, url: String? = nil, revision: String? = nil, retrievedAt: Date) {
        self.id = id
        self.kind = kind
        self.url = url
        self.revision = revision
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
    public let validFrom: Date?
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
        validFrom: Date? = nil,
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
        self.validFrom = validFrom
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

public enum MeasurementPlatform: String, Codable, CaseIterable, Sendable {
    case iOS = "ios"
    case iPadOS = "ipados"
    case macOS = "macos"
    case unknown
}

public struct ConsultationMeasurement: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let profileRef: PseudonymousReference
    public let measuredAt: Date
    public let validUntil: Date
    public let method: MeasurementMethod
    public let platform: MeasurementPlatform
    public let values: [EvidenceFact]

    public init(id: PseudonymousReference, profileRef: PseudonymousReference, measuredAt: Date, validUntil: Date, method: MeasurementMethod, platform: MeasurementPlatform = .unknown, values: [EvidenceFact]) {
        self.id = id
        self.profileRef = profileRef
        self.measuredAt = measuredAt
        self.validUntil = validUntil
        self.method = method
        self.platform = platform
        self.values = values
    }
}

public enum ConsultationEntityKind: String, Codable, CaseIterable, Sendable {
    case profile, device, plan, connection, environment, room
}

public struct ConsultationEntity: Codable, Equatable, Sendable, Identifiable {
    public let id: PseudonymousReference
    public let kind: ConsultationEntityKind
    public let sourceRefs: [PseudonymousReference]

    public init(id: PseudonymousReference, kind: ConsultationEntityKind, sourceRefs: [PseudonymousReference] = []) {
        self.id = id
        self.kind = kind
        self.sourceRefs = sourceRefs
    }
}

public enum ConsultationTool: String, Codable, CaseIterable, Sendable {
    case readNetworkContext = "read_network_context"
    case selectMeasurementEvidence = "select_measurement_evidence"
    case evaluateOpportunities = "evaluate_opportunities"
    case lookupDeviceSpecs = "lookup_device_specs"
    case retrieveNetworkGuidance = "retrieve_network_guidance"
    case proposeNetworkTest = "propose_network_test"
    case runExistingTest = "run_existing_test"
    case compareMeasurements = "compare_measurements"
    case saveConsultation = "save_consultation"
}

public enum CapabilityAvailability: String, Codable, CaseIterable, Sendable { case available, unavailable, notAuthorized = "not_authorized" }

public struct ConsultationCapability: Codable, Equatable, Sendable {
    public let tool: ConsultationTool
    public let availability: CapabilityAvailability
    public let limitation: String?

    public init(tool: ConsultationTool, availability: CapabilityAvailability, limitation: String? = nil) {
        self.tool = tool
        self.availability = availability
        self.limitation = limitation
    }
}

public struct ContextSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let snapshotID: PseudonymousReference
    public let revision: Int
    public let purpose: ConsultationPurpose
    public let intent: ConsultationIntent
    public let consent: ConsentReceipt
    public let consentReceiptRef: PseudonymousReference
    public let selectedProfileRef: PseudonymousReference?
    public let createdAt: Date
    public let sources: [ContextSource]
    public let entities: [ConsultationEntity]
    public let facts: [EvidenceFact]
    public let hypotheses: [ConsultationHypothesis]
    public let absences: [KnownAbsence]
    public let measurements: [ConsultationMeasurement]
    public let capabilities: [ConsultationCapability]

    public init(
        schemaVersion: String = AssistConsultationContract.schemaVersion,
        snapshotID: PseudonymousReference,
        revision: Int,
        purpose: ConsultationPurpose = .consultation,
        intent: ConsultationIntent,
        consent: ConsentReceipt,
        selectedProfileRef: PseudonymousReference? = nil,
        createdAt: Date,
        sources: [ContextSource] = [],
        entities: [ConsultationEntity] = [],
        facts: [EvidenceFact] = [],
        hypotheses: [ConsultationHypothesis] = [],
        absences: [KnownAbsence] = [],
        measurements: [ConsultationMeasurement] = [],
        capabilities: [ConsultationCapability] = []
    ) {
        self.schemaVersion = schemaVersion
        self.snapshotID = snapshotID
        self.revision = revision
        self.purpose = purpose
        self.intent = intent
        self.consent = consent
        self.consentReceiptRef = consent.ref
        self.selectedProfileRef = selectedProfileRef
        self.createdAt = createdAt
        self.sources = sources
        self.entities = entities
        self.facts = facts
        self.hypotheses = hypotheses
        self.absences = absences
        self.measurements = measurements
        self.capabilities = capabilities
    }

    public func validate(at now: Date) throws {
        guard schemaVersion == AssistConsultationContract.schemaVersion, revision > 0, createdAt <= now else {
            throw ContractError.invalid("A versão ou revisão do ContextSnapshot é incompatível.")
        }
        guard consentReceiptRef == consent.ref else { throw ContractError.invalid("Recibo do ContextSnapshot diverge do consentimento.") }
        let hasContext = selectedProfileRef != nil || !sources.isEmpty || !entities.isEmpty || !facts.isEmpty || !hypotheses.isEmpty || !absences.isEmpty || !measurements.isEmpty
        if hasContext && !consent.scope.permitsContext { throw ContractError.contextNotAuthorized }
        if consent.state != .granted && hasContext { throw ContractError.consentNotGranted }

        for measurement in measurements {
            guard measurement.validUntil > now, measurement.measuredAt <= now, measurement.measuredAt <= measurement.validUntil, !measurement.values.isEmpty else {
                throw ContractError.invalid("Medição sem validade, vazia ou expirada.")
            }
        }
        let allFacts = facts + measurements.flatMap(\.values)
        let factRefs = Set(allFacts.map(\.id))
        guard factRefs.count == allFacts.count else { throw ContractError.invalid("Há fatos com referências repetidas.") }
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        guard sourcesByID.count == sources.count else { throw ContractError.invalid("Há fontes com referências repetidas.") }
        let entitiesByID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        guard entitiesByID.count == entities.count else { throw ContractError.invalid("Há entidades com referências repetidas.") }
        if let selectedProfileRef, entitiesByID[selectedProfileRef]?.kind != .profile {
            throw ContractError.invalid("O perfil selecionado não pertence ao snapshot.")
        }
        for source in sources { try validateSource(source, at: now) }
        for entity in entities where !Set(entity.sourceRefs).isSubset(of: Set(sourcesByID.keys)) {
            throw ContractError.invalid("Entidade referencia fonte ausente.")
        }
        for fact in allFacts { try validateFact(fact, knownSources: sourcesByID, at: now) }
        let availableEvidence = factRefs.union(measurements.flatMap { $0.values.map(\.id) })
        for hypothesis in hypotheses {
            guard !hypothesis.text.isEmpty, !hypothesis.evidenceRefs.isEmpty,
                  Set(hypothesis.evidenceRefs).isSubset(of: availableEvidence) else {
                throw ContractError.invalid("Hipótese sem evidência disponível.")
            }
        }
        for absence in absences where !Set(absence.sourceRefs).isSubset(of: Set(sourcesByID.keys)) {
            throw ContractError.invalid("Ausência referencia fonte ausente.")
        }
        let capabilityTools = capabilities.map(\.tool)
        guard Set(capabilityTools).count == capabilityTools.count else { throw ContractError.invalid("Há capabilities repetidas.") }
    }

    private func validateFact(_ fact: EvidenceFact, knownSources: [PseudonymousReference: ContextSource], at now: Date) throws {
        guard !fact.property.isEmpty, !fact.sourceRefs.isEmpty, fact.consentScope.permitsContext, fact.observedAt <= now else {
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
        if let validFrom = fact.validFrom, validFrom > fact.observedAt {
            throw ContractError.invalid("Fato começa a valer depois da observação.")
        }
        let knownFacts = Set((facts + measurements.flatMap(\.values)).map(\.id).filter { $0 != fact.id })
        guard Set(fact.derivedFrom).isSubset(of: knownFacts) else {
            throw ContractError.invalid("Fato derivado referencia evidência ausente ou circular.")
        }
    }

    private func validateSource(_ source: ContextSource, at now: Date) throws {
        guard source.retrievedAt <= now,
              source.kind != .officialDocument || isPublicHTTPSURL(source.url) else {
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

public struct QuestionAnswer: Codable, Equatable, Sendable {
    public let questionID: PseudonymousReference
    public let optionID: PseudonymousReference?
    public let text: String?

    public init(questionID: PseudonymousReference, optionID: PseudonymousReference? = nil, text: String? = nil) {
        self.questionID = questionID
        self.optionID = optionID
        self.text = text
    }

    fileprivate func validate() throws {
        let hasText = !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard (optionID != nil) != hasText, (text?.unicodeScalars.count ?? 0) <= 2_000 else {
            throw ContractError.invalid("Resposta exige exatamente uma opção ou texto válido.")
        }
    }
}

public enum ToolResultStatus: String, Codable, CaseIterable, Sendable {
    case completed, partial, cancelled, denied, unavailable, failed
}

public enum ToolValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case boolean(Bool)
    case reference(PseudonymousReference)
}

extension ToolValue: Codable {
    private enum CodingKeys: String, CodingKey { case kind, text, number, boolean, reference }
    private enum Kind: String, Codable { case text, number, boolean, reference }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text: self = .text(try container.decode(String.self, forKey: .text))
        case .number: self = .number(try container.decode(Double.self, forKey: .number))
        case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case .reference: self = .reference(try container.decode(PseudonymousReference.self, forKey: .reference))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value): try container.encode(Kind.text, forKey: .kind); try container.encode(value, forKey: .text)
        case .number(let value): try container.encode(Kind.number, forKey: .kind); try container.encode(value, forKey: .number)
        case .boolean(let value): try container.encode(Kind.boolean, forKey: .kind); try container.encode(value, forKey: .boolean)
        case .reference(let value): try container.encode(Kind.reference, forKey: .kind); try container.encode(value, forKey: .reference)
        }
    }
}

public struct ToolArgument: Codable, Equatable, Sendable {
    public let name: String
    public let value: ToolValue

    public init(name: String, value: ToolValue) { self.name = name; self.value = value }
}

public struct ToolResultPayload: Codable, Equatable, Sendable {
    public let proposalID: PseudonymousReference
    public let tool: ConsultationTool
    public let status: ToolResultStatus
    public let reason: String?
    public let output: [ToolArgument]

    public init(proposalID: PseudonymousReference, tool: ConsultationTool, status: ToolResultStatus, reason: String? = nil, output: [ToolArgument] = []) {
        self.proposalID = proposalID
        self.tool = tool
        self.status = status
        self.reason = reason
        self.output = output
    }

    fileprivate func validate() throws {
        guard Set(output.map(\.name)).count == output.count, output.allSatisfy({ !$0.name.isEmpty }) else {
            throw ContractError.invalid("Resultado de ferramenta contém argumentos inválidos.")
        }
        if status == .partial || status == .completed { return }
        guard output.isEmpty else { throw ContractError.invalid("Resultado não concluído não pode inventar valores.") }
    }
}

public enum ActionFeedbackStatus: String, Codable, CaseIterable, Sendable {
    case accepted, completed, ignored, impossible, retestRequested = "retest_requested"
}

public struct ActionFeedbackPayload: Codable, Equatable, Sendable {
    public let actionID: PseudonymousReference
    public let status: ActionFeedbackStatus
    public let note: String?

    public init(actionID: PseudonymousReference, status: ActionFeedbackStatus, note: String? = nil) {
        self.actionID = actionID
        self.status = status
        self.note = note
    }
}

public enum ConsultationInput: Equatable, Sendable {
    case userMessage(String)
    case answer(QuestionAnswer)
    case toolResult(ToolResultPayload)
    case actionFeedback(ActionFeedbackPayload)
}

extension ConsultationInput: Codable {
    private enum CodingKeys: String, CodingKey { case kind, text, answer, toolResult = "tool_result", actionFeedback = "action_feedback" }
    private enum Kind: String, Codable { case userMessage = "user_message", answer, toolResult = "tool_result", actionFeedback = "action_feedback" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .userMessage: self = .userMessage(try container.decode(String.self, forKey: .text))
        case .answer: self = .answer(try container.decode(QuestionAnswer.self, forKey: .answer))
        case .toolResult: self = .toolResult(try container.decode(ToolResultPayload.self, forKey: .toolResult))
        case .actionFeedback: self = .actionFeedback(try container.decode(ActionFeedbackPayload.self, forKey: .actionFeedback))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .userMessage(let text): try container.encode(Kind.userMessage, forKey: .kind); try container.encode(text, forKey: .text)
        case .answer(let value): try container.encode(Kind.answer, forKey: .kind); try container.encode(value, forKey: .answer)
        case .toolResult(let value): try container.encode(Kind.toolResult, forKey: .kind); try container.encode(value, forKey: .toolResult)
        case .actionFeedback(let value): try container.encode(Kind.actionFeedback, forKey: .kind); try container.encode(value, forKey: .actionFeedback)
        }
    }

    fileprivate func validate() throws {
        switch self {
        case .userMessage(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.unicodeScalars.count <= 2_000 else {
                throw ContractError.invalid("Mensagem inválida.")
            }
        case .answer(let answer): try answer.validate()
        case .toolResult(let result): try result.validate()
        case .actionFeedback(let feedback):
            guard (feedback.note?.unicodeScalars.count ?? 0) <= 2_000 else { throw ContractError.invalid("Retorno de ação longo demais.") }
        }
    }
}

/// Payload local serializável. Carrega somente uma referência de sessão, sem URL,
/// provider ou operação de rede; a etapa remota será outro bloco, com autorização própria.
public struct ConsultationPayload: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestID: PseudonymousReference
    public let localSessionID: PseudonymousReference
    public let transportSessionID: PseudonymousReference
    public let turnID: PseudonymousReference
    public let expectedRevision: Int
    public let locale: String
    public let input: ConsultationInput
    public let contextSnapshot: ContextSnapshot
    public let consentReceiptRef: PseudonymousReference

    public init(schemaVersion: String = AssistConsultationContract.schemaVersion, requestID: PseudonymousReference, localSessionID: PseudonymousReference? = nil, transportSessionID: PseudonymousReference, turnID: PseudonymousReference, expectedRevision: Int, locale: String, input: ConsultationInput, contextSnapshot: ContextSnapshot, consentReceiptRef: PseudonymousReference) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.localSessionID = localSessionID ?? .generated(prefix: "local-session")
        self.transportSessionID = transportSessionID
        self.turnID = turnID
        self.expectedRevision = expectedRevision
        self.locale = locale
        self.input = input
        self.contextSnapshot = contextSnapshot
        self.consentReceiptRef = consentReceiptRef
    }

    public func validate(at now: Date) throws {
        guard schemaVersion == AssistConsultationContract.schemaVersion, expectedRevision > 0, expectedRevision == contextSnapshot.revision else {
            throw ContractError.invalid("Schema de consulta incompatível.")
        }
        guard locale.range(of: "^[a-z]{2,3}(-[A-Z]{2})?$", options: .regularExpression) != nil else { throw ContractError.invalid("Locale inválido.") }
        try input.validate()
        guard consentReceiptRef == contextSnapshot.consent.ref else {
            throw ContractError.invalid("Recibo do payload diverge do ContextSnapshot.")
        }
        guard contextSnapshot.consent.state == .granted, contextSnapshot.consent.scope.permitsQuestion else {
            throw ContractError.consentNotGranted
        }
        try contextSnapshot.validate(at: now)
    }
}

public enum ConsultationDisposition: String, Codable, CaseIterable, Sendable {
    case awaitingAnswer = "awaiting_answer"
    case awaitingApproval = "awaiting_approval"
    case answered, inconclusive, outOfScope = "out_of_scope", unavailable
}

public enum ConsultationClaimKind: String, Codable, CaseIterable, Sendable {
    case observation, inference, recommendation, limitation
}

public struct ConsultationClaim: Codable, Equatable, Sendable {
    public let id: PseudonymousReference
    public let kind: ConsultationClaimKind
    public let text: String
    public let evidenceRefs: [PseudonymousReference]

    public init(id: PseudonymousReference, kind: ConsultationClaimKind, text: String, evidenceRefs: [PseudonymousReference]) {
        self.id = id
        self.kind = kind
        self.text = text
        self.evidenceRefs = evidenceRefs
    }
}

public struct EvidenceGap: Codable, Equatable, Sendable {
    public let id: PseudonymousReference
    public let text: String
    public let evidenceRefs: [PseudonymousReference]

    public init(id: PseudonymousReference, text: String, evidenceRefs: [PseudonymousReference] = []) {
        self.id = id
        self.text = text
        self.evidenceRefs = evidenceRefs
    }
}

public enum ConsultationConclusion: String, Codable, CaseIterable, Sendable {
    case nextTest = "next_test", safeAction = "safe_action", escalation, insufficient
    case keep, adjust, upgradeCandidate = "upgrade_candidate", notJustified = "not_justified"
    case repositionCandidate = "reposition_candidate", wiredAPCandidate = "wired_ap_candidate", meshCandidate = "mesh_candidate"
    case usageFit = "usage_fit", reviewCost = "review_cost", capacityCandidate = "capacity_candidate"
    case commercialDataMissing = "commercial_data_missing", explained, needsContext = "needs_context"
}

public struct ConsultationAssessment: Codable, Equatable, Sendable {
    public let conclusion: ConsultationConclusion
    public let summary: String
    public let observations: [String]
    public let hypotheses: [String]
    public let unknowns: [EvidenceGap]
    public let evidenceRefs: [PseudonymousReference]
    public let actionIDs: [PseudonymousReference]
    public let alternatives: [String]
    public let limitations: [String]

    public init(conclusion: ConsultationConclusion, summary: String, observations: [String] = [], hypotheses: [String] = [], unknowns: [EvidenceGap] = [], evidenceRefs: [PseudonymousReference] = [], actionIDs: [PseudonymousReference] = [], alternatives: [String] = [], limitations: [String] = []) {
        self.conclusion = conclusion
        self.summary = summary
        self.observations = observations
        self.hypotheses = hypotheses
        self.unknowns = unknowns
        self.evidenceRefs = evidenceRefs
        self.actionIDs = actionIDs
        self.alternatives = alternatives
        self.limitations = limitations
    }
}

public enum QuestionOptionKind: String, Codable, CaseIterable, Sendable { case option, unknown }

public struct QuestionOption: Codable, Equatable, Sendable {
    public let id: PseudonymousReference
    public let text: String
    public let kind: QuestionOptionKind

    public init(id: PseudonymousReference, text: String, kind: QuestionOptionKind = .option) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}

public struct ConsultationQuestion: Codable, Equatable, Sendable {
    public let id: PseudonymousReference
    public let text: String
    public let options: [QuestionOption]
    public let allowFreeText: Bool
    public let allowUnknown: Bool
    public let rationale: String
    public let nextState: ConsultationDisposition

    public init(id: PseudonymousReference, text: String, options: [QuestionOption] = [], allowFreeText: Bool = false, allowUnknown: Bool = false, rationale: String, nextState: ConsultationDisposition = .awaitingAnswer) {
        self.id = id
        self.text = text
        self.options = options
        self.allowFreeText = allowFreeText
        self.allowUnknown = allowUnknown
        self.rationale = rationale
        self.nextState = nextState
    }
}

public enum ProposalRisk: String, Codable, CaseIterable, Sendable { case none, low, medium, high }

public struct ToolProposal: Codable, Equatable, Sendable {
    public let id: PseudonymousReference
    public let tool: ConsultationTool
    public let arguments: [ToolArgument]
    public let objective: String
    public let evidenceRefs: [PseudonymousReference]
    public let risk: ProposalRisk
    public let expiresAt: Date
    public let revision: Int

    public init(id: PseudonymousReference, tool: ConsultationTool, arguments: [ToolArgument] = [], objective: String, evidenceRefs: [PseudonymousReference] = [], risk: ProposalRisk, expiresAt: Date, revision: Int) {
        self.id = id
        self.tool = tool
        self.arguments = arguments
        self.objective = objective
        self.evidenceRefs = evidenceRefs
        self.risk = risk
        self.expiresAt = expiresAt
        self.revision = revision
    }
}

public enum ConsultationActionKind: String, Codable, CaseIterable, Sendable { case inspect, adjust, contactSupport = "contact_support", retest }

public struct ActionProposal: Codable, Equatable, Sendable {
    public let id: PseudonymousReference
    public let kind: ConsultationActionKind
    public let title: String
    public let steps: [String]
    public let evidenceRefs: [PseudonymousReference]
    public let limitations: [String]
    public let expiresAt: Date?

    public init(id: PseudonymousReference, kind: ConsultationActionKind, title: String, steps: [String], evidenceRefs: [PseudonymousReference] = [], limitations: [String] = [], expiresAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.steps = steps
        self.evidenceRefs = evidenceRefs
        self.limitations = limitations
        self.expiresAt = expiresAt
    }
}

public enum ConsultationNext: Equatable, Sendable {
    case question(ConsultationQuestion)
    case toolProposal(ToolProposal)
    case actionProposal(ActionProposal)
    case none
}

extension ConsultationNext: Codable {
    private enum CodingKeys: String, CodingKey { case kind, question, toolProposal = "tool_proposal", actionProposal = "action_proposal" }
    private enum Kind: String, Codable { case question, toolProposal = "tool_proposal", actionProposal = "action_proposal", none }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .question: self = .question(try container.decode(ConsultationQuestion.self, forKey: .question))
        case .toolProposal: self = .toolProposal(try container.decode(ToolProposal.self, forKey: .toolProposal))
        case .actionProposal: self = .actionProposal(try container.decode(ActionProposal.self, forKey: .actionProposal))
        case .none: self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .question(let value): try container.encode(Kind.question, forKey: .kind); try container.encode(value, forKey: .question)
        case .toolProposal(let value): try container.encode(Kind.toolProposal, forKey: .kind); try container.encode(value, forKey: .toolProposal)
        case .actionProposal(let value): try container.encode(Kind.actionProposal, forKey: .kind); try container.encode(value, forKey: .actionProposal)
        case .none: try container.encode(Kind.none, forKey: .kind)
        }
    }
}

public enum ConsultationErrorCode: String, Codable, CaseIterable, Sendable {
    case invalidRequest = "invalid_request", revisionConflict = "revision_conflict", consentRequired = "consent_required"
    case unavailable, outOfScope = "out_of_scope", policyBlocked = "policy_blocked", expiredProposal = "expired_proposal"
}

public enum ConsultationFallback: String, Codable, CaseIterable, Sendable { case retry, refreshContext = "refresh_context", askQuestion = "ask_question", stop }

public struct ConsultationErrorPayload: Codable, Equatable, Sendable {
    public let code: ConsultationErrorCode
    public let message: String
    public let recoverable: Bool
    public let fallback: ConsultationFallback
    public let currentRevision: Int?

    public init(code: ConsultationErrorCode, message: String, recoverable: Bool, fallback: ConsultationFallback, currentRevision: Int? = nil) {
        self.code = code
        self.message = message
        self.recoverable = recoverable
        self.fallback = fallback
        self.currentRevision = currentRevision
    }
}

public struct ConsultationTurnResponse: Codable, Equatable, Sendable {
    public let intent: ConsultationIntent
    public let disposition: ConsultationDisposition
    public let claims: [ConsultationClaim]
    public let limitations: [String]
    public let assessment: ConsultationAssessment?
    public let next: ConsultationNext

    public init(intent: ConsultationIntent, disposition: ConsultationDisposition, claims: [ConsultationClaim] = [], limitations: [String] = [], assessment: ConsultationAssessment? = nil, next: ConsultationNext) {
        self.intent = intent
        self.disposition = disposition
        self.claims = claims
        self.limitations = limitations
        self.assessment = assessment
        self.next = next
    }
}

public enum ConsultationResponseOutcome: Equatable, Sendable {
    case turn(ConsultationTurnResponse)
    case error(ConsultationErrorPayload)
}

extension ConsultationResponseOutcome: Codable {
    private enum CodingKeys: String, CodingKey { case kind, turn, error }
    private enum Kind: String, Codable { case turn, error }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .turn: self = .turn(try container.decode(ConsultationTurnResponse.self, forKey: .turn))
        case .error: self = .error(try container.decode(ConsultationErrorPayload.self, forKey: .error))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .turn(let value): try container.encode(Kind.turn, forKey: .kind); try container.encode(value, forKey: .turn)
        case .error(let value): try container.encode(Kind.error, forKey: .kind); try container.encode(value, forKey: .error)
        }
    }
}

public struct ConsultationResponse: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestID: PseudonymousReference
    public let transportSessionID: PseudonymousReference
    public let turnID: PseudonymousReference
    public let revision: Int
    public let outcome: ConsultationResponseOutcome

    public init(schemaVersion: String = AssistConsultationContract.schemaVersion, requestID: PseudonymousReference, transportSessionID: PseudonymousReference, turnID: PseudonymousReference, revision: Int, outcome: ConsultationResponseOutcome) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.transportSessionID = transportSessionID
        self.turnID = turnID
        self.revision = revision
        self.outcome = outcome
    }

    public func validate(for payload: ConsultationPayload, at now: Date) throws {
        guard schemaVersion == AssistConsultationContract.schemaVersion,
              requestID == payload.requestID,
              transportSessionID == payload.transportSessionID,
              turnID == payload.turnID,
              revision == payload.expectedRevision else {
            throw ContractError.invalid("Resposta não corresponde à consulta local.")
        }
        let knownRefs = Set(payload.contextSnapshot.facts.map(\.id)
            + payload.contextSnapshot.measurements.flatMap { $0.values.map(\.id) }
            + payload.contextSnapshot.sources.map(\.id)
            + payload.contextSnapshot.entities.map(\.id))
        switch outcome {
        case .error(let error):
            guard !error.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ContractError.invalid("Erro sem mensagem.") }
            if error.code == .revisionConflict, error.currentRevision == nil { throw ContractError.invalid("Conflito sem revisão atual.") }
            if !error.recoverable, error.fallback != .stop { throw ContractError.invalid("Erro não recuperável precisa encerrar o fluxo.") }
        case .turn(let turn):
            try turn.validate(for: payload, knownRefs: knownRefs, at: now)
        }
    }
}

private extension ConsultationTurnResponse {
    func validate(for payload: ConsultationPayload, knownRefs: Set<PseudonymousReference>, at now: Date) throws {
        guard intent == payload.contextSnapshot.intent else { throw ContractError.invalid("Intent da resposta diverge do contexto.") }
        guard Set(claims.map(\.id)).count == claims.count else { throw ContractError.invalid("Claims duplicadas.") }
        for claim in claims {
            guard !claim.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(claim.evidenceRefs).isSubset(of: knownRefs) else { throw ContractError.invalid("Claim sem evidência válida.") }
        }
        if let assessment {
            guard !assessment.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(assessment.evidenceRefs).isSubset(of: knownRefs),
                  Set(assessment.unknowns.flatMap(\.evidenceRefs)).isSubset(of: knownRefs) else { throw ContractError.invalid("Assessment inválido.") }
        }
        switch (disposition, next) {
        case (.awaitingAnswer, .question(let question)):
            guard !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !question.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(question.options.map(\.id)).count == question.options.count,
                  question.nextState == .awaitingAnswer,
                  question.options.filter({ $0.kind == .unknown }).count == (question.allowUnknown ? 1 : 0) else { throw ContractError.invalid("Pergunta inválida.") }
        case (.awaitingApproval, .toolProposal(let proposal)):
            guard proposal.revision == payload.expectedRevision,
                  proposal.expiresAt > now,
                  Set(proposal.arguments.map(\.name)).count == proposal.arguments.count,
                  Set(proposal.evidenceRefs).isSubset(of: knownRefs),
                  payload.contextSnapshot.capabilities.contains(where: { $0.tool == proposal.tool && $0.availability == .available }) else { throw ContractError.invalid("Proposta de ferramenta inválida.") }
        case (.answered, .none), (.inconclusive, .none), (.outOfScope, .none), (.unavailable, .none):
            guard assessment != nil else { throw ContractError.invalid("Resposta conclusiva sem assessment.") }
        case (.answered, .actionProposal(let proposal)), (.inconclusive, .actionProposal(let proposal)), (.outOfScope, .actionProposal(let proposal)), (.unavailable, .actionProposal(let proposal)):
            guard !proposal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !proposal.steps.isEmpty,
                  Set(proposal.evidenceRefs).isSubset(of: knownRefs),
                  proposal.expiresAt.map({ $0 > now }) ?? true,
                  assessment != nil else { throw ContractError.invalid("Ação proposta inválida.") }
        default:
            throw ContractError.invalid("Disposição e próximo passo incompatíveis.")
        }
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
            platform: platform(for: candidate.measurement.devicePlatform),
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

    private static func platform(for value: String?) -> MeasurementPlatform {
        switch value?.lowercased() {
        case "ios", "iphone": return .iOS
        case "ipados", "ipad": return .iPadOS
        case "macos", "mac": return .macOS
        default: return .unknown
        }
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
            var matches = 0
            for option in options {
                do {
                    try validate(value, against: option, root: root, path: path)
                    matches += 1
                } catch {
                    continue
                }
            }
            guard matches == 1 else { throw ContractError.invalid("União inválida em \(path).") }
            return
        }
        if let options = schema["anyOf"] as? [Any] {
            var matches = false
            for option in options {
                if (try? validate(value, against: option, root: root, path: path)) != nil {
                    matches = true
                    break
                }
            }
            guard matches else {
                throw ContractError.invalid("União incompatível em \(path).")
            }
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
