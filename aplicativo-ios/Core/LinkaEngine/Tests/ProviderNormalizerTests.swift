import XCTest
@testable import LinkaEngine

final class ProviderNormalizerTests: XCTestCase {

    private var normalizer: ProviderNormalizer!

    override func setUp() {
        super.setUp()
        normalizer = ProviderNormalizer()
    }

    // MARK: - ASN lookup wins

    func test_ASN_resolvesVivoInBrazil() {
        let result = normalizer.normalize(org: "AS27699 TELEFÔNICA BRASIL S.A")
        XCTAssertEqual(result?.commercialName, "Vivo")
        XCTAssertEqual(result?.country, "BR")
    }

    func test_ASN_resolvesClaroInBrazil() {
        let result = normalizer.normalize(org: "AS28573 Claro NXT Telecomunicações Ltda")
        XCTAssertEqual(result?.commercialName, "Claro")
        XCTAssertEqual(result?.country, "BR")
    }

    func test_ASN_resolvesTIMInBrazil() {
        let result = normalizer.normalize(org: "AS26615 TIM S.A.")
        XCTAssertEqual(result?.commercialName, "TIM")
    }

    func test_ASN_resolvesNioInBrazil() {
        let result = normalizer.normalize(org: "AS7738 Telemar Norte Leste S.A.")
        XCTAssertEqual(result?.commercialName, "Nio")
    }

    func test_ASN_resolvesXfinityInUS() {
        let result = normalizer.normalize(org: "AS7922 COMCAST-7922")
        XCTAssertEqual(result?.commercialName, "Xfinity")
        XCTAssertEqual(result?.country, "US")
    }

    func test_ASN_resolvesTelekomInGermany() {
        let result = normalizer.normalize(org: "AS3320 Deutsche Telekom AG")
        XCTAssertEqual(result?.commercialName, "Telekom")
    }

    func test_ASN_resolvesJioInIndia() {
        let result = normalizer.normalize(org: "AS55836 Reliance Jio Infocomm Limited")
        XCTAssertEqual(result?.commercialName, "Jio")
    }

    func test_ASN_resolvesMEOInPortugal() {
        let result = normalizer.normalize(org: "AS3243 Altice Portugal S.A.")
        XCTAssertEqual(result?.commercialName, "MEO")
    }

    // MARK: - Substring fallback (unknown ASN, known brand)

    func test_substring_matchesComcastByName() {
        let result = normalizer.normalize(org: "AS999999 COMCAST CABLE COMMUNICATIONS, LLC")
        XCTAssertEqual(result?.commercialName, "Xfinity")
    }

    func test_substring_matchesTelefonicaBrasil() {
        let result = normalizer.normalize(org: "AS888888 TELEFONICA BRASIL Regional")
        XCTAssertEqual(result?.commercialName, "Vivo")
    }

    func test_substring_matchesBoltStarlink() {
        let result = normalizer.normalize(org: "AS777777 SpaceX Services, Inc.")
        XCTAssertEqual(result?.commercialName, "Starlink")
    }

    func test_substring_accentInsensitive() {
        let result = normalizer.normalize(org: "AS666666 TELEFÔNICA BRASIL Regional")
        XCTAssertEqual(result?.commercialName, "Vivo")
    }

    // MARK: - Heuristic fallback (unknown ASN, unknown brand)

    func test_heuristic_stripsLegalSuffix() {
        let result = normalizer.normalize(org: "AS555555 Provedor Regional LTDA")
        XCTAssertEqual(result?.commercialName, "Provedor Regional")
    }

    func test_heuristic_stripsMultipleSuffixes() {
        let result = normalizer.normalize(org: "AS444444 Fictitious Telecom LTDA")
        XCTAssertEqual(result?.commercialName, "Fictitious")
    }

    func test_heuristic_stripsCorporateSA() {
        let result = normalizer.normalize(org: "AS333333 Nova Rede Comunicações S.A")
        XCTAssertEqual(result?.commercialName, "Nova Rede")
    }

    func test_heuristic_preservesShortAcronyms() {
        let result = normalizer.normalize(org: "AS222222 XYZ Telecom")
        XCTAssertEqual(result?.commercialName, "XYZ")
    }

    func test_heuristic_titleCasesConnectors() {
        let result = normalizer.normalize(org: "AS111111 CONEXAO DO INTERIOR LTDA")
        XCTAssertEqual(result?.commercialName, "Conexao do Interior")
    }

    // MARK: - Edge cases

    func test_emptyOrg_returnsNil() {
        XCTAssertNil(normalizer.normalize(org: ""))
        XCTAssertNil(normalizer.normalize(org: "   "))
    }

    func test_orgWithoutASPrefix_stillNormalizes() {
        let result = normalizer.normalize(org: "COMCAST CABLE COMMUNICATIONS, LLC")
        XCTAssertEqual(result?.commercialName, "Xfinity")
    }

    func test_orgWithoutASPrefix_fallsThroughToHeuristic() {
        let result = normalizer.normalize(org: "Provedor Do Bairro LTDA")
        XCTAssertEqual(result?.commercialName, "Provedor do Bairro")
    }

    func test_asnAloneWithNoName_returnsHeuristicOfEmpty() {
        // Only an AS number, nothing else — pretty degenerate, but shouldn't crash.
        let result = normalizer.normalize(org: "AS12345")
        XCTAssertNotNil(result)
    }

    func test_multipleWhitespace_isCollapsed() {
        let result = normalizer.normalize(org: "AS0    Provedor    Regional   LTDA")
        XCTAssertEqual(result?.commercialName, "Provedor Regional")
    }

    // MARK: - Split helper

    func test_splitASN_parsesNumber() {
        let (asn, remainder) = normalizer.splitASN("AS27699 TELEFONICA BRASIL S.A")
        XCTAssertEqual(asn, 27699)
        XCTAssertEqual(remainder, "TELEFONICA BRASIL S.A")
    }

    func test_splitASN_missingPrefix_returnsNilAndOriginal() {
        let (asn, remainder) = normalizer.splitASN("COMCAST CABLE")
        XCTAssertNil(asn)
        XCTAssertEqual(remainder, "COMCAST CABLE")
    }

    func test_splitASN_prefixWithoutNumber_returnsNil() {
        let (asn, _) = normalizer.splitASN("AS Company Name")
        XCTAssertNil(asn)
    }
}
