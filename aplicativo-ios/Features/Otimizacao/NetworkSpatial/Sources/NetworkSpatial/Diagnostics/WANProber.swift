import Foundation
import Network

public struct WANProbeResult: Sendable, Equatable {
    public let wanMedianLatencyMs: Double
    public let wanP95LatencyMs: Double
    public let wanMeanLatencyMs: Double
    public let wanJitterMs: Double
    public let wanPacketLossPercent: Double
    public let wanLostCount: Int
    public let wanTotalProbes: Int
    public let wanLossInterpretation: LossInterpretation
    public let didRunAdaptiveConfirmation: Bool

    /// Acesso legado compatível mapeado para a mediana
    public var wanLatencyMs: Double {
        wanMedianLatencyMs
    }

    public init(
        wanMedianLatencyMs: Double,
        wanP95LatencyMs: Double,
        wanMeanLatencyMs: Double,
        wanJitterMs: Double,
        wanPacketLossPercent: Double,
        wanLostCount: Int = 0,
        wanTotalProbes: Int = 0,
        wanLossInterpretation: LossInterpretation = .stable,
        didRunAdaptiveConfirmation: Bool = false
    ) {
        self.wanMedianLatencyMs = wanMedianLatencyMs
        self.wanP95LatencyMs = wanP95LatencyMs
        self.wanMeanLatencyMs = wanMeanLatencyMs
        self.wanJitterMs = wanJitterMs
        self.wanPacketLossPercent = wanPacketLossPercent
        self.wanLostCount = wanLostCount
        self.wanTotalProbes = wanTotalProbes
        self.wanLossInterpretation = wanLossInterpretation
        self.didRunAdaptiveConfirmation = didRunAdaptiveConfirmation
    }

    /// Inicializador legado de compatibilidade
    public init(wanLatencyMs: Double, wanPacketLossPercent: Double) {
        self.wanMedianLatencyMs = wanLatencyMs
        self.wanP95LatencyMs = wanLatencyMs
        self.wanMeanLatencyMs = wanLatencyMs
        self.wanJitterMs = 0.0
        self.wanPacketLossPercent = wanPacketLossPercent
        self.wanLostCount = 0
        self.wanTotalProbes = 8
        self.wanLossInterpretation = wanPacketLossPercent == 0 ? .stable : (wanPacketLossPercent <= 15 ? .isolatedEvent : .confirmedLoss)
        self.didRunAdaptiveConfirmation = false
    }
}

