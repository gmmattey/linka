import XCTest
import AssistConsultation
import MeasurementHistory
import NetworkCore
import NetworkInventory
import NetworkProfiles
@testable import LinkaApp

@MainActor
final class AssistV4LocalContextAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_623_200)

    func testQuestionOnlyConsentDoesNotReadLocalContext() async throws {
        let reader = FakeContextReader()
        let history = InMemoryMeasurementHistoryRepository()
        let adapter = AssistV4LocalContextAdapter(
            household: reader,
            history: history,
            eligibility: FakeEligibilityReader()
        )

        let snapshot = try await adapter.assemble(
            snapshotID: ref("snapshot-question-only"),
            revision: 1,
            intent: .openQuestion,
            consent: consent(scope: .question),
            selection: AssistV4ContextSelection(profileID: UUID()),
            at: now
        )

        XCTAssertNil(snapshot.selectedProfileRef)
        XCTAssertTrue(snapshot.sources.isEmpty)
        XCTAssertTrue(snapshot.entities.isEmpty)
        XCTAssertTrue(snapshot.facts.isEmpty)
        XCTAssertTrue(snapshot.measurements.isEmpty)
        let readCount = await reader.readCount
        XCTAssertEqual(readCount, 0)
    }

    func testPlanProjectionUsesOnlyTechnicalAllowlist() async throws {
        let profile = HomeNetworkProfile(displayName: "Casa da Marina")
        let plan = NetworkServicePlan(
            ispName: "Provedor Particular",
            planName: "Fibra VIP",
            nominalDownloadMbps: 500,
            nominalUploadMbps: 250,
            technology: .fiber,
            monthlyCostCents: 12_345,
            currencyCode: "BRL",
            notes: "Não pode sair do aparelho"
        )
        let active = HomeNetworkProfile(
            id: profile.id,
            displayName: profile.displayName,
            activePlanID: plan.id,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
        let adapter = AssistV4LocalContextAdapter(
            household: FakeContextReader(profile: active, plans: [plan.id: plan]),
            history: InMemoryMeasurementHistoryRepository(),
            eligibility: FakeEligibilityReader()
        )

        let snapshot = try await adapter.assemble(
            snapshotID: ref("snapshot-plan"),
            revision: 1,
            intent: .planValue,
            consent: consent(),
            selection: AssistV4ContextSelection(profileID: active.id, planID: plan.id),
            at: now
        )

        XCTAssertEqual(Set(snapshot.facts.map(\.property)), ["nominal_download_mbps", "nominal_upload_mbps", "access_technology"])
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        ["Casa da Marina", "Provedor Particular", "Fibra VIP", "12345", "Não pode sair"].forEach {
            XCTAssertFalse(encoded.contains($0), "Não deve vazar \($0)")
        }
    }

    func testDeviceProjectionExcludesNicknameLocationAndSpecificationSources() async throws {
        let profile = HomeNetworkProfile(displayName: "Minha casa")
        let active = HomeNetworkProfile(id: profile.id, displayName: profile.displayName, createdAt: profile.createdAt, updatedAt: profile.updatedAt)
        let specification = DeviceSpecificationSnapshot(
            identity: DeviceIdentity(brand: "TP-Link", model: "AX10"),
            status: .complete,
            attributes: [SpecificationAttribute(key: "serial", value: "secret-serial", evidenceIDs: ["official"])],
            sources: [SpecificationSource(id: "official", url: URL(string: "https://example.com/private")!, title: "Source", matchedIdentity: DeviceIdentity(brand: "TP-Link", model: "AX10"))]
        )
        let device = RegisteredNetworkDevice(
            kind: .router,
            identity: DeviceIdentity(brand: "TP-Link", model: "AX10"),
            nickname: "Roteador da sala",
            installation: DeviceInstallation(role: .mainRouter, fiberDirectConnected: .no, environmentID: UUID(), locationLabel: "Sala de estar"),
            specifications: specification
        )
        let adapter = AssistV4LocalContextAdapter(
            household: FakeContextReader(profile: active, devices: [device.id: device]),
            history: InMemoryMeasurementHistoryRepository(),
            eligibility: FakeEligibilityReader()
        )

        let snapshot = try await adapter.assemble(
            snapshotID: ref("snapshot-device"),
            revision: 1,
            intent: .routerAdequacy,
            consent: consent(),
            selection: AssistV4ContextSelection(profileID: active.id, deviceIDs: [device.id]),
            at: now
        )

        XCTAssertTrue(snapshot.facts.contains(where: { $0.property == "device_model" }))
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        ["Roteador da sala", "Sala de estar", "secret-serial", "example.com"].forEach {
            XCTAssertFalse(encoded.contains($0), "Não deve vazar \($0)")
        }
    }

    func testMeasurementRequiresAssignmentAndMatchingEligibilitySignals() async throws {
        let profile = HomeNetworkProfile(displayName: "Minha casa")
        let active = HomeNetworkProfile(id: profile.id, displayName: profile.displayName, createdAt: profile.createdAt, updatedAt: profile.updatedAt)
        let environment = NetworkEnvironment(name: "Sala")!
        let measurement = NetworkMeasurement(
            measuredAt: now.addingTimeInterval(-20),
            outcome: .complete,
            downloadMbps: 480,
            uploadMbps: 120,
            latencyMs: 12,
            connectionKind: .wifi,
            networkIdentifier: "rede-privada",
            serverIdentifier: "server-privado"
        )
        let history = InMemoryMeasurementHistoryRepository()
        try await history.save(measurement)
        let eligibility = AssistV4MeasurementEligibility(
            measurementID: measurement.id,
            measuredAt: measurement.measuredAt,
            validUntil: now.addingTimeInterval(60),
            isExpensive: false,
            isPersonalHotspot: false
        )
        let reader = FakeContextReader(
            profile: active,
            environments: [environment.id: environment],
            assignments: [measurement.id: EnvironmentMeasurementAssignment(measurementID: measurement.id, environmentID: environment.id)]
        )
        let adapter = AssistV4LocalContextAdapter(
            household: reader,
            history: history,
            eligibility: FakeEligibilityReader(values: [measurement.id: eligibility])
        )

        let snapshot = try await adapter.assemble(
            snapshotID: ref("snapshot-measurement"),
            revision: 1,
            intent: .slowConnection,
            consent: consent(),
            selection: AssistV4ContextSelection(profileID: active.id, measurementIDs: [measurement.id]),
            at: now
        )

        XCTAssertEqual(snapshot.measurements.count, 1)
        XCTAssertEqual(Set(snapshot.measurements[0].values.map(\.property)), ["download_mbps", "upload_mbps"])
        XCTAssertNotEqual(snapshot.measurements[0].id, snapshot.sources.first(where: { $0.kind == .systemMeasurement })?.id)
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("rede-privada"))
        XCTAssertFalse(encoded.contains("server-privado"))
    }

    func testExpensiveMeasurementIsAnExplicitIneligibleAbsence() async throws {
        let profile = HomeNetworkProfile(displayName: "Minha casa")
        let active = HomeNetworkProfile(id: profile.id, displayName: profile.displayName, createdAt: profile.createdAt, updatedAt: profile.updatedAt)
        let environment = NetworkEnvironment(name: "Sala")!
        let measurement = NetworkMeasurement(
            measuredAt: now.addingTimeInterval(-20),
            outcome: .complete,
            downloadMbps: 480,
            uploadMbps: 120,
            latencyMs: 12,
            connectionKind: .wifi
        )
        let history = InMemoryMeasurementHistoryRepository()
        try await history.save(measurement)
        let eligibility = AssistV4MeasurementEligibility(
            measurementID: measurement.id,
            measuredAt: measurement.measuredAt,
            validUntil: now.addingTimeInterval(60),
            isExpensive: true,
            isPersonalHotspot: false
        )
        let adapter = AssistV4LocalContextAdapter(
            household: FakeContextReader(
                profile: active,
                environments: [environment.id: environment],
                assignments: [measurement.id: EnvironmentMeasurementAssignment(measurementID: measurement.id, environmentID: environment.id)]
            ),
            history: history,
            eligibility: FakeEligibilityReader(values: [measurement.id: eligibility])
        )

        let snapshot = try await adapter.assemble(
            snapshotID: ref("snapshot-expensive"),
            revision: 1,
            intent: .slowConnection,
            consent: consent(),
            selection: AssistV4ContextSelection(profileID: active.id, measurementIDs: [measurement.id]),
            at: now
        )

        XCTAssertTrue(snapshot.measurements.isEmpty)
        XCTAssertEqual(snapshot.absences.first?.reason, .ineligibleMeasurement)
    }

    func testMeasurementWithoutEligibilitySignalsIsOmittedInsteadOfDefaultingToFalse() async throws {
        let profile = HomeNetworkProfile(displayName: "Minha casa")
        let active = HomeNetworkProfile(id: profile.id, displayName: profile.displayName, createdAt: profile.createdAt, updatedAt: profile.updatedAt)
        let environment = NetworkEnvironment(name: "Sala")!
        let measurement = NetworkMeasurement(
            measuredAt: now.addingTimeInterval(-20),
            outcome: .complete,
            downloadMbps: 480,
            uploadMbps: 120,
            latencyMs: 12,
            connectionKind: .wifi
        )
        let history = InMemoryMeasurementHistoryRepository()
        try await history.save(measurement)
        let adapter = AssistV4LocalContextAdapter(
            household: FakeContextReader(
                profile: active,
                environments: [environment.id: environment],
                assignments: [measurement.id: EnvironmentMeasurementAssignment(measurementID: measurement.id, environmentID: environment.id)]
            ),
            history: history,
            eligibility: FakeEligibilityReader()
        )

        let snapshot = try await adapter.assemble(
            snapshotID: ref("snapshot-no-eligibility"),
            revision: 1,
            intent: .slowConnection,
            consent: consent(),
            selection: AssistV4ContextSelection(profileID: active.id, measurementIDs: [measurement.id]),
            at: now
        )

        XCTAssertTrue(snapshot.measurements.isEmpty)
        XCTAssertTrue(snapshot.absences.isEmpty)
        XCTAssertEqual(snapshot.capabilities.first(where: { $0.tool == .selectMeasurementEvidence })?.availability, .unavailable)
    }

    private func ref(_ value: String) -> PseudonymousReference { try! PseudonymousReference(value) }

    private func consent(scope: ConsentScope = .questionAndContext) -> ConsentReceipt {
        ConsentReceipt(ref: ref("consent-test"), state: .granted, scope: scope, recordedAt: now)
    }
}

