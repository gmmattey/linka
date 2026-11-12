#if os(iOS)
import Foundation
import AssistConsultation
import LinkaModules
import MeasurementHistory
import NetworkCore
import NetworkInventory
import NetworkProfiles

/// Leitura local mínima que a consulta V4 pode usar. A composição de produção
/// continua no `HouseholdRepository`; este protocolo só permite testar a
/// projeção sem abrir arquivos reais ou trazer dados não selecionados.
protocol AssistV4LocalContextReading: Sendable {
    func homeProfile() async throws -> HomeNetworkProfile?
    func plan(id: UUID) async throws -> NetworkServicePlan?
    func device(id: UUID) async throws -> RegisteredNetworkDevice?
    func connection(id: UUID) async throws -> DeviceConnection?
    func environment(id: UUID) async throws -> NetworkEnvironment?
    func assignment(for measurementID: UUID) async throws -> EnvironmentMeasurementAssignment?
}

extension HouseholdRepository: AssistV4LocalContextReading {}

/// Sinais de elegibilidade devem ser capturados para a própria medição. Eles
/// não fazem parte do histórico e, portanto, nunca recebem `false` por padrão.
struct AssistV4MeasurementEligibility: Sendable, Equatable {
    let measurementID: UUID
    let measuredAt: Date
    let validUntil: Date
    let isExpensive: Bool
    let isPersonalHotspot: Bool
}

protocol AssistV4MeasurementEligibilityReading: Sendable {
    func eligibility(for measurement: NetworkMeasurement) async throws -> AssistV4MeasurementEligibility?
}

/// A pessoa escolhe explicitamente quais referências locais podem compor a
/// consulta. UUIDs só existem dentro do app; o adapter os substitui por refs
/// pseudônimas por snapshot antes de montar o contrato.
struct AssistV4ContextSelection: Sendable, Equatable {
    var profileID: UUID?
    var planID: UUID?
    var deviceIDs: Set<UUID>
    var connectionIDs: Set<UUID>
    var measurementIDs: Set<UUID>

    init(
        profileID: UUID? = nil,
        planID: UUID? = nil,
        deviceIDs: Set<UUID> = [],
        connectionIDs: Set<UUID> = [],
        measurementIDs: Set<UUID> = []
    ) {
        self.profileID = profileID
        self.planID = planID
        self.deviceIDs = deviceIDs
        self.connectionIDs = connectionIDs
        self.measurementIDs = measurementIDs
    }
}

/// Projeta a allowlist da Minha Rede para o contrato `assist.consultation/1.0`.
/// Não cria transporte, não persiste snapshots e não usa identificadores ou
/// labels locais como dados do contrato.
struct AssistV4LocalContextAdapter: Sendable {
    private let household: any AssistV4LocalContextReading
    private let history: any MeasurementHistoryRepository
    private let eligibility: any AssistV4MeasurementEligibilityReading

    init(
        household: any AssistV4LocalContextReading = LinkaHousehold.repository,
        history: any MeasurementHistoryRepository = LinkaMeasurementHistory.makeRepository(),
        eligibility: any AssistV4MeasurementEligibilityReading
    ) {
        self.household = household
        self.history = history
        self.eligibility = eligibility
    }

