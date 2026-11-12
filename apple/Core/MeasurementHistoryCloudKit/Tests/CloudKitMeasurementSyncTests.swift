import Foundation
import XCTest
import CloudKit
import NetworkCore
import MeasurementHistory
@testable import MeasurementHistoryCloudKit

// MARK: - Dublês de teste (sem rede, sem conta iCloud, sem container real)

/// "Servidor" CloudKit falso, compartilhável entre múltiplas
/// `FakeMeasurementRemoteStore` para simular dois dispositivos diferentes
/// sincronizando com o mesmo container privado.
private actor FakeCloudKitServer {
    private var records: [CKRecord.ID: CKRecord] = [:]
    /// Log ordenado de mudanças (upload ou delete) para permitir fetch
    /// incremental por token — o token de teste é só o índice neste log,
    /// codificado como `Data` (o protocolo `MeasurementRemoteStore` não
    /// conhece `CKServerChangeToken`, só `Data` opaco).
    private var changeLog: [(id: CKRecord.ID, record: CKRecord?)] = []

    func record(for id: CKRecord.ID) -> CKRecord? {
        records[id]
    }

    func upload(_ recordsToSave: [CKRecord]) {
        for record in recordsToSave {
            records[record.recordID] = record
            changeLog.append((record.recordID, record))
        }
    }

    func delete(_ recordIDs: [CKRecord.ID]) {
        for id in recordIDs {
            records.removeValue(forKey: id)
            changeLog.append((id, nil))
        }
    }

    func changes(since token: Data?) -> MeasurementRemoteChangeSet {
        let startIndex = token
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(Int.init) ?? 0

        let entries = changeLog[min(startIndex, changeLog.count)...]

        // Colapsa o log em "estado final por recordID" no intervalo pedido,
        // igual ao que `CKFetchRecordZoneChangesOperation` devolveria.
        var changedByID: [CKRecord.ID: CKRecord] = [:]
        var deletedIDs: Set<CKRecord.ID> = []
        for entry in entries {
            if let record = entry.record {
                changedByID[entry.id] = record
                deletedIDs.remove(entry.id)
            } else {
                changedByID.removeValue(forKey: entry.id)
                deletedIDs.insert(entry.id)
            }
        }

        let newToken = "\(changeLog.count)".data(using: .utf8)

        return MeasurementRemoteChangeSet(
            changedRecords: Array(changedByID.values),
            deletedRecordIDs: Array(deletedIDs),
            newChangeToken: newToken
        )
    }
}

/// `MeasurementRemoteStore` falso: fala com `FakeCloudKitServer` em vez de
/// `CKContainer`, então roda em qualquer máquina/CI sem conta iCloud, sem
/// container provisionado e sem rede.
private actor FakeMeasurementRemoteStore: MeasurementRemoteStore {
    private let server: FakeCloudKitServer
    private var isAccountAvailable: Bool
    private let uploadDelayNanoseconds: UInt64
    /// Simula um erro transitório do CloudKit especificamente em
    /// `deleteRemote` mesmo com conta disponível — usado para testar que
    /// `applyRemote` não ressuscita uma medição já apagada localmente
    /// quando o push da exclusão falha mas o pull ainda encontra o record
    /// remoto (PR #93 R2, achado 1).
    private var shouldFailDelete: Bool = false

    init(
        server: FakeCloudKitServer,
        isAccountAvailable: Bool = true,
        uploadDelayNanoseconds: UInt64 = 0
    ) {
        self.server = server
        self.isAccountAvailable = isAccountAvailable
        self.uploadDelayNanoseconds = uploadDelayNanoseconds
    }

    func setAccountAvailable(_ value: Bool) {
        isAccountAvailable = value
    }

    func setShouldFailDelete(_ value: Bool) {
        shouldFailDelete = value
    }

    func accountStatus() async -> CKAccountStatus {
        isAccountAvailable ? .available : .noAccount
    }

    func ensureZoneExists() async throws {}

    func upload(_ records: [CKRecord]) async throws {
        if uploadDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: uploadDelayNanoseconds)
        }
        await server.upload(records)
    }

    func deleteRemote(recordIDs: [CKRecord.ID]) async throws {
        if shouldFailDelete {
            struct SimulatedTransientCloudKitError: Error {}
            throw SimulatedTransientCloudKitError()
        }
        await server.delete(recordIDs)
    }

    func fetchChanges(since token: Data?) async throws -> MeasurementRemoteChangeSet {
        await server.changes(since: token)
    }
}

