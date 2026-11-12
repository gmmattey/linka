import XCTest
@testable import NetworkDNSBenchmark

final class NetworkDNSBenchmarkTests: XCTestCase {
    func testCatalogHasFiveNamedProviders() {
        XCTAssertEqual(DNSProviderCatalog.all.map(\.name), ["Cloudflare", "Google", "Quad9", "OpenDNS", "AdGuard"])
    }

    func testMedianNeedsTwoValidSamplesAndIgnoresFailures() {
        let provider = DNSProviderCatalog.all[0]
        XCTAssertNil(DNSBenchmarkCandidate(provider: provider, samples: [.response(milliseconds: 10), .failed]).medianMilliseconds)
        XCTAssertEqual(DNSBenchmarkCandidate(provider: provider, samples: [.response(milliseconds: 30), .failed, .response(milliseconds: 10)]).medianMilliseconds, 20)
    }

    func testEqualMediansHaveNoWinner() {
        let candidates = DNSProviderCatalog.all.prefix(2).map { DNSBenchmarkCandidate(provider: $0, samples: [.response(milliseconds: 20), .response(milliseconds: 20)]) }
        XCTAssertNil(DNSBenchmarkResult(candidates: candidates).winner)
    }

    func testEachRoundRotatesSameCatalog() {
        XCTAssertEqual(DNSBenchmarkPlan.providers(forRound: 0).map(\.id), ["cloudflare", "google", "quad9", "opendns", "adguard"])
        XCTAssertEqual(DNSBenchmarkPlan.providers(forRound: 1).map(\.id), ["google", "quad9", "opendns", "adguard", "cloudflare"])
    }

    func testRoundNonceChangesNameButKeepsPayloadEqualForProviders() {
        let first = DNSBenchmarkPlan.syntheticQueryName(round: 0, nonce: "abcd")
        let second = DNSBenchmarkPlan.syntheticQueryName(round: 1, nonce: "efgh")
        XCTAssertNotEqual(first, second)
        let query = DNSWireQuery.makeAQuery(name: first, transactionID: 42)
        XCTAssertTrue(query.contains(Data("r0-abcd".utf8)))
        XCTAssertTrue(DNSWireResponse.isValid(queryWithResponseBit(query, rcode: 3), for: query))
    }

    func testInvalidResponseNeverBecomesAValidSample() {
        let query = DNSWireQuery.makeAQuery(name: "r0-nonce.linka-dns-check.invalid", transactionID: 42)
        XCTAssertFalse(DNSWireResponse.isValid(queryWithResponseBit(query, rcode: 2), for: query))
        var wrongID = queryWithResponseBit(query, rcode: 3)
        wrongID[1] = 43
        XCTAssertFalse(DNSWireResponse.isValid(wrongID, for: query))
    }

    func testCancelledSamplesAreInconclusive() {
        let candidate = DNSBenchmarkCandidate(provider: DNSProviderCatalog.all[0], samples: [.response(milliseconds: 12), .cancelled, .failed])
        XCTAssertTrue(candidate.isInconclusive)
    }
    func testHTTPParserHandlesArbitraryFragmentsAndChunked() throws {
        var parser = HTTPResponseParser()
        XCTAssertNil(try parser.append(Data("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r".utf8)))
        XCTAssertEqual(try parser.append(Data("\nabc".utf8)), Data("abc".utf8))
        var chunked = HTTPResponseParser()
        XCTAssertNil(try chunked.append(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\na".utf8)))
        XCTAssertEqual(try chunked.append(Data("bc\r\n0\r\n\r\n".utf8)), Data("abc".utf8))
    }
    func testConnectionGateCompletesOnlyOnceAndPathGateCancelsOnSecondCallback() {
        let connection = DNSConnectionCompletionGate(); var completions = 0
        connection.resolveOnce { completions += 1 }; connection.resolveOnce { completions += 1 }
        XCTAssertEqual(completions, 1)
        let path = DNSPathSessionGate(); var invalidations = 0
        path.receiveUpdate { invalidations += 1 }; path.receiveUpdate { invalidations += 1 }
        XCTAssertEqual(invalidations, 1)
    }

    private func queryWithResponseBit(_ query: Data, rcode: UInt8) -> Data {
        var response = query
        response[2] |= 0x80
        response[3] = rcode
        return response
    }
}
