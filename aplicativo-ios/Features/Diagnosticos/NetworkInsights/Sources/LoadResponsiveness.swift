import Foundation
import NetworkCore

/// Categoria objetiva de responsividade da conexão quando ocupada (issue
/// #128) — o quanto a latência cresce sob carga real (download/upload) em
/// relação à latência parada (`latencyMs`). É o proxy observável de
/// bufferbloat: uma fila cheia no roteador atrasa pacotes concorrentes
/// (ex.: um pacote de chamada de vídeo enquanto um upload grande está em
/// andamento), mesmo quando a vazão medida (Mbps) está ótima.
///
/// `.notAssessed` não é "boa" nem "ruim" — é "não sabemos", reservado para
/// quando falta a latência parada ou nenhuma das duas latências sob carga
/// (download/upload) está disponível. Mesmo espírito de
/// `UsageSuitability.SuitabilityLevel.notAssessed`: uma métrica ausente
/// nunca é tratada como zero, e nunca promove/rebaixa silenciosamente para
/// uma categoria fabricada.
public enum LoadResponsivenessCategory: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
    case notAssessed
}

/// Limiares que convertem "quanto a latência cresce sob carga, em ms" em
/// `LoadResponsivenessCategory`.
///
/// Delta absoluto em milissegundos, não percentual — decisão revisada
/// depois da primeira implementação (que reaproveitava `percentDelta` de
/// `MetricComparator`). Percentual falsifica o sintoma nas duas pontas: numa
/// conexão rápida (ex. 8ms parado → 20ms sob carga, +150%) o atraso extra
/// real é de 12ms, imperceptível em qualquer chamada, mas a categoria
/// percentual soaria "baixa responsividade"; numa conexão mais lenta (ex.
/// 150ms parado → 220ms sob carga, +47%) os 70ms extras já são um sintoma
/// claro de bufferbloat, mas o percentual ficaria na faixa "média". O que
/// importa para o usuário é o atraso extra em si — é isso que atrasa um
/// pacote de voz/vídeo concorrente —, não a proporção sobre uma base que
/// varia de conexão para conexão. Este pacote continua calculando
/// `percentDelta` (via `MetricComparator`) para exibição/comparação
/// genérica, mas a categorização de bufferbloat usa `absoluteDelta`.
///
/// Os dois limiares abaixo são o parâmetro público desta decisão — nenhum
/// deles é número mágico dentro da lógica de categorização, ambos existem
/// por um motivo escrito:
///
/// - `highThresholdMs` (30ms): atraso extra até aqui é menor que o jitter
///   natural que qualquer chamada de voz/vídeo saudável já tolera — soa
///   "praticamente igual" a estar parado.
/// - `mediumThresholdMs` (100ms): referência comum de atraso perceptível em
///   tempo real (ex. ITU-T G.114 trata ~150ms de atraso unidirecional total
///   como o teto aceitável para voz) — acima disso o atraso *extra* sozinho
///   já é grande o bastante para ser notado com clareza numa chamada em
///   andamento, sinal inequívoco de fila cheia no roteador.
///
/// Entre os dois fica a faixa "média": perceptível, mas não necessariamente
/// grave (ex.: uma chamada de vídeo ainda funciona, com atraso notável).
public struct LoadResponsivenessThresholds: Equatable, Sendable {
    public var highThresholdMs: Double
    public var mediumThresholdMs: Double

    public init(
        highThresholdMs: Double = 30,
        mediumThresholdMs: Double = 100
    ) {
        self.highThresholdMs = max(0, highThresholdMs)
        self.mediumThresholdMs = max(self.highThresholdMs, mediumThresholdMs)
    }
}

/// Resultado completo da avaliação de responsividade sob carga de uma
/// medição: a categoria e as duas comparações (parada-vs-carga) que a
/// sustentam, uma por direção. `downloadComparison`/`uploadComparison` nunca
/// são "ausentes" no sentido de Optional — seguem o mesmo padrão de
/// `MetricComparison.direction == .unavailable` já usado em todo o pacote
/// para representar "faltou dado", em vez de esconder a ausência atrás de
/// `nil` na struct inteira.
public struct LoadResponsivenessResult: Codable, Equatable, Sendable {
    public let category: LoadResponsivenessCategory
    public let downloadComparison: MetricComparison
    public let uploadComparison: MetricComparison

    public init(
        category: LoadResponsivenessCategory,
        downloadComparison: MetricComparison,
        uploadComparison: MetricComparison
    ) {
        self.category = category
        self.downloadComparison = downloadComparison
        self.uploadComparison = uploadComparison
    }
}