    func assemble(
        snapshotID: PseudonymousReference,
        revision: Int,
        intent: ConsultationIntent,
        consent: ConsentReceipt,
        selection: AssistV4ContextSelection,
        at now: Date = Date()
    ) async throws -> ContextSnapshot {
        // Consentimento de pergunta não é consentimento para contexto. Não
        // lemos os stores antes deste gate para evitar montar informação que
        // já deveria sair redigida.
        guard consent.state == .granted, consent.scope == .questionAndContext else {
            return try ContextSnapshotAssembler.assemble(
                ContextSnapshotAssemblyRequest(
                    snapshotID: snapshotID,
                    revision: revision,
                    intent: intent,
                    consent: consent
                ),
                at: now
            )
        }

        var sources: [ContextSource] = []
        var entities: [ConsultationEntity] = []
        var evidence: [EvidenceCandidate] = []
        var measurements: [MeasurementCandidate] = []
        var deviceRefs: [UUID: PseudonymousReference] = [:]

        let inventorySource = reference("source-local-inventory")
        var usesInventorySource = false
        func includeInventorySource() {
            guard !usesInventorySource else { return }
            sources.append(ContextSource(id: inventorySource, kind: .userDeclaration, retrievedAt: now))
            usesInventorySource = true
        }

        let storedProfile = try await household.homeProfile()
        let profile = storedProfile.flatMap { profile in
            selection.profileID == profile.id ? profile : nil
        }
        let profileRef = profile.map { _ in reference("profile-1") }
        if let profileRef {
            includeInventorySource()
            entities.append(ConsultationEntity(id: profileRef, kind: .profile, sourceRefs: [inventorySource]))
        }

        if intent == .planValue,
           let profile,
           let selectedPlanID = selection.planID,
           profile.activePlanID == selectedPlanID,
           let plan = try await household.plan(id: selectedPlanID) {
            includeInventorySource()
            let planRef = reference("plan-1")
            entities.append(ConsultationEntity(id: planRef, kind: .plan, sourceRefs: [inventorySource]))
            appendPlanFacts(plan, subjectRef: planRef, sourceRef: inventorySource, consent: consent, now: now, to: &evidence)
        }

        if intent == .routerAdequacy || intent == .meshNeed {
            for (index, id) in selection.deviceIDs.sorted(by: uuidOrder).enumerated() {
                guard let device = try await household.device(id: id) else { continue }
                includeInventorySource()
                let deviceRef = reference("device-\(index + 1)")
                deviceRefs[id] = deviceRef
                entities.append(ConsultationEntity(id: deviceRef, kind: .device, sourceRefs: [inventorySource]))
                appendDeviceFacts(device, subjectRef: deviceRef, sourceRef: inventorySource, consent: consent, now: now, to: &evidence)
            }

            for (index, id) in selection.connectionIDs.sorted(by: uuidOrder).enumerated() {
                guard let connection = try await household.connection(id: id),
                      let first = deviceRefs[connection.endpointADeviceID],
                      let second = deviceRefs[connection.endpointBDeviceID] else { continue }
                includeInventorySource()
                let connectionRef = reference("connection-\(index + 1)")
                entities.append(ConsultationEntity(id: connectionRef, kind: .connection, sourceRefs: [inventorySource]))
                evidence.append(EvidenceCandidate(fact: EvidenceFact(
                    id: reference("evidence-connection-\(index + 1)"),
                    subjectRef: connectionRef,
                    property: "link_medium",
                    value: .text(connection.medium.rawValue),
                    sourceType: .userDeclared,
                    sourceRefs: [inventorySource],
                    observedAt: bounded(connection.updatedAt, by: now),
                    scope: EvidenceScope(appliesToRefs: [connectionRef, first, second]),
                    consentScope: consent.scope
                )))
            }
        }

        if let profileRef {
            for (index, id) in selection.measurementIDs.sorted(by: uuidOrder).enumerated() {
                guard let measurement = try await history.measurement(id: id) else { continue }
                let sourceRef = reference("source-measurement-\(index + 1)")
                sources.append(ContextSource(id: sourceRef, kind: .systemMeasurement, retrievedAt: now))

                let assignment = try await household.assignment(for: measurement.id)
                let hasKnownEnvironment: Bool
                if let assignment {
                    hasKnownEnvironment = try await household.environment(id: assignment.environmentID) != nil
                } else {
                    hasKnownEnvironment = false
                }
                let observedEligibility = try await self.eligibility.eligibility(for: measurement)
                let verifiedEligibility = observedEligibility.flatMap { candidate in
                    candidate.measurementID == measurement.id && candidate.measuredAt == measurement.measuredAt ? candidate : nil
                }
                // O histórico não carrega esses sinais; sem uma leitura que
                // pertence à medição, não há candidato para o projetor e não
                // há como assumir rede barata ou sem hotspot.
                guard let verifiedEligibility else { continue }
                let measurementRef = reference("measurement-\(index + 1)")
                measurements.append(MeasurementCandidate(
                    reference: measurementRef,
                    sourceRef: sourceRef,
                    measurement: measurement,
                    profileRef: hasKnownEnvironment ? profileRef : nil,
                    validUntil: verifiedEligibility.validUntil,
                    isExpensive: verifiedEligibility.isExpensive,
                    isPersonalHotspot: verifiedEligibility.isPersonalHotspot,
                    consent: consent
                ))
            }
        }

        let measurementCapability: ConsultationCapability
        if measurements.isEmpty {
            measurementCapability = ConsultationCapability(
                tool: .selectMeasurementEvidence,
                availability: .unavailable,
                limitation: "Não há medição selecionada com associação e elegibilidade verificáveis."
            )
        } else {
            measurementCapability = ConsultationCapability(tool: .selectMeasurementEvidence, availability: .available)
        }

        return try ContextSnapshotAssembler.assemble(
            ContextSnapshotAssemblyRequest(
                snapshotID: snapshotID,
                revision: revision,
                intent: intent,
                consent: consent,
                selectedProfileRef: profileRef,
                sources: sources,
                entities: entities,
                evidence: evidence,
                measurements: measurements,
                capabilities: [
                    ConsultationCapability(tool: .readNetworkContext, availability: .available),
                    measurementCapability
                ]
            ),
            at: now
        )
    }

