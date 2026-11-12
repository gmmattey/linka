import Foundation
@testable import NetscopeTransport
import XCTest

final class NetscopeProgressTests: XCTestCase {
    func testDecodesOnlySafeMilestones() throws {
        for milestone in NetscopeProgressMilestone.allCases {
            let event = try NetscopeProgressDecoder.decode(Data("{\"milestone\":\"\(milestone.rawValue)\"}".utf8))
            XCTAssertEqual(event, .init(milestone: milestone))
        }
    }

    func testRejectsUnknownOrUnsafeProgress() {
        XCTAssertThrowsError(try NetscopeProgressDecoder.decode(Data("{\"milestone\":\"thinking\"}".utf8))) {
            XCTAssertEqual($0 as? NetscopeProgressDecodingError, .unsupportedMilestone)
        }
        XCTAssertThrowsError(try NetscopeProgressDecoder.decode(Data("{\"milestone\":\"accepted\",\"detail\":\"provider text\"}".utf8))) {
            XCTAssertEqual($0 as? NetscopeProgressDecodingError, .malformedEvent)
        }
        XCTAssertThrowsError(try NetscopeProgressDecoder.decode(Data("not-json".utf8)))
    }
}
