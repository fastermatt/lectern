import XCTest
import Foundation
@testable import StudyTable

final class ScriptureCitationTests: XCTestCase {
    private func anchors(_ text: String) -> [String] {
        ScriptureReferenceScanner.citations(in: text).map { a in
            let v = a.anchor.verseStart == a.anchor.verseEnd ? "\(a.anchor.verseStart)" : "\(a.anchor.verseStart)-\(a.anchor.verseEnd)"
            return "\(a.anchor.book) \(a.anchor.chapterStart):\(v)"
        }
    }

    func testHistoricAndModernReferenceForms() {
        XCTAssertEqual(anchors("as it is written (Rom. viii. 28), and"), ["ROM 8:28"])
        XCTAssertEqual(anchors("Ps. lxxiii. 28; Matt. x. 28; Gen. i. 1"), ["PSA 73:28", "MAT 10:28", "GEN 1:1"])
        XCTAssertEqual(anchors("1 Cor. xiii. 4–7 and 2 Cor. v. 21"), ["1CO 13:4-7", "2CO 5:21"])
        XCTAssertEqual(anchors("John 3:16, Heb. 11:1-3, I John iv. 8"), ["JHN 3:16", "HEB 11:1-3", "1JN 4:8"])
        XCTAssertEqual(anchors("Phil. ii. 13. Prov. ii. 5"), ["PHP 2:13", "PRO 2:5"])
        XCTAssertEqual(anchors("Rom. viii. 28, 1 Cor. ii. 9"), ["ROM 8:28", "1CO 2:9"])
        XCTAssertEqual(anchors("Isa. liii. 5 and Is. vi. 3"), ["ISA 53:5", "ISA 6:3"])
    }

    func testProseNumbersAndImpossibleReferencesAreNotLinked() {
        XCTAssertTrue(anchors("Ch. 10. 3 and Vol. 1, 200 in 1901").isEmpty)
        XCTAssertTrue(anchors("It is 3 4 times larger. So 5, 6 more.").isEmpty)
        XCTAssertTrue(anchors("Rom. xxx. 1 and Jude ii. 3 and Gen. i. 0").isEmpty, "Out-of-range chapters and verse 0")
        XCTAssertTrue(anchors("September 15, 2020 and June 1, 2001").isEmpty)
        XCTAssertTrue(anchors("Rom. viiii. 2").isEmpty, "Non-canonical roman numerals")
        XCTAssertTrue(anchors("romans 8:28 lowercase prose").isEmpty)
    }

    func testRomanNumerals() {
        XCTAssertEqual(ScriptureReferenceScanner.romanValue("cxix"), 119)
        XCTAssertEqual(ScriptureReferenceScanner.romanValue("XLIV"), 44)
        XCTAssertNil(ScriptureReferenceScanner.romanValue("iiii"))
        XCTAssertNil(ScriptureReferenceScanner.romanValue("vx"))
    }

    func testIndexFindsOneEntryPerParagraphForAPassage() throws {
        let book = ResourceBook(id: "pg-1", title: "Sample Father", author: "Writer", attribution: "", source: nil, articles: [
            ResourceArticle(id: "a", title: "Book I", body: "First, see Rom. viii. 28 and again Rom. viii. 28.\n\nThen John iii. 16.\n\nNo references here.", anchor: nil),
            ResourceArticle(id: "b", title: "Book II", body: "All things work together (Rom. viii. 26–30).", anchor: nil)])
        let notes = ResourceBook(id: "tyndale-notes", title: "Notes", author: "Tyndale", attribution: "", source: nil, articles: [
            ResourceArticle(id: "n", title: "Note", body: "Rom. viii. 28", anchor: nil)])
        let index = try LibraryCitationIndex.build([book, notes])
        XCTAssertEqual(index.books, 1, "Anchored study notes are not rescanned")
        let hits = index.citing(Anchor(book: "ROM", chapter: 8, verse: 28))
        XCTAssertEqual(hits.map(\.articleID), ["a", "b"])
        XCTAssertEqual(hits.first?.paragraph, 0)
        XCTAssertEqual(index.citing(Anchor(book: "JHN", chapter: 3, throughChapter: nil)).first?.paragraph, 1)
        XCTAssertTrue(index.citing(Anchor(book: "GEN", chapter: 1, verse: 1)).isEmpty)
    }

