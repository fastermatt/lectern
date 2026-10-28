import XCTest
import StudyTableCore
@testable import StudyTable

/// `selectedAnchor` / `rangeEndVerse`. Uses only the injected offline state (ephemeral defaults and
/// study store); nothing here may touch ~/Library/Application Support/StudyTable/.
@MainActor
final class SelectionAnchorTests: XCTestCase {
    func testSingleVerseAnchor() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        let anchor = state.selectedAnchor
        XCTAssertEqual(anchor, Anchor(book: "ROM", chapter: 8, verse: 28))
        XCTAssertEqual(anchor?.isSingleVerse, true)
        XCTAssertNil(state.rangeEndVerse)
    }

    func testRangeAnchorWhenRangeEndIsSet() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.rangeEndVerse = 39
        let anchor = state.selectedAnchor
        XCTAssertEqual(anchor, Anchor(book: "ROM", chapter: 8, verses: 28, to: 39))
        XCTAssertEqual(anchor?.isSingleVerse, false)
        XCTAssertEqual(state.selectedVerse, 28, "the range starts at the selected verse")
    }

    func testRangeEndEqualToStartIsSingleVerse() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.rangeEndVerse = 28
        XCTAssertEqual(state.selectedAnchor, Anchor(book: "ROM", chapter: 8, verse: 28))
    }

    func testRangeClearedOnVerseChapterAndBookNavigation() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)

        state.rangeEndVerse = 39
        state.selectedVerse = 30
        XCTAssertNil(state.rangeEndVerse, "changing the selected verse clears the range")
        XCTAssertEqual(state.selectedAnchor, Anchor(book: "ROM", chapter: 8, verse: 30))

        state.rangeEndVerse = 39
        state.selectedChapter = 9
        XCTAssertNil(state.rangeEndVerse, "changing chapter clears the range")

        state.navigate(bookCode: "ROM", chapter: 8, verse: 1)
        state.rangeEndVerse = 5
        state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
        XCTAssertNil(state.rangeEndVerse, "navigating to another book clears the range")
        XCTAssertEqual(state.selectedAnchor, Anchor(book: "JHN", chapter: 3, verse: 16))

        state.rangeEndVerse = 18
        state.selectedBookCode = "ROM"
        XCTAssertNil(state.rangeEndVerse, "changing book directly clears the range")
    }

    func testNilWhenNothingSelected() {
        let state = makeOfflineState()
        state.selectedVerse = nil
        XCTAssertNil(state.selectedAnchor)
        state.rangeEndVerse = 5
        XCTAssertNil(state.selectedAnchor)
    }
}
