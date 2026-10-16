import XCTest
import SwiftUI
import NetworkCore
@testable import LinkaApp

/// Cobertura do contrato de ciclo de vida da issue #65: backgrounding
/// durante uma medição em andamento nunca deixa o motor em estado
/// indefinido, nunca mostra um resultado completo que não foi medido por
/// completo, e sempre preserva o último resultado válido da sessão.
///
/// Estes testes chamam `handleScenePhaseChange(_:)` diretamente no
/// `SpeedTestViewModel` — ele é um `ObservableObject` comum, não precisa de
/// UI real nem de simulador rodando pra exercitar a lógica de decisão
/// (ver nota de Guinho no `plano.md` da issue #65). O que eles NÃO cobrem:
/// a interação real com `SpeedTestCore` (rede real) e com o
/// `FileMeasurementHistoryRepository` (disco real) durante um cancelamento
/// em andamento — isso segue como verificação manual (ver PR desta issue),
/// não automatizada, para não depender de rede/IO real em teste unitário.
@MainActor
final class SpeedTestViewModelScenePhaseTests: XCTestCase {

    private func makeSnapshot(
        downloadSpeed: Double = 87.3
    ) -> SpeedTestViewModel.ResultSnapshot {
        SpeedTestViewModel.ResultSnapshot(
            downloadSpeed: downloadSpeed,
            uploadSpeed: 21.4,
            ping: 14,
            jitter: 1.2,
            provider: "Provedor Teste",
            networkType: "Wi-Fi",
            testDuration: "9,8s",
            packetLossPercent: 0.0,
            connectionKind: .wifi,
            wifiBandGHz: 5.0
        )
    }

    func test_cancelDuringRetest_returnsToHomeInsteadOfRestoringResult() {
        let viewModel = SpeedTestViewModel()
        viewModel.lastValidResultSnapshot = makeSnapshot(downloadSpeed: 87.3)
        viewModel.uiPhase = .downloading
        viewModel.isTesting = true
        viewModel.downloadSpeed = 4.2
        viewModel.progress = 0.4

        viewModel.skipOrCancel()

        XCTAssertEqual(viewModel.uiPhase, .idle)
        XCTAssertFalse(viewModel.isTesting)
        XCTAssertEqual(viewModel.progress, 0)
    }

    // MARK: - .background durante medição em andamento, SEM snapshot válido

