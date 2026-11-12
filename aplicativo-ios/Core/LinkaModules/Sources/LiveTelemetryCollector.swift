import Foundation
import Network
import NetworkCore
import NetworkInsights
import MeasurementHistory

/// Amostra individual registrada na janela deslizante de telemetria ao vivo.
public struct LiveProbeSample: Equatable, Sendable {
    public let timestamp: Date
    public let rttMs: Double?

    public init(timestamp: Date = Date(), rttMs: Double?) {
        self.timestamp = timestamp
        self.rttMs = rttMs
    }
}

/// Buffer com janela deslizante (Sliding Window) para cálculo contínuo de RTT mediano, Jitter (RFC 3550) e Perda.
public struct SlidingWindowTelemetryBuffer: Equatable, Sendable {
    public let maxCapacity: Int
    public let maxSampleAgeSeconds: TimeInterval
    private(set) public var samples: [LiveProbeSample] = []

    public init(maxCapacity: Int = 8, maxSampleAgeSeconds: TimeInterval = 30) {
        self.maxCapacity = maxCapacity
        self.maxSampleAgeSeconds = maxSampleAgeSeconds
    }

    public mutating func append(sample: LiveProbeSample) {
        samples.append(sample)
        pruneOldSamples(referenceDate: sample.timestamp)
        if samples.count > maxCapacity {
            samples.removeFirst(samples.count - maxCapacity)
        }
    }

    public mutating func clear() {
        samples.removeAll(keepingCapacity: true)
    }

    public mutating func pruneOldSamples(referenceDate: Date = Date()) {
        samples.removeAll { referenceDate.timeIntervalSince($0.timestamp) > maxSampleAgeSeconds }
    }

    /// Mediana dos tempos RTT das amostras válidas na janela.
    public var medianLatencyMs: Double? {
        let valid = samples.compactMap { $0.rttMs }.sorted()
        guard !valid.isEmpty else { return nil }
        let count = valid.count
        if count % 2 == 1 {
            return valid[count / 2]
        } else {
            return (valid[(count / 2) - 1] + valid[count / 2]) / 2.0
        }
    }

    /// Jitter calculado conforme RFC 3550 (variação média entre amostras consecutivas).
    /// Retorna `nil` se houver menos de 3 amostras válidas (ausência não é zero).
    public var jitterMs: Double? {
        let valid = samples.compactMap { $0.rttMs }
        guard valid.count >= 3 else { return nil }
        var totalDiff: Double = 0
        for i in 1..<valid.count {
            totalDiff += abs(valid[i] - valid[i - 1])
        }
        return totalDiff / Double(valid.count - 1)
    }

    /// Percentual de falhas/timeouts na janela (0 a 100%).
    public var packetLossPercent: Double? {
        guard !samples.isEmpty else { return nil }
        let lostCount = samples.filter { $0.rttMs == nil }.count
        return (Double(lostCount) / Double(samples.count)) * 100.0
    }

    public var sampleCount: Int {
        samples.count
    }
}

/// Coletor orquestrador de telemetria ao vivo.
///
/// Monitora o caminho de rede passivamente e dispara sondas efêmeras ultra-leves
/// quando o app está ativo e a medição pesada não está em curso.
public final class LiveTelemetryCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = SlidingWindowTelemetryBuffer()
    private var isSuspended: Bool = false
    private var pollingTask: Task<Void, Never>?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 2.0
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    public init() {}

    deinit {
        stop()
    }

    public func recordProbe(rttMs: Double?, timestamp: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(sample: LiveProbeSample(timestamp: timestamp, rttMs: rttMs))
    }

    public func clearBuffer() {
        lock.lock()
        defer { lock.unlock() }
        buffer.clear()
    }

    public func snapshot(
        connectionKind: NetworkConnectionKind?,
        interfaceLabel: String,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        wifiLinkSpeedMbps: Double? = nil,
        wifiRssiDbm: Double? = nil
    ) -> LiveNetworkTelemetrySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return LiveNetworkTelemetrySnapshot(
            timestamp: Date(),
            connectionKind: connectionKind,
            interfaceLabel: interfaceLabel,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            latencyMs: buffer.medianLatencyMs,
            jitterMs: buffer.jitterMs,
            packetLossPercent: buffer.packetLossPercent,
            wifiLinkSpeedMbps: wifiLinkSpeedMbps,
            wifiRssiDbm: wifiRssiDbm,
            sampleCount: buffer.sampleCount
        )
    }

    public func start(
        probeIntervalSeconds: TimeInterval = 4.0,
        probeURL: URL = URL(string: "https://www.apple.com/library/test/success.html")!,
        onUpdate: (@Sendable (LiveNetworkTelemetrySnapshot) -> Void)? = nil
    ) {
        stop()
        lock.lock()
        isSuspended = false
        lock.unlock()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                let suspended: Bool = {
                    self.lock.lock()
                    defer { self.lock.unlock() }
                    return self.isSuspended
                }()

                if !suspended {
                    await self.performProbe(target: probeURL)
                }

                try? await Task.sleep(nanoseconds: UInt64(probeIntervalSeconds * 1_000_000_000))
            }
        }
    }

    public func suspend() {
        lock.lock()
        defer { lock.unlock() }
        isSuspended = true
    }

    public func resume() {
        lock.lock()
        defer { lock.unlock() }
        isSuspended = false
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func performProbe(target: URL) async {
        let start = Date()
        do {
            let (_, response) = try await session.data(from: target)
            let rtt = Date().timeIntervalSince(start) * 1000.0
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode >= 200 && statusCode < 400 {
                recordProbe(rttMs: rtt)
            } else {
                recordProbe(rttMs: nil)
            }
        } catch {
            recordProbe(rttMs: nil)
        }
    }

    /// Busca a vazão histórica elegível para o SSID da rede Wi-Fi atual.
    ///
    /// `NetworkMeasurement.networkIdentifier` identifica o provedor/servidor
    /// do teste, não a rede local. Nunca pode ser usado para reaproveitar uma
    /// medição de throughput na Home.
    public static func fetchThroughputBaseline(
        forWiFiSSID ssid: String?,
        maxAge: TimeInterval = 14400,
        repository: any MeasurementHistoryRepository
    ) async -> ThroughputBaseline? {
        guard let ssid, !ssid.isEmpty else { return nil }
        let query = MeasurementQuery(
            outcomes: [.complete],
            sortOrder: .newestFirst
        )
        guard let list = try? await repository.measurements(matching: query) else {
            return nil
        }
        let matching = list.filter {
            $0.wifiContext?.ssid == ssid
                && $0.uploadMbps != nil
                && Date().timeIntervalSince($0.measuredAt) <= maxAge
        }
        guard let latest = matching.first,
              let dl = latest.downloadMbps, dl > 0,
              let upload = latest.uploadMbps, upload > 0 else {
            return nil
        }
        return ThroughputBaseline(
            downloadMbps: dl,
            uploadMbps: upload,
            lastMeasuredAt: latest.measuredAt,
            networkIdentifier: ssid,
            sampleCount: matching.count
        )
    }
}
