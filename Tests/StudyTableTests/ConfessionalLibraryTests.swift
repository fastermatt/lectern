import XCTest
@testable import StudyTable

/// Item 7 (0.7 fix batch): ~13 confession citations point at verses that don't exist in the
/// bundled canon (old-print-run errors -- `StandardsTests`'s `knownMismatches` is the source of
/// truth for the exact list). These must never be a dead-end tap in the Confessional Library, and
/// `AppState.navigate` must never leave a nonexistent verse selected even if something else in the
/// app hands it an out-of-range target.
@MainActor
final class ConfessionalLibraryTests: XCTestCase {
    private func proof(_ ref: String, _ code: String, _ chapter: Int, _ start: Int, _ end: Int? = nil) -> StandardProof {
        StandardProof(ref: ref, code: code, chapter: chapter, start: start, end: end ?? start)
    }

    // MARK: - standardProofResolves

    func testKnownMismatchedCitationsDoNotResolve() {
        let books = ScriptureLibrary().books
        XCTAssertFalse(books.isEmpty, "sanity: the bundled BSB canon should have loaded")

        // Every entry in StandardsTests.knownMismatches, reproduced here rather than imported
        // (that set is private to that file) so a change to one list without the other is a
        // visible diff, not a silent gap in coverage.
        let knownMismatches: [(ref: String, code: String, chapter: Int, verse: Int)] = [
            ("Rom. 16:27", "ROM", 16, 27), ("Luke 23:56", "LUK", 23, 56), ("Matt. 18:35", "MAT", 18, 35),
            ("Job 15:36", "JOB", 15, 36), ("1 John 1:16", "1JN", 1, 16), ("Mic. 7:23", "MIC", 7, 23),
            ("Mic. 7:24", "MIC", 7, 24), ("Mic. 7:25", "MIC", 7, 25), ("1 Tim. 4:19", "1TI", 4, 19),
            ("Gal. 30:15", "GAL", 30, 15), ("Psa. 49:21", "PSA", 49, 21), ("John 16:38", "JHN", 16, 38),
            ("Psa. 62:13", "PSA", 62, 13),
        ]
        for entry in knownMismatches {
            XCTAssertFalse(standardProofResolves(proof(entry.ref, entry.code, entry.chapter, entry.verse), in: books),
                            "\(entry.ref) (\(entry.code).\(entry.chapter).\(entry.verse)) unexpectedly resolved -- "
                            + "if the canon changed, update StandardsTests.knownMismatches too")
        }
    }

    func testRealCitationsResolve() {
        let books = ScriptureLibrary().books
        // WCF 3.5/3.6's own proof texts (verified against two independent sources -- see the
        // wiki's 0.6.4 entry): Romans 8:30 and 8:28.
        XCTAssertTrue(standardProofResolves(proof("Rom. 8:30", "ROM", 8, 30), in: books))
        XCTAssertTrue(standardProofResolves(proof("Rom. 8:28-30", "ROM", 8, 28, 30), in: books))
        XCTAssertTrue(standardProofResolves(proof("John 3:16", "JHN", 3, 16), in: books))
    }

    func testChapterOutOfBookRangeDoesNotResolve() {
        // Galatians has 6 chapters; GAL.30.15 (one of the real knownMismatches) is a chapter
        // that doesn't exist at all, not just a verse -- confirms the chapter-range guard, not
        // only the verse-range guard, actually runs.
        let books = ScriptureLibrary().books
        XCTAssertFalse(standardProofResolves(proof("Gal. 30:15", "GAL", 30, 15), in: books))
    }

    func testUnknownBookCodeDoesNotResolve() {
        XCTAssertFalse(standardProofResolves(proof("XYZ 1:1", "XYZ", 1, 1), in: ScriptureLibrary().books))
    }

    func testEndBeforeStartDoesNotResolve() {
        let books = ScriptureLibrary().books
        XCTAssertFalse(standardProofResolves(proof("Rom. 8:30-28", "ROM", 8, 30, 28), in: books))
    }

    // MARK: - AppState.navigate clamping

    func testNavigateClampsAnOutOfRangeVerseToTheChaptersLastVerse() {
        let state = makeOfflineState()
        // 1 Timothy 4 has 16 verses in the BSB; verse 19 (the real WLC citation error) doesn't exist.
        state.navigate(bookCode: "1TI", chapter: 4, verse: 19)
        XCTAssertEqual(state.selectedBookCode, "1TI")
        XCTAssertEqual(state.selectedChapter, 4)
        let lastVerse = state.book?.verseCount(chapter: 4) ?? 0
        XCTAssertGreaterThan(lastVerse, 0)
        XCTAssertEqual(state.selectedVerse, lastVerse, "an out-of-range verse should clamp to the chapter's last verse, not stay at 19")
    }

    func testNavigateClampsAnOutOfRangeChapterToTheBooksRange() {
        let state = makeOfflineState()
        // Galatians has 6 chapters; chapter 30 (the real GAL.30.15 citation error) doesn't exist.
        state.navigate(bookCode: "GAL", chapter: 30, verse: 15)
        XCTAssertEqual(state.selectedBookCode, "GAL")
        let chapterCount = state.book?.chapterCount ?? 0
        XCTAssertGreaterThan(chapterCount, 0)
        XCTAssertEqual(state.selectedChapter, chapterCount, "an out-of-range chapter should clamp to the book's last chapter")
        XCTAssertLessThanOrEqual(state.selectedVerse ?? 0, state.book?.verseCount(chapter: chapterCount) ?? 0)
    }

    func testNavigateLeavesAnInRangeTargetUntouched() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        XCTAssertEqual(state.selectedBookCode, "ROM")
        XCTAssertEqual(state.selectedChapter, 8)
        XCTAssertEqual(state.selectedVerse, 28)
    }

    func testNavigateWithNoSpecificVerseIsNotTreatedAsOutOfRange() {
        // verse <= 0 is the existing "whole chapter, no specific verse" sentinel used throughout
        // the app (LCDDisplay's `verse > 0` checks etc.) -- clamping must never mistake it for an
        // out-of-range value that needs correcting.
        let state = makeOfflineState()
        state.navigate(bookCode: "PSA", chapter: 119, verse: 0)
        XCTAssertEqual(state.selectedChapter, 119)
        XCTAssertEqual(state.selectedVerse, 0)
    }
}