private actor FakeContextReader: AssistV4LocalContextReading {
    let profile: HomeNetworkProfile?
    let plans: [UUID: NetworkServicePlan]
    let devices: [UUID: RegisteredNetworkDevice]
    let connections: [UUID: DeviceConnection]
    let environments: [UUID: NetworkEnvironment]
    let assignments: [UUID: EnvironmentMeasurementAssignment]
    private(set) var readCount = 0

    init(
        profile: HomeNetworkProfile? = nil,
        plans: [UUID: NetworkServicePlan] = [:],
        devices: [UUID: RegisteredNetworkDevice] = [:],
        connections: [UUID: DeviceConnection] = [:],
        environments: [UUID: NetworkEnvironment] = [:],
        assignments: [UUID: EnvironmentMeasurementAssignment] = [:]
    ) {
        self.profile = profile
        self.plans = plans
        self.devices = devices
        self.connections = connections
        self.environments = environments
        self.assignments = assignments
    }

    func homeProfile() async throws -> HomeNetworkProfile? { readCount += 1; return profile }
    func plan(id: UUID) async throws -> NetworkServicePlan? { readCount += 1; return plans[id] }
    func device(id: UUID) async throws -> RegisteredNetworkDevice? { readCount += 1; return devices[id] }
    func connection(id: UUID) async throws -> DeviceConnection? { readCount += 1; return connections[id] }
    func environment(id: UUID) async throws -> NetworkEnvironment? { readCount += 1; return environments[id] }
    func assignment(for measurementID: UUID) async throws -> EnvironmentMeasurementAssignment? { readCount += 1; return assignments[measurementID] }
}

private actor FakeEligibilityReader: AssistV4MeasurementEligibilityReading {
    let values: [UUID: AssistV4MeasurementEligibility]
    init(values: [UUID: AssistV4MeasurementEligibility] = [:]) { self.values = values }
    func eligibility(for measurement: NetworkMeasurement) async throws -> AssistV4MeasurementEligibility? { values[measurement.id] }
}
