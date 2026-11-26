import XCTest
@testable import LaserdotKit

final class ChangelogTests: XCTestCase {
    let log = """
    # Changelog

    ## 0.1.22

    - Newest.

    ## 0.1.21

    - Middle.

    ## 0.1.9

    - Old.
    """

    func testWhatsNewShowsTheVersionsSinceTheLastSeen() {
        let s = Changelog.sections(log, after: "0.1.9", upTo: "0.1.22")
        XCTAssertEqual(s.map(\.version), ["0.1.22", "0.1.21"])
        XCTAssertEqual(s.first?.text, "- Newest.")
    }

    func testVersionsCompareNumberByNumber() {
        XCTAssertTrue(Changelog.newer("0.1.10", than: "0.1.9"))
        XCTAssertFalse(Changelog.newer("0.1.9", than: "0.1.10"))
        XCTAssertFalse(Changelog.newer("0.1.9", than: "0.1.9"))
        XCTAssertTrue(Changelog.newer("0.1.0", than: nil))
    }

    func testNothingNewerThanTheRunningVersionIsShown() {
        XCTAssertEqual(Changelog.sections(log, after: "0.1.20", upTo: "0.1.21").map(\.version), ["0.1.21"])
    }
}
