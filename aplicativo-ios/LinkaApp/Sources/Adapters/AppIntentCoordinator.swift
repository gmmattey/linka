import AppIntents
import CryptoKit
import Foundation
import LinkaEntitlements
import NetworkCore
import StoreKit

/// Ponte observável entre a execução de `LinkaAppIntentExecutor`
/// (Siri/Shortcuts/Widget — issue #55) e `MainView`.
///
/// App Intents com `openAppWhenRun = true` rodam dentro do processo do
/// app quando o sistema abre o Linka para executá-los, mas não têm
/// acesso ao `@StateObject` de `SpeedTestViewModel` que vive em `MainView`
/// — `perform()` de um `AppIntent` não é uma `View` e não recebe
/// ambiente SwiftUI. Este coordinator existe só para atravessar essa
/// fronteira: o executor publica que uma ação foi pedida, `MainView`
/// observa e é quem decide traduzir isso para `viewModel.startTest()`.
///
/// Não mede nada, não decide nada sobre o motor — é só o mensageiro
/// (mesmo espírito do "adapter não acopla UI ao motor" de
/// `escreverAdaptadorNativo`).
@MainActor
public final class AppIntentCoordinator: ObservableObject {
    /// Singleton porque o `Handler` do `LinkaAppIntentExecutor` é
    /// registrado uma única vez, cedo, em `LinkaApp.init`/`.task`
    /// (`AppDependencyManager.shared.add`), fora da árvore de `View` —
    /// não há como injetar isto via `@EnvironmentObject` no ponto onde o
    /// executor é construído. `MainView` observa a mesma instância via
    /// `@ObservedObject`.
    public static let shared = AppIntentCoordinator()

    /// Alterna para `true` quando o widget/Siri/Shortcuts pede uma
    /// medição; `MainView` consome (`consumeStartSpeedTestRequest()`)
    /// depois de reagir, para não disparar `startTest()` de novo em toda
    /// recomposição de view.
    @Published public private(set) var pendingStartSpeedTest: Bool = false

    /// Alterna para `true` quando o widget/Siri/Shortcuts é acionado por
    /// usuário Free — `MainView` abre `PurchaseSheet` em vez de rodar
    /// medição. Decisão do Luiz (2026-08-15): Widget/Siri/App Intents são
    /// exclusivos do Linka Plus, incluindo o disparo de `startSpeedTest`
    /// por essas superfícies.
    @Published public private(set) var pendingPurchasePrompt: Bool = false
    @Published public private(set) var pendingAdvancedWiFiDiagnosticsImport: Bool = false
    @Published public private(set) var pendingOpenHistory: Bool = false
    @Published public private(set) var pendingOpenLatestMeasurement: Bool = false
    @Published public private(set) var pendingCancelMeasurement: Bool = false
    @Published public private(set) var pendingOpenSettings: Bool = false
    @Published public private(set) var isMeasurementActive: Bool = false

    private init() {}

    public func requestStartSpeedTest() {
        pendingStartSpeedTest = true
    }

    public func consumeStartSpeedTestRequest() {
        pendingStartSpeedTest = false
    }

    public func requestPurchasePrompt() {
        pendingPurchasePrompt = true
    }

    public func consumePurchasePrompt() {
        pendingPurchasePrompt = false
    }

    public func requestAdvancedWiFiDiagnosticsImport() {
        pendingAdvancedWiFiDiagnosticsImport = true
    }

    public func consumeAdvancedWiFiDiagnosticsImport() {
        pendingAdvancedWiFiDiagnosticsImport = false
    }

    public func requestOpenHistory() {
        pendingOpenHistory = true
    }

    public func consumeOpenHistory() {
        pendingOpenHistory = false
    }

    public func requestOpenLatestMeasurement() {
        pendingOpenLatestMeasurement = true
    }

    public func consumeOpenLatestMeasurement() {
        pendingOpenLatestMeasurement = false
    }

    public func requestCancelMeasurement() { pendingCancelMeasurement = true }
    public func consumeCancelMeasurement() { pendingCancelMeasurement = false }
    public func requestOpenSettings() { pendingOpenSettings = true }
    public func consumeOpenSettings() { pendingOpenSettings = false }
    public func setMeasurementActive(_ isActive: Bool) { isMeasurementActive = isActive }
}

/// Caixa local e efêmera entre o App Intent/URL e a próxima atualização do
/// `SpeedTestViewModel`. O dado bruto do Atalhos só existe dentro de
/// `importPayload`; BSSID/MAC nunca são gravados em `UserDefaults`.
enum AdvancedWiFiDiagnosticsInbox {
    private static let pendingKey = "linka.advanced-wifi.pending.v1"
    private static let handledIdentifiersKey = "linka.advanced-wifi.handled.v1"
    // Compartilhado com `SpeedTestViewModel`: a captura nativa só é aceita
    // quando seu AP anonimizado coincide com o AP da própria medição.
    private static let accessPointSaltKey = "linka.wifi.access-point-salt.v1"
    static let maximumPayloadBytes = 4_096
    static let pendingLifetime: TimeInterval = 180

