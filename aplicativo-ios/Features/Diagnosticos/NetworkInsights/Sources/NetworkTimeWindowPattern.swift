import Foundation
import NetworkCore

extension NetworkMetric {
    /// Extrai o valor bruto dessa métrica de uma medição. Compartilhado entre
    /// `BasicNetworkInsightsAnalyzer` (estatística/tendência) e
    /// `NetworkTimeWindowPatternDetector` (padrão por horário, issue #125)
    /// para as duas nunca divergirem sobre qual campo cada métrica lê.
    func measuredValue(in measurement: NetworkMeasurement) -> Double? {
        switch self {
        case .downloadMbps:
            return measurement.downloadMbps
        case .uploadMbps:
            return measurement.uploadMbps
        case .latencyMs:
            return measurement.latencyMs
        case .jitterMs:
            return measurement.jitterMs
        case .packetLossPercent:
            return measurement.packetLossPercent
        case .loadedLatencyMs:
            return measurement.trustedLoadedLatencies.downloadMs
        case .loadedLatencyUploadMs:
            return measurement.trustedLoadedLatencies.uploadMs
        }
    }
}

/// Limiares objetivos da detecção de padrão por horário do dia (issue #125,
/// item 2). Nenhum valor aqui é "mágico": cada um existe para impedir que o
/// motor aponte um padrão a partir de coincidência estatística.
public struct NetworkTimeWindowPatternConfiguration: Equatable, Sendable {
    /// Tamanho de cada janela candidata, em horas. `24` precisa ser
    /// divisível por este valor para cobrir o dia inteiro sem sobra; `2`
    /// (padrão) produz janelas como "20h–22h", do mesmo tamanho do exemplo
    /// dado pelo dono do produto na issue #125.
    public let windowSizeHours: Int
    /// Dias-calendário distintos que o grupo precisa ter no histórico
    /// inteiro antes de sequer avaliar qualquer janela. Menos que isso e
    /// qualquer "padrão" seria coincidência de poucos dias, não recorrência.
    public let minimumDistinctDaysInHistory: Int
    /// Dias-calendário distintos em que a métrica precisa ter sido medida
    /// *dentro* da janela candidata para essa janela contar como
    /// recorrente. Duas medições no mesmo dia (ex.: dois testes às 20h05 e
    /// 20h40) não bastam para dizer "todos os dias" — precisa aparecer em
    /// dias diferentes.
    public let minimumDistinctDaysInsideWindow: Int
    /// Piora mínima (%) da média dentro da janela em relação à média fora
    /// dela para a diferença deixar de ser variação normal e virar padrão
    /// reportável. 20% é deliberadamente conservador: o objetivo é uma
    /// frase que o usuário reconheça como real, não uma flutuação de ruído
    /// de rede do dia a dia.
    public let minimumDegradationPercent: Double

    public init(
        windowSizeHours: Int = 2,
        minimumDistinctDaysInHistory: Int = 5,
        minimumDistinctDaysInsideWindow: Int = 3,
        minimumDegradationPercent: Double = 20
    ) {
        self.windowSizeHours = min(24, max(1, windowSizeHours))
        self.minimumDistinctDaysInHistory = max(1, minimumDistinctDaysInHistory)
        self.minimumDistinctDaysInsideWindow = max(1, minimumDistinctDaysInsideWindow)
        self.minimumDegradationPercent = max(0, minimumDegradationPercent)
    }
}

/// Um padrão de horário efetivamente detectado — só existe quando todos os
/// limiares de `NetworkTimeWindowPatternConfiguration` foram atendidos.
public struct NetworkTimeWindowPattern: Equatable, Sendable {
    public let metric: NetworkMetric
    /// Hora local de início da janela (0–23).
    public let startHour: Int
    /// Hora local de fim da janela (1–24, exclusiva; `24` representa
    /// meia-noite do dia seguinte).
    public let endHour: Int
    /// Dias-calendário distintos em que a janela foi observada.
    public let distinctDayCount: Int
    public let insideWindowAverage: Double
    public let outsideWindowAverage: Double
    /// Piora percentual da média dentro da janela em relação à média fora
    /// dela, sempre positiva (a direção de "pior" já foi resolvida
    /// conforme `metric.preference`).
    public let degradationPercent: Double
}