public actor WANProber {
    public init() {}

    private let primaryTarget: (host: String, port: UInt16) = ("1.1.1.1", 53)     // Cloudflare DNS Principal
    private let secondaryTarget: (host: String, port: UInt16) = ("8.8.8.8", 53)   // Google DNS de Confirmação

    /// Executa medição determinística de latência, jitter e perda WAN com destino consistente (RFC 3550)
    public func probe(
        sampleCount: Int = 8,
        timeoutSeconds: Double = 1.0,
        enableAdaptiveProbing: Bool = true,
        onAdaptiveConfirmation: (@Sendable () -> Void)? = nil
    ) async -> WANProbeResult {
        var rtts: [Double] = []
        var lostCount = 0

        // Rodada 1: Sondas enviadas para o mesmo destino primário (evita jitter falso entre CDNs distintas)
        for _ in 0..<sampleCount {
            if Task.isCancelled { break }

            if let rtt = await measureTargetRTT(host: primaryTarget.host, port: primaryTarget.port, timeoutSeconds: timeoutSeconds) {
                rtts.append(rtt)
            } else {
                lostCount += 1
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        // Avaliação adaptativa (+8 probes se houver perda ou spike WAN p95 > 120ms)
        var didRunAdaptiveConfirmation = false
        var isSecondaryDestinationReachable = false

        if enableAdaptiveProbing && !Task.isCancelled {
            let sortedInitial = rtts.sorted()
            let initialP95 = GatewayLatencyProber.calculateP95(sortedInitial)
            let hasSuspectedAnomaly = lostCount > 0 || initialP95 > 120.0

            if hasSuspectedAnomaly {
                didRunAdaptiveConfirmation = true
                onAdaptiveConfirmation?()

                // Validação secundária: testa alcance em destino de referência independente (Google DNS 8.8.8.8)
                // para distinguir bloqueio DNS/rota específica do primário de queda total da WAN.
                // NOTA RFC 3550: As amostras do secundário NÃO são misturadas na série 'rtts' nem alteram
                // 'lostCount' para não poluir os cálculos de latência e jitter com destinos heterogêneos.
                var secondarySuccessCount = 0
                for _ in 0..<4 {
                    if Task.isCancelled { break }

                    if await measureTargetRTT(host: secondaryTarget.host, port: secondaryTarget.port, timeoutSeconds: timeoutSeconds) != nil {
                        secondarySuccessCount += 1
                    }

                    try? await Task.sleep(nanoseconds: 120_000_000)
                }

                isSecondaryDestinationReachable = (secondarySuccessCount > 0)
            }
        }

        let total = rtts.count + lostCount
        let loss = total > 0 ? (Double(lostCount) / Double(total)) * 100.0 : 100.0

        let sorted = rtts.sorted()
        let median = GatewayLatencyProber.calculateMedian(sorted)
        let p95 = GatewayLatencyProber.calculateP95(sorted)
        let mean = !rtts.isEmpty ? rtts.reduce(0.0, +) / Double(rtts.count) : 999.0

        // Variação média absoluta de atraso (Mean Delay Variation) estritamente sobre o mesmo destino primário
        let jitter: Double
        if rtts.count > 1 {
            var diffSum = 0.0
            for i in 1..<rtts.count {
                diffSum += abs(rtts[i] - rtts[i - 1])
            }
            jitter = diffSum / Double(rtts.count - 1)
        } else {
            jitter = 0.0
        }

        let interpretation: LossInterpretation
        if total == 0 || lostCount == total {
            // Se o destino primário falhou totalmente mas o secundário respondeu, trata como falha específica de destino
            if isSecondaryDestinationReachable && didRunAdaptiveConfirmation {
                interpretation = .isolatedEvent
            } else {
                interpretation = .severeLoss
            }
        } else if lostCount == 0 {
            interpretation = .stable
        } else if lostCount == 1 {
            interpretation = .isolatedEvent
        } else {
            interpretation = .confirmedLoss
        }

        return WANProbeResult(
            wanMedianLatencyMs: round(median * 10) / 10,
            wanP95LatencyMs: round(p95 * 10) / 10,
            wanMeanLatencyMs: round(mean * 10) / 10,
            wanJitterMs: round(jitter * 10) / 10,
            wanPacketLossPercent: round(loss * 10) / 10,
            wanLostCount: lostCount,
            wanTotalProbes: total,
            wanLossInterpretation: interpretation,
            didRunAdaptiveConfirmation: didRunAdaptiveConfirmation
        )
    }

    private func measureTargetRTT(host: String, port: UInt16, timeoutSeconds: Double) async -> Double? {
        final class ResumeState: @unchecked Sendable {
            var hasResumed = false
        }
        let stateLock = ResumeState()

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!
            )
            let params = NWParameters.tcp
            params.prohibitExpensivePaths = true
            params.requiredInterfaceType = .wifi
            let connection = NWConnection(to: endpoint, using: params)

            let startTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let queue = DispatchQueue(label: "com.linka.assist.wanprobe")

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                queue.async {
                    if !stateLock.hasResumed {
                        stateLock.hasResumed = true
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                }
            }
            timer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !stateLock.hasResumed {
                        stateLock.hasResumed = true
                        timer.cancel()
                        let endTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                        let elapsedMs = Double(endTime - startTime) / 1_000_000.0
                        connection.cancel()
                        continuation.resume(returning: elapsedMs)
                    }
                case .failed, .cancelled:
                    if !stateLock.hasResumed {
                        stateLock.hasResumed = true
                        timer.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}
