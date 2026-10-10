import Foundation

/// Entrada já obtida localmente para uma consulta. Este tipo não conhece
/// armazenamento, URLSession ou serviços do app: a camada chamadora decide o
/// que é elegível e entrega apenas referências pseudônimas ao contrato V4.
public struct ContextSnapshotAssemblyRequest: Sendable {
    public let snapshotID: PseudonymousReference
    public let revision: Int
    public let intent: ConsultationIntent
    public let consent: ConsentReceipt
    public let selectedProfileRef: PseudonymousReference?
    public let sources: [ContextSource]
    public let entities: [ConsultationEntity]
    public let evidence: [EvidenceCandidate]
    public let hypotheses: [ConsultationHypothesis]
    public let measurements: [MeasurementCandidate]
    public let capabilities: [ConsultationCapability]

    public init(
        snapshotID: PseudonymousReference,
        revision: Int,
        intent: ConsultationIntent,
        consent: ConsentReceipt,
        selectedProfileRef: PseudonymousReference? = nil,
        sources: [ContextSource] = [],
        entities: [ConsultationEntity] = [],
        evidence: [EvidenceCandidate] = [],
        hypotheses: [ConsultationHypothesis] = [],
        measurements: [MeasurementCandidate] = [],
        capabilities: [ConsultationCapability] = []
    ) {
        self.snapshotID = snapshotID
        self.revision = revision
        self.intent = intent
        self.consent = consent
        self.selectedProfileRef = selectedProfileRef
        self.sources = sources
        self.entities = entities
        self.evidence = evidence
        self.hypotheses = hypotheses
        self.measurements = measurements
        self.capabilities = capabilities
    }
}

/// Monta um snapshot mínimo e validado. Sem consentimento de contexto, toda a
/// entrada sensível é descartada antes de o snapshot existir; uma eventual
/// pergunta só poderá seguir depois do fluxo explícito de consentimento.
public enum ContextSnapshotAssembler {
    public static func assemble(_ request: ContextSnapshotAssemblyRequest, at now: Date) throws -> ContextSnapshot {
        guard request.revision > 0 else {
            throw ContractError.invalid("Snapshot exige revisão positiva.")
        }

        guard request.consent.state == .granted, request.consent.scope.permitsContext else {
            let redacted = ContextSnapshot(
                snapshotID: request.snapshotID,
                revision: request.revision,
                intent: request.intent,
                consent: request.consent,
                createdAt: now
            )
            try redacted.validate(at: now)
            return redacted
        }

        var facts: [EvidenceFact] = []
        var absences: [KnownAbsence] = []
        for candidate in request.evidence {
            guard candidate.fact.consentScope.permitsContext else {
                absences.append(absence(for: candidate.fact, reason: .consentNotGranted, at: now))
                continue
            }
            switch EvidenceProjector.project(candidate, at: now) {
            case .evidence(let fact): facts.append(fact)
            case .absence(let absence): absences.append(absence)
            }
        }

        var projectedMeasurements: [ConsultationMeasurement] = []
        for candidate in request.measurements {
            switch MeasurementProjector.project(candidate, at: now) {
            case .measurement(let measurement): projectedMeasurements.append(measurement)
            case .absence(let absence): absences.append(absence)
            }
        }

        let snapshot = ContextSnapshot(
            snapshotID: request.snapshotID,
            revision: request.revision,
            intent: request.intent,
            consent: request.consent,
            selectedProfileRef: request.selectedProfileRef,
            createdAt: now,
            sources: request.sources,
            entities: request.entities,
            facts: facts,
            hypotheses: request.hypotheses,
            absences: absences,
            measurements: projectedMeasurements,
            capabilities: request.capabilities
        )
        try snapshot.validate(at: now)
        return snapshot
    }

    private static func absence(for fact: EvidenceFact, reason: AbsenceReason, at now: Date) -> KnownAbsence {
        KnownAbsence(
            id: try! PseudonymousReference("absence-\(UUID().uuidString.lowercased())"),
            subjectRef: fact.subjectRef,
            property: fact.property,
            reason: reason,
            observedAt: now,
            sourceRefs: fact.sourceRefs
        )
    }
}

/// Cache efêmero de uma sessão. Ele não grava em disco nem sincroniza dados;
/// snapshots vencidos são removidos no primeiro acesso e não podem ser usados
/// para montar uma nova consulta.
public actor ExpiringContextSnapshotCache {
    private struct Entry: Sendable {
        let snapshot: ContextSnapshot
        let expiresAt: Date
    }

    private var entries: [PseudonymousReference: Entry] = [:]

    public init() {}

    public func store(_ snapshot: ContextSnapshot, expiresAt: Date, at now: Date) throws {
        guard expiresAt > now else {
            throw ContractError.invalid("Cache de contexto exige expiração futura.")
        }
        try snapshot.validate(at: now)
        entries[snapshot.snapshotID] = Entry(snapshot: snapshot, expiresAt: expiresAt)
    }

    public func snapshot(for reference: PseudonymousReference, at now: Date) -> ContextSnapshot? {
        guard let entry = entries[reference] else { return nil }
        guard entry.expiresAt > now else {
            entries[reference] = nil
            return nil
        }
        return entry.snapshot
    }

    public func discard(_ reference: PseudonymousReference) {
        entries[reference] = nil
    }
}
