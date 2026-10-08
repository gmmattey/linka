// Justificativa de Arquitetura (validarModularidade):
// Este arquivo coordena a lógica de sincronização remota com a CloudKit e conversão de schemas.
// É mantido coeso para não espalhar o tratamento de chaves, limites e tokens do CloudKit em vários arquivos.
import Foundation
import CloudKit
import NetworkCore

// MARK: - Identificadores canônicos

/// Container privado do Linka no CloudKit, usado exclusivamente para
/// espelhar `NetworkMeasurement` entre os dispositivos Apple do próprio
/// usuário (issue #71). Não é backend do Linka — é a private database do
/// container iCloud do usuário; o Linka nunca lê nem escreve fora dela.
public enum LinkaCloudKitContainer {
    /// PENDÊNCIA (issue #71): placeholder até o container ser provisionado
    /// no Apple Developer Portal por Luiz/Giam — mesma natureza de
    /// pendência de conta que `LinkaStoreProductID` documenta para o Linka
    /// Plus em `LinkaEntitlements/Sources/StoreKitEntitlementProvider.swift`.
    /// Sem esse provisionamento, `CKContainer(identifier:)` resolve para um
    /// container inexistente e toda chamada de rede falha — o que é
    /// inofensivo aqui porque todo o sync é best-effort (ver
    /// `SyncingMeasurementHistoryRepository`): o app continua funcionando
    /// 100% local.
    public static let identifier = "iCloud.com.linka.assist"
}

/// Nome do tipo de record no CloudKit. Precisa ser criado no CloudKit
/// Console (ou pela primeira gravação em ambiente de desenvolvimento) com
/// os mesmos campos de `MeasurementRecordMapper.FieldKey`.
public enum MeasurementRecordType {
    public static let name = "Measurement"
}

/// Zona custom (não a zona default) — usada para poder pedir mudanças
/// incrementais por zona (`CKDatabase.recordZoneChanges`) de forma isolada
/// de qualquer outro uso futuro do mesmo container.
public enum MeasurementRecordZone {
    public static let name = "MeasurementHistoryZone"
    public static let zoneID = CKRecordZone.ID(zoneName: name, ownerName: CKCurrentUserDefaultName)
}

// MARK: - Mapeamento NetworkMeasurement <-> CKRecord

/// Converte `NetworkMeasurement` para `CKRecord` e vice-versa usando
/// somente os campos já aprovados do contrato canônico (issue #50) — nenhum
/// campo novo, nenhum identificador sensível adicional (issue #71, não
/// objetivo). `id: UUID` vira `CKRecord.ID.recordName` diretamente: dá
/// identidade estável entre dispositivos e faz de qualquer push repetido um
/// upsert idempotente pelo mesmo recordID, nunca uma duplicata.
public enum MeasurementRecordMapper {
    enum FieldKey: String {
        case schemaVersion
        case measuredAt
        case outcome
        case downloadMbps
        case uploadMbps
        case latencyMs
        case jitterMs
        case packetLossPercent
        case packetProbeEvidenceData
        case regionalGameReferenceData
        case loadedLatencyMs
        case loadedLatencyUploadMs
        /// JSON codificado do envelope aditivo. CloudKit não aceita structs
        /// aninhadas; `Data` mantém o schema remoto compatível com records
        /// antigos que naturalmente não possuem esta chave.
        case loadResponsivenessData
        case durationMs
        case connectionKind
        case wifiBandGHz
        case networkIdentifier
        case serverIdentifier
        case engineVersion
    }

    public static func recordID(
        for id: UUID,
        zoneID: CKRecordZone.ID = MeasurementRecordZone.zoneID
    ) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    public static func record(
        from measurement: NetworkMeasurement,
        zoneID: CKRecordZone.ID = MeasurementRecordZone.zoneID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: MeasurementRecordType.name,
            recordID: recordID(for: measurement.id, zoneID: zoneID)
        )

