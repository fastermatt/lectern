import XCTest
@testable import StudyTable

final class KnobValueTests: XCTestCase {
    func testKnobsClampAtBothEnds() {
        XCTAssertEqual(KnobValue.clamp(-100, to: 15...30, step: 1), 15)
        XCTAssertEqual(KnobValue.clamp(100, to: 15...30, step: 1), 30)
        XCTAssertEqual(KnobValue.clamp(-100, to: 2...16, step: 1), 2)
        XCTAssertEqual(KnobValue.clamp(100, to: 2...16, step: 1), 16)
    }

    func testKnobsSnapRelativeToLowerBound() {
        XCTAssertEqual(KnobValue.clamp(19.6, to: 15...30, step: 1), 20)
        XCTAssertEqual(KnobValue.clamp(8.2, to: 2...16, step: 1), 8)
        XCTAssertEqual(KnobValue.clamp(4.1, to: 1...9, step: 2), 5)
    }
}
