import Foundation
import Darwin

public struct LatencyProbeResult: Sendable, Equatable {
    public let medianLatencyMs: Double
    public let p95LatencyMs: Double
    public let meanLatencyMs: Double
    public let jitterMs: Double
    public let packetLossPercent: Double
    public let samples: [Double]
    public let lostCount: Int
    public let totalProbes: Int
    public let consecutiveLossCount: Int
    public let lossInterpretation: LossInterpretation
    public let didRunAdaptiveConfirmation: Bool

    public init(
        medianLatencyMs: Double,
        p95LatencyMs: Double,
        meanLatencyMs: Double,
        jitterMs: Double,
        packetLossPercent: Double,
        samples: [Double],
        lostCount: Int = 0,
        totalProbes: Int = 0,
        consecutiveLossCount: Int = 0,
        lossInterpretation: LossInterpretation = .stable,
        didRunAdaptiveConfirmation: Bool = false
    ) {
        self.medianLatencyMs = medianLatencyMs
        self.p95LatencyMs = p95LatencyMs
        self.meanLatencyMs = meanLatencyMs
        self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent
        self.samples = samples
        self.lostCount = lostCount
        self.totalProbes = totalProbes
        self.consecutiveLossCount = consecutiveLossCount
        self.lossInterpretation = lossInterpretation
        self.didRunAdaptiveConfirmation = didRunAdaptiveConfirmation
    }

    /// Inicializador de compatibilidade legado
    public init(
        meanLatencyMs: Double,
        jitterMs: Double,
        packetLossPercent: Double,
        samples: [Double]
    ) {
        let sorted = samples.sorted()
        let median = GatewayLatencyProber.calculateMedian(sorted)
        let p95 = GatewayLatencyProber.calculateP95(sorted)
        self.init(
            medianLatencyMs: samples.isEmpty ? meanLatencyMs : median,
            p95LatencyMs: samples.isEmpty ? meanLatencyMs : p95,
            meanLatencyMs: meanLatencyMs,
            jitterMs: jitterMs,
            packetLossPercent: packetLossPercent,
            samples: samples,
            lostCount: 0,
            totalProbes: samples.count,
            consecutiveLossCount: 0,
            lossInterpretation: packetLossPercent == 0 ? .stable : (packetLossPercent <= 5 ? .isolatedEvent : .confirmedLoss),
            didRunAdaptiveConfirmation: false
        )
    }
}