        record[FieldKey.schemaVersion.rawValue] = measurement.schemaVersion
        record[FieldKey.measuredAt.rawValue] = measurement.measuredAt
        record[FieldKey.outcome.rawValue] = measurement.outcome.rawValue
        record[FieldKey.downloadMbps.rawValue] = measurement.downloadMbps
        record[FieldKey.uploadMbps.rawValue] = measurement.uploadMbps
        record[FieldKey.latencyMs.rawValue] = measurement.latencyMs
        record[FieldKey.jitterMs.rawValue] = measurement.jitterMs
        record[FieldKey.packetLossPercent.rawValue] = measurement.packetLossPercent
        if let evidence = measurement.packetProbeEvidence,
           let encoded = try? JSONEncoder().encode(evidence) {
            record[FieldKey.packetProbeEvidenceData.rawValue] = encoded as NSData
        }
        if let reference = measurement.regionalGameReference,
           let encoded = try? JSONEncoder().encode(reference) {
            record[FieldKey.regionalGameReferenceData.rawValue] = encoded as NSData
        }
        record[FieldKey.loadedLatencyMs.rawValue] = measurement.loadedLatencyMs
        record[FieldKey.loadedLatencyUploadMs.rawValue] = measurement.loadedLatencyUploadMs
        if let responsiveness = measurement.loadResponsiveness,
           let encoded = try? JSONEncoder().encode(responsiveness) {
            record[FieldKey.loadResponsivenessData.rawValue] = encoded as NSData
        }
        record[FieldKey.durationMs.rawValue] = measurement.durationMs
        record[FieldKey.connectionKind.rawValue] = measurement.connectionKind?.rawValue
        record[FieldKey.wifiBandGHz.rawValue] = measurement.wifiBandGHz
        record[FieldKey.networkIdentifier.rawValue] = measurement.networkIdentifier
        record[FieldKey.serverIdentifier.rawValue] = measurement.serverIdentifier
        record[FieldKey.engineVersion.rawValue] = measurement.engineVersion

        return record
    }

    /// `nil` quando o record não tem os campos mínimos exigidos pelo
    /// contrato canônico (`NetworkMeasurementContract`) ou quando o
    /// `recordID.recordName` não é um `UUID` válido — nesse caso o record
    /// remoto é ignorado silenciosamente (nunca derruba o sync inteiro).
    public static func measurement(from record: CKRecord) -> NetworkMeasurement? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let schemaVersion = record[FieldKey.schemaVersion.rawValue] as? Int,
              let measuredAt = record[FieldKey.measuredAt.rawValue] as? Date,
              let outcomeRaw = record[FieldKey.outcome.rawValue] as? String,
              let outcome = MeasurementOutcome(rawValue: outcomeRaw)
        else {
            return nil
        }

        let connectionKind = (record[FieldKey.connectionKind.rawValue] as? String)
            .flatMap(NetworkConnectionKind.init(rawValue:))

        let measurement = NetworkMeasurement(
            schemaVersion: schemaVersion,
            id: id,
            measuredAt: measuredAt,
            outcome: outcome,
            downloadMbps: record[FieldKey.downloadMbps.rawValue] as? Double,
            uploadMbps: record[FieldKey.uploadMbps.rawValue] as? Double,
            latencyMs: record[FieldKey.latencyMs.rawValue] as? Double,
            jitterMs: record[FieldKey.jitterMs.rawValue] as? Double,
            packetLossPercent: record[FieldKey.packetLossPercent.rawValue] as? Double,
            packetProbeEvidence: (record[FieldKey.packetProbeEvidenceData.rawValue] as? Data)
                .flatMap { try? JSONDecoder().decode(PacketProbeEvidence.self, from: $0) },
            regionalGameReference: (record[FieldKey.regionalGameReferenceData.rawValue] as? Data)
                .flatMap { try? JSONDecoder().decode(RegionalGameReference.self, from: $0) },
            loadedLatencyMs: record[FieldKey.loadedLatencyMs.rawValue] as? Double,
            loadedLatencyUploadMs: record[FieldKey.loadedLatencyUploadMs.rawValue] as? Double,
            loadResponsiveness: (record[FieldKey.loadResponsivenessData.rawValue] as? Data)
                .flatMap { try? JSONDecoder().decode(LoadResponsivenessEvidence.self, from: $0) },
            durationMs: record[FieldKey.durationMs.rawValue] as? Int,
            connectionKind: connectionKind,
            wifiBandGHz: record[FieldKey.wifiBandGHz.rawValue] as? Double,
            networkIdentifier: record[FieldKey.networkIdentifier.rawValue] as? String,
            serverIdentifier: record[FieldKey.serverIdentifier.rawValue] as? String,
            engineVersion: record[FieldKey.engineVersion.rawValue] as? String
        )

        return NetworkMeasurementContract.isValid(measurement) ? measurement : nil
    }
}

