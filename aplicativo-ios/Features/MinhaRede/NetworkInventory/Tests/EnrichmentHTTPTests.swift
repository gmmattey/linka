import XCTest
import Foundation
@testable import NetworkInventory
private final class LookupProtocol: URLProtocol {
    static let lock = NSLock()
    static var fixtures: [URL: (Data, URL)] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let fixture = Self.fixtures[request.url!]; Self.lock.unlock()
        guard let (data, finalURL) = fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: finalURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class EnrichmentHTTPTests: XCTestCase {
    private func service(_ payload: String, mismatchURL: Bool = false) -> HTTPDeviceSpecEnrichmentService {
        let endpoint = URL(string: "https://\(UUID().uuidString).example/lookup")!
        LookupProtocol.lock.lock(); LookupProtocol.fixtures[endpoint] = (Data(payload.utf8), mismatchURL ? URL(string: "https://other.example/lookup")! : endpoint); LookupProtocol.lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [LookupProtocol.self]
        return .init(endpoint: endpoint, session: URLSession(configuration: configuration))
    }
    private var json: String { #"{"schemaVersion":1,"identity":{"brand":"TP-Link","model":"C6","marketRegion":"BR"},"status":"partial","attributes":[],"sources":[],"checkedAt":"2026-10-08T12:00:00.123Z"}"# }
    func testFractionalDateAndNormalizedIdentity() async throws {
        let identity = DeviceIdentity(brand: " TP-Link ", model: " C6 ", marketRegion: " br ")
        let result = try await service(json).enrich(identity: identity)
        XCTAssertEqual(result.identity.marketRegion, "BR")
        XCTAssertTrue(identity.isResearchable)
        XCTAssertFalse(DeviceIdentity(model: "C6").isResearchable)
        XCTAssertTrue(DeviceIdentity(model: "C6").isValid)
    }
    func testExtraWireFieldsRejected() async {
        let payload = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"unexpected\":true")
        do { _ = try await service(payload).enrich(identity: .init(brand: "TP-Link", model: "C6", marketRegion: "BR")); XCTFail() } catch {}
    }
    func testDifferentFinalURLRejected() async {
        do { _ = try await service(json, mismatchURL: true).enrich(identity: .init(brand: "TP-Link", model: "C6", marketRegion: "BR")); XCTFail() } catch {}
    }
    func testOversizedStreamRejected() async {
        do { _ = try await service(String(repeating: " ", count: 256_001)).enrich(identity: .init(brand: "TP-Link", model: "C6")); XCTFail() } catch {}
    }
}