public actor GatewayLatencyProber {
    private let targetPorts: [UInt16] = [53, 80, 443, 8080]

    public init() {}

    /// Dispara uma sequência determinística de probes RTT até o Gateway com amostragem adaptativa
    public func probe(
        gatewayIP: String,
        sampleCount: Int = 20,
        timeoutSeconds: Double = 0.5,
        enableAdaptiveProbing: Bool = true,
        onAdaptiveConfirmation: (@Sendable () -> Void)? = nil
    ) async -> LatencyProbeResult {
        var successfulRTTs: [Double] = []
        var lostCount = 0
        var currentConsecutiveLosses = 0
        var maxConsecutiveLosses = 0

        // Descobre uma porta que responde mais prontamente
        let selectedPort = await discoverResponsivePort(gatewayIP: gatewayIP)

        // Etapa 1: Rodada Inicial (ex: 20 probes, 80ms intervalo, 500ms timeout)
        for _ in 0..<sampleCount {
            if Task.isCancelled { break }

            if await !LocalNetworkPermissionService.shared.isAppActiveAsync {
                let returned = await LocalNetworkPermissionService.shared.waitForAppToBeActive(timeoutSeconds: 20.0)
                if !returned || Task.isCancelled {
                    break
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            if let rtt = await measureSingleRTT(host: gatewayIP, port: selectedPort, timeoutSeconds: timeoutSeconds) {
                successfulRTTs.append(rtt)
                currentConsecutiveLosses = 0
            } else {
                if await LocalNetworkPermissionService.shared.isAppActiveAsync {
                    lostCount += 1
                    currentConsecutiveLosses += 1
                    maxConsecutiveLosses = max(maxConsecutiveLosses, currentConsecutiveLosses)
                }
            }

            // Intervalo rápido de 80ms entre probes (RFC 7680 timing calibration)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        // Etapa 2: Avaliação da necessidade de confirmação adaptativa (+20 probes)
        var didRunAdaptiveConfirmation = false
        if enableAdaptiveProbing && !Task.isCancelled {
            let sortedInitial = successfulRTTs.sorted()
            let initialP95 = Self.calculateP95(sortedInitial)
            let hasSuspectedAnomaly = lostCount > 0 || initialP95 > 80.0

            if hasSuspectedAnomaly {
                didRunAdaptiveConfirmation = true
                onAdaptiveConfirmation?()

                // Envia segunda bateria de 20 probes para confirmação
                for _ in 0..<sampleCount {
                    if Task.isCancelled { break }

                    if await !LocalNetworkPermissionService.shared.isAppActiveAsync {
                        let returned = await LocalNetworkPermissionService.shared.waitForAppToBeActive(timeoutSeconds: 20.0)
                        if !returned || Task.isCancelled { break }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }

                    if let rtt = await measureSingleRTT(host: gatewayIP, port: selectedPort, timeoutSeconds: timeoutSeconds) {
                        successfulRTTs.append(rtt)
                        currentConsecutiveLosses = 0
                    } else {
                        if await LocalNetworkPermissionService.shared.isAppActiveAsync {
                            lostCount += 1
                            currentConsecutiveLosses += 1
                            maxConsecutiveLosses = max(maxConsecutiveLosses, currentConsecutiveLosses)
                        }
                    }

                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
            }
        }

        let totalProbes = successfulRTTs.count + lostCount
        let lossPercent = totalProbes > 0 ? (Double(lostCount) / Double(totalProbes)) * 100.0 : 100.0

        let sorted = successfulRTTs.sorted()
        let medianLatency = Self.calculateMedian(sorted)
        let p95Latency = Self.calculateP95(sorted)

        let meanLatency: Double
        if !successfulRTTs.isEmpty {
            let sum = successfulRTTs.reduce(0.0, +)
            meanLatency = sum / Double(successfulRTTs.count)
        } else {
            meanLatency = 999.0
        }

        // Cálculo determinístico do Jitter (RFC 3550 / média das diferenças sucessivas)
        let jitter: Double
        if successfulRTTs.count > 1 {
            var diffSum = 0.0
            for i in 1..<successfulRTTs.count {
                diffSum += abs(successfulRTTs[i] - successfulRTTs[i - 1])
            }
            jitter = diffSum / Double(successfulRTTs.count - 1)
        } else {
            jitter = 0.0
        }

        // Interpretação estatística de perda (RFC 7680)
        let interpretation: LossInterpretation
        if totalProbes == 0 || lostCount == totalProbes {
            interpretation = .severeLoss
        } else if lostCount == 0 {
            interpretation = .stable
        } else if lostCount == 1 && maxConsecutiveLosses <= 1 {
            // 1 perda isolada (na janela de 20 ou 40): evento isolado (não penalizar duramente)
            interpretation = .isolatedEvent
        } else if maxConsecutiveLosses >= 2 {
            interpretation = .consecutiveLoss
        } else if lostCount >= 2 {
            interpretation = .confirmedLoss
        } else {
            interpretation = .stable
        }

        return LatencyProbeResult(
            medianLatencyMs: round(medianLatency * 10) / 10,
            p95LatencyMs: round(p95Latency * 10) / 10,
            meanLatencyMs: round(meanLatency * 10) / 10,
            jitterMs: round(jitter * 10) / 10,
            packetLossPercent: round(lossPercent * 10) / 10,
            samples: successfulRTTs,
            lostCount: lostCount,
            totalProbes: totalProbes,
            consecutiveLossCount: maxConsecutiveLosses,
            lossInterpretation: interpretation,
            didRunAdaptiveConfirmation: didRunAdaptiveConfirmation
        )
    }

    public static func calculateMedian(_ sortedValues: [Double]) -> Double {
        guard !sortedValues.isEmpty else { return 999.0 }
        let count = sortedValues.count
        if count % 2 == 1 {
            return sortedValues[count / 2]
        } else {
            return (sortedValues[count / 2 - 1] + sortedValues[count / 2]) / 2.0
        }
    }

    public static func calculateP95(_ sortedValues: [Double]) -> Double {
        guard !sortedValues.isEmpty else { return 999.0 }
        let count = sortedValues.count
        let index = max(0, min(count - 1, Int(ceil(Double(count) * 0.95)) - 1))
        return sortedValues[index]
    }

    /// Testa portas comuns para selecionar a que responde mais rápido
    private func discoverResponsivePort(gatewayIP: String) async -> UInt16 {
        for port in targetPorts {
            if let _ = await measureSingleRTT(host: gatewayIP, port: port, timeoutSeconds: 0.3) {
                return port
            }
        }
        return 53 // Default para roteadores domésticos (DNS local)
    }

    /// Mede o RTT de um handshake TCP na camada de sockets BSD com medição em nanosegundos
    private func measureSingleRTT(host: String, port: UInt16, timeoutSeconds: Double) async -> Double? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var serverAddr = sockaddr_in()
                serverAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                serverAddr.sin_family = sa_family_t(AF_INET)
                serverAddr.sin_port = port.bigEndian

                guard inet_pton(AF_INET, host, &serverAddr.sin_addr) == 1 else {
                    continuation.resume(returning: nil)
                    return
                }

                let sock = socket(AF_INET, SOCK_STREAM, 0)
                guard sock >= 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { close(sock) }

                // Torna o socket não bloqueante para controlar o timeout via poll/select
                let flags = fcntl(sock, F_GETFL, 0)
                _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

                let startTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

                let connectRes = withUnsafePointer(to: &serverAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        connect(sock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                if connectRes == 0 {
                    let endTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                    let rttMs = Double(endTime - startTime) / 1_000_000.0
                    continuation.resume(returning: rttMs)
                    return
                }

                if errno != EINPROGRESS {
                    continuation.resume(returning: nil)
                    return
                }

                // Aguarda conclusão da conexão via poll
                var pfd = pollfd(fd: sock, events: Int16(POLLOUT | POLLERR | POLLHUP), revents: 0)
                let timeoutMs = Int32(timeoutSeconds * 1000.0)
                let pollRes = poll(&pfd, 1, timeoutMs)

                if pollRes > 0 {
                    var err: Int32 = 0
                    var len = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len)

                    // Em redes locais, tanto resposta SYN-ACK (err == 0) quanto RST (err == ECONNREFUSED)
                    // confirmam que o pacote chegou ao roteador e retornou pela interface de rádio!
                    if err == 0 || err == ECONNREFUSED {
                        let endTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                        let rttMs = Double(endTime - startTime) / 1_000_000.0
                        continuation.resume(returning: rttMs)
                        return
                    }
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
