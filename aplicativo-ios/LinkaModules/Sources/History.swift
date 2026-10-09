import Foundation
import MeasurementHistory
import MeasurementHistoryCloudKit
import LinkaEntitlements

/// Compatibilidade temporária com a fundação inicial da branch.
/// Código novo deve importar `MeasurementHistory` diretamente.
public typealias HistoryProviding = MeasurementHistory.MeasurementHistoryRepository
public typealias InMemoryHistoryStore = MeasurementHistory.InMemoryMeasurementHistoryRepository

/// Decorator de sincronização do histórico via CloudKit (issue #71) — espelha
/// o histórico local (fonte de verdade) para a private database do iCloud
/// do usuário, em segundo plano, sem introduzir login nem backend próprio
/// do Linka. Ver `MeasurementHistoryCloudKit.SyncingMeasurementHistoryRepository`
/// para as garantias estruturais (local-first, iCloud opcional, exclusão
/// propagada, conflito determinístico).
public typealias SyncingHistoryRepository = MeasurementHistoryCloudKit.SyncingMeasurementHistoryRepository
public typealias CloudKitMeasurementRemoteStore = MeasurementHistoryCloudKit.CloudKitMeasurementRemoteStore

/// Ponto único de construção do repositório de histórico usado pelo app
/// (issue #71). Antes desta issue, `FileMeasurementHistoryRepository` era
/// instanciado separadamente em três lugares de `LinkaApp/Sources`, sempre
/// com o mesmo `fileURL` — este factory centraliza isso e, de quebra, é
/// onde a sincronização CloudKit entra sem vazar `CloudKit`/`CKContainer`
/// para os consumidores de UI (eles continuam enxergando só o protocolo
/// `MeasurementHistoryRepository`).
public enum LinkaMeasurementHistory {
    /// Mesmo caminho de arquivo usado antes desta issue — preservado para
    /// não perder histórico local existente na migração (requisito de
    /// aceite: "histórico local antigo continua legível").
    public static var defaultFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("measurements.json")
    }

    /// Repositório usado pelo app: `FileMeasurementHistoryRepository` como
    /// fonte de verdade local (síncrona, sempre disponível) com sync
    /// CloudKit em segundo plano por cima. A sincronização respeita o
    /// mesmo gate de entitlement que já protege a superfície de Histórico
    /// (`LinkaCapability.history`) — este pacote não reimplementa checagem
    /// de plano, só consulta a decisão já existente em `LinkaEntitlements`.
    ///
    /// Devolve **a mesma instância** para o mesmo `fileURL` em chamadas
    /// repetidas (PR #93 R2, achado 2 do Marcelo) — antes disso, cada
    /// chamador (`SpeedTestViewModel.loadLastTest()`/`startTest()`,
    /// `HistoryView`, `SettingsSheet`) criava um `SyncingHistoryRepository`
    /// novo, e o `init` desse tipo dispara `syncNow()` sozinho: várias
    /// chamadas em sequência (ex.: `init` do view model seguido de cada
    /// teste salvo) disparavam um `syncNow()` redundante por chamada, cada
    /// um reenviando todo o histórico local para o CloudKit. A entitlements
    /// usada é a da primeira chamada que criou a instância para aquele
    /// `fileURL`; instâncias diferentes de `StoreKitEntitlementProvider`
    /// convergem para o mesmo estado (StoreKit/`UserDefaults`), então isso
    /// não muda o resultado da checagem de plano.
    /// `remote` é injetável (default `CloudKitMeasurementRemoteStore()`, o
    /// mesmo de sempre) só para permitir testar o cache/singleton deste
    /// factory sem construir um `CKContainer` real — instanciar
    /// `CKContainer` fora de um binário assinado com o entitlement de
    /// iCloud (caso de `swift test`, inclusive em CI) derruba o processo.
    /// Todo chamador de produção continua usando o default.
    public static func makeRepository(
        fileURL: URL = defaultFileURL,
        entitlements: any LinkaEntitlementProviding,
        remote: any MeasurementHistoryCloudKit.MeasurementRemoteStore = CloudKitMeasurementRemoteStore()
    ) -> SyncingHistoryRepository {
        repositoryCache.repository(for: fileURL) {
            SyncingHistoryRepository(
                local: FileMeasurementHistoryRepository(fileURL: fileURL),
                remote: remote,
                isSyncPermitted: {
                    await entitlements.hasAccess(to: .history)
                }
            )
        }
    }

    public static func makeRepository() -> SyncingHistoryRepository {
        let snapshot = LinkaEntitlementSnapshotResolver.resolve()
        return makeRepository(entitlements: StaticLinkaEntitlementProvider(snapshot: snapshot))
    }

    private static let repositoryCache = RepositoryCache()

    /// Cache thread-safe (lock simples, sem `async`: `makeRepository`
    /// precisa continuar síncrona para os chamadores atuais em `LinkaApp`)
    /// do único `SyncingHistoryRepository` por `fileURL`. Na prática é um
    /// singleton, já que `defaultFileURL` é sempre o mesmo caminho.
    private final class RepositoryCache: @unchecked Sendable {
        private let lock = NSLock()
        private var instances: [URL: SyncingHistoryRepository] = [:]

        func repository(
            for fileURL: URL,
            make: () -> SyncingHistoryRepository
        ) -> SyncingHistoryRepository {
            lock.lock()
            defer { lock.unlock() }
            if let existing = instances[fileURL] {
                return existing
            }
            let created = make()
            instances[fileURL] = created
            return created
        }
    }
}