// MARK: - Resolução de conflito

/// Regra determinística de conflito (issue #71, requisito de aceite):
/// quando o mesmo `id` chega de dois dispositivos com conteúdo diferente
/// (não deveria acontecer em teoria — uma medição é imutável após criada —
/// mas pode acontecer por edição parcial/retry), o registro mais completo
/// vence: `.complete` vence sobre `.partial`; em empate de completude, mais
/// campos não-nil vence; em empate total, a modificação mais recente vence.
/// Nunca descarta silenciosamente o perdedor: os campos não-nil dele
/// preenchem as lacunas do vencedor.
public enum MeasurementConflictResolver {
    public static func resolve(
        local: NetworkMeasurement,
        localModifiedAt: Date?,
        remote: NetworkMeasurement,
        remoteModifiedAt: Date?
    ) -> NetworkMeasurement {
        guard local.id == remote.id else {
            // Não deveria ser chamado fora desse caso — devolve o remoto
            // como fallback defensivo, nunca trava o caller.
            return remote
        }

        guard local != remote else { return local }

        let localIsWinner: Bool
        if local.outcome != remote.outcome {
            localIsWinner = local.outcome == .complete
        } else if nonNilFieldCount(local) != nonNilFieldCount(remote) {
            localIsWinner = nonNilFieldCount(local) > nonNilFieldCount(remote)
        } else {
            let localDate = localModifiedAt ?? .distantPast
            let remoteDate = remoteModifiedAt ?? .distantPast
            localIsWinner = localDate >= remoteDate
        }

        let winner = localIsWinner ? local : remote
        let loser = localIsWinner ? remote : local
        let merged = merge(winner: winner, fillingFrom: loser)

        // Defesa extra: se por algum motivo a mescla produzir uma medição
        // que viola o contrato canônico (ex.: wifiBandGHz sem
        // connectionKind == .wifi vindo de lados diferentes), preferimos o
        // vencedor puro a propagar um registro inválido.
        return NetworkMeasurementContract.isValid(merged) ? merged : winner
    }

    private static func nonNilFieldCount(_ measurement: NetworkMeasurement) -> Int {
        [
            measurement.downloadMbps != nil,
            measurement.uploadMbps != nil,
            measurement.latencyMs != nil,
            measurement.jitterMs != nil,
            measurement.packetLossPercent != nil,
            measurement.packetProbeEvidence != nil,
            measurement.regionalGameReference != nil,
            measurement.loadedLatencyMs != nil,
            measurement.loadedLatencyUploadMs != nil,
            measurement.loadResponsiveness != nil,
            measurement.durationMs != nil,
            measurement.connectionKind != nil,
            measurement.wifiBandGHz != nil,
            measurement.networkIdentifier != nil,
            measurement.serverIdentifier != nil,
            measurement.engineVersion != nil
        ].filter { $0 }.count
    }

