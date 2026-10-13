import XCTest
@testable import LinkaApp

final class PublicUniversalLinkParserTests: XCTestCase {
    func testAcceptsOnlyDocumentedCanonicalRoutes() {
        XCTAssertEqual(
            PublicUniversalLinkParser.parse(URL(string: "https://linka.signallq.com/abrir/teste?utm_source=campaign")!),
            .home
        )
        XCTAssertEqual(
            PublicUniversalLinkParser.parse(URL(string: "https://linka.signallq.com/abrir/historico/")!),
            .history
        )
        XCTAssertEqual(
            PublicUniversalLinkParser.parse(URL(string: "https://linka.signallq.com/abrir/minha-rede")!),
            .myNetwork
        )
    }

    func testRejectsPrivateAndUntrustedURLs() {
        XCTAssertNil(PublicUniversalLinkParser.parse(URL(string: "http://linka.signallq.com/abrir/teste")!))
        XCTAssertNil(PublicUniversalLinkParser.parse(URL(string: "https://evil.example/abrir/teste")!))
        XCTAssertNil(PublicUniversalLinkParser.parse(URL(string: "https://linka.signallq.com/abrir/teste/extra")!))
        XCTAssertNil(PublicUniversalLinkParser.parse(URL(string: "linka://wifi-advanced?payload=private")!))
    }
}
