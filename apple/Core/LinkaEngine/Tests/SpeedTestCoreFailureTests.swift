import XCTest
@testable import LinkaEngine

/// Cobre o estado de erro explícito do motor (issue #66): o motor
/// diferencia falha transitória (retry silencioso, motor segue sozinho) de
/// falha fatal (para, cancela, devolve um fato tipado — nunca um número
/// inventado).
///
/// A checagem de offline é testável de ponta a ponta via `runTest()` porque
/// ela retorna antes de qualquer request de rede quando `pathStatusProvider`
/// injetado reporta ausência de conectividade. Já a decisão de abortar por
/// falha fatal *durante* download/upload não tem ponto de injeção de
/// transporte hoje (mesma limitação documentada em `SpeedTestCoreTests` para
/// as fases reais) — por isso as peças puras que a compõem
/// (`isFatalTransportError`, `shouldAbortPhase`, `errorState`) são
/// exercitadas diretamente, com o mesmo padrão `nonisolated static` já usado
/// para `hasConverged`/`shouldStopPhase` (issue #62).
final class SpeedTestCoreFailureTests: XCTestCase {

    private struct StubPathStatusProvider: PathStatusProvider {
        let connected: Bool
        func hasConnectivity() async -> Bool { connected }
    }

    /// Nunca deve ser chamado nos testes desta classe — a checagem de
    /// offline retorna antes do enriquecimento de provedor entrar em jogo.
    private struct UnusedOrgLookup: ProviderOrgLookup {
        func fetchOrg() async throws -> String? {
            XCTFail("providerLookup não deveria ser chamado quando offline")
            return nil
        }
    }

    // MARK: - Cenário 1: offline inicial (via provider injetável)

    func test_runTest_offlineAtStart_yieldsSingleErrorStateAndFinishesWithoutThrowing() async throws {
        let engine = SpeedTestCore(
            providerLookup: UnusedOrgLookup(),
            pathStatusProvider: StubPathStatusProvider(connected: false)
        )

        var received: [MeasurementState] = []
        for try await state in await engine.runTest() {
            received.append(state)
        }

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.phase, .error)
        XCTAssertEqual(received.first?.failureReason, .offline)
    }

    // MARK: - isFatalTransportError

    func test_isFatalTransportError_classifiesTransportLossCodesAsFatal() {
        XCTAssertTrue(SpeedTestCore.isFatalTransportError(URLError(.notConnectedToInternet)))
        XCTAssertTrue(SpeedTestCore.isFatalTransportError(URLError(.networkConnectionLost)))
        XCTAssertTrue(SpeedTestCore.isFatalTransportError(URLError(.cannotConnectToHost)))
        XCTAssertTrue(SpeedTestCore.isFatalTransportError(URLError(.cannotFindHost)))
        XCTAssertTrue(SpeedTestCore.isFatalTransportError(URLError(.dataNotAllowed)))
    }

    func test_isFatalTransportError_classifiesTimeoutAsRecoverableNotFatal() {
        // Timeout é tratado como recuperável — junto com 429/5xx (por status
        // code, não por URLError), o motor segue tentando sem abortar.
        XCTAssertFalse(SpeedTestCore.isFatalTransportError(URLError(.timedOut)))
    }

    // MARK: - shouldAbortPhase

    func test_shouldAbortPhase_thresholdReachedWithZeroBytes_aborts() {
        let result = SpeedTestCore.shouldAbortPhase(consecutiveFatalErrors: 6, bytesTransferred: 0)

        XCTAssertTrue(result)
    }

    func test_shouldAbortPhase_belowThreshold_doesNotAbortEvenWithZeroBytes() {
        let result = SpeedTestCore.shouldAbortPhase(consecutiveFatalErrors: 1, bytesTransferred: 0)

        XCTAssertFalse(result)
    }

    /// Teste negativo (regressão): erro isolado numa fase que já entrega
    /// throughput real nunca aborta — nem mesmo se a contagem de falhas
    /// fatais consecutivas atingisse o piso, bytes já transferidos vencem.
    func test_shouldAbortPhase_isolatedErrorWithThroughputFlowing_neverAborts() {
        let isolatedError = SpeedTestCore.shouldAbortPhase(consecutiveFatalErrors: 1, bytesTransferred: 5_000_000)
        let manyErrorsButDataFlowed = SpeedTestCore.shouldAbortPhase(consecutiveFatalErrors: 50, bytesTransferred: 1)

        XCTAssertFalse(isolatedError)
        XCTAssertFalse(manyErrorsButDataFlowed)
    }

    // MARK: - errorState

    /// Cenário 2: falha fatal durante download preserva ping/jitter já
    /// capturados na fase anterior.
    func test_errorState_fatalFailureDuringDownload_preservesPingAndJitterAlreadyCaptured() {
        var state = MeasurementState(ping: 42.0, jitter: 3.5, packetLossPercent: 0.0, phase: .download)
        state.networkType = .wifi

        let errored = SpeedTestCore.errorState(preserving: state, reason: .connectionLost(phase: .download))

        XCTAssertEqual(errored.phase, .error)
        XCTAssertEqual(errored.failureReason, .connectionLost(phase: .download))
        XCTAssertEqual(errored.ping, 42.0)
        XCTAssertEqual(errored.jitter, 3.5)
        XCTAssertEqual(errored.packetLossPercent, 0.0)
        XCTAssertEqual(errored.networkType, .wifi)
        XCTAssertNil(errored.downloadSpeed)
    }

    /// Cenário 3: falha fatal durante upload preserva o download já medido
    /// (além de ping/jitter da fase anterior a ele).
    func test_errorState_fatalFailureDuringUpload_preservesDownloadAlreadyMeasured() {
        var state = MeasurementState(ping: 40.0, jitter: 2.0, downloadSpeed: 87.3, phase: .upload)
        state.provider = "Vivo"

        let errored = SpeedTestCore.errorState(preserving: state, reason: .connectionLost(phase: .upload))

        XCTAssertEqual(errored.phase, .error)
        XCTAssertEqual(errored.failureReason, .connectionLost(phase: .upload))
        XCTAssertEqual(errored.downloadSpeed, 87.3)
        XCTAssertEqual(errored.ping, 40.0)
        XCTAssertEqual(errored.jitter, 2.0)
        XCTAssertEqual(errored.provider, "Vivo")
        XCTAssertNil(errored.uploadSpeed)
    }

    func test_errorState_offline_marksErrorWithoutInventingAnyMeasuredValue() {
        let state = MeasurementState(progress: 0.0, phase: .ping)

        let errored = SpeedTestCore.errorState(preserving: state, reason: .offline)

        XCTAssertEqual(errored.phase, .error)
        XCTAssertEqual(errored.failureReason, .offline)
        XCTAssertNil(errored.ping)
        XCTAssertNil(errored.downloadSpeed)
        XCTAssertNil(errored.uploadSpeed)
    }

}
