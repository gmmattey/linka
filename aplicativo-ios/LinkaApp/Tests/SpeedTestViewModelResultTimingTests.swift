import XCTest
import Combine
import NetworkCore
import LinkaEngine
import LinkaEntitlements
@testable import LinkaApp

/// Cobertura do requisito de aceite da issue #88: no instante síncrono em
/// que `uiPhase` publica `.done`, `connectionKind`/`wifiBandGHz` já
/// refletem o valor final resolvido — nenhum observador consegue capturar
/// `uiPhase == .done` com esses campos ainda `nil` por causa do teste em si.
///
/// `engine` (`SpeedTestCore`) não é injetável em `SpeedTestViewModel`, então
/// não dá pra exercitar `startTest()` fim-a-fim aqui sem rede real. Em vez
/// disso, este arquivo cobre `processResultState(_:startingKind:endingKind:
/// generation:)` — o método `internal` que `startTest()` chama, dentro do
/// loop de consumo do stream, exatamente na ordem de produção: resolve
/// connectionKind/wifiBandGHz primeiro, só depois publica o state via
/// `update(with:)` (que marca `uiPhase = .done`). Ver nota de Guinho no
/// `plano.md` da issue #88 — mesma extração mínima usada em #65 para
/// `handleScenePhaseChange`.
@MainActor
final class SpeedTestViewModelResultTimingTests: XCTestCase {

    func test_liveCellularNetworkLabel_ignoresSystemCarrierPlaceholder() {
        XCTAssertEqual(
            SpeedTestViewModel.liveCellularNetworkLabel(operatorName: "--", technology: "5G"),
            "5G"
        )
        XCTAssertEqual(
            SpeedTestViewModel.liveCellularNetworkLabel(operatorName: "Vivo", technology: "5G"),
            "Vivo · 5G"
        )
        XCTAssertEqual(
            SpeedTestViewModel.liveCellularNetworkLabel(operatorName: "—", technology: nil),
            LinkaCopy.value("network.cellular")
        )
    }

    func test_advancedWiFiInboxValidatesAndDerivesOnlyLocalAccessPointIdentifier() throws {
        let suite = "linka-issue-134-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("suite de teste indisponível") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(-60)
        let entitlement = LinkaEntitlementSnapshotResolver.resolve(at: now, promotionSupported: true)
        XCTAssertTrue(LinkaEntitlementPolicy.shouldShowAds(for: entitlement, at: now))
        let payload = """
        {"schemaVersion":1,"shortcutVersion":1,"captureIdentifier":"550E8400-E29B-41D4-A716-446655440000","capturedAt":"\(ISO8601DateFormatter().string(from: now))","ssid":"Casa","bssid":"AA:BB:CC:DD:EE:FF","hardwareMacAddress":"11:22:33:44:55:66","rssiDbm":-54,"noiseDbm":-92,"channelNumber":44}
        """

        let diagnostics = try AdvancedWiFiDiagnosticsInbox.importPayload(
            payload,
            entitlement: entitlement,
            now: now,
            defaults: defaults
        )

        XCTAssertNotNil(diagnostics.accessPointIdentifier)
        XCTAssertEqual(diagnostics.snrDb, 38)
        let stored = try XCTUnwrap(defaults.data(forKey: "linka.advanced-wifi.pending.v1"))
        let json = String(decoding: stored, as: UTF8.self)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("AA:BB:CC:DD:EE:FF"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("11:22:33:44:55:66"))
    }

