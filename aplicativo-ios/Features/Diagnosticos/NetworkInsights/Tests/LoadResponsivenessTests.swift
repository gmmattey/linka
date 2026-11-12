import XCTest
import NetworkCore
@testable import NetworkInsights

/// Cobre `LoadResponsivenessEvaluator` (issue #128): categorização objetiva
/// de responsividade sob carga a partir do delta absoluto em ms entre
/// latência parada e latência sob carga (download/upload) — deliberadamente
/// não percentual, ver `LoadResponsivenessThresholds`. Função pura — sem
/// rede, sem `Date()` ao vivo — mesmo espírito de `UsageSuitabilityTests`.
final class LoadResponsivenessTests: XCTestCase {
    func testHighConfidenceEvaluationRejectsIncompleteEnvelope() {
        let measurement = NetworkMeasurement(
            latencyMs: 10,
            loadedLatencyMs: 200,
            loadedLatencyUploadMs: 200,
            loadResponsiveness: LoadResponsivenessEvidence(
                environmentIdentifier: "cloudflare-speedtest-v1",
                integrity: .downloadInconclusive,
                baseline: nil,
                download: nil,
                upload: nil
            )
        )

        XCTAssertEqual(LoadResponsivenessEvaluator.evaluateHighConfidence(measurement).category, .notAssessed)
        XCTAssertEqual(LoadResponsivenessEvaluator.evaluateForConsumer(measurement).category, .notAssessed)
    }


    // MARK: - Categorias com limiares padrão (high 30ms / medium 100ms)

    func testSmallIncreaseIsHighResponsiveness() {
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 20,
            loadedDownloadLatencyMs: 40, // +20ms
            loadedUploadLatencyMs: 28    // +8ms
        )

        XCTAssertEqual(result.category, .high)
    }

    func testHighThresholdIsInclusiveAtTheBoundary() {
        // Exatamente 30ms de acréscimo — limiar documentado como inclusivo
        // ("até highThresholdMs") em `LoadResponsivenessThresholds`.
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 20,
            loadedDownloadLatencyMs: 50, // exatamente +30ms
            loadedUploadLatencyMs: nil
        )

        XCTAssertEqual(result.category, .high)
    }

    func testModerateIncreaseIsMediumResponsiveness() {
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 20,
            loadedDownloadLatencyMs: 70, // +50ms
            loadedUploadLatencyMs: nil
        )

        XCTAssertEqual(result.category, .medium)
    }

    func testLargeIncreaseIsLowResponsiveness() {
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 20,
            loadedDownloadLatencyMs: nil,
            loadedUploadLatencyMs: 150 // +130ms
        )

        XCTAssertEqual(result.category, .low)
        XCTAssertEqual(result.uploadComparison.direction, .worsened)
    }

    /// Caso que motivou reescrever a categorização de percentual para ms
    /// absoluto: numa conexão rápida, um crescimento percentual grande pode
    /// ser um acréscimo em ms irrelevante para qualquer chamada real.
    func testLargePercentIncreaseOnFastConnectionIsStillHighResponsiveness() {
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 8,
            loadedDownloadLatencyMs: 20, // +150%, mas só +12ms
            loadedUploadLatencyMs: nil
        )

        XCTAssertEqual(result.category, .high)
    }

    /// Caso simétrico: numa conexão mais lenta, um crescimento percentual
    /// pequeno ainda pode ser um acréscimo em ms claramente perceptível.
    func testModeratePercentIncreaseOnSlowConnectionIsLowResponsiveness() {
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 150,
            loadedDownloadLatencyMs: 260, // +73%, mas +110ms
            loadedUploadLatencyMs: nil
        )

        XCTAssertEqual(result.category, .low)
    }

    // MARK: - Pior direção decide a categoria

    func testWorstOfDownloadAndUploadDecidesCategory() {
        // Download quase inalterado (+8ms, alta responsividade sozinho);
        // upload degrada muito (+130ms, baixa responsividade sozinho). Um
        // sintoma claro de bufferbloat em qualquer direção já é suficiente —
        // a categoria final acompanha a pior das duas.
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 20,
            loadedDownloadLatencyMs: 28,
            loadedUploadLatencyMs: 150
        )

        XCTAssertEqual(result.category, .low)
    }

    // MARK: - Estado explícito "não avaliado"

    func testMissingIdleLatencyIsNotAssessedEvenWithBothLoadedValues() {
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: nil,
            loadedDownloadLatencyMs: 30,
            loadedUploadLatencyMs: 40
        )

        XCTAssertEqual(result.category, .notAssessed)
        XCTAssertEqual(result.downloadComparison.direction, .unavailable)
        XCTAssertEqual(result.uploadComparison.direction, .unavailable)
    }

    func testMissingBothLoadedLatenciesIsNotAssessedEvenWithIdlePresent() {
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 20,
            loadedDownloadLatencyMs: nil,
            loadedUploadLatencyMs: nil
        )

        XCTAssertEqual(result.category, .notAssessed)
    }

    // MARK: - Uma única direção disponível

    func testAssessesFromDownloadAloneWhenUploadIsMissing() {
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 40,
            loadedDownloadLatencyMs: 160, // +120ms
            loadedUploadLatencyMs: nil
        )

        XCTAssertEqual(result.category, .low)
        XCTAssertEqual(result.uploadComparison.direction, .unavailable)
    }

    func testAssessesFromUploadAloneWhenDownloadIsMissing() {
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 40,
            loadedDownloadLatencyMs: nil,
            loadedUploadLatencyMs: 48 // +8ms
        )

        XCTAssertEqual(result.category, .high)
        XCTAssertEqual(result.downloadComparison.direction, .unavailable)
    }

    // MARK: - Latência sob carga menor que a parada (ruído favorável)

    func testLoadedLatencyLowerThanIdleNeverLowersCategory() {
        // Sob carga saiu mais rápida que parada (ruído de medição) — não é
        // um sintoma de bufferbloat, então não deve rebaixar a categoria
        // para "melhor que alta" (não existe tal categoria) nem para
        // qualquer outra coisa fabricada a partir de um delta negativo.
        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 50,
            loadedDownloadLatencyMs: 30, // -20ms
            loadedUploadLatencyMs: nil
        )

        XCTAssertEqual(result.category, .high)
        XCTAssertEqual(result.downloadComparison.direction, .improved)
    }

    // MARK: - Limiares customizados

    func testCustomThresholdsChangeCategoryBoundaries() {
        let thresholds = LoadResponsivenessThresholds(
            highThresholdMs: 10,
            mediumThresholdMs: 50
        )

        let result = LoadResponsivenessEvaluator.evaluate(
            idleLatencyMs: 20,
            loadedDownloadLatencyMs: 35, // +15ms: seria "high" no padrão (30ms), mas não com highThresholdMs: 10
            loadedUploadLatencyMs: nil,
            thresholds: thresholds
        )

        XCTAssertEqual(result.category, .medium)
    }

    func testThresholdsClampMediumToAtLeastHigh() {
        // `mediumThresholdMs` nunca pode ficar abaixo de `highThresholdMs` —
        // faria uma faixa "medium" invertida/vazia.
        let thresholds = LoadResponsivenessThresholds(
            highThresholdMs: 50,
            mediumThresholdMs: 20
        )

        XCTAssertEqual(thresholds.mediumThresholdMs, 50)
    }
}