    func test_background_duringDownload_withoutSnapshot_goesIdle() {
        let viewModel = SpeedTestViewModel()
        viewModel.uiPhase = .downloading
        viewModel.isTesting = true
        XCTAssertNil(viewModel.lastValidResultSnapshot)

        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.uiPhase, .idle)
        XCTAssertFalse(viewModel.isTesting)
        XCTAssertNil(viewModel.failureReason)
    }

    func test_background_duringUpload_withoutSnapshot_goesIdle() {
        let viewModel = SpeedTestViewModel()
        viewModel.uiPhase = .uploading
        viewModel.isTesting = true
        XCTAssertNil(viewModel.lastValidResultSnapshot)

        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.uiPhase, .idle)
        XCTAssertFalse(viewModel.isTesting)
    }

    func test_background_duringConnecting_withoutSnapshot_goesIdle() {
        let viewModel = SpeedTestViewModel()
        viewModel.uiPhase = .connecting
        viewModel.isTesting = true

        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.uiPhase, .idle)
        XCTAssertFalse(viewModel.isTesting)
    }

    // MARK: - .background durante medição em andamento, COM snapshot válido

    func test_background_duringDownload_withSnapshot_goesIdle() {
        let viewModel = SpeedTestViewModel()
        let snapshot = makeSnapshot(downloadSpeed: 87.3)
        viewModel.lastValidResultSnapshot = snapshot
        viewModel.uiPhase = .downloading
        viewModel.isTesting = true
        viewModel.downloadSpeed = 3.1

        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.uiPhase, .idle)
        XCTAssertFalse(viewModel.isTesting)
        XCTAssertEqual(viewModel.progress, 0.0)
    }

    func test_background_duringUpload_withSnapshot_goesIdle() {
        let viewModel = SpeedTestViewModel()
        let snapshot = makeSnapshot(downloadSpeed: 55.0)
        viewModel.lastValidResultSnapshot = snapshot
        viewModel.uiPhase = .uploading
        viewModel.isTesting = true

        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.uiPhase, .idle)
        XCTAssertFalse(viewModel.isTesting)
        XCTAssertEqual(viewModel.progress, 0.0)
    }

    // MARK: - .background em estado terminal (.done/.error) não mexe em nada

    func test_background_whileDone_doesNothing() {
        let viewModel = SpeedTestViewModel()
        let snapshot = makeSnapshot()
        viewModel.lastValidResultSnapshot = snapshot
        viewModel.uiPhase = .done
        viewModel.isTesting = false
        viewModel.downloadSpeed = snapshot.downloadSpeed

        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.uiPhase, .done)
        XCTAssertEqual(viewModel.downloadSpeed, snapshot.downloadSpeed)
    }

    func test_background_whileError_doesNothing() {
        let viewModel = SpeedTestViewModel()
        viewModel.uiPhase = .error
        viewModel.isTesting = false

        viewModel.handleScenePhaseChange(.background)

        XCTAssertEqual(viewModel.uiPhase, .error)
    }

    // MARK: - .inactive isolado (blip transitório) nunca cancela nada

    func test_inactive_duringDownload_doesNotCancel() {
        let viewModel = SpeedTestViewModel()
        viewModel.uiPhase = .downloading
        viewModel.isTesting = true

        viewModel.handleScenePhaseChange(.inactive)

        XCTAssertEqual(viewModel.uiPhase, .downloading)
        XCTAssertTrue(viewModel.isTesting)
    }

    func test_inactive_duringUpload_doesNotCancel() {
        let viewModel = SpeedTestViewModel()
        viewModel.uiPhase = .uploading
        viewModel.isTesting = true

        viewModel.handleScenePhaseChange(.inactive)

        XCTAssertEqual(viewModel.uiPhase, .uploading)
        XCTAssertTrue(viewModel.isTesting)
    }

    /// Sequência realista de um blip transitório (permission prompt, ad
    /// interstitial, share sheet): `.active` → `.inactive` → `.active`,
    /// sem nunca passar por `.background`. Nada deve mudar.
    func test_inactiveThenActive_withoutBackground_isNoOp() {
        let viewModel = SpeedTestViewModel()
        viewModel.uiPhase = .downloading
        viewModel.isTesting = true

        viewModel.handleScenePhaseChange(.inactive)
        viewModel.handleScenePhaseChange(.active)

        XCTAssertEqual(viewModel.uiPhase, .downloading)
        XCTAssertTrue(viewModel.isTesting)
    }

    // MARK: - Retorno a .active nunca inicia uma medição sozinho

    func test_active_afterIdleFromBackground_staysReadyForExplicitTest() {
        let viewModel = SpeedTestViewModel()
        viewModel.uiPhase = .downloading
        viewModel.isTesting = true

        viewModel.handleScenePhaseChange(.background)
        XCTAssertEqual(viewModel.uiPhase, .idle)

        viewModel.handleScenePhaseChange(.active)

        XCTAssertEqual(viewModel.uiPhase, .idle)
        XCTAssertFalse(viewModel.isTesting)
    }

    /// Retorno a `.active` quando o teste foi cancelado por backgrounding
    /// NÃO deve reiniciar sozinho; o estado `.idle` permanece pronto
    /// para uma ação explícita da pessoa.
    func test_active_afterBackgroundDuringTest_staysIdleAndDoesNotRestart() {
        let viewModel = SpeedTestViewModel()
        let snapshot = makeSnapshot()
        viewModel.lastValidResultSnapshot = snapshot
        viewModel.uiPhase = .downloading
        viewModel.isTesting = true

        viewModel.handleScenePhaseChange(.background)
        XCTAssertEqual(viewModel.uiPhase, .idle)

        viewModel.handleScenePhaseChange(.active)

        XCTAssertEqual(viewModel.uiPhase, .idle)
        XCTAssertFalse(viewModel.isTesting)
    }

    func test_connectionChange_discardsPartialMeasurementAndRequiresExplicitNewTest() {
        let viewModel = SpeedTestViewModel()
        viewModel.uiPhase = .downloading
        viewModel.isTesting = true
        viewModel.downloadSpeed = 87.3
        viewModel.uploadSpeed = 21.4
        viewModel.progress = 0.6

        viewModel.cancelForConnectionChange()

        XCTAssertEqual(viewModel.uiPhase, .connectionChanged)
        XCTAssertFalse(viewModel.isTesting)
        XCTAssertEqual(viewModel.progress, 0)
        XCTAssertEqual(viewModel.downloadSpeed, 0)
        XCTAssertEqual(viewModel.uploadSpeed, 0)
        XCTAssertNil(viewModel.latestFinishedMeasurement)
    }

    func test_wifiSSIDChangeWithoutInterfaceChangeClearsLiveWindowBaselineAndReport() async {
        let viewModel = SpeedTestViewModel()
        viewModel.stopLivePolling()
        viewModel.liveConnectionKind = .wifi
        viewModel.reconcileLiveUsageNetworkIdentity(for: "Casa")
        viewModel.liveTelemetryCollector.recordProbe(rttMs: 12)
        viewModel.liveTelemetryCollector.recordProbe(rttMs: 14)
        viewModel.liveTelemetryCollector.recordProbe(rttMs: 13)
        viewModel.currentThroughputBaseline = ThroughputBaseline(
            downloadMbps: 300,
            uploadMbps: 40,
            lastMeasuredAt: Date(),
            networkIdentifier: "Casa"
        )
        await viewModel.refreshLiveUsageSuitability()
        XCTAssertNotNil(viewModel.liveUsageReport)

        // O NWPathMonitor pode continuar em `.wifi`; o SSID reamostrado pelo
        // polling ainda precisa invalidar toda evidência da Casa.
        viewModel.reconcileLiveUsageNetworkIdentity(for: "Outra")

        XCTAssertEqual(viewModel.liveUsageWiFiSSID, "Outra")
        XCTAssertNil(viewModel.currentThroughputBaseline)
        XCTAssertNil(viewModel.liveUsageReport)
        XCTAssertEqual(
            viewModel.liveTelemetryCollector.snapshot(
                connectionKind: .wifi,
                interfaceLabel: "Outra"
            ).sampleCount,
            0
        )
    }
}