/// Categoriza a responsividade sob carga de uma medição a partir da latência
/// parada e da(s) latência(s) sob carga (download e/ou upload) — issue #128,
/// item 2 do aceite ("Existe uma categorização objetiva e testável").
///
/// Função pura e testável (mesmo espírito de `UsageSuitabilityEvaluator`):
/// não lança, não conhece copy de produto, não conhece UI. Recebe valores
/// já extraídos em vez de um `NetworkMeasurement` inteiro porque o chamador
/// mais natural (Detalhes, fora de escopo deste pacote) normalmente já tem
/// os três valores em mãos a partir de uma única medição — mas nada aqui
/// impede um `NetworkMeasurement` de ser a fonte desses três `Double?`.
public enum LoadResponsivenessEvaluator {
    /// Avaliação destinada a consumidores que precisam de confiança alta.
    /// Medições legadas continuam apresentáveis pelo método escalar abaixo,
    /// mas não recebem promoção silenciosa para a metodologia v1.
    public static func evaluateHighConfidence(
        _ measurement: NetworkMeasurement,
        thresholds: LoadResponsivenessThresholds = .init()
    ) -> LoadResponsivenessResult {
        guard measurement.loadResponsiveness?.integrity == .valid else {
            return evaluate(
                idleLatencyMs: nil,
                loadedDownloadLatencyMs: nil,
                loadedUploadLatencyMs: nil,
                thresholds: thresholds
            )
        }
        return evaluate(
            idleLatencyMs: measurement.loadResponsiveness?.baseline?.medianMs,
            loadedDownloadLatencyMs: measurement.loadResponsiveness?.download?.latency?.medianMs,
            loadedUploadLatencyMs: measurement.loadResponsiveness?.upload?.latency?.medianMs,
            thresholds: thresholds
        )
    }

    /// Gate compartilhado pelos consumidores de produto. O fallback escalar
    /// é exclusivamente para registros sem envelope (metodologia legada).
    public static func evaluateForConsumer(
        _ measurement: NetworkMeasurement,
        thresholds: LoadResponsivenessThresholds = .init()
    ) -> LoadResponsivenessResult {
        let loaded = measurement.trustedLoadedLatencies
        let idle = measurement.loadResponsiveness?.baseline?.medianMs ?? measurement.latencyMs
        return evaluate(
            idleLatencyMs: idle,
            loadedDownloadLatencyMs: loaded.downloadMs,
            loadedUploadLatencyMs: loaded.uploadMs,
            thresholds: thresholds
        )
    }

    /// - Parameters:
    ///   - idleLatencyMs: latência parada (`NetworkMeasurement.latencyMs`) —
    ///     é a referência ("baseline") das duas comparações.
    ///   - loadedDownloadLatencyMs: latência sob carga durante download
    ///     (`NetworkMeasurement.loadedLatencyMs`).
    ///   - loadedUploadLatencyMs: latência sob carga durante upload
    ///     (`NetworkMeasurement.loadedLatencyUploadMs`, issue #128).
    ///   - thresholds: limiares em milissegundos que decidem a categoria.
    /// - Returns: `.notAssessed` quando `idleLatencyMs` está ausente, ou
    ///   quando nenhuma das duas latências sob carga está disponível.
    ///   Caso contrário, a pior (maior) variação absoluta em ms entre
    ///   download e upload decide a categoria — um único sinal claro de
    ///   bufferbloat em qualquer direção já é o suficiente para revelar
    ///   fila cheia no roteador, mesmo que a outra direção esteja saudável.
    public static func evaluate(
        idleLatencyMs: Double?,
        loadedDownloadLatencyMs: Double?,
        loadedUploadLatencyMs: Double?,
        thresholds: LoadResponsivenessThresholds = .init()
    ) -> LoadResponsivenessResult {
        // `direction` (em `MetricComparison`) e `category` respondem
        // perguntas diferentes de propósito: `direction` usa o limiar de
        // "estável" padrão do pacote (ruído estatístico — mudou de verdade
        // ou não?), enquanto `category` usa os limiares em ms acima
        // (impacto perceptível — o quanto isso incomoda um humano numa
        // chamada?). Uma medição pode legitimamente aparecer como
        // `.worsened` e ainda cair em `.high` (mudança real, porém pequena
        // demais para importar) — não é inconsistência, é a mesma distinção
        // entre significância estatística e significância prática.
        let downloadComparison = MetricComparator.compare(
            metric: .loadedLatencyMs,
            current: loadedDownloadLatencyMs,
            baseline: idleLatencyMs,
            stableChangeThresholdPercent: NetworkInsightsConfiguration().stableChangeThresholdPercent
        )
        let uploadComparison = MetricComparator.compare(
            metric: .loadedLatencyUploadMs,
            current: loadedUploadLatencyMs,
            baseline: idleLatencyMs,
            stableChangeThresholdPercent: NetworkInsightsConfiguration().stableChangeThresholdPercent
        )

        let measuredDeltasMs = [downloadComparison, uploadComparison]
            .filter { $0.direction != .unavailable }
            .compactMap(\.absoluteDelta)

        guard let worstDeltaMs = measuredDeltasMs.max() else {
            return LoadResponsivenessResult(
                category: .notAssessed,
                downloadComparison: downloadComparison,
                uploadComparison: uploadComparison
            )
        }

        // Só a piora (latência sob carga maior que parada) indica fila
        // cheia; uma latência sob carga menor que a parada (ruído/medição
        // mais favorável) nunca é tratada como sintoma — conta como "alta
        // responsividade", não como uma redução que abaixaria
        // artificialmente a categoria.
        let worstIncreaseMs = max(0, worstDeltaMs)

        let category: LoadResponsivenessCategory
        if worstIncreaseMs <= thresholds.highThresholdMs {
            category = .high
        } else if worstIncreaseMs <= thresholds.mediumThresholdMs {
            category = .medium
        } else {
            category = .low
        }

        return LoadResponsivenessResult(
            category: category,
            downloadComparison: downloadComparison,
            uploadComparison: uploadComparison
        )
    }
}
