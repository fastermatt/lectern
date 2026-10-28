import XCTest
@testable import StudyTable

@MainActor
final class ReadingNavigationTests: XCTestCase {
    func testChapterFaderClampsAndSnapsEveryChapterIncludingPsalms() {
        for count in [1, 21, 150] {
            XCTAssertEqual(ChapterFaderScale.chapter(at: -1, count: count), 1)
            XCTAssertEqual(ChapterFaderScale.chapter(at: 2, count: count), count)
            for chapter in 1...count {
                XCTAssertEqual(ChapterFaderScale.chapter(at: ChapterFaderScale.fraction(chapter: chapter, count: count), count: count), chapter)
            }
        }
        XCTAssertEqual(ChapterFaderScale.chapter(at: 0.5, count: 21), 11)
    }
    func testJumpValidatesBeforeChangingSelection() {
        let state = makeOfflineState()
        XCTAssertTrue(state.jumpToReference("Romans 8:28"))
        XCTAssertEqual(state.passage, "Romans 8:28")
        for invalid in ["Romans 99:1", "Romans 8:999", "John 3:", "Unknown 1:1", "John 0:1"] {
            XCTAssertFalse(state.jumpToReference(invalid))
            XCTAssertEqual(state.passage, "Romans 8:28")
        }
        XCTAssertTrue(state.jumpToReference("1 Corinthians 13:4"))
        XCTAssertTrue(state.jumpToReference("JHN 3:16"))
    }

    func testNavigationUsesVerseIdentifiersInsteadOfCounts() throws {
        let state = makeOfflineState()
        for (book, chapter, verse) in [("ROM", 16, 27), ("LUK", 23, 56), ("MAT", 18, 35)] {
            state.navigate(bookCode: book, chapter: chapter, verse: verse)
            XCTAssertEqual(state.selectedVerse, verse)
            let name = try XCTUnwrap(state.library.summary(code: book)).name
            XCTAssertTrue(state.jumpToReference("\(name) \(chapter):\(verse)"))
            XCTAssertEqual(state.selectedVerse, verse)
        }
        XCTAssertTrue(state.jumpToReference("Rom 8:28–39"))
        XCTAssertEqual(state.selectedAnchor?.displayString, "Romans 8:28–39")
        XCTAssertFalse(state.jumpToReference("John 5:4"), "BSB omits this verse identifier")
        XCTAssertEqual(state.selectedAnchor?.displayString, "Romans 8:28–39")
    }

    func testLinkedPassageBackRestoresWithoutCreatingLoop() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        let count = state.passageHistory.count
        state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
        XCTAssertEqual(state.passageHistory.last, "Romans 8:28")
        state.returnToPreviousPassage()
        XCTAssertEqual(state.passage, "Romans 8:28")
        XCTAssertEqual(state.passageHistory.count, count)
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        XCTAssertEqual(state.passageHistory.count, count)
    }
}
