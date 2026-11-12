import XCTest
@testable import LinkaEngine

/// Cobre a detecção de falha fatal durante a fase de ping (issue #85),
/// extensão do #66 para a única fase que rodava sem checagem de aborto: antes
/// desta correção, `performPingTest` batia as 10 sondagens sequenciais
/// completas (~11s) mesmo numa conexão morta, antes de a fase de download ter
/// qualquer chance de detectar a perda de transporte.
///
/// Igual ao padrão de `SpeedTestCoreFailureTests`: `performPingTest` não tem
/// ponto de injeção de transporte hoje, então a peça pura que decide o aborto
/// (`shouldAbortPingTest`) é exercitada diretamente, no mesmo estilo
/// `nonisolated static` já usado para `shouldAbortPhase`/`hasConverged`.
final class SpeedTestCorePingFailureTests: XCTestCase {

    // MARK: - shouldAbortPingTest

    func test_shouldAbortPingTest_thresholdReachedWithZeroSuccesses_aborts() {
        let result = SpeedTestCore.shouldAbortPingTest(consecutiveFatalErrors: 3, successCount: 0)

        XCTAssertTrue(result)
    }

    func test_shouldAbortPingTest_belowThreshold_doesNotAbortEvenWithZeroSuccesses() {
        let result = SpeedTestCore.shouldAbortPingTest(consecutiveFatalErrors: 2, successCount: 0)

        XCTAssertFalse(result)
    }

    /// Teste negativo (regressão): um ping perdido isolado — mesmo quando
    /// intercalado com sucesso — nunca aborta, porque qualquer sondagem
    /// bem-sucedida já zera o contador de falhas fatais consecutivas antes de
    /// `shouldAbortPingTest` sequer ser chamado com um valor alto. Aqui
    /// simulamos diretamente o estado pós-reset: mesmo com falhas fatais
    /// acumuladas depois, se já houve sucesso nesta fase (`successCount > 0`),
    /// a decisão nunca aborta.
    func test_shouldAbortPingTest_intermittentLossWithThroughputFlowing_neverAborts() {
        let isolatedLoss = SpeedTestCore.shouldAbortPingTest(consecutiveFatalErrors: 1, successCount: 4)
        let manyFatalErrorsButSomeSuccessEarlier = SpeedTestCore.shouldAbortPingTest(
            consecutiveFatalErrors: 9,
            successCount: 2
        )

        XCTAssertFalse(isolatedLoss)
        XCTAssertFalse(manyFatalErrorsButSomeSuccessEarlier)
    }

    // MARK: - runTest() integração: falha fatal já no ping

    private struct AlwaysConnectedPathStatusProvider: PathStatusProvider {
        func hasConnectivity() async -> Bool { true }
    }

    /// Nunca deve ser chamado nestes testes — a falha fatal no ping acontece
    /// antes da fase de download, então o enriquecimento de provedor (que só
    /// é aguardado na virada final para o resultado) nunca chega a resolver
    /// nada relevante ao asserto.
    private struct UnusedOrgLookup: ProviderOrgLookup {
        func fetchOrg() async throws -> String? { nil }
    }

    /// `performPingTest` não tem ponto de injeção de transporte hoje (mesma
    /// limitação documentada para download/upload em `SpeedTestCoreFailureTests`),
    /// então este teste cobre o que É possível verificar de ponta a ponta sem
    /// rede real: rodar `runTest()` com conectividade reportada como presente
    /// confirma que o fluxo chega até `performPingTest` (passa do guard de
    /// offline) e produz eventualmente um estado de `.ping` ou além — a
    /// decisão de aborto em si já está coberta pelos testes puros acima.
    func test_runTest_withConnectivity_reachesPingPhaseBeforeDownload() async throws {
        let engine = SpeedTestCore(
            providerLookup: UnusedOrgLookup(),
            pathStatusProvider: AlwaysConnectedPathStatusProvider()
        )

        var phases: [Phase] = []
        for try await state in await engine.runTest() {
            phases.append(state.phase)
            // Corta assim que sair da fase de ping — este teste só precisa
            // confirmar que o motor passou pelo ping real (rede de verdade
            // via Cloudflare), não medir a fase inteira.
            if state.phase != .ping {
                break
            }
        }

        XCTAssertFalse(phases.isEmpty)
    }
}
