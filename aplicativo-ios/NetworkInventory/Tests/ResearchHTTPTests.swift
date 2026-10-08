import XCTest
import Foundation
@testable import NetworkInventory

private final class ResearchProtocol: URLProtocol {
    static let lock = NSLock()
    static var fixtures: [URL: Data] = [:]
    static var requests: [URL: URLRequest] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let data = Self.fixtures[request.url!]
        Self.requests[request.url!] = request
        Self.lock.unlock()
        guard let data else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class ResearchHTTPTests: XCTestCase {
    private let query = DeviceResearchQuery(query: " Nokia G-1425-B ")
    private var fixture: String {
        #"{"schemaVersion":2,"requestID":"q1","query":"Nokia G-1425-B","status":"available","reason":null,"identity":{"brand":"Nokia","model":"G-1425-B","hardwareRevision":null,"marketRegion":null},"deviceKind":"ont","candidates":[],"attributes":[{"key":"deviceKind","value":"ont","unit":null,"evidenceIDs":["s1"]},{"key":"lanPorts","value":"4","unit":null,"evidenceIDs":["s1"]}],"sources":[{"id":"s1","url":"https://example.com/manual.pdf","title":"Equipment manual","retrievedAt":"2026-10-08T12:00:00Z"}],"checkedAt":"2026-10-08T12:00:00.123Z"}"#
    }
    private func service(_ text: String) -> HTTPDeviceSpecResearchService {
        let url = URL(string: "https://\(UUID().uuidString).example/v2/device-specs/lookup")!
        ResearchProtocol.lock.lock(); ResearchProtocol.fixtures[url] = Data(text.utf8); ResearchProtocol.lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ResearchProtocol.self]
        return .init(endpoint: url, session: URLSession(configuration: configuration))
    }
    func testOpenQueryWithoutRevisionOrRegionMapsToLegacyStorage() async throws {
        let client = service(fixture)
        let result = try await client.research(query)
        XCTAssertEqual(result.status, .available)
        XCTAssertEqual(result.proposedSnapshot?.schemaVersion, 1)
        XCTAssertFalse(result.proposedSnapshot!.attributes.contains(where: { $0.key == "deviceKind" }))
        XCTAssertEqual(result.proposedSnapshot?.identity, .init(brand: "Nokia", model: "G-1425-B"))
        XCTAssertNoThrow(try result.proposedSnapshot?.validate(for: .init(brand: "Nokia", model: "G-1425-B")))
        let sent = Self.sentRequest(client.endpoint)
        XCTAssertEqual(sent?.timeoutInterval, 100)
        XCTAssertNil(sent?.value(forHTTPHeaderField: "Authorization"))
    }
    private static func sentRequest(_ url: URL) -> URLRequest? {
        ResearchProtocol.lock.lock(); defer { ResearchProtocol.lock.unlock() }
        return ResearchProtocol.requests[url]
    }
    func testRequestContainsOnlyQueryAndOptionalContext() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(query)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "query"])
        XCTAssertEqual(object["query"] as? String, "Nokia G-1425-B")
        XCTAssertTrue(DeviceResearchQuery(query: "G-1425-B").isValid)
    }
    func testIncorrectQueryAndUngroundedAttributeRejected() async {
        for payload in [fixture.replacingOccurrences(of: "\"query\":\"Nokia G-1425-B\"", with: "\"query\":\"Other\""), fixture.replacingOccurrences(of: "\"evidenceIDs\":[\"s1\"]", with: "\"evidenceIDs\":[\"missing\"]"), fixture.replacingOccurrences(of: "https://example.com/manual.pdf", with: "https://127.0.0.1/private")] {
            do { _ = try await service(payload).research(query); XCTFail("Untrusted research accepted") } catch {}
        }
    }
    func testTimeoutIsNotNotFound() async throws {
        let json = #"{"schemaVersion":2,"requestID":"q2","query":"Nokia G-1425-B","status":"unavailable","reason":"providerTimeout","identity":null,"deviceKind":null,"candidates":[],"attributes":[],"sources":[],"checkedAt":"2026-10-08T12:00:00Z"}"#
        let response = try await service(json).research(query)
        XCTAssertEqual(response.status, .unavailable)
        XCTAssertEqual(response.reason, .providerTimeout)
        XCTAssertNil(response.proposedSnapshot)
        let bad = json.replacingOccurrences(of: "\"status\":\"unavailable\"", with: "\"status\":\"notFound\"")
        do { _ = try await service(bad).research(query); XCTFail("Timeout disguised as absence") } catch {}
    }
    func testAmbiguityNeverBecomesAutomaticReplacement() async throws {
        let json = #"{"schemaVersion":2,"requestID":"q3","query":"Nokia G-1425-B","status":"ambiguous","reason":"multipleMatches","identity":null,"deviceKind":null,"candidates":[{"id":"candidate1","label":"Nokia G-1425G-B","identity":{"brand":"Nokia","model":"G-1425G-B"},"evidenceIDs":["s1"]}],"attributes":[],"sources":[{"id":"s1","url":"https://example.com/manual.pdf","title":"Manual","retrievedAt":"2026-10-08T12:00:00Z"}],"checkedAt":"2026-10-08T12:00:00Z"}"#
        let response = try await service(json).research(query)
        XCTAssertEqual(response.status, .ambiguous)
        XCTAssertEqual(response.candidates.first?.identity.model, "G-1425G-B")
        XCTAssertNil(response.identity)
        XCTAssertNil(response.proposedSnapshot)
    }
    func testCapturedProviderResultsDecodeWithoutLosingModelSeparation() async throws {
        // Recorded authenticated research outputs; this is a contract replay, not a new live lookup.
        let availableURL = try XCTUnwrap(Bundle.module.url(forResource: "nokia-g1425gb-v2-available", withExtension: "json"))
        let ambiguousURL = try XCTUnwrap(Bundle.module.url(forResource: "nokia-g1425b-v2-ambiguous", withExtension: "json"))
        let available = try await service(String(contentsOf: availableURL, encoding: .utf8)).research(.init(query: "Nokia G-1425G-B"))
        XCTAssertEqual(available.status, .available)
        XCTAssertEqual(available.attributes.count, 10)
        XCTAssertEqual(available.proposedSnapshot?.attributes.count, 9)
        XCTAssertEqual(available.sources.count, 2)
        XCTAssertEqual(available.identity?.model, "G-1425G-B")
        let ambiguous = try await service(String(contentsOf: ambiguousURL, encoding: .utf8)).research(.init(query: "Nokia G-1425-B"))
        XCTAssertEqual(ambiguous.status, .ambiguous)
        XCTAssertEqual(ambiguous.query, "Nokia G-1425-B")
        XCTAssertNil(ambiguous.proposedSnapshot)
        XCTAssertEqual(ambiguous.candidates.first?.identity.model, "G-1425G-B")
    }
    func testUnlabelledSecretsNeverBecomeBrandAcrossOCRLines() {
        for field in ["Password:", "SSID:", "Senha:", "WPA Key:", "Login:", "Serial:"] {
            let candidates = DeviceLabelParser.candidates(from: [field, "supersecret", "Model: G-1425-B"])
            XCTAssertEqual(candidates.first?.identity, .init(model: "G-1425-B"), field)
            XCTAssertFalse(candidates.contains(where: { $0.identity.brand.contains("supersecret") || $0.identity.model.contains("supersecret") }), field)
        }
    }
    func testNewBrandLabelIsAcceptedWithoutSendingSecrets() {
        let candidates = DeviceLabelParser.candidates(from: ["Manufacturer: New Vendor", "Model: ONT-42", "Password: never-send", "SSID: private-home"])
        XCTAssertEqual(candidates.first?.identity, .init(brand: "New Vendor", model: "ONT-42"))
        XCTAssertTrue(DeviceLabelParser.candidates(from: ["Manufacturer: New Vendor Password: never-send", "Model: ONT-42 SSID: private-home"]).isEmpty)
    }
}