    private static func merge(
        winner: NetworkMeasurement,
        fillingFrom loser: NetworkMeasurement
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            schemaVersion: winner.schemaVersion,
            id: winner.id,
            measuredAt: winner.measuredAt,
            outcome: winner.outcome,
            downloadMbps: winner.downloadMbps ?? loser.downloadMbps,
            uploadMbps: winner.uploadMbps ?? loser.uploadMbps,
            latencyMs: winner.latencyMs ?? loser.latencyMs,
            jitterMs: winner.jitterMs ?? loser.jitterMs,
            packetLossPercent: winner.packetLossPercent ?? loser.packetLossPercent,
            packetProbeEvidence: winner.packetProbeEvidence ?? loser.packetProbeEvidence,
            regionalGameReference: winner.regionalGameReference ?? loser.regionalGameReference,
            loadedLatencyMs: winner.loadedLatencyMs ?? loser.loadedLatencyMs,
            loadedLatencyUploadMs: winner.loadedLatencyUploadMs ?? loser.loadedLatencyUploadMs,
            loadResponsiveness: winner.loadResponsiveness ?? loser.loadResponsiveness,
            durationMs: winner.durationMs ?? loser.durationMs,
            connectionKind: winner.connectionKind ?? loser.connectionKind,
            wifiBandGHz: winner.wifiBandGHz ?? loser.wifiBandGHz,
            networkIdentifier: winner.networkIdentifier ?? loser.networkIdentifier,
            serverIdentifier: winner.serverIdentifier ?? loser.serverIdentifier,
            engineVersion: winner.engineVersion ?? loser.engineVersion
        )
    }
}

// MARK: - Abstração do transporte remoto (testável sem rede/iCloud)

/// Resultado de um fetch incremental de mudanças de uma zona.
///
/// `changeToken` é opaco (`Data`) de propósito: `CKServerChangeToken` não
/// tem inicializador público (só o CloudKit pode criar um), então
/// mantê-lo como tipo concreto no protocolo de transporte tornaria
/// `MeasurementRemoteStore` impossível de faquear em teste sem rede/conta
/// iCloud real. `CloudKitMeasurementRemoteStore` (implementação real)
/// converte para/de `CKServerChangeToken` internamente via
/// `NSKeyedArchiver`/`NSKeyedUnarchiver`, que é o mecanismo que a própria
/// Apple documenta para persistir esse token.
public struct MeasurementRemoteChangeSet: Sendable {
    public let changedRecords: [CKRecord]
    public let deletedRecordIDs: [CKRecord.ID]
    public let newChangeToken: Data?

    public init(
        changedRecords: [CKRecord],
        deletedRecordIDs: [CKRecord.ID],
        newChangeToken: Data?
    ) {
        self.changedRecords = changedRecords
        self.deletedRecordIDs = deletedRecordIDs
        self.newChangeToken = newChangeToken
    }
}

/// Transporte remoto usado por `SyncingMeasurementHistoryRepository`.
/// Isolar isso num protocolo (em vez de falar direto com `CKContainer`) é o
/// que permite testar upload, delete, fetch incremental, conflito e
/// múltiplos dispositivos em `CloudKitMeasurementSyncTests` sem depender de
/// rede, conta iCloud logada nem container provisionado.
public protocol MeasurementRemoteStore: Sendable {
    /// Nunca lança — indisponibilidade de conta é estado normal, não erro.
    func accountStatus() async -> CKAccountStatus
    func ensureZoneExists() async throws
    func upload(_ records: [CKRecord]) async throws
    func deleteRemote(recordIDs: [CKRecord.ID]) async throws
    func fetchChanges(since token: Data?) async throws -> MeasurementRemoteChangeSet
}

// MARK: - Implementação real (CKContainer / CKDatabase)