// MARK: - Testes

final class CloudKitMeasurementSyncTests: XCTestCase {

    // MARK: Primeiro sync

    func testFirstSyncPushesNewLocalMeasurementToRemote() async throws {
        let server = FakeCloudKitServer()
        let local = InMemoryMeasurementHistoryRepository()
        let remote = FakeMeasurementRemoteStore(server: server)
        let sut = SyncingMeasurementHistoryRepository(
            local: local,
            remote: remote,
            tokenStore: InMemoryChangeTokenStore()
        )
        await sut.waitForBackgroundSync() // pull inicial do init (vazio)

        let measurement = Self.makeMeasurement()
        try await sut.save(measurement)
        await sut.waitForBackgroundSync()

        let recordID = MeasurementRecordMapper.recordID(for: measurement.id)
        let uploadedRecord = await server.record(for: recordID)
        XCTAssertNotNil(uploadedRecord)

        let roundTripped = uploadedRecord.flatMap(MeasurementRecordMapper.measurement(from:))
        XCTAssertEqual(roundTripped, measurement)
    }

    func testSaveReturnsBeforeRemotePushCompletes() async throws {
        // Prova que `save()` é local-first: nunca espera a rede, mesmo
        // quando o push remoto é artificialmente lento (AGENTS.md §8 /
        // issue #71, requisito de aceite "salvar uma medição nunca depende
        // de sync remoto bem-sucedido").
        let server = FakeCloudKitServer()
        let local = InMemoryMeasurementHistoryRepository()
        let remote = FakeMeasurementRemoteStore(server: server, uploadDelayNanoseconds: 200_000_000)
        let sut = SyncingMeasurementHistoryRepository(
            local: local,
            remote: remote,
            tokenStore: InMemoryChangeTokenStore()
        )
        await sut.waitForBackgroundSync()

        let measurement = Self.makeMeasurement()
        try await sut.save(measurement)

        // `save()` já retornou: o dado já está local...
        let storedLocally = try await local.measurement(id: measurement.id)
        XCTAssertNotNil(storedLocally)

        // ...mas o push (200ms de delay artificial) não teve tempo de
        // completar ainda — prova que `save()` não esperou por ele.
        let recordID = MeasurementRecordMapper.recordID(for: measurement.id)
        let notYetUploaded = await server.record(for: recordID)
        XCTAssertNil(notYetUploaded)

        await sut.waitForBackgroundSync()
        let uploadedAfterWaiting = await server.record(for: recordID)
        XCTAssertNotNil(uploadedAfterWaiting)
    }

    // MARK: Offline -> online

    func testOfflineSaveSyncsLaterWhenICloudBecomesAvailable() async throws {
        let server = FakeCloudKitServer()
        let local = InMemoryMeasurementHistoryRepository()
        let remote = FakeMeasurementRemoteStore(server: server, isAccountAvailable: false)
        let sut = SyncingMeasurementHistoryRepository(
            local: local,
            remote: remote,
            tokenStore: InMemoryChangeTokenStore()
        )
        await sut.waitForBackgroundSync()

        let measurement = Self.makeMeasurement()
        try await sut.save(measurement)
        await sut.waitForBackgroundSync()

        // Salvou local mesmo com iCloud indisponível — requisito de aceite:
        // "uso offline continua registrando localmente".
        let storedLocally = try await local.measurement(id: measurement.id)
        XCTAssertNotNil(storedLocally)

        let recordID = MeasurementRecordMapper.recordID(for: measurement.id)
        let uploadedWhileOffline = await server.record(for: recordID)
        XCTAssertNil(uploadedWhileOffline)

        // Volta a ficar online.
        await remote.setAccountAvailable(true)
        await sut.syncNow()

        let uploadedAfterReconnecting = await server.record(for: recordID)
        XCTAssertNotNil(uploadedAfterReconnecting)
    }

    // MARK: Exclusão pendente ("tombstones", PR #93 R2, achado 1)

