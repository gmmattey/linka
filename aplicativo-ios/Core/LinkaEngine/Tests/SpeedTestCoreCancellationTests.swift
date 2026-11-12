import XCTest
@testable import LinkaEngine

/// Cobre a propagação de cancelamento da consumidora até o motor (issue
/// #47, rodada 2 do PR #91 — bug real reportado por Marcelo).
///
/// Antes desta correção, `AsyncThrowingStream` em `SpeedTestCore.runTest()`
/// criava a Task interna sem `continuation.onTermination`: quando a Task
/// consumidora (`SpeedTestViewModel.testTask`) era cancelada, a stream parava
/// de ser lida, mas a Task interna do motor seguia rodando sozinha —
/// download/upload reais continuavam batendo na rede mesmo depois de
/// "Cancelar"/"Pular".
///
/// Estes testes não dependem de rede real: usam um `PathStatusProvider` de
/// teste que dorme por um tempo longo (5s) e registra se, ao acordar, a
/// própria Task que a executa (a Task interna do motor) já estava cancelada
/// — e por quanto tempo ela realmente dormiu. Como `Task.sleep` observa o
/// cancelamento da Task corrente, um sleep cortado bem antes dos 5s prova
/// que o cancelamento da consumidora chegou até dentro do motor.
final class SpeedTestCoreCancellationTests: XCTestCase {

    private struct UnusedOrgLookup: ProviderOrgLookup {
        func fetchOrg() async throws -> String? {
            XCTFail("providerLookup não deveria ser chamado nestes testes de cancelamento")
            return nil
        }
    }

    private actor CancellationProbe {
        private(set) var started = false
        private(set) var sleepElapsed: TimeInterval?
        private(set) var wasCancelledAfterSleep = false

        func markStarted() { started = true }

        func recordSleepResult(elapsed: TimeInterval, cancelled: Bool) {
            sleepElapsed = elapsed
            wasCancelledAfterSleep = cancelled
        }
    }

    /// Simula trabalho demorado dentro da checagem de conectividade que
    /// precede o ping — o primeiro ponto de `await` real dentro da Task
    /// interna de `runTest()`. Sempre reporta offline ao final, para que o
    /// teste nunca avance para fases que batem em rede real.
    private struct SlowThenOfflinePathStatusProvider: PathStatusProvider {
        let probe: CancellationProbe

        func hasConnectivity() async -> Bool {
            await probe.markStarted()
            let start = Date()
            // Sleep bem mais longo que qualquer timeout razoável de teste —
            // se o cancelamento propagar (via `continuation.onTermination`
            // cancelando a Task interna), `Task.sleep` lança
            // `CancellationError` quase imediatamente e o `try?` engole,
            // deixando `elapsed` bem menor que os 5s pedidos.
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let elapsed = Date().timeIntervalSince(start)
            await probe.recordSleepResult(elapsed: elapsed, cancelled: Task.isCancelled)
            return false
        }
    }

    func test_cancellingConsumingTask_cancelsInnerEngineTaskViaOnTermination() async throws {
        let probe = CancellationProbe()
        let engine = SpeedTestCore(
            providerLookup: UnusedOrgLookup(),
            pathStatusProvider: SlowThenOfflinePathStatusProvider(probe: probe)
        )

        // Mesmo formato de `SpeedTestViewModel.testTask`: uma Task própria
        // consumindo a stream com `for try await`.
        let consumer = Task {
            for try await _ in await engine.runTest() {
                // Não importa o conteúdo — só mantém a iteração viva até o
                // cancelamento externo abaixo.
            }
        }

        // Espera a Task interna do motor realmente começar a rodar (dentro
        // do sleep de 5s) antes de cancelar — senão o cancelamento chegaria
        // cedo demais para provar que ele corta um `await` já em andamento.
        var waited = 0
        while await !probe.started, waited < 500 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
        }
        let started = await probe.started
        XCTAssertTrue(started, "a Task interna do motor deveria ter começado a rodar")

        // Equivalente a `SpeedTestViewModel.skipOrCancel()` chamando
        // `testTask?.cancel()`.
        consumer.cancel()

        // Espera o sleep interno de 5s terminar (cedo, se a correção
        // funcionar) — timeout generoso (até ~4s) sem chegar perto dos 5s
        // completos que a correção deveria evitar.
        var attempts = 0
        while await probe.sleepElapsed == nil, attempts < 200 {
            try await Task.sleep(nanoseconds: 20_000_000)
            attempts += 1
        }

        let elapsed = await probe.sleepElapsed
        let wasCancelled = await probe.wasCancelledAfterSleep

        XCTAssertNotNil(elapsed, "o sleep interno deveria ter terminado (cedo, por cancelamento)")
        XCTAssertTrue(wasCancelled, "a Task interna do motor deveria estar marcada como cancelada")
        XCTAssertLessThan(
            elapsed ?? 5.0,
            1.0,
            "o sleep de 5s dentro do motor deveria ser cortado quase imediatamente pelo cancelamento propagado via onTermination — sem a correção, ele levaria os 5s inteiros"
        )

        _ = try? await consumer.value
    }

    /// Regressão negativa: sem cancelar nada, a stream conclui normalmente
    /// (`.offline`) e o motor nunca é interrompido no meio — a correção não
    /// deve fazer `innerTask.cancel()` disparar em cima de um fluxo que
    /// termina sozinho por `continuation.finish()`.
    func test_streamFinishingNormally_doesNotReportEngineCancellation() async throws {
        let probe = CancellationProbe()
        // Sleep curto o bastante para não estourar o timeout do teste.
        struct FastOfflinePathStatusProvider: PathStatusProvider {
            let probe: CancellationProbe
            func hasConnectivity() async -> Bool {
                await probe.markStarted()
                let start = Date()
                let elapsed = Date().timeIntervalSince(start)
                await probe.recordSleepResult(elapsed: elapsed, cancelled: Task.isCancelled)
                return false
            }
        }

        let engine = SpeedTestCore(
            providerLookup: UnusedOrgLookup(),
            pathStatusProvider: FastOfflinePathStatusProvider(probe: probe)
        )

        var received: [MeasurementState] = []
        for try await state in await engine.runTest() {
            received.append(state)
        }

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.phase, .error)
        XCTAssertEqual(received.first?.failureReason, .offline)

        let wasCancelled = await probe.wasCancelledAfterSleep
        XCTAssertFalse(wasCancelled, "um fluxo concluído normalmente não deveria marcar a Task interna como cancelada")
    }
}