    func testBundledApostolicFathersYieldCitations() throws {
        let fathers = try PatristicReader.load()
        let start = Date()
        let index = try LibraryCitationIndex.build([fathers])
        print("APOSTOLIC FATHERS CITATIONS: \(index.count) in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        XCTAssertGreaterThan(index.count, 50)
    }

    /// Precision check on real Gutenberg EPUBs: STUDYTABLE_CITATION_SAMPLES=/path/to/epubs
    func testRealEditionsSample() throws {
        guard let folder = ProcessInfo.processInfo.environment["STUDYTABLE_CITATION_SAMPLES"] else { throw XCTSkip("Opt-in sample folder") }
        let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil).filter { $0.pathExtension == "epub" }
        var books: [ResourceBook] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var book = try PersonalBookImporter.read(file); book.id = file.lastPathComponent; books.append(book)
        }
        let start = Date()
        let index = try LibraryCitationIndex.build(books)
        print("REAL EDITIONS: \(books.count) books, \(index.count) citations in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        var perBook: [String: Int] = [:], texts: [String: Int] = [:]
        for list in index.byBibleBook.values { for c in list { perBook[c.bookID, default: 0] += 1; texts[c.reference, default: 0] += 1 } }
        for (book, count) in perBook.sorted(by: { $0.key < $1.key }) { print("  \(book): \(count)") }
        for book in books where ["pg45304.epub", "pg70561.epub", "pg45001.epub", "pg58783.epub"].contains(book.id) {
            let all: [LibraryCitation] = index.byBibleBook.values.flatMap { $0 }.filter { $0.bookID == book.id }
            var hits: [LibraryCitation] = []
            for (offset, hit) in all.prefix(400).enumerated() where offset % 80 == 0 { hits.append(hit) }
            for hit in hits {
                let text = book.articles.first { $0.id == hit.articleID }?.paragraphs[safe: hit.paragraph] ?? ""
                print("  PARA \(book.id) [\(hit.reference.split(whereSeparator: \.isWhitespace).joined(separator: " "))] len \(text.count): \(text.prefix(220).replacingOccurrences(of: "\n", with: " ⏎ "))")
            }
        }
        // Random-ish sample of matched strings for manual precision review.
        for (text, _) in texts.sorted(by: { $0.key.hashValue < $1.key.hashValue }).prefix(80) { print("  SAMPLE: \(text)") }
    }
}

@MainActor
final class LinkedLibraryTests: XCTestCase {
    private let sample = ResourceBook(id: "pg-test", title: "On Providence", author: "A Father", attribution: "Public domain", source: nil, articles: [
        ResourceArticle(id: "s1", title: "Chapter I", body: "Opening words.\n\nAll things work together for good (Rom. viii. 28), says the apostle.\n\nProvidence governs the sparrow.", anchor: nil),
        ResourceArticle(id: "s2", title: "Chapter II", body: "Of grace and the will.\n\nGod so loved the world (John iii. 16).", anchor: nil)])

    func testPassageLinksRoundTripAndRejectForeignURLs() {
        let anchor = Anchor(book: "ROM", chapter: 8, verses: 28, to: 30)
        XCTAssertEqual(PassageLink.anchor(PassageLink.url(anchor)), anchor)
        XCTAssertNil(PassageLink.anchor(URL(string: "https://example.com/passage/ROM/8/28/28")!))
        XCTAssertNil(PassageLink.anchor(URL(string: "thruline://passage/XXX/8/28/28")!))
        XCTAssertNil(PassageLink.anchor(URL(string: "thruline://passage/ROM/99/1/1")!))
    }

    func testReaderTextLinksReferencesAndHighlightsTerms() {
        let text = ReaderText.attributed("Read Rom. viii. 28 on providence and Providence again.", terms: ["providence"])
        let links = text.runs.compactMap(\.link)
        XCTAssertEqual(links.compactMap(PassageLink.anchor), [Anchor(book: "ROM", chapter: 8, verse: 28)])
        XCTAssertEqual(text.runs.filter { $0.backgroundColor != nil }.count, 2)
        XCTAssertEqual(String(ReaderText.attributed("plain", terms: []).characters), "plain")
    }