    private func appendPlanFacts(
        _ plan: NetworkServicePlan,
        subjectRef: PseudonymousReference,
        sourceRef: PseudonymousReference,
        consent: ConsentReceipt,
        now: Date,
        to evidence: inout [EvidenceCandidate]
    ) {
        if let value = plan.nominalDownloadMbps, value > 0 {
            appendFact("nominal_download_mbps", value: .number(value), subjectRef: subjectRef, sourceRef: sourceRef, consent: consent, observedAt: bounded(plan.updatedAt, by: now), to: &evidence)
        }
        if let value = plan.nominalUploadMbps, value > 0 {
            appendFact("nominal_upload_mbps", value: .number(value), subjectRef: subjectRef, sourceRef: sourceRef, consent: consent, observedAt: bounded(plan.updatedAt, by: now), to: &evidence)
        }
        if plan.technology != .unknown {
            appendFact("access_technology", value: .text(plan.technology.rawValue), subjectRef: subjectRef, sourceRef: sourceRef, consent: consent, observedAt: bounded(plan.updatedAt, by: now), to: &evidence)
        }
    }

    private func appendDeviceFacts(
        _ device: RegisteredNetworkDevice,
        subjectRef: PseudonymousReference,
        sourceRef: PseudonymousReference,
        consent: ConsentReceipt,
        now: Date,
        to evidence: inout [EvidenceCandidate]
    ) {
        let observedAt = bounded(device.updatedAt, by: now)
        appendFact("device_kind", value: .text(device.kind.rawValue), subjectRef: subjectRef, sourceRef: sourceRef, consent: consent, observedAt: observedAt, to: &evidence)
        let brand = device.identity.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !brand.isEmpty {
            appendFact("device_brand", value: .text(brand), subjectRef: subjectRef, sourceRef: sourceRef, consent: consent, observedAt: observedAt, to: &evidence)
        }
        appendFact("device_model", value: .text(device.identity.model), subjectRef: subjectRef, sourceRef: sourceRef, consent: consent, observedAt: observedAt, to: &evidence)
        if device.installation.role != .unknown {
            appendFact("installed_role", value: .text(device.installation.role.rawValue), subjectRef: subjectRef, sourceRef: sourceRef, consent: consent, observedAt: observedAt, to: &evidence)
        }
        switch device.installation.fiberDirectConnected {
        case .yes:
            appendFact("fiber_direct_connected", value: .boolean(true), subjectRef: subjectRef, sourceRef: sourceRef, consent: consent, observedAt: observedAt, to: &evidence)
        case .no:
            appendFact("fiber_direct_connected", value: .boolean(false), subjectRef: subjectRef, sourceRef: sourceRef, consent: consent, observedAt: observedAt, to: &evidence)
        case .unknown:
            break
        }
    }

    private func appendFact(
        _ property: String,
        value: EvidenceValue,
        subjectRef: PseudonymousReference,
        sourceRef: PseudonymousReference,
        consent: ConsentReceipt,
        observedAt: Date,
        to evidence: inout [EvidenceCandidate]
    ) {
        evidence.append(EvidenceCandidate(fact: EvidenceFact(
            id: reference("evidence-\(UUID().uuidString.lowercased())"),
            subjectRef: subjectRef,
            property: property,
            value: value,
            sourceType: .userDeclared,
            sourceRefs: [sourceRef],
            observedAt: observedAt,
            consentScope: consent.scope
        )))
    }

    private func reference(_ value: String) -> PseudonymousReference {
        try! PseudonymousReference(value)
    }

    private func bounded(_ date: Date, by now: Date) -> Date { min(date, now) }

    private func uuidOrder(_ first: UUID, _ second: UUID) -> Bool {
        first.uuidString < second.uuidString
    }
}
#endif
