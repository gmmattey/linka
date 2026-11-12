import Foundation

/// Catálogo fechado: não identifica provedores por rede nem consulta um serviço
/// remoto. Os IPs são usados exclusivamente pela configuração DoH criada pela
/// pessoa, não para inferir o DNS upstream da conexão.
public struct DNSProvider: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let dohURL: URL
    public let bootstrapIPs: [String]
    public let privacyURL: URL

    public init(id: String, name: String, dohURL: URL, bootstrapIPs: [String], privacyURL: URL) {
        self.id = id
        self.name = name
        self.dohURL = dohURL
        self.bootstrapIPs = bootstrapIPs
        self.privacyURL = privacyURL
    }
}

public enum DNSProviderCatalog {
    public static let all: [DNSProvider] = [
        DNSProvider(id: "cloudflare", name: "Cloudflare", dohURL: URL(string: "https://cloudflare-dns.com/dns-query")!, bootstrapIPs: ["1.1.1.1", "1.0.0.1"], privacyURL: URL(string: "https://www.cloudflare.com/privacypolicy/")!),
        DNSProvider(id: "google", name: "Google", dohURL: URL(string: "https://dns.google/dns-query")!, bootstrapIPs: ["8.8.8.8", "8.8.4.4"], privacyURL: URL(string: "https://policies.google.com/privacy")!),
        DNSProvider(id: "quad9", name: "Quad9", dohURL: URL(string: "https://dns.quad9.net/dns-query")!, bootstrapIPs: ["9.9.9.9", "149.112.112.112"], privacyURL: URL(string: "https://www.quad9.net/privacy/policy/")!),
        DNSProvider(id: "opendns", name: "OpenDNS", dohURL: URL(string: "https://doh.opendns.com/dns-query")!, bootstrapIPs: ["208.67.222.222", "208.67.220.220"], privacyURL: URL(string: "https://www.cisco.com/c/en/us/about/legal/privacy-full.html")!),
        DNSProvider(id: "adguard", name: "AdGuard", dohURL: URL(string: "https://dns.adguard-dns.com/dns-query")!, bootstrapIPs: ["94.140.14.14", "94.140.15.15"], privacyURL: URL(string: "https://adguard.com/en/privacy.html")!)
    ]
}

public enum DNSProbeOutcome: Equatable, Sendable {
    case response(milliseconds: Double)
    case timedOut
    case failed
    case cancelled
}

public struct DNSBenchmarkCandidate: Identifiable, Equatable, Sendable {
    public let provider: DNSProvider
    public let samples: [DNSProbeOutcome]

    public init(provider: DNSProvider, samples: [DNSProbeOutcome]) {
        self.provider = provider
        self.samples = samples
    }

    public var id: String { provider.id }
    public var validSamples: [Double] { samples.compactMap { if case let .response(milliseconds) = $0 { return milliseconds }; return nil } }
    public var medianMilliseconds: Double? {
        let values = validSamples.sorted()
        guard values.count >= 2 else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }
    public var isInconclusive: Bool { medianMilliseconds == nil }
}

public struct DNSBenchmarkResult: Equatable, Sendable {
    public let candidates: [DNSBenchmarkCandidate]

    public init(candidates: [DNSBenchmarkCandidate]) { self.candidates = candidates }

    /// A ordem de exibição é estável: mediana crescente e catálogo como desempate.
    public var orderedCandidates: [DNSBenchmarkCandidate] {
        candidates.sorted {
            switch ($0.medianMilliseconds, $1.medianMilliseconds) {
            case let (left?, right?) where left != right: return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.provider.name.localizedCaseInsensitiveCompare($1.provider.name) == .orderedAscending
            }
        }
    }