    func testDeleteOfflineIsPendingAndPropagatesOnNextSyncNowWhenBackOnline() async throws {
        let server = FakeCloudKitServer()
        let local = InMemoryMeasurementHistoryRepository()
        let remote = FakeMeasurementRemoteStore(server: server)
        let tombstoneStore = InMemoryTombstoneStore()
        let sut = SyncingMeasurementHistoryRepository(
            local: local,
            remote: remote,
            tokenStore: InMemoryChangeTokenStore(),
            tombstoneStore: tombstoneStore
        )
        await sut.waitForBackgroundSync()

        let measurement = Self.makeMeasurement()
        try await sut.save(measurement)
        await sut.waitForBackgroundSync()

        let recordID = MeasurementRecordMapper.recordID(for: measurement.id)
        let uploadedBeforeDelete = await server.record(for: recordID)
        XCTAssertNotNil(uploadedBeforeDelete)

        // Fica offline e apaga localmente.
        await remote.setAccountAvailable(false)
        try await sut.delete(id: measurement.id)
        await sut.waitForBackgroundSync()

        // Apagou local mesmo sem conta iCloud disponível — requisito de
        // aceite preservado.
        let storedLocally = try await local.measurement(id: measurement.id)
        XCTAssertNil(storedLocally)

        // Não conseguiu propagar (offline): sem a fila de pendências, isto
        // ficaria perdido para sempre. O record remoto continua existindo
        // e a exclusão fica registrada como pendente.
        let stillOnServerWhileOffline = await server.record(for: recordID)
        XCTAssertNotNil(stillOnServerWhileOffline)
        let pendingWhileOffline = await tombstoneStore.loadPendingDeletes()
        XCTAssertEqual(pendingWhileOffline, [measurement.id])

        // Volta a ficar online: `syncNow` reprocessa a fila de pendências
        // antes de qualquer pull/push.
        await remote.setAccountAvailable(true)
        await sut.syncNow()

        let onServerAfterSync = await server.record(for: recordID)
        XCTAssertNil(onServerAfterSync)
        let pendingAfterSync = await tombstoneStore.loadPendingDeletes()
        XCTAssertTrue(pendingAfterSync.isEmpty)
    }

    func testPendingDeleteIsNotResurrectedWhenPullFindsTheRemoteRecordAgain() async throws {
        let server = FakeCloudKitServer()
        let local = InMemoryMeasurementHistoryRepository()
        let remote = FakeMeasurementRemoteStore(server: server)
        let tombstoneStore = InMemoryTombstoneStore()
        let sut = SyncingMeasurementHistoryRepository(
            local: local,
            remote: remote,
            tokenStore: InMemoryChangeTokenStore(),
            tombstoneStore: tombstoneStore
        )
        await sut.waitForBackgroundSync()

        let measurement = Self.makeMeasurement()
        try await sut.save(measurement)
        await sut.waitForBackgroundSync()

        // Apaga localmente, mas o push da exclusão falha mesmo com conta
        // disponível (simula erro transitório do CloudKit) — o record
        // continua existindo no servidor.
        await remote.setShouldFailDelete(true)
        try await sut.delete(id: measurement.id)
        await sut.waitForBackgroundSync()

        let recordID = MeasurementRecordMapper.recordID(for: measurement.id)
        let stillOnServerAfterFailedDelete = await server.record(for: recordID)
        XCTAssertNotNil(stillOnServerAfterFailedDelete) // delete não propagou

        // `syncNow` reprocessa a fila: o push da exclusão falha de novo
        // (mesmo erro simulado), então o pull que roda em seguida encontra
        // o record remoto de novo. Sem a defesa em `applyRemote`, isso
        // ressuscitaria localmente uma medição que o usuário já apagou.
        await sut.syncNow()

        let afterFailedRetry = try await local.measurement(id: measurement.id)
        XCTAssertNil(afterFailedRetry)
        let stillPending = await tombstoneStore.loadPendingDeletes()
        XCTAssertEqual(stillPending, [measurement.id])

        // O CloudKit volta a responder normalmente: a próxima sync limpa
        // tudo (remoto e fila de pendências).
        await remote.setShouldFailDelete(false)
        await sut.syncNow()

        let onServerAfterRecovery = await server.record(for: recordID)
        XCTAssertNil(onServerAfterRecovery)
        let pendingAfterRecovery = await tombstoneStore.loadPendingDeletes()
        XCTAssertTrue(pendingAfterRecovery.isEmpty)
    }

