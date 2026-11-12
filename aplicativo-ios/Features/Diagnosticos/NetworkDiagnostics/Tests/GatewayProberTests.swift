import Foundation
import XCTest
@testable import NetworkDiagnostics

final class GatewayProberTests: XCTestCase {
    override func tearDown() {
        RedirectingGatewayURLProtocol.handler = nil
        super.tearDown()
    }

    func testProbeRejectsARedirectThatLeavesTheGatewayHost() async {
        RedirectingGatewayURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "https://outside.example"]
            )!
            return (response, nil)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingGatewayURLProtocol.self]
        let prober = GatewayProber(sessionConfiguration: configuration)

        let result = await prober.probe(gatewayIP: "192.168.1.1")

        XCTAssertFalse(result.isAccessible)
        XCTAssertEqual(result.adminURL?.host, "192.168.1.1")
    }
}

private final class RedirectingGatewayURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