    struct Payload: Decodable {
        let schemaVersion: Int
        let shortcutVersion: Int
        let captureIdentifier: UUID
        let capturedAt: Date
        let ssid: String?
        let bssid: String?
        let wifiStandard: String?
        let rxRateMbps: Double?
        let txRateMbps: Double?
        let rssiDbm: Double?
        let noiseDbm: Double?
        let channelNumber: Int?
        let hardwareMacAddress: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion, shortcutVersion, captureIdentifier, capturedAt, ssid, bssid, wifiStandard
            case rxRateMbps, txRateMbps, rssiDbm, noiseDbm, channelNumber, hardwareMacAddress
        }
    }

    enum ImportError: Error, Equatable {
        case notEntitled
        case integrationDisabled
        case invalidPayload
        case unsupportedSchema
        case expiredTimestamp
        case duplicate
    }

    static func importPayload(
        _ json: String,
        entitlement: LinkaEntitlementSnapshot,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) throws -> AdvancedWiFiDiagnostics {
        guard defaults.object(forKey: LinkaWiFiPreferences.advancedDiagnosticsEnabledKey) == nil ||
                defaults.bool(forKey: LinkaWiFiPreferences.advancedDiagnosticsEnabledKey) else {
            throw ImportError.integrationDisabled
        }
        guard LinkaEntitlementPolicy.decision(
            for: .advancedWiFiDiagnostics,
            snapshot: entitlement,
            at: now
        ).isGranted else {
            throw ImportError.notEntitled
        }

        let data = Data(json.utf8)
        guard !data.isEmpty, data.count <= maximumPayloadBytes else {
            throw ImportError.invalidPayload
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw ImportError.invalidPayload
        }
        guard payload.schemaVersion == AdvancedWiFiDiagnostics.currentSchemaVersion,
              (1...AdvancedWiFiDiagnostics.currentShortcutVersion).contains(payload.shortcutVersion) else {
            throw ImportError.unsupportedSchema
        }
        guard payload.capturedAt <= now.addingTimeInterval(30),
              payload.capturedAt >= now.addingTimeInterval(-pendingLifetime) else {
            throw ImportError.expiredTimestamp
        }

        var handled = Set(defaults.stringArray(forKey: handledIdentifiersKey) ?? [])
        let identifier = payload.captureIdentifier.uuidString
        guard !handled.contains(identifier) else { throw ImportError.duplicate }

        let diagnostics = AdvancedWiFiDiagnostics(
            schemaVersion: payload.schemaVersion,
            shortcutVersion: payload.shortcutVersion,
            captureIdentifier: payload.captureIdentifier,
            capturedAt: payload.capturedAt,
            ssid: normalized(payload.ssid, maximumLength: 64),
            accessPointIdentifier: localAccessPointIdentifier(for: payload.bssid, defaults: defaults),
            wifiStandard: normalized(payload.wifiStandard, maximumLength: 32),
            rxRateMbps: nonNegativeFinite(payload.rxRateMbps),
            txRateMbps: nonNegativeFinite(payload.txRateMbps),
            rssiDbm: finite(payload.rssiDbm),
            noiseDbm: finite(payload.noiseDbm),
            channelNumber: positive(payload.channelNumber),
            bandGHz: AdvancedWiFiDiagnostics.bandGHz(forChannel: positive(payload.channelNumber)),
            snrDb: AdvancedWiFiDiagnostics.snrDb(rssiDbm: finite(payload.rssiDbm), noiseDbm: finite(payload.noiseDbm))
        )

        guard let encoded = try? JSONEncoder().encode(diagnostics) else {
            throw ImportError.invalidPayload
        }
        defaults.set(encoded, forKey: pendingKey)
        defaults.set(true, forKey: LinkaWiFiPreferences.advancedConfiguredKey)
        handled.insert(identifier)
        defaults.set(Array(handled.suffix(32)), forKey: handledIdentifiersKey)
        return diagnostics
    }

    static func importFields(
        entitlement: LinkaEntitlementSnapshot,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        captureIdentifier: UUID = UUID(),
        ssid: String? = nil,
        bssid: String? = nil,
        wifiStandard: String? = nil,
        rxRateMbps: Double? = nil,
        txRateMbps: Double? = nil,
        rssiDbm: Double? = nil,
        noiseDbm: Double? = nil,
        channelNumber: Int? = nil
    ) throws -> AdvancedWiFiDiagnostics {
        guard defaults.object(forKey: LinkaWiFiPreferences.advancedDiagnosticsEnabledKey) == nil ||
                defaults.bool(forKey: LinkaWiFiPreferences.advancedDiagnosticsEnabledKey) else {
            throw ImportError.integrationDisabled
        }
        guard LinkaEntitlementPolicy.decision(
            for: .advancedWiFiDiagnostics,
            snapshot: entitlement,
            at: now
        ).isGranted else {
            throw ImportError.notEntitled
        }

        var handled = Set(defaults.stringArray(forKey: handledIdentifiersKey) ?? [])
        let identifier = captureIdentifier.uuidString
        guard !handled.contains(identifier) else { throw ImportError.duplicate }

        let validChannel = positive(channelNumber)
        let diagnostics = AdvancedWiFiDiagnostics(
            schemaVersion: AdvancedWiFiDiagnostics.currentSchemaVersion,
            shortcutVersion: AdvancedWiFiDiagnostics.currentShortcutVersion,
            captureIdentifier: captureIdentifier,
            capturedAt: now,
            ssid: normalized(ssid, maximumLength: 64),
            accessPointIdentifier: localAccessPointIdentifier(for: bssid, defaults: defaults),
            wifiStandard: normalized(wifiStandard, maximumLength: 32),
            rxRateMbps: nonNegativeFinite(rxRateMbps),
            txRateMbps: nonNegativeFinite(txRateMbps),
            rssiDbm: finite(rssiDbm),
            noiseDbm: finite(noiseDbm),
            channelNumber: validChannel,
            bandGHz: AdvancedWiFiDiagnostics.bandGHz(forChannel: validChannel),
            snrDb: AdvancedWiFiDiagnostics.snrDb(rssiDbm: finite(rssiDbm), noiseDbm: finite(noiseDbm))
        )

        guard let encoded = try? JSONEncoder().encode(diagnostics) else {
            throw ImportError.invalidPayload
        }
        defaults.set(encoded, forKey: pendingKey)
        defaults.set(true, forKey: LinkaWiFiPreferences.advancedConfiguredKey)
        handled.insert(identifier)
        defaults.set(Array(handled.suffix(32)), forKey: handledIdentifiersKey)
        return diagnostics
    }

    static func takePending(now: Date = Date(), defaults: UserDefaults = .standard) -> AdvancedWiFiDiagnostics? {
        defer { defaults.removeObject(forKey: pendingKey) }
        guard let data = defaults.data(forKey: pendingKey),
              let diagnostics = try? JSONDecoder().decode(AdvancedWiFiDiagnostics.self, from: data),
              diagnostics.capturedAt >= now.addingTimeInterval(-pendingLifetime) else {
            return nil
        }
        return diagnostics
    }

    static func requeue(_ diagnostics: AdvancedWiFiDiagnostics, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(diagnostics) else { return }
        defaults.set(data, forKey: pendingKey)
    }

    static func removePending(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingKey)
    }

    /// Constrói uma captura nativa já sanitizada. Diferente do caminho de
    /// Atalhos, não grava inbox nem altera preferência: o chamador associa o
    /// objeto diretamente à medição que a pessoa acabou de iniciar.
    static func makeNativeDiagnostics(
        entitlement: LinkaEntitlementSnapshot,
        capturedAt: Date = Date(),
        ssid: String? = nil,
        bssid: String? = nil,
        txRateMbps: Double? = nil,
        rssiDbm: Double? = nil,
        channelNumber: Int? = nil,
        defaults: UserDefaults = .standard
    ) -> AdvancedWiFiDiagnostics? {
        guard LinkaWiFiPreferences.isAdvancedDiagnosticsEnabled,
              LinkaEntitlementPolicy.decision(
                for: .advancedWiFiDiagnostics,
                snapshot: entitlement,
                at: capturedAt
              ).isGranted else { return nil }

        guard let accessPointIdentifier = localAccessPointIdentifier(for: bssid, defaults: defaults) else {
            return nil
        }
        let validChannel = positive(channelNumber)
        return AdvancedWiFiDiagnostics(
            capturedAt: capturedAt,
            ssid: normalized(ssid, maximumLength: 64),
            accessPointIdentifier: accessPointIdentifier,
            txRateMbps: nonNegativeFinite(txRateMbps),
            rssiDbm: finite(rssiDbm),
            channelNumber: validChannel,
            bandGHz: AdvancedWiFiDiagnostics.bandGHz(forChannel: validChannel)
        )
    }

    private static func normalized(_ value: String?, maximumLength: Int) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= maximumLength else { return nil }
        return value
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func nonNegativeFinite(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }

    private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func localAccessPointIdentifier(for bssid: String?, defaults: UserDefaults) -> String? {
        guard let bssid = normalized(bssid, maximumLength: 17),
              bssid.range(of: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$", options: .regularExpression) != nil else {
            return nil
        }
        let salt: String
        if let saved = defaults.string(forKey: accessPointSaltKey) {
            salt = saved
        } else {
            salt = UUID().uuidString
            defaults.set(salt, forKey: accessPointSaltKey)
        }
        let digest = SHA256.hash(data: Data("\(salt)|\(bssid.lowercased())".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// Ação que o atalho oficial usa após `Obter detalhes da rede`. O JSON é um
// parâmetro padrão suportado por App Intents e mantém a composição dentro do
// app Atalhos; não há API privada, serviço intermediário ou segredo na URL.
#if os(iOS)
private enum ShortcutEntitlementSnapshot {
    static func current() async -> LinkaEntitlementSnapshot {
        #if DEBUG
        // O App Intent roda fora da árvore SwiftUI e, por isso, não recebe o
        // provider usado pela tela de Ajustes. Mantém o override de teste
        // alinhado ao app sem expô-lo em builds de distribuição.
        let forcePlusKey = await StoreKitEntitlementProvider.forcePlusKey
        if UserDefaults.standard.bool(forKey: forcePlusKey) {
            return .plus(status: .active, source: .promotion)
        }
        #endif

        var verifiedPurchase: LinkaEntitlementSnapshot?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  LinkaStoreProductID.all.contains(transaction.productID) else { continue }
            verifiedPurchase = .plus(status: .active, source: .subscription, validUntil: transaction.expirationDate)
            break
        }
        return LinkaEntitlementSnapshotResolver.resolve(verifiedPurchase: verifiedPurchase)
    }
}

struct ImportWiFiDiagnosticsIntent: AppIntent {
    static var title: LocalizedStringResource { "Importar diagnóstico Wi-Fi" }
    static let description = IntentDescription("Importa dados Wi-Fi medidos pelo atalho Linka Wi-Fi Advanced.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Payload de diagnóstico")
    var payloadJSON: String

    init() {}

    init(payloadJSON: String) {
        self.payloadJSON = payloadJSON
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Importar \(\.$payloadJSON)")
    }

    func perform() async throws -> some IntentResult {
        let snapshot = await ShortcutEntitlementSnapshot.current()
        _ = try AdvancedWiFiDiagnosticsInbox.importPayload(payloadJSON, entitlement: snapshot)
        await MainActor.run {
            AppIntentCoordinator.shared.requestAdvancedWiFiDiagnosticsImport()
        }
        return .result()
    }

}

struct RegisterAdvancedWiFiDiagnosticsIntent: AppIntent {
    static var title: LocalizedStringResource { "Registrar diagnóstico Wi-Fi avançado" }
    static let description = IntentDescription("Recebe dados Wi-Fi do Atalhos e prepara o Linka para associá-los à próxima medição.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Nome da rede")
    var ssid: String?

    @Parameter(title: "BSSID")
    var bssid: String?

    @Parameter(title: "Padrão Wi-Fi")
    var wifiStandard: String?

    @Parameter(title: "Taxa RX")
    var rxRateMbps: Double?

    @Parameter(title: "Taxa TX")
    var txRateMbps: Double?

    @Parameter(title: "RSSI")
    var rssiDbm: Double?

    @Parameter(title: "Ruído")
    var noiseDbm: Double?

    @Parameter(title: "Canal")
    var channelNumber: Int?

    init() {}

    init(
        ssid: String? = nil,
        bssid: String? = nil,
        wifiStandard: String? = nil,
        rxRateMbps: Double? = nil,
        txRateMbps: Double? = nil,
        rssiDbm: Double? = nil,
        noiseDbm: Double? = nil,
        channelNumber: Int? = nil
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.wifiStandard = wifiStandard
        self.rxRateMbps = rxRateMbps
        self.txRateMbps = txRateMbps
        self.rssiDbm = rssiDbm
        self.noiseDbm = noiseDbm
        self.channelNumber = channelNumber
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar diagnóstico Wi-Fi avançado")
    }

    func perform() async throws -> some IntentResult {
        let snapshot = await ShortcutEntitlementSnapshot.current()
        _ = try AdvancedWiFiDiagnosticsInbox.importFields(
            entitlement: snapshot,
            ssid: ssid,
            bssid: bssid,
            wifiStandard: wifiStandard,
            rxRateMbps: rxRateMbps,
            txRateMbps: txRateMbps,
            rssiDbm: rssiDbm,
            noiseDbm: noiseDbm,
            channelNumber: channelNumber
        )
        await MainActor.run {
            AppIntentCoordinator.shared.requestAdvancedWiFiDiagnosticsImport()
        }
        return .result()
    }

}
#endif
