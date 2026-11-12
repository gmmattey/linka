import XCTest
@testable import LinkaEngine

final class URLSessionSpeedTestTransportRequestTests: XCTestCase {
    private let download = URL(string: "https://speed.cloudflare.com/__down?bytes=10000000")!

    func testCloudflareDownloadCarriesOriginContextAndCacheBuster() throws {
        let request = URLSessionSpeedTestTransport.makeRequest(for: .download(download), cacheBuster: "abc")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://speed.cloudflare.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://speed.cloudflare.com/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        let url = try XCTUnwrap(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "bytes" }?.value, "10000000", "o tamanho do bloco não pode mudar")
        XCTAssertEqual(items.first { $0.name == "_cb" }?.value, "abc")
    }

    func testProbeKeepsHeadAndShortTimeout() {
        let probe = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
        let request = URLSessionSpeedTestTransport.makeRequest(for: .probe(probe), cacheBuster: "x")
        XCTAssertEqual(request.httpMethod, "HEAD")
        XCTAssertEqual(request.timeoutInterval, 1)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://speed.cloudflare.com")
    }

    func testUploadIsPostWithoutCacheBusterQuery() {
        let upload = URL(string: "https://speed.cloudflare.com/__up")!
        let request = URLSessionSpeedTestTransport.makeRequest(for: .upload(upload, Data([1])), cacheBuster: "x")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, upload)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://speed.cloudflare.com")
    }

    func testOtherHostsDoNotReceiveCloudflareOrigin() {
        let other = URL(string: "https://example.com/__down?bytes=1")!
        let request = URLSessionSpeedTestTransport.makeRequest(for: .download(other), cacheBuster: "x")
        XCTAssertNil(request.value(forHTTPHeaderField: "Origin"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
    }
}