    // MARK: Conflito

    func testConflictResolverPrefersCompleteOverPartial() {
        let id = UUID()
        let measuredAt = Date(timeIntervalSince1970: 1_000)

        let partial = Self.makeMeasurement(
            id: id,
            measuredAt: measuredAt,
            outcome: .partial,
            download: nil,
            upload: nil,
            latency: 20
        )
        let complete = Self.makeMeasurement(
            id: id,
            measuredAt: measuredAt,
            outcome: .complete,
            download: 150,
            upload: 30,
            latency: 20
        )

        let resolved = MeasurementConflictResolver.resolve(
            local: partial,
            localModifiedAt: Date(),
            remote: complete,
            remoteModifiedAt: Date(timeIntervalSince1970: 500)
        )

        XCTAssertEqual(resolved.outcome, .complete)
        XCTAssertEqual(resolved.downloadMbps, 150)
    }

    func testConflictResolverMergesNonNilFieldsInsteadOfDiscardingLoser() {
        let id = UUID()
        let measuredAt = Date(timeIntervalSince1970: 2_000)

        // Ambos completos e com a mesma contagem de campos preenchidos,
        // mas divergindo em quais campos têm valor — cenário "edição
        // parcial/retry" descrito no plano da issue #71.
        let local = Self.makeMeasurement(
            id: id,
            measuredAt: measuredAt,
            outcome: .complete,
            download: 100,
            upload: 20,
            latency: 15,
            serverIdentifier: "sp1"
        )
        let remote = Self.makeMeasurement(
            id: id,
            measuredAt: measuredAt,
            outcome: .complete,
            download: 100,
            upload: 20,
            latency: 15,
            networkIdentifier: "Operadora X"
        )

        let resolved = MeasurementConflictResolver.resolve(
            local: local,
            localModifiedAt: Date(timeIntervalSince1970: 3_000),
            remote: remote,
            remoteModifiedAt: Date(timeIntervalSince1970: 1_000)
        )

        // Nada foi descartado silenciosamente: os dois campos exclusivos
        // sobrevivem na mescla.
        XCTAssertEqual(resolved.serverIdentifier, "sp1")
        XCTAssertEqual(resolved.networkIdentifier, "Operadora X")
    }

    func testConflictResolverIsDeterministicForSameInputs() {
        let id = UUID()
        let local = Self.makeMeasurement(id: id, outcome: .complete, download: 100, upload: 10, latency: 5)
        let remote = Self.makeMeasurement(id: id, outcome: .partial, download: nil, upload: nil, latency: 8)

        let firstRun = MeasurementConflictResolver.resolve(
            local: local, localModifiedAt: nil, remote: remote, remoteModifiedAt: nil
        )
        let secondRun = MeasurementConflictResolver.resolve(
            local: local, localModifiedAt: nil, remote: remote, remoteModifiedAt: nil
        )

        XCTAssertEqual(firstRun, secondRun)
    }

    func testPullingConflictingRemoteRecordMergesIntoLocalStore() async throws {
        let id = UUID()
        let measuredAt = Date(timeIntervalSince1970: 5_000)

        let server = FakeCloudKitServer()
        let local = InMemoryMeasurementHistoryRepository()
        let localVersion = Self.makeMeasurement(
            id: id,
            measuredAt: measuredAt,
            outcome: .partial,
            download: nil,
            upload: nil,
            latency: 12
        )
        try await local.save(localVersion)

        // Outro dispositivo já subiu uma versão mais completa da mesma
        // medição (mesmo id, contrato #50).
        let remoteVersion = Self.makeMeasurement(
            id: id,
            measuredAt: measuredAt,
            outcome: .complete,
            download: 80,
            upload: 15,
            latency: 12
        )
        await server.upload([MeasurementRecordMapper.record(from: remoteVersion)])

        let remote = FakeMeasurementRemoteStore(server: server)
        let sut = SyncingMeasurementHistoryRepository(
            local: local,
            remote: remote,
            tokenStore: InMemoryChangeTokenStore()
        )
        await sut.waitForBackgroundSync()

        let merged = try await local.measurement(id: id)
        XCTAssertEqual(merged?.outcome, .complete)
        XCTAssertEqual(merged?.downloadMbps, 80)
    }