    /// Vencedor apenas quando a menor mediana é estritamente menor; medianas
    /// iguais são empate, sem limiar editorial.
    public var winner: DNSBenchmarkCandidate? {
        let valid = candidates.compactMap { candidate -> DNSBenchmarkCandidate? in candidate.medianMilliseconds == nil ? nil : candidate }.sorted { $0.medianMilliseconds! < $1.medianMilliseconds! }
        guard let first = valid.first else { return nil }
        guard let second = valid.dropFirst().first else { return first }
        guard second.medianMilliseconds != first.medianMilliseconds else { return nil }
        return first
    }
}

public enum DNSBenchmarkPlan {
    public static let rounds = 3

    /// Todas as consultas de uma rodada usam o mesmo payload. A ordenação é
    /// rotacionada de modo determinístico para não privilegiar sempre o primeiro.
    public static func providers(forRound round: Int, catalog: [DNSProvider] = DNSProviderCatalog.all) -> [DNSProvider] {
        guard !catalog.isEmpty else { return [] }
        let offset = round % catalog.count
        return Array(catalog[offset...] + catalog[..<offset])
    }

    public static func syntheticQueryName(round: Int, nonce: String) -> String {
        "r\(round)-\(nonce.lowercased()).linka-dns-check.invalid"
    }
}

public enum DNSWireQuery {
    /// Consulta A minimalista em wire-format para DoH (RFC 8484). O nonce é
    /// igual para todos os provedores da rodada, mas muda entre rodadas.
    public static func makeAQuery(name: String, transactionID: UInt16) -> Data {
        var bytes: [UInt8] = [UInt8(transactionID >> 8), UInt8(transactionID & 0xFF), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in name.split(separator: ".") {
            bytes.append(UInt8(label.utf8.count))
            bytes.append(contentsOf: label.utf8)
        }
        bytes.append(0)
        bytes += [0, 1, 0, 1]
        return Data(bytes)
    }
}

public enum DNSWireResponse {
    /// Confere ID, QR, pergunta idêntica e um RCODE DNS válido para a sonda.
    /// NXDOMAIN (3) é esperado para um nome sintético; outros códigos não
    /// entram na mediana.
    public static func isValid(_ response: Data, for query: Data) -> Bool {
        guard response.count >= 12, query.count >= 12,
              response.prefix(2) == query.prefix(2), response[2] & 0x80 != 0,
              response[4] == 0, response[5] == 1 else { return false }
        let rcode = response[3] & 0x0F
        guard rcode == 0 || rcode == 3 else { return false }
        return response.count >= query.count && response[12..<query.count] == query[12..<query.count]
    }
}

public struct HTTPResponseParser: Sendable {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ fragment: Data) throws -> Data? {
        buffer.append(fragment)
        guard let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let header = String(data: buffer[..<boundary.lowerBound], encoding: .utf8), header.hasPrefix("HTTP/1.1 200") else { throw URLError(.badServerResponse) }
        let body = Data(buffer[boundary.upperBound...])
        let fields = header.components(separatedBy: "\r\n")
        if fields.contains(where: { $0.lowercased() == "transfer-encoding: chunked" }) { return try chunked(body) }
        guard let line = fields.first(where: { $0.lowercased().hasPrefix("content-length:") }),
              let separator = line.firstIndex(of: ":"),
              let length = Int(line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)), length >= 0 else { throw URLError(.badServerResponse) }
        return body.count >= length ? Data(body.prefix(length)) : nil
    }
    private func chunked(_ body: Data) throws -> Data? {
        var rest = body; var output = Data()
        while true {
            guard let end = rest.range(of: Data("\r\n".utf8)), let size = Int(String(data: rest[..<end.lowerBound], encoding: .utf8)!, radix: 16) else { return nil }
            rest = Data(rest[end.upperBound...]); guard rest.count >= size + 2 else { return nil }
            if size == 0 { return output }
            output.append(rest.prefix(size)); guard Data(rest.dropFirst(size).prefix(2)) == Data("\r\n".utf8) else { throw URLError(.badServerResponse) }
            rest = Data(rest.dropFirst(size + 2))
        }
    }
}