    func testSnippetCentresOnTheMatch() {
        let long = String(repeating: "filler ", count: 200) + "the sparrow falls" + String(repeating: " more", count: 200)
        let snippet = ReaderText.snippet(long, terms: ["sparrow"], length: 120)
        XCTAssertTrue(snippet.contains("sparrow")); XCTAssertTrue(snippet.hasPrefix("…")); XCTAssertLessThan(snippet.count, 130)
    }

    func testReferenceQueriesFindCitingParagraphsFirst() throws {
        XCTAssertEqual(LibraryTextSearch.referenceQuery("rom 8:28"), Anchor(book: "ROM", chapter: 8, verse: 28))
        XCTAssertEqual(LibraryTextSearch.referenceQuery("1 cor 13:4-7"), Anchor(book: "1CO", chapter: 13, verses: 4, to: 7))
        XCTAssertNil(LibraryTextSearch.referenceQuery("providence of god"))
        let index = try LibraryCitationIndex.build([sample])
        let page = try LibraryTextSearch.search(query: "rom 8:28", scope: .books, offset: 0, studyRoot: nil, books: [sample], notes: [],
            historicRoot: nil, includeResearch: false, citing: index.citing(Anchor(book: "ROM", chapter: 8, verse: 28)))
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.hits.first?.focus?.articleID, "s1"); XCTAssertEqual(page.hits.first?.focus?.paragraph, 1)
        XCTAssertTrue(page.hits.first?.collection.contains("cites Rom. viii. 28") == true)
    }

    func testWordSearchReturnsTheMatchingParagraph() throws {
        let page = try LibraryTextSearch.search(query: "sparrow", scope: .books, offset: 0, studyRoot: nil, books: [sample], notes: [],
            historicRoot: nil, includeResearch: false)
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.hits.first?.body, "Providence governs the sparrow.")
        XCTAssertEqual(page.hits.first?.focus?.articleID, "s1")
        XCTAssertEqual(page.hits.first?.focus?.paragraph, 2)
        XCTAssertEqual(page.hits.first?.focus?.terms, ["sparrow"])
    }

    func testLibraryIndexesIncludedFathersAndDownloadsTogether() async throws {
        let root = temporaryDirectory("linked-library")
        try ResourceBookFiles.store(sample, root: root)
        let library = ResourceBookLibrary(root: root)
        await library.load()
        await library.citationsReady()
        XCTAssertEqual(library.includedBooks.first?.id, "apostolic-fathers-1870")
        XCTAssertNotNil(library.book(id: "pg-test")); XCTAssertNotNil(library.book(id: "apostolic-fathers-1870"))
        let romans = library.citations.citing(Anchor(book: "ROM", chapter: 8, verse: 28))
        XCTAssertTrue(romans.contains { $0.bookID == "pg-test" })
        XCTAssertGreaterThan(library.citations.count, 50, "The included Apostolic Fathers contribute citations")
    }

    func testOpenPassageKeepsSameChapterRange() {
        let state = makeOfflineState()
        state.openPassage(Anchor(book: "ROM", chapter: 8, verses: 28, to: 30))
        XCTAssertEqual(state.selectedBookCode, "ROM"); XCTAssertEqual(state.selectedVerse, 28); XCTAssertEqual(state.rangeEndVerse, 30)
    }
}