/// Resultado explícito da varredura — nunca um valor vazio nem um "sem
/// padrão" silencioso disfarçado de sucesso. `insufficientSamples` e
/// `noPatternDetected` são estados distintos de propósito: o primeiro diz
/// "não sei ainda, faltam dias de histórico"; o segundo diz "sei, e não há
/// horário que se destaque" — a camada de apresentação (issue #125, item 3)
/// depende dessa distinção para nunca fabricar uma frase genérica.
public enum NetworkTimeWindowPatternOutcome: Equatable, Sendable {
    case detected(NetworkTimeWindowPattern)
    case noPatternDetected
    case insufficientSamples(distinctDayCount: Int, required: Int)
}

/// Motor puro e determinístico (sem I/O, sem dependência de transporte
/// remoto — mesmo espírito de `NetworkAssistInvestigationEngine`): varre
/// janelas fixas de horário do dia dentro do histórico de uma única rede
/// (já agrupado por `NetworkGroupInsightsAnalyzer`) e decide se alguma
/// janela concentra uma piora recorrente de uma métrica.
public enum NetworkTimeWindowPatternDetector {
    public static func detect(
        metric: NetworkMetric,
        in measurements: [NetworkMeasurement],
        configuration: NetworkTimeWindowPatternConfiguration = .init(),
        calendar: Calendar = .current
    ) -> NetworkTimeWindowPatternOutcome {
        let samples: [(day: Date, hour: Int, value: Double)] = measurements.compactMap { measurement in
            guard let value = metric.measuredValue(in: measurement) else { return nil }
            let hour = calendar.component(.hour, from: measurement.measuredAt)
            let day = calendar.startOfDay(for: measurement.measuredAt)
            return (day, hour, value)
        }

        let distinctDays = Set(samples.map { $0.day })
        guard distinctDays.count >= configuration.minimumDistinctDaysInHistory else {
            return .insufficientSamples(
                distinctDayCount: distinctDays.count,
                required: configuration.minimumDistinctDaysInHistory
            )
        }

        var best: NetworkTimeWindowPattern?

        var startHour = 0
        while startHour < 24 {
            let endHour = startHour + configuration.windowSizeHours
            defer { startHour = endHour }

            let inside = samples.filter { $0.hour >= startHour && $0.hour < endHour }
            guard !inside.isEmpty else { continue }

            let insideDistinctDays = Set(inside.map { $0.day })
            guard insideDistinctDays.count >= configuration.minimumDistinctDaysInsideWindow else { continue }

            let outside = samples.filter { $0.hour < startHour || $0.hour >= endHour }
            guard !outside.isEmpty else { continue }

            let insideAverage = average(inside.map { $0.value })
            let outsideAverage = average(outside.map { $0.value })
            guard outsideAverage != 0 else { continue }

            let degradationPercent: Double
            switch metric.preference {
            case .higherIsBetter:
                // download/upload: "pior" dentro da janela é uma média MENOR.
                degradationPercent = ((outsideAverage - insideAverage) / abs(outsideAverage)) * 100
            case .lowerIsBetter:
                // latência/jitter/perda de pacote: "pior" dentro da janela é uma média MAIOR.
                degradationPercent = ((insideAverage - outsideAverage) / abs(outsideAverage)) * 100
            }

            guard degradationPercent >= configuration.minimumDegradationPercent else { continue }

            let candidate = NetworkTimeWindowPattern(
                metric: metric,
                startHour: startHour,
                endHour: endHour,
                distinctDayCount: insideDistinctDays.count,
                insideWindowAverage: insideAverage,
                outsideWindowAverage: outsideAverage,
                degradationPercent: degradationPercent
            )

            // Quando mais de uma janela qualifica, ficamos só com a mais
            // forte: a frase final (issue #125, item 3) cita um único
            // horário, e reportar o sinal mais nítido evita uma lista de
            // janelas parcialmente sobrepostas que confundiria mais do que
            // ajudaria.
            if best == nil || candidate.degradationPercent > best!.degradationPercent {
                best = candidate
            }
        }

        if let best {
            return .detected(best)
        }
        return .noPatternDetected
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