    // MARK: Múltiplos dispositivos

    func testMeasurementSavedOnOneDeviceAppearsOnAnotherAfterSync() async throws {
        let server = FakeCloudKitServer()

        let deviceALocal = InMemoryMeasurementHistoryRepository()
        let deviceA = SyncingMeasurementHistoryRepository(
            local: deviceALocal,
            remote: FakeMeasurementRemoteStore(server: server),
            tokenStore: InMemoryChangeTokenStore()
        )
        await deviceA.waitForBackgroundSync()

        let deviceBLocal = InMemoryMeasurementHistoryRepository()
        let deviceB = SyncingMeasurementHistoryRepository(
            local: deviceBLocal,
            remote: FakeMeasurementRemoteStore(server: server),
            tokenStore: InMemoryChangeTokenStore()
        )
        await deviceB.waitForBackgroundSync()

        let measurement = Self.makeMeasurement()
        try await deviceA.save(measurement)
        await deviceA.waitForBackgroundSync()

        // Ainda não sincronizado no B (B só sabe do que já puxou).
        let beforeSync = try await deviceB.measurement(id: measurement.id)
        XCTAssertNil(beforeSync)

        await deviceB.syncNow()

        let afterSync = try await deviceB.measurement(id: measurement.id)
        XCTAssertEqual(afterSync?.id, measurement.id)
        XCTAssertEqual(afterSync?.downloadMbps, measurement.downloadMbps)
    }

    func testRepeatedSyncNeverDuplicatesAcrossDevices() async throws {
        let server = FakeCloudKitServer()

        let deviceALocal = InMemoryMeasurementHistoryRepository()
        let deviceA = SyncingMeasurementHistoryRepository(
            local: deviceALocal,
            remote: FakeMeasurementRemoteStore(server: server),
            tokenStore: InMemoryChangeTokenStore()
        )
        await deviceA.waitForBackgroundSync()

        let measurement = Self.makeMeasurement()
        try await deviceA.save(measurement)
        await deviceA.waitForBackgroundSync()

        // Sincroniza o mesmo dispositivo várias vezes e sincroniza um
        // segundo dispositivo várias vezes — nada disso deve duplicar.
        await deviceA.syncNow()
        await deviceA.syncNow()

        let deviceBLocal = InMemoryMeasurementHistoryRepository()
        let deviceB = SyncingMeasurementHistoryRepository(
            local: deviceBLocal,
            remote: FakeMeasurementRemoteStore(server: server),
            tokenStore: InMemoryChangeTokenStore()
        )
        await deviceB.syncNow()
        await deviceB.syncNow()

        let countA = try await deviceALocal.totalCount()
        let countB = try await deviceBLocal.totalCount()
        XCTAssertEqual(countA, 1)
        XCTAssertEqual(countB, 1)
    }

    func testDeleteOnOneDevicePropagatesToAnotherDevice() async throws {
        let server = FakeCloudKitServer()

        let deviceALocal = InMemoryMeasurementHistoryRepository()
        let deviceA = SyncingMeasurementHistoryRepository(
            local: deviceALocal,
            remote: FakeMeasurementRemoteStore(server: server),
            tokenStore: InMemoryChangeTokenStore()
        )
        await deviceA.waitForBackgroundSync()

        let measurement = Self.makeMeasurement()
        try await deviceA.save(measurement)
        await deviceA.waitForBackgroundSync()

        let deviceBLocal = InMemoryMeasurementHistoryRepository()
        let deviceB = SyncingMeasurementHistoryRepository(
            local: deviceBLocal,
            remote: FakeMeasurementRemoteStore(server: server),
            tokenStore: InMemoryChangeTokenStore()
        )
        await deviceB.syncNow()
        let onDeviceBBeforeDelete = try await deviceB.measurement(id: measurement.id)
        XCTAssertNotNil(onDeviceBBeforeDelete)

        // Apaga no A e propaga.
        try await deviceA.delete(id: measurement.id)
        await deviceA.waitForBackgroundSync()

        await deviceB.syncNow()
        let onDeviceBAfterDelete = try await deviceB.measurement(id: measurement.id)
        XCTAssertNil(onDeviceBAfterDelete)
    }

    // MARK: - Mapeamento CKRecord <-> NetworkMeasurement