final class FootnoteLinkTests: XCTestCase {
    func testNoteReferencesAreShownWithTheSentenceThatCitesThem() throws {
        let book = ResourceBook(id: "pg-notes", title: "Institutes", author: "Calvin", attribution: "", source: nil, articles: [
            ResourceArticle(id: "c1", title: "Chapter I", body: "Where there is no vision the people perish.[2] And more.\n\nAnother paragraph.", anchor: nil),
            ResourceArticle(id: "fn", title: "Footnotes", body: "[1] A translator's remark.\n\n[2] Prov. xxix. 18.", anchor: nil),
            ResourceArticle(id: "af", title: "Polycarp", body: "Grace be with you all.[395] Amen.\n\nFootnote 395:\n\nMatt. v. 3.", anchor: nil)])
        let index = try LibraryCitationIndex.build([book])
        let proverbs = try XCTUnwrap(index.citing(Anchor(book: "PRO", chapter: 29, verse: 18)).first)
        XCTAssertEqual(proverbs.articleID, "c1"); XCTAssertEqual(proverbs.paragraph, 0); XCTAssertEqual(proverbs.footnote, "2")
        let matthew = try XCTUnwrap(index.citing(Anchor(book: "MAT", chapter: 5, verse: 3)).first)
        XCTAssertEqual(matthew.articleID, "af"); XCTAssertEqual(matthew.paragraph, 0); XCTAssertEqual(matthew.footnote, "395")
        let map = FootnoteMap.build(book.articles.map(\.paragraphs))
        XCTAssertEqual(map.noteLocation("2"), .init(article: 1, paragraph: 1))
        XCTAssertEqual(map.bodyLocation("2", near: .init(article: 1, paragraph: 1)), .init(article: 0, paragraph: 0))
    }

    func testNoteMarkersBecomeInternalLinks() {
        let body = ReaderText.attributed("Text.[12] More.", terms: [], linkNotes: true)
        XCTAssertEqual(body.runs.compactMap(\.link).map(\.absoluteString), ["thruline://note/12"])
        let note = ReaderText.attributed("[12] Rom. v. 1.", terms: [], linkNotes: true)
        XCTAssertEqual(Set(note.runs.compactMap(\.link).map(\.absoluteString)), ["thruline://noteref/12", PassageLink.url(Anchor(book: "ROM", chapter: 5, verse: 1)).absoluteString])
    }
}

final class TextMatchTests: XCTestCase {
    func testWholeWordStartsAndQuotedPhrases() {
        XCTAssertEqual(TextMatch.terms("\"first resurrection\" Augustine"), ["first resurrection", "augustine"])
        XCTAssertNil(TextMatch.range(of: "rapture", in: "they were enraptured"))
        XCTAssertNotNil(TextMatch.range(of: "rapture", in: "the Raptures of the saints"))
        XCTAssertTrue(TextMatch.matchesAll(["first resurrection"], in: "the first  resurrection".split(whereSeparator: \.isWhitespace).joined(separator: " ")))
    }
    func testPhraseMatchesListBeforeScatteredWords() throws {
        let book = ResourceBook(id: "b", title: "Book", author: "A", attribution: "", source: nil, articles: [
            ResourceArticle(id: "1", title: "One", body: "The resurrection came first, before all.", anchor: nil),
            ResourceArticle(id: "2", title: "Two", body: "This is the first resurrection.", anchor: nil)])
        let page = try LibraryTextSearch.search(query: "first resurrection", scope: .books, offset: 0, studyRoot: nil, books: [book], notes: [], historicRoot: nil, includeResearch: false)
        XCTAssertEqual(page.hits.map(\.focus?.articleID), ["2", "1"])
    }
}

final class NumberedNoteTests: XCTestCase {
    func testNumberedNotesMapBackAndBareOrIndexEntriesAreSkipped() throws {
        let book = ResourceBook(id: "o", title: "Origen", author: "Origen", attribution: "", source: nil, articles: [
            ResourceArticle(id: "t", title: "Book II", body: "We shall be caught up to meet the Lord.[344] So he says.", anchor: nil),
            ResourceArticle(id: "n", title: "Notes", body: "344. 1 Thess. iv. 17.\n\n642. Rev. xx. 4.", anchor: nil),
            ResourceArticle(id: "i", title: "INDEX OF TEXTS", body: "Rev. xx. 4, 120", anchor: nil)])
        let index = try LibraryCitationIndex.build([book])
        let thess = index.citing(Anchor(book: "1TH", chapter: 4, verse: 17))
        XCTAssertEqual(thess.map(\.articleID), ["t"]); XCTAssertEqual(thess.first?.footnote, "344")
        XCTAssertTrue(index.citing(Anchor(book: "REV", chapter: 20, verse: 4)).isEmpty)
    }
}