    func test_advancedWiFiInboxImportsTypedShortcutFields() throws {
        let suite = "linka-issue-134-typed-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("suite de teste indisponível") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let captureIdentifier = UUID()
        let now = LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(-60)
        let entitlement = LinkaEntitlementSnapshotResolver.resolve(at: now, promotionSupported: true)
        XCTAssertTrue(LinkaEntitlementPolicy.shouldShowAds(for: entitlement, at: now))

        let diagnostics = try AdvancedWiFiDiagnosticsInbox.importFields(
            entitlement: entitlement,
            now: now,
            defaults: defaults,
            captureIdentifier: captureIdentifier,
            ssid: "Casa",
            bssid: "AA:BB:CC:DD:EE:FF",
            wifiStandard: "Wi-Fi 6",
            rxRateMbps: 720,
            txRateMbps: 866,
            rssiDbm: -54,
            noiseDbm: -92,
            channelNumber: 44
        )

        XCTAssertEqual(diagnostics.captureIdentifier, captureIdentifier)
        XCTAssertEqual(diagnostics.ssid, "Casa")
        XCTAssertEqual(diagnostics.wifiStandard, "Wi-Fi 6")
        XCTAssertEqual(diagnostics.rxRateMbps, 720)
        XCTAssertEqual(diagnostics.txRateMbps, 866)
        XCTAssertEqual(diagnostics.rssiDbm, -54)
        XCTAssertEqual(diagnostics.noiseDbm, -92)
        XCTAssertEqual(diagnostics.channelNumber, 44)
        XCTAssertEqual(diagnostics.bandGHz, 5)
        XCTAssertEqual(diagnostics.snrDb, 38)
        XCTAssertNotNil(diagnostics.accessPointIdentifier)
        XCTAssertTrue(defaults.bool(forKey: LinkaWiFiPreferences.advancedConfiguredKey))

        let stored = try XCTUnwrap(defaults.data(forKey: "linka.advanced-wifi.pending.v1"))
        let json = String(decoding: stored, as: UTF8.self)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("AA:BB:CC:DD:EE:FF"))
    }

    func test_advancedWiFiInboxRejectsFreeExpiredAndDuplicatePayload() throws {
        let suite = "linka-issue-134-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("suite de teste indisponível") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let payload = """
        {"schemaVersion":1,"shortcutVersion":1,"captureIdentifier":"550E8400-E29B-41D4-A716-446655440000","capturedAt":"\(ISO8601DateFormatter().string(from: now))"}
        """
        XCTAssertThrowsError(try AdvancedWiFiDiagnosticsInbox.importPayload(payload, entitlement: .free, now: now, defaults: defaults))
        _ = try AdvancedWiFiDiagnosticsInbox.importPayload(payload, entitlement: .plus(status: .active, source: .promotion), now: now, defaults: defaults)
        XCTAssertThrowsError(try AdvancedWiFiDiagnosticsInbox.importPayload(payload, entitlement: .plus(status: .active, source: .promotion), now: now, defaults: defaults))
    }

    func test_advancedWiFiInboxRejectsShortcutAfterIntegrationWasDisabled() {
        let suite = "linka-issue-135-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("suite de teste indisponível") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: LinkaWiFiPreferences.advancedDiagnosticsEnabledKey)
        let payload = "{\"schemaVersion\":1,\"shortcutVersion\":1,\"captureIdentifier\":\"550E8400-E29B-41D4-A716-446655440000\",\"capturedAt\":\"\(ISO8601DateFormatter().string(from: Date()))\"}"

        XCTAssertThrowsError(
            try AdvancedWiFiDiagnosticsInbox.importPayload(
                payload,
                entitlement: .plus(status: .active, source: .promotion),
                defaults: defaults
            )
        ) { error in
            XCTAssertEqual(error as? AdvancedWiFiDiagnosticsInbox.ImportError, .integrationDisabled)
        }
    }

    private func resultState() -> MeasurementState {
        MeasurementState(
            ping: 14,
            jitter: 1.2,
            packetLossPercent: 0.0,
            downloadSpeed: 87.3,
            uploadSpeed: 21.4,
            progress: 1.0,
            phase: .result,
            provider: "Provedor Teste",
            networkType: .wifi,
            duration: 9.8
        )
    }

    /// Aceite #1 e #5: no exato instante em que o subscriber de `$uiPhase`
    /// observa `.done`, `connectionKind` já não é `nil` — não é uma leitura
    /// assíncrona subsequente que só por acaso encontra o valor certo
    /// depois.
    ///
    /// Não afirma `wifiBandGHz` não-nulo aqui de propósito: no iPhone (sem
    /// `CoreWLAN`) `nil` é o estado normal mesmo em Wi-Fi — ver
    /// `ApplePlatformSignalProvider.currentWifiBandGHz()`. O teste de
    /// ordenação para `wifiBandGHz` (que ele foi *reatribuído*, não deixado
    /// com um valor obsoleto) vive no teste seguinte, com um sentinela.
    func test_finalConnectionKind_resolvedBeforeUiPhasePublishesDone() {
        let viewModel = SpeedTestViewModel()
        var sawDone = false
        var connectionKindWhenDone: NetworkConnectionKind?

        let cancellable = viewModel.$uiPhase.sink { phase in
            if phase == .done {
                sawDone = true
                connectionKindWhenDone = viewModel.connectionKind
            }
        }
        defer { cancellable.cancel() }

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .wifi,
            generation: 0 // testGeneration nunca foi incrementado (init padrão)
        )

        XCTAssertTrue(sawDone, "o subscriber precisa ter observado uiPhase == .done")
        XCTAssertEqual(viewModel.uiPhase, .done)
        XCTAssertNotNil(connectionKindWhenDone, "connectionKind não pode estar nil no instante em que uiPhase == .done")
        XCTAssertEqual(connectionKindWhenDone, .wifi)
    }

    /// Aceite #1 e #5, complemento pra `wifiBandGHz`: mesmo quando a
    /// plataforma não confirma banda (iPhone, sem `CoreWLAN` — `nil` é
    /// estado normal), o campo precisa ter sido *reatribuído* (resolvido)
    /// antes de `uiPhase` publicar `.done`, nunca deixado com um valor
    /// obsoleto de um teste anterior. Um sentinela antes da chamada prova
    /// isso independente do valor real que a plataforma devolve.
    func test_wifiBandGHz_reassignedBeforeUiPhasePublishesDone_neverStale() {
        let viewModel = SpeedTestViewModel()
        let staleSentinel = 999.9
        viewModel.wifiBandGHz = staleSentinel
        var sawDone = false
        var wifiBandGHzWhenDone: Double?

        let cancellable = viewModel.$uiPhase.sink { phase in
            if phase == .done {
                sawDone = true
                wifiBandGHzWhenDone = viewModel.wifiBandGHz
            }
        }
        defer { cancellable.cancel() }

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .wifi,
            generation: 0
        )

        XCTAssertTrue(sawDone, "o subscriber precisa ter observado uiPhase == .done")
        XCTAssertNotEqual(
            wifiBandGHzWhenDone,
            staleSentinel,
            "wifiBandGHz precisa ter sido reatribuído (a valor real ou nil) antes de uiPhase == .done, nunca deixado com o valor obsoleto do teste anterior"
        )
    }

    /// Troca de rede no meio do teste continua produzindo `nil` (aceite #1
    /// e #2) — `NetworkConnectionKind.resolve(start:end:)` continua a única
    /// fonte que decide isso, sem lógica duplicada aqui.
    func test_networkChangedDuringTest_connectionKindStaysNil() {
        let viewModel = SpeedTestViewModel()

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .cellular,
            generation: 0
        )

        XCTAssertEqual(viewModel.uiPhase, .done)
        XCTAssertNil(viewModel.connectionKind)
        XCTAssertNil(viewModel.wifiBandGHz)
    }

    func test_wifiContextIsPersistableOnlyWhenSSIDMatchesAcrossMeasurement() {
        let viewModel = SpeedTestViewModel()
        let start = WiFiNetworkContext(ssid: "Casa", accessPointIdentifier: "ap-1", securityType: .personal)
        let end = WiFiNetworkContext(ssid: "Casa", accessPointIdentifier: "ap-2", securityType: .personal)

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .wifi,
            startingWiFiContext: start,
            endingWiFiContext: end,
            generation: 0
        )

        XCTAssertEqual(viewModel.wifiContext?.ssid, "Casa")
        XCTAssertNil(viewModel.wifiContext?.accessPointIdentifier, "roaming não escolhe um BSSID")
    }

    func test_ssidChangeDuringMeasurementLeavesWiFiContextAbsent() {
        let viewModel = SpeedTestViewModel()

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .wifi,
            startingWiFiContext: WiFiNetworkContext(ssid: "Casa"),
            endingWiFiContext: WiFiNetworkContext(ssid: "Trabalho"),
            generation: 0
        )

        XCTAssertNil(viewModel.wifiContext)
    }

    func test_advancedWiFiDiagnosticsPersistsOnlyForMatchingWiFiMeasurement() {
        let viewModel = SpeedTestViewModel()
        let advanced = AdvancedWiFiDiagnostics(
            capturedAt: Date(),
            ssid: "Casa",
            accessPointIdentifier: "ap-1",
            rssiDbm: -54,
            noiseDbm: -92,
            snrDb: 38
        )

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .wifi,
            startingWiFiContext: WiFiNetworkContext(ssid: "Casa", accessPointIdentifier: "ap-1"),
            endingWiFiContext: WiFiNetworkContext(ssid: "Casa", accessPointIdentifier: "ap-1"),
            advancedWiFiDiagnostics: advanced,
            generation: 0
        )

        XCTAssertEqual(viewModel.advancedWiFiDiagnostics, advanced)
    }

    func test_advancedWiFiDiagnosticsRejectsConflictingSSID() {
        let viewModel = SpeedTestViewModel()
        let advanced = AdvancedWiFiDiagnostics(capturedAt: Date(), ssid: "Trabalho")

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .wifi,
            startingWiFiContext: WiFiNetworkContext(ssid: "Casa"),
            endingWiFiContext: WiFiNetworkContext(ssid: "Casa"),
            advancedWiFiDiagnostics: advanced,
            generation: 0
        )

        XCTAssertNil(viewModel.advancedWiFiDiagnostics)
    }

    func test_nativeAdvancedWiFiDiagnosticsRejectsCaptureWithoutMatchingAccessPoint() {
        let viewModel = SpeedTestViewModel()
        let advanced = AdvancedWiFiDiagnostics(
            capturedAt: Date(),
            accessPointIdentifier: "captured-ap",
            rssiDbm: -54
        )

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .wifi,
            startingWiFiContext: WiFiNetworkContext(accessPointIdentifier: "measured-ap"),
            endingWiFiContext: WiFiNetworkContext(accessPointIdentifier: "measured-ap"),
            advancedWiFiDiagnostics: advanced,
            generation: 0
        )

        XCTAssertNil(viewModel.advancedWiFiDiagnostics)
    }

    func test_nativeAdvancedWiFiDiagnosticsRequiresBSSIDForAPVerification() {
        let diagnostics = AdvancedWiFiDiagnosticsInbox.makeNativeDiagnostics(
            entitlement: .plus(status: .active, source: .promotion),
            rssiDbm: -54
        )

        XCTAssertNil(diagnostics)
    }

    /// Rede não-Wi-Fi nunca carrega banda (aceite #1: `nil` é resultado
    /// legítimo quando não é Wi-Fi).
    func test_cellularConnection_wifiBandGHzStaysNil() {
        let viewModel = SpeedTestViewModel()

        viewModel.processResultState(
            resultState(),
            startingKind: .cellular,
            endingKind: .cellular,
            generation: 0
        )

        XCTAssertEqual(viewModel.uiPhase, .done)
        XCTAssertEqual(viewModel.connectionKind, .cellular)
        XCTAssertNil(viewModel.wifiBandGHz)
    }

    /// Aceite #3: a guarda por geração continua protegendo o ponto de
    /// assignment — se a geração passada não bate mais com a corrente
    /// (equivalente a um `skipOrCancel()`/novo `startTest()` que avançou
    /// `testGeneration` durante os ~100ms de amostragem final), esta
    /// execução não deve escrever `connectionKind`/`wifiBandGHz` por baixo
    /// de quem é dono deles agora — mas o state ainda é publicado via
    /// `update(with:)` (mesmo comportamento de antes desta issue).
    func test_staleGeneration_doesNotOverwriteConnectionKind() {
        let viewModel = SpeedTestViewModel()
        // Simula uma T2 já em andamento, dona de connectionKind == nil por
        // ter acabado de reiniciar o teste.
        viewModel.connectionKind = nil
        viewModel.wifiBandGHz = nil

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .wifi,
            generation: -1 // geração que nunca vai bater com testGeneration (0 por padrão)
        )

        XCTAssertNil(viewModel.connectionKind)
        XCTAssertNil(viewModel.wifiBandGHz)
    }

    func test_processResultState_populatesLatestFinishedMeasurementSynchronouslyWithDonePhase() {
        let viewModel = SpeedTestViewModel()
        XCTAssertNil(viewModel.latestFinishedMeasurement)

        viewModel.processResultState(
            resultState(),
            startingKind: .wifi,
            endingKind: .wifi,
            startingWiFiContext: WiFiNetworkContext(ssid: "Casa"),
            endingWiFiContext: WiFiNetworkContext(ssid: "Casa"),
            generation: 0
        )

        XCTAssertEqual(viewModel.uiPhase, .done)
        XCTAssertNotNil(viewModel.latestFinishedMeasurement)
        XCTAssertEqual(viewModel.latestFinishedMeasurement?.outcome, .complete)
        XCTAssertEqual(viewModel.latestFinishedMeasurement?.downloadMbps, 87.3)
        XCTAssertEqual(viewModel.latestFinishedMeasurement?.connectionKind, .wifi)
    }
}
