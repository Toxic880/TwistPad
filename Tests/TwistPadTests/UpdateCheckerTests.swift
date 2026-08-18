import XCTest
@testable import TwistPad

final class UpdateCheckerTests: XCTestCase {

    func testNewerPatchIsAnUpdate() {
        XCTAssertTrue(UpdateChecker.isVersion("1.6.1", newerThan: "1.6.0"))
    }

    func testSameVersionIsNot() {
        XCTAssertFalse(UpdateChecker.isVersion("1.6", newerThan: "1.6"))
    }

    func testOlderVersionIsNot() {
        XCTAssertFalse(UpdateChecker.isVersion("1.5", newerThan: "1.6"))
    }

    /// The classic way these ship broken: compared as strings, "1.10" sorts
    /// before "1.9" and the update is never offered.
    func testDoubleDigitComponentsCompareNumerically() {
        XCTAssertTrue(UpdateChecker.isVersion("1.10", newerThan: "1.9"))
        XCTAssertFalse(UpdateChecker.isVersion("1.9", newerThan: "1.10"))
    }

    func testLeadingVIsTolerated() {
        XCTAssertTrue(UpdateChecker.isVersion("v1.7", newerThan: "1.6"))
        XCTAssertFalse(UpdateChecker.isVersion("V1.6", newerThan: "1.6"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertTrue(UpdateChecker.isVersion("1.6.1", newerThan: "1.6"))
        XCTAssertFalse(UpdateChecker.isVersion("1.6", newerThan: "1.6.0"))
    }

    func testSuffixesAreIgnored() {
        XCTAssertTrue(UpdateChecker.isVersion("1.7-beta", newerThan: "1.6"))
    }

    func testGarbageDoesNotReadAsNewer() {
        XCTAssertFalse(UpdateChecker.isVersion("", newerThan: "1.6"))
        XCTAssertFalse(UpdateChecker.isVersion("latest", newerThan: "1.6"))
    }
}
