import XCTest
@testable import StudyTable

final class BetaPolishTests: XCTestCase {
    func testCopiedVerseCitesItsOwnRowAndTranslation() {
        let text = verseClipboardText(bookName: "Romans", chapter: 8,
            verse: BibleVerse(number: 30, text: "Test verse text"), translation: "ASV")
        XCTAssertEqual(text, "Romans 8:30 (ASV) — Test verse text")
    }

    func testInitialAndReloadedPassageScrollsToSelectedVerse() {
        let verses = [BibleVerse(number: 1, text: "First"), BibleVerse(number: 28, text: "Selected")]
        XCTAssertEqual(scriptureScrollTarget(verses: verses, selected: 28), 28)
        XCTAssertEqual(scriptureScrollTarget(verses: verses, selected: nil), 1)
        XCTAssertEqual(scriptureScrollTarget(verses: verses, selected: 29), 1)
        XCTAssertNil(scriptureScrollTarget(verses: [], selected: 28))
    }
}
