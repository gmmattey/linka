import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Research has its own wire contract. Stored specification snapshots remain version 1.
public struct DeviceResearchQuery: Codable, Equatable, Sendable {
    public struct Context: Codable, Equatable, Sendable {
        public var hardwareRevision: String?
        public var marketRegion: String?
        public init(hardwareRevision: String? = nil, marketRegion: String? = nil) {
            self.hardwareRevision = hardwareRevision; self.marketRegion = marketRegion
        }
    }
    public var schemaVersion = 2
    public var query: String
    public var context: Context?
    public init(query: String, context: Context? = nil) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines); self.context = context
    }
    public var isValid: Bool {
        schemaVersion == 2 && !query.isEmpty && query.count <= 240 &&
        !query.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
        [context?.hardwareRevision, context?.marketRegion].allSatisfy { value in
            value == nil || (value!.count <= 120 && !value!.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))
        }
    }
}
public enum DeviceResearchStatus: String, Codable, Sendable { case available, ambiguous, notFound, unavailable }
public enum DeviceResearchReason: String, Codable, Sendable {
    case multipleMatches, noDocumentedData, providerTimeout, providerFailure, invalidEvidence, rateLimited, disabled, inProgress, budgetUnavailable
}
public struct DeviceResearchCandidate: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var identity: DeviceIdentity
    public var evidenceIDs: [String]
}
public struct DeviceResearchSource: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var url: URL
    public var title: String
    public var retrievedAt: Date
}
public struct DeviceResearchResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestID: String
    public var query: String
    public var status: DeviceResearchStatus
    public var reason: DeviceResearchReason?
    public var identity: DeviceIdentity?
    public var deviceKind: DeviceKind?
    public var candidates: [DeviceResearchCandidate]
    public var attributes: [SpecificationAttribute]
    public var sources: [DeviceResearchSource]
    public var checkedAt: Date

    public init(requestID: String = UUID().uuidString, query: String, status: DeviceResearchStatus, reason: DeviceResearchReason? = nil, identity: DeviceIdentity? = nil, deviceKind: DeviceKind? = nil, candidates: [DeviceResearchCandidate] = [], attributes: [SpecificationAttribute] = [], sources: [DeviceResearchSource] = [], checkedAt: Date = Date()) {
        self.schemaVersion = 2; self.requestID = requestID; self.query = query; self.status = status; self.reason = reason
        self.identity = identity; self.deviceKind = deviceKind; self.candidates = candidates; self.attributes = attributes; self.sources = sources; self.checkedAt = checkedAt
    }

    public func validate(for request: DeviceResearchQuery) throws {
        guard schemaVersion == 2, query == request.query, !requestID.isEmpty, requestID.count <= 100,
              candidates.count <= 10, sources.count <= 30, Set(candidates.map(\.id)).count == candidates.count else { throw NetworkInventoryError.invalidResponse }
        let evidence = Set(sources.map(\.id))
        for candidate in candidates {
            guard !candidate.id.isEmpty, candidate.id.count <= 100, !candidate.label.isEmpty, candidate.label.count <= 240,
                  candidate.identity.isValid, !candidate.evidenceIDs.isEmpty,
                  Set(candidate.evidenceIDs).count == candidate.evidenceIDs.count, candidate.evidenceIDs.allSatisfy(evidence.contains) else { throw NetworkInventoryError.invalidResponse }
        }
        switch status {
        case .available:
            guard let identity, identity.isValid, !attributes.isEmpty, candidates.isEmpty, reason == nil else { throw NetworkInventoryError.invalidResponse }
            try snapshot(for: identity, includeDeviceKind: true).validate(for: identity)
            if let deviceKind {
                guard attributes.contains(where: { $0.key == "deviceKind" && $0.value == deviceKind.rawValue }) else { throw NetworkInventoryError.invalidResponse }
            }
        case .ambiguous:
            guard identity == nil, attributes.isEmpty, !candidates.isEmpty, reason == .multipleMatches else { throw NetworkInventoryError.invalidResponse }
            for candidate in candidates { try snapshot(for: candidate.identity).validate(for: candidate.identity) }
        case .notFound:
            guard attributes.isEmpty, candidates.isEmpty, reason == .noDocumentedData else { throw NetworkInventoryError.invalidResponse }
            let expected = identity ?? DeviceIdentity(model: "Unidentified")
            try snapshot(for: expected).validate(for: expected)
        case .unavailable:
            guard attributes.isEmpty, candidates.isEmpty, sources.isEmpty, reason != nil,
                  reason != .multipleMatches, reason != .noDocumentedData else { throw NetworkInventoryError.invalidResponse }
        }
    }
    /// The user confirms this proposed identity before it becomes a registered device.
    public var proposedSnapshot: DeviceSpecificationSnapshot? {
        guard status == .available, let identity else { return nil }
        return snapshot(for: identity)
    }
    private func snapshot(for identity: DeviceIdentity, includeDeviceKind: Bool = false) -> DeviceSpecificationSnapshot {
        .init(identity: identity, status: .partial, attributes: attributes.filter { includeDeviceKind || $0.key != "deviceKind" },
              sources: sources.map { .init(id: $0.id, url: $0.url, title: $0.title, retrievedAt: $0.retrievedAt, matchedIdentity: identity) }, checkedAt: checkedAt)
    }
}
public protocol DeviceSpecResearchService: Sendable {
    func research(_ request: DeviceResearchQuery) async throws -> DeviceResearchResult
}
public struct HTTPDeviceSpecResearchService: DeviceSpecResearchService {
    public let endpoint: URL
    private let session: URLSession
    public init(endpoint: URL, session: URLSession = .shared) { self.endpoint = endpoint; self.session = session }
    public func research(_ input: DeviceResearchQuery) async throws -> DeviceResearchResult {
        try Task.checkCancellation()
        guard input.isValid, endpoint.scheme == "https" else { throw NetworkInventoryError.invalidDevice }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 100
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(input)
        let (bytes, response) = try await session.bytes(for: request, delegate: ResearchRedirectGuard())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == endpoint,
              response.expectedContentLength <= 256_000 else { bytes.task.cancel(); throw NetworkInventoryError.unavailable }
        var data = Data()
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 256_000 else { throw NetworkInventoryError.invalidResponse }
                data.append(byte)
            }
        } catch { bytes.task.cancel(); throw error }
        try Task.checkCancellation()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw NetworkInventoryError.invalidResponse }
            return date
        }
        let result: DeviceResearchResult
        do { result = try decoder.decode(DeviceResearchResult.self, from: data) }
        catch { throw NetworkInventoryError.invalidResponse }
        try result.validate(for: input)
        try Task.checkCancellation()
        return result
    }
}
private final class ResearchRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
