import Foundation
import Network

/// Referência curta de rota UDP pública da AWS GameLift. Não consulta IP,
/// GPS nem faz fallback para HTTP/ICMP; ausência de resposta é inconclusiva.
public struct GameLiftRegionalReferenceProbe: Sendable {
    private final class ContinuationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var completed = false
        func resume(_ continuation: CheckedContinuation<Double?, Never>, with value: Double?) {
            lock.lock(); defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            continuation.resume(returning: value)
        }
    }
    private struct Candidate: Sendable {
        let id: String
        let host: String
    }

    public static let catalogVersion = "gamelift-static-2026-09-21.1"
    private static let candidates = [
        Candidate(id: "sa-east-1", host: "gamelift-ping.sa-east-1.api.aws"),
        Candidate(id: "us-east-1", host: "gamelift-ping.us-east-1.api.aws"),
        Candidate(id: "us-west-2", host: "gamelift-ping.us-west-2.api.aws"),
        Candidate(id: "eu-west-1", host: "gamelift-ping.eu-west-1.api.aws"),
        Candidate(id: "eu-central-1", host: "gamelift-ping.eu-central-1.api.aws"),
        Candidate(id: "ap-southeast-1", host: "gamelift-ping.ap-southeast-1.api.aws"),
        Candidate(id: "ap-northeast-1", host: "gamelift-ping.ap-northeast-1.api.aws")
    ]

    public init() {}

    public func measure(locale: Locale = .current) async -> EngineRegionalGameReference {
        let ordered = Self.orderedCandidates(for: locale)
        var evaluated: [(Candidate, [Double], Int)] = []
        for candidate in ordered.prefix(3) {
            let samples = await Self.samples(for: candidate, count: 3)
            let valid = samples.compactMap { $0 }
            evaluated.append((candidate, valid, samples.count - valid.count))
        }
        guard let winner = Self.select(evaluated) else {
            let attempts = evaluated.count * 3
            let timeouts = evaluated.reduce(0) { $0 + $1.2 }
            return EngineRegionalGameReference(catalogVersion: Self.catalogVersion, regionIdentifier: nil, p50LatencyMs: nil, jitterMs: nil, attemptCount: attempts, validResponseCount: 0, timeoutCount: timeouts, packetLossPercent: attempts > 0 ? 100 : nil, isMeasured: false)
        }
        let confirmation = await Self.samples(for: winner.0, count: 3)
        let all = winner.1 + confirmation.compactMap { $0 }
        let attempts = 6
        let timeouts = winner.2 + confirmation.filter { $0 == nil }.count
        guard all.count >= 2, let p50 = Self.median(all) else {
            return EngineRegionalGameReference(catalogVersion: Self.catalogVersion, regionIdentifier: nil, p50LatencyMs: nil, jitterMs: nil, attemptCount: attempts, validResponseCount: all.count, timeoutCount: timeouts, packetLossPercent: Double(attempts - all.count) / Double(attempts) * 100, isMeasured: false)
        }
        let jitter = all.count < 2 ? nil : zip(all.dropFirst(), all).map { abs($0 - $1) }.reduce(0, +) / Double(all.count - 1)
        return EngineRegionalGameReference(catalogVersion: Self.catalogVersion, regionIdentifier: winner.0.id, p50LatencyMs: p50, jitterMs: jitter, attemptCount: attempts, validResponseCount: all.count, timeoutCount: timeouts, packetLossPercent: Double(attempts - all.count) / Double(attempts) * 100, isMeasured: true)
    }

    private static func orderedCandidates(for locale: Locale) -> [Candidate] {
        let region = locale.region?.identifier.uppercased() ?? ""
        let preferred: [String]
        switch region {
        case "BR", "AR", "CL", "CO", "PE": preferred = ["sa-east-1", "us-east-1", "us-west-2"]
        case "GB", "IE", "FR", "DE", "ES", "PT", "IT": preferred = ["eu-west-1", "eu-central-1", "us-east-1"]
        case "JP", "KR", "SG", "AU", "IN": preferred = ["ap-northeast-1", "ap-southeast-1", "us-east-1"]
        default: preferred = ["us-east-1", "eu-west-1", "ap-southeast-1"]
        }
        return preferred.compactMap { id in candidates.first { $0.id == id } }
    }

    private static func select(_ values: [(Candidate, [Double], Int)]) -> (Candidate, [Double], Int)? {
        let eligible = values.compactMap { value -> (Candidate, [Double], Int, Double)? in
            guard value.1.count >= 2, let p50 = median(value.1) else { return nil }
            return (value.0, value.1, value.2, p50)
        }
        guard !eligible.isEmpty else { return nil }
        let sorted = eligible.sorted { lhs, rhs in
            if abs(lhs.3 - rhs.3) >= 6 { return lhs.3 < rhs.3 }
            if lhs.1.count != rhs.1.count { return lhs.1.count > rhs.1.count }
            return lhs.0.id < rhs.0.id
        }
        let selected = sorted[0]
        return (selected.0, selected.1, selected.2)
    }

    private static func samples(for candidate: Candidate, count: Int) async -> [Double?] {
        var values: [Double?] = []
        for sequence in 0..<count {
            guard !Task.isCancelled else { return [] }
            values.append(await udpEcho(host: candidate.host, sequence: sequence))
        }
        return values
    }

    private static func udpEcho(host: String, sequence: Int) async -> Double? {
        await rawEcho(host: host, sequence: sequence)
    }

    private static func rawEcho(host: String, sequence: Int) async -> Double? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: 7770, using: .udp)
            let queue = DispatchQueue(label: "com.linka.gamelift.reference")
            let session = UUID().uuidString.data(using: .utf8) ?? Data()
            var payload = Data([0x4E, 0x4C, 0x50, 0x47, 0x01])
            payload.append(session.prefix(16))
            payload.append(contentsOf: withUnsafeBytes(of: UInt32(sequence).bigEndian, Array.init))
            payload.append(contentsOf: withUnsafeBytes(of: UInt64.random(in: .min ... .max).bigEndian, Array.init))
            let start = DispatchTime.now().uptimeNanoseconds
            let gate = ContinuationGate()
            let timeout = DispatchWorkItem {
                connection.cancel()
                gate.resume(continuation, with: nil)
            }
            connection.start(queue: queue)
            connection.receiveMessage { data, _, _, _ in
                timeout.cancel()
                defer { connection.cancel() }
                guard data == payload else { gate.resume(continuation, with: nil); return }
                gate.resume(continuation, with: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            connection.send(content: payload, completion: .contentProcessed { error in
                if error != nil {
                    timeout.cancel()
                    connection.cancel()
                    gate.resume(continuation, with: nil)
                }
            })
            queue.asyncAfter(deadline: .now() + 1.5, execute: timeout)
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