/// Implementação real de `MeasurementRemoteStore` sobre a private database
/// do `CKContainer` do usuário.
///
/// Deliberadamente usa as APIs `async throws` modernas de `CKDatabase`
/// (`modifyRecords`, `modifyRecordZones`, `recordZoneChanges`) — todas
/// disponíveis desde iOS 15 / macOS 12 — em vez de `CKSyncEngine`, que exige
/// iOS 17 / macOS 14. Isso preserva o deployment target atual do produto
/// (iOS 16 / macOS 13) sem estreitar o alcance de dispositivos suportados;
/// subir o deployment target para adotar `CKSyncEngine` é uma decisão de
/// produto/plataforma que fica para Giam/Luiz decidirem separadamente, não
/// algo resolvido "de carona" nesta implementação (issue #71).
public final class CloudKitMeasurementRemoteStore: MeasurementRemoteStore, @unchecked Sendable {
    private let container: CKContainer?
    private let database: CKDatabase?
    private let zoneID: CKRecordZone.ID

    public init(
        containerIdentifier: String = LinkaCloudKitContainer.identifier,
        zoneID: CKRecordZone.ID = MeasurementRecordZone.zoneID
    ) {
        // Hotfix pós-#71: `CKContainer(identifier:)` crasha com `os_crash`
        // duro (SIGTRAP) quando o entitlement
        // `com.apple.developer.icloud-container-identifiers` não está
        // embarcado no binário. Isso acontece hoje em qualquer build sem
        // code-signing (simulador, CI) e enquanto o container
        // `iCloud.com.linka.speedtest` não estiver provisionado no Apple
        // Developer Portal. Detectamos a ausência via `SecTaskCopyValueFor
        // Entitlement` e degradamos silenciosamente para no-op — sync
        // CloudKit fica desabilitado até o provisionamento acontecer, mas
        // o app não crasha e todo o fluxo local continua funcionando.
        if Self.hasICloudContainerEntitlement(for: containerIdentifier) {
            let c = CKContainer(identifier: containerIdentifier)
            self.container = c
            self.database = c.privateCloudDatabase
        } else {
            self.container = nil
            self.database = nil
        }
        self.zoneID = zoneID
    }

