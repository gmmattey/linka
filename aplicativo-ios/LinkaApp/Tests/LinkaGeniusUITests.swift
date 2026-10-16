import XCTest
import SwiftUI
import NetworkCore
@testable import LinkaApp

@MainActor
final class LinkaGeniusUITests: XCTestCase {

    func testAssistViewInitializesWithRecentMeasurementAndCallbacks() {
        let measurement = NetworkMeasurement(
            id: UUID(),
            outcome: .complete,
            downloadMbps: 450.5,
            uploadMbps: 125.0,
            latencyMs: 14.0,
            jitterMs: 2.0,
            packetLossPercent: 0.0,
            connectionKind: .wifi,
            wifiBandGHz: 5.0
        )

        var retestCalled = false
        var retryCalled = false

        let view = AssistView(
            currentMeasurement: measurement,
            recentMeasurements: [measurement],
            onRetry: { retryCalled = true },
            onRetest: { retestCalled = true }
        )

        XCTAssertNotNil(view.currentMeasurement)
        XCTAssertEqual(view.currentMeasurement?.downloadMbps, 450.5)
        XCTAssertEqual(view.currentMeasurement?.uploadMbps, 125.0)
        XCTAssertEqual(view.currentMeasurement?.latencyMs, 14.0)

        view.onRetry?()
        XCTAssertTrue(retryCalled)

        view.onRetest?()
        XCTAssertTrue(retestCalled)
    }

    func testAssistViewInitializesWithoutRecentMeasurementHonoringEmptyTelemetryState() {
        var retestTriggered = false

        let view = AssistView(
            currentMeasurement: nil,
            recentMeasurements: [],
            onRetest: { retestTriggered = true }
        )

        XCTAssertNil(view.currentMeasurement)
        view.onRetest?()
        XCTAssertTrue(retestTriggered)
    }

    func testLinkaGeniusViewModelExecutesShortcutAndTransitionsToSuccess() async throws {
        final class MockGeniusService: LinkaGeniusServicing, @unchecked Sendable {
            func analyze(context: LinkaGeniusContext) async throws -> LinkaGeniusAnalysis {
                LinkaGeniusAnalysis(
                    symptom: "Áudio picotando e atraso em reuniões",
                    cause: "Bufferbloat elevado sob carga e canal Wi-Fi saturado",
                    actions: [
                        "Ative SQM/QoS no roteador residencial",
                        "Migre para a rede de 5 GHz",
                        "Reinicie o roteador se estiver ligado há meses"
                    ],
                    operatorScript: "Prezados, venho solicitar verificação de rota e troca de perfil de latência.",
                    needsRetest: true
                )
            }
        }

        let mockService = MockGeniusService()
        let measurement = NetworkMeasurement(
            id: UUID(),
            outcome: .complete,
            downloadMbps: 200,
            uploadMbps: 50,
            latencyMs: 35
        )

        let viewModel = LinkaGeniusViewModel(
            geniusService: mockService,
            measurementProvider: { measurement }
        )

        XCTAssertEqual(viewModel.state, .idle)

        viewModel.ask(shortcut: .slowCalls)

        // Aguarda a transição assíncrona
        let exp = expectation(description: "Aguardar análise do Genius")
        Task {
            for _ in 0..<30 {
                if case .success = viewModel.state {
                    exp.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        await fulfillment(of: [exp], timeout: 2.0)

        guard case .success(let analysis) = viewModel.state else {
            XCTFail("ViewModel deveria estar no estado .success")
            return
        }

        XCTAssertEqual(analysis.symptom, "Áudio picotando e atraso em reuniões")
        XCTAssertEqual(analysis.cause, "Bufferbloat elevado sob carga e canal Wi-Fi saturado")
        XCTAssertEqual(analysis.actions.count, 3)
        XCTAssertTrue(analysis.needsRetest)
        XCTAssertFalse(analysis.operatorScript.isEmpty)

        // Reset
        viewModel.reset()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.activeAnalysis)
    }

    func testLocalizationKeysExistForGenius() {
        let keys = [
            "genius.title",
            "genius.subtitle",
            "genius.badge",
            "genius.telemetry.title",
            "genius.telemetry.empty.title",
            "genius.telemetry.empty.message",
            "genius.telemetry.testNow",
            "genius.prompt.placeholder",
            "genius.prompt.send",
            "genius.shortcuts.title",
            "genius.loading.telemetry",
            "genius.loading.consulting",
            "genius.loading.finalizing",
            "genius.result.symptom",
            "genius.result.cause",
            "genius.result.actions",
            "genius.result.script",
            "genius.result.script.copy",
            "genius.result.script.copied",
            "genius.result.retest",
            "genius.result.newQuestion",
            "genius.footer.attribution",
            "genius.error.title",
            "genius.error.retry"
        ]

        for key in keys {
            let val = LinkaCopy.value(key)
            XCTAssertNotEqual(val, key, "A chave \(key) deve estar localizada e não retornar a si mesma")
        }
    }
}