    func testRecordRoundTripPreservesAllApprovedFields() {
        let summary = LatencyEvidenceSummary(medianMs: 12, p95Ms: 18, maximumMs: 20, sampleCount: 8, timeoutCount: 1, warmupDurationMs: 2_000)
        let phase = LoadPhaseEvidence(latency: summary, usefulDurationMs: 10_000, bytesTransferred: 4_000_000, averageMbps: 80, saturation: .sustained)
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 120.5,
            uploadMbps: 25.3,
            latencyMs: 18,
            jitterMs: 2,
            packetLossPercent: 0,
            loadedLatencyMs: 12,
            loadedLatencyUploadMs: 12,
            loadResponsiveness: LoadResponsivenessEvidence(
                environmentIdentifier: "cloudflare-speedtest-v1",
                integrity: .valid,
                baseline: LatencyEvidenceSummary(medianMs: 18, p95Ms: 20, maximumMs: 22, sampleCount: 8, timeoutCount: 0, warmupDurationMs: 200),
                download: phase,
                upload: phase
            ),
            connectionKind: .wifi,
            wifiBandGHz: 5.0,
            serverIdentifier: "sp-42",
            engineVersion: "1.2.3"
        )

        let record = MeasurementRecordMapper.record(from: measurement)
        let roundTripped = MeasurementRecordMapper.measurement(from: record)

        XCTAssertEqual(roundTripped, measurement)
    }

    func testLegacyRecordWithoutLoadResponsivenessStillDecodes() {
        let measurement = Self.makeMeasurement()
        let record = MeasurementRecordMapper.record(from: measurement)
        XCTAssertNil(record["loadedLatencyUploadMs"])
        XCTAssertNil(record["loadResponsivenessData"])
        XCTAssertNil(MeasurementRecordMapper.measurement(from: record)?.loadResponsiveness)
    }

    func testRecordDoesNotSynchronizeWiFiIdentityByDefault() {
        let measurement = Self.makeMeasurement(
            connectionKind: .wifi,
            networkIdentifier: "Provedor",
            wifiContext: WiFiNetworkContext(
                ssid: "Casa",
                accessPointIdentifier: "derived-ap",
                securityType: .personal
            ),
            advancedWiFiDiagnostics: AdvancedWiFiDiagnostics(
                capturedAt: Date(timeIntervalSince1970: 100_000),
                ssid: "Casa",
                accessPointIdentifier: "advanced-derived-ap",
                rssiDbm: -54,
                noiseDbm: -92,
                snrDb: 38
            )
        )

        let record = MeasurementRecordMapper.record(from: measurement)
        let roundTripped = MeasurementRecordMapper.measurement(from: record)

        XCTAssertNil(roundTripped?.wifiContext)
        XCTAssertNil(roundTripped?.advancedWiFiDiagnostics)
    }

    func testRecordIDUsesMeasurementIDAsRecordName() {
        let id = UUID()
        let recordID = MeasurementRecordMapper.recordID(for: id)
        XCTAssertEqual(recordID.recordName, id.uuidString)
    }

    // MARK: - Helpers

    private static func makeMeasurement(
        id: UUID = UUID(),
        measuredAt: Date = Date(timeIntervalSince1970: 100_000),
        outcome: MeasurementOutcome = .complete,
        download: Double? = 120.5,
        upload: Double? = 25.3,
        latency: Double? = 18,
        connectionKind: NetworkConnectionKind? = nil,
        wifiBand: Double? = nil,
        networkIdentifier: String? = nil,
        wifiContext: WiFiNetworkContext? = nil,
        advancedWiFiDiagnostics: AdvancedWiFiDiagnostics? = nil,
        serverIdentifier: String? = nil,
        engineVersion: String? = nil
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            id: id,
            measuredAt: measuredAt,
            outcome: outcome,
            downloadMbps: download,
            uploadMbps: upload,
            latencyMs: latency,
            jitterMs: 2,
            packetLossPercent: 0,
            connectionKind: connectionKind,
            wifiBandGHz: wifiBand,
            wifiContext: wifiContext,
            advancedWiFiDiagnostics: advancedWiFiDiagnostics,
            networkIdentifier: networkIdentifier,
            serverIdentifier: serverIdentifier,
            engineVersion: engineVersion
        )
    }
}