    private static func hasICloudContainerEntitlement(for id: String) -> Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        
        #if targetEnvironment(simulator)
        // No simulador sem assinatura de entitlements CloudKit (build de CLI/dev sem provisioning profile),
        // CKContainer(identifier:) crasha com SIGTRAP. Degradamos com segurança para evitar crash em tempo de execução.
        guard Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil ||
              Bundle.main.url(forResource: "archived-expanded-entitlements", withExtension: "xcent") != nil else {
            return false
        }
        return true
        #else
        #if DEBUG
        // Habilita também em DEBUG em device físico (Personal Team / Conta Paga)
        return true
        #else
        // Em device release, mantemos a verificação do mobileprovision por segurança
        return Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
        #endif
        #endif
    }

    public func accountStatus() async -> CKAccountStatus {
        guard let container else { return .couldNotDetermine }
        return (try? await container.accountStatus()) ?? .couldNotDetermine
    }

    public func ensureZoneExists() async throws {
        guard let database else { return }
        _ = try await database.modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID)],
            deleting: []
        )
    }

    public func upload(_ records: [CKRecord]) async throws {
        guard !records.isEmpty else { return }
        guard let database else { return }
        _ = try await database.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false
        )
    }

    public func deleteRemote(recordIDs: [CKRecord.ID]) async throws {
        guard !recordIDs.isEmpty else { return }
        guard let database else { return }
        _ = try await database.modifyRecords(
            saving: [],
            deleting: recordIDs,
            savePolicy: .changedKeys,
            atomically: false
        )
    }

    public func fetchChanges(since token: Data?) async throws -> MeasurementRemoteChangeSet {
        guard let database else {
            return MeasurementRemoteChangeSet(
                changedRecords: [],
                deletedRecordIDs: [],
                newChangeToken: token
            )
        }
        let previousToken = token.flatMap(Self.decodeToken)

        let result = try await database.recordZoneChanges(
            inZoneWith: zoneID,
            since: previousToken
        )

        let changedRecords = result.modificationResultsByID.values.compactMap { modificationResult -> CKRecord? in
            guard case .success(let modification) = modificationResult else { return nil }
            return modification.record
        }
        let deletedRecordIDs = result.deletions.map(\.recordID)
        let newToken = Self.encodeToken(result.changeToken)

        return MeasurementRemoteChangeSet(
            changedRecords: changedRecords,
            deletedRecordIDs: deletedRecordIDs,
            newChangeToken: newToken
        )
    }

    private static func encodeToken(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func decodeToken(_ data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
}

// MARK: - Persistência do change token

/// Guarda o último `changeToken` (opaco, ver `MeasurementRemoteChangeSet`)
/// entre execuções do app, para que `pullRemoteChanges` busque só o que
/// mudou desde a última vez em vez de reler a zona inteira toda vez.
public protocol MeasurementSyncChangeTokenStore: Sendable {
    func loadToken() async -> Data?
    func saveToken(_ token: Data?) async
}

public actor UserDefaultsChangeTokenStore: MeasurementSyncChangeTokenStore {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "com.linka.measurementHistorySync.changeToken"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadToken() async -> Data? {
        defaults.data(forKey: key)
    }

    public func saveToken(_ token: Data?) async {
        if let token {
            defaults.set(token, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Usado em teste e como estado efêmero quando persistência em disco não é
/// necessária.
public actor InMemoryChangeTokenStore: MeasurementSyncChangeTokenStore {
    private var token: Data?

    public init(initialToken: Data? = nil) {
        self.token = initialToken
    }

    public func loadToken() async -> Data? {
        token
    }

    public func saveToken(_ token: Data?) async {
        self.token = token
    }
}

// MARK: - Fila de exclusões pendentes ("tombstones")

/// Fila persistida de exclusões locais ainda não confirmadas no CloudKit
/// (PR #93, R2 — achado 1 do Marcelo). `delete`/`deleteAll` gravam aqui logo
/// depois de apagar localmente, antes de tentar o push remoto: se o
/// dispositivo estiver offline ou sem conta iCloud disponível *naquele
/// instante*, a exclusão não se perde silenciosamente — fica registrada até
/// `syncNow` (chamado de novo mais tarde, ex. app voltando a ficar ativo)
/// conseguir propagá-la ao CloudKit.
///
/// Sem isso, `pushRemoteDelete` falhava calado quando offline e nada
/// reenfileirava a exclusão depois: `pushAllLocalMeasurements` só reenvia o
/// que ainda existe localmente, então uma medição já apagada localmente
/// nunca era reenviada como exclusão — o registro remoto sobrevivia para
/// sempre e podia "ressuscitar" localmente no próximo pull.
public protocol MeasurementSyncTombstoneStore: Sendable {
    func loadPendingDeletes() async -> [UUID]
    func addPendingDeletes(_ ids: [UUID]) async
    func removePendingDeletes(_ ids: [UUID]) async
}

public actor UserDefaultsTombstoneStore: MeasurementSyncTombstoneStore {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "com.linka.measurementHistorySync.pendingDeletes"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadPendingDeletes() async -> [UUID] {
        (defaults.array(forKey: key) as? [String] ?? []).compactMap(UUID.init(uuidString:))
    }

    public func addPendingDeletes(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        var current = Set(await loadPendingDeletes())
        current.formUnion(ids)
        persist(current)
    }

    public func removePendingDeletes(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        var current = Set(await loadPendingDeletes())
        current.subtract(ids)
        persist(current)
    }

    private func persist(_ ids: Set<UUID>) {
        defaults.set(ids.map(\.uuidString), forKey: key)
    }
}

/// Usado em teste e como estado efêmero quando persistência em disco não é
/// necessária.
public actor InMemoryTombstoneStore: MeasurementSyncTombstoneStore {
    private var ids: Set<UUID>

    public init(initialIDs: Set<UUID> = []) {
        self.ids = initialIDs
    }

    public func loadPendingDeletes() async -> [UUID] {
        Array(ids)
    }

    public func addPendingDeletes(_ newIDs: [UUID]) async {
        ids.formUnion(newIDs)
    }

    public func removePendingDeletes(_ removedIDs: [UUID]) async {
        ids.subtract(removedIDs)
    }
}
