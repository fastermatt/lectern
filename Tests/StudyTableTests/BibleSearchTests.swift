import XCTest
import StudyTableCore
@testable import StudyTable

@MainActor
final class BibleSearchTests: XCTestCase {
    private func bsbSource() -> BibleSearchSource {
        BibleSearchSource(translationID: "BSB", directory: TestPaths.scripturePacks.appendingPathComponent("BSB"),
                          bookCodes: Canon.bookCodes, revision: UUID())
    }

    private func fixture() throws -> (BibleSearchSource, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Lectern-BibleSearch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let books = [
            BookPack(code: "GEN", name: "Genesis", chapters: [ChapterPack(n: 1, v: [1], t: ["Love in the beginning"])]),
            BookPack(code: "JHN", name: "John", chapters: [ChapterPack(n: 1, v: Array(1...8), t: [
                "Love world hope", "Faithful hope. Café!", "Faith love", "In the beginning God",
                "In distant beginning", "and love", "God's steadfast love", "Faith faith hope"
            ])])
        ]
        for book in books { try JSONEncoder().encode(book).write(to: root.appendingPathComponent("\(book.code).json")) }
        return (BibleSearchSource(translationID: "TEST", directory: root, bookCodes: ["GEN", "JHN"], revision: UUID()), root)
    }

    func testWordsPhrasesBooleanPrecedenceAndPrefixes() async throws {
        let (source, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = BibleSearchEngine()
        let cases: [(String, [Int])] = [
            ("faith hope", [8]), ("faith AND hope", [8]), ("faith", [3, 8]),
            ("fai*", [2, 3, 8]), ("cafe", [2]), ("and", [6]),
            ("\"in the beginning\"", [4]), ("\"faith faith\"", [8]),
            ("\"God's steadfast\"", [7]), ("love NOT world", [3, 6, 7]),
            ("(hope OR faith) AND love", [1, 3]),
            ("faith OR hope AND love", [1, 3, 8]),
            ("NOT (love OR hope)", [4, 5]), ("LOVE", [1, 3, 6, 7])
        ]
        for (query, expected) in cases {
            let result = try await engine.search(source: source, query: query, scope: .book("JHN"))
            XCTAssertEqual(result.hits.map(\.verse), expected, query)
        }
        let ot = try await engine.search(source: source, query: "love", scope: .oldTestament)
        XCTAssertEqual(ot.hits.map(\.id), ["GEN.1.1"])
        let nt = try await engine.search(source: source, query: "love", scope: .newTestament)
        XCTAssertEqual(nt.hits.map(\.id), ["JHN.1.1", "JHN.1.3", "JHN.1.6", "JHN.1.7"])
    }

    func testMalformedQueriesHaveActionableErrorsAndPunctuationIsNotAnOperator() throws {
        for query in ["", "  ", "()", "love AND", "OR love", "love OR OR hope", "(love", "love)", "\"love", "\"\"", "*", "lo*ve", "love**", "\"lov*\"", String(repeating: "(", count: 33) + "love" + String(repeating: ")", count: 33)] {
            XCTAssertThrowsError(try BibleSearchParser.parse(query), query) { error in
                XCTAssertTrue(error is BibleSearchError)
                XCTAssertGreaterThan(error.localizedDescription.count, 15)
            }
        }
        XCTAssertEqual(try BibleSearchParser.parse("faith, hope"), .and(.term("faith"), .term("hope")))
    }

    func testUnsupportedSyntaxFailsInsteadOfBecomingMisleadingWords() throws {
        let cases = [
            ("lemma:G26", "Field queries"), ("love?", "? wildcard"),
            ("love NEAR world", "NEAR"), ("love WITHIN 5 world", "WITHIN"),
            ("love BEFORE world", "BEFORE"), ("love AFTER world", "AFTER"),
            ("love NEAR/5 world", "NEAR")
        ]
        for (query, guidance) in cases {
            XCTAssertThrowsError(try BibleSearchParser.parse(query), query) { error in
                XCTAssertTrue(error.localizedDescription.contains(guidance))
            }
        }
        XCTAssertEqual(try BibleSearchParser.parse("before"), .term("before"))
        XCTAssertEqual(try BibleSearchParser.parse("\"BEFORE\""), .phrase(["before"]))
        XCTAssertEqual(try BibleSearchParser.parse("\"who is this?\""), .phrase(["who", "is", "this"]))
    }

    func testSearchSessionSurvivesViewRecreationAndReaderContextChanges() {
        let session = BibleSearchSession(query: "faith OR hope", translationID: "KJV", area: .passage,
                                        passage: "Romans 8–9", offset: 80)
        let first = BibleSearchView(session: session)
        first.session.prepareContext(translationID: "BSB", passage: "John 3:16", book: "JHN")
        let reopened = BibleSearchView(session: session)
        reopened.session.prepareContext(translationID: "WEB", passage: "Genesis 1:1", book: "GEN")
        XCTAssertTrue(first.session === reopened.session)
        XCTAssertEqual(reopened.session.query, "faith OR hope")
        XCTAssertEqual(reopened.session.translationID, "KJV", "Reading another translation does not overwrite search selection")
        XCTAssertEqual(reopened.session.area, .passage)
        XCTAssertEqual(reopened.session.passage, "Romans 8–9")
        XCTAssertEqual(reopened.session.offset, 80)
        session.query = "love"
        XCTAssertEqual(session.offset, 0, "An edited query starts from the first page")
        session.passage = ""
        session.offset = 40
        session.prepareContext(translationID: "BSB", passage: "John 1:1", book: "JHN")
        XCTAssertEqual(session.passage, "", "A cleared custom passage is retained across presentations")
        XCTAssertEqual(session.offset, 40)
        session.area = .currentBook
        session.offset = 80
        session.updateCurrentBook("ROM")
        XCTAssertEqual(session.offset, 0, "Current-book pagination resets when its scope changes")
        let fresh = BibleSearchSession(query: "the")
        fresh.prepareContext(translationID: "WEB", passage: "Psalm 23", book: "PSA")
        XCTAssertEqual(fresh.translationID, "WEB")
        XCTAssertEqual(fresh.passage, "Psalm 23")
    }

    func testLibraryReferenceValidationUsesActualEndpoints() {
        let library = ScriptureLibrary(bundledRoot: TestPaths.scripturePacks,
                                       userRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertNil(library.navigationAnchor(for: "John 3:99", translationID: "BSB"))
        XCTAssertNil(library.navigationAnchor(for: "John 5:4", translationID: "BSB"))
        XCTAssertNotNil(library.navigationAnchor(for: "John 5:47", translationID: "BSB"))
        XCTAssertNotNil(library.navigationAnchor(for: "Romans 8:28–9:5", translationID: "BSB"))
        XCTAssertNil(library.navigationAnchor(for: "Romans 15:1–16:24", translationID: "BSB"))
        XCTAssertNotNil(library.navigationAnchor(for: "Romans 15:1–16:27", translationID: "BSB"))
        XCTAssertNotNil(library.navigationAnchor(for: "John 3:16", translationID: "ESV"), "Online navigation validates against offline BSB")
    }

    func testBSBExactTotalsAndEveryPageMatchIndependentRawCorpusScan() async throws {
        let source = bsbSource(), engine = BibleSearchEngine()
        var all: [ScriptureSearchHit] = []
        for code in Canon.bookCodes {
            let data = try Data(contentsOf: source.directory.appendingPathComponent("\(code).json"))
            let book = try JSONDecoder().decode(BookPack.self, from: data)
            for chapter in book.chapters {
                for (verse, text) in zip(chapter.v, chapter.t) where verse > 0 {
                    all.append(ScriptureSearchHit(bookCode: code, bookName: book.name, chapter: chapter.n, verse: verse, text: text))
                }
            }
        }
        func containsWord(_ word: String, _ text: String) -> Bool {
            text.range(of: "\\b\(word)\\b", options: [.regularExpression, .caseInsensitive]) != nil
        }
        let expected = all.filter { containsWord("the", $0.text) }
        XCTAssertGreaterThan(expected.count, 60)
        var returned: [String] = [], offset = 0
        repeat {
            let page = try await engine.search(source: source, query: "the", offset: offset, pageSize: 40)
            XCTAssertEqual(page.total, expected.count)
            XCTAssertEqual(page.offset, offset)
            guard !page.hits.isEmpty else { return XCTFail("Pagination stopped before the exact total") }
            returned.append(contentsOf: page.hits.map(\.id))
            offset += page.hits.count
        } while offset < expected.count
        XCTAssertEqual(returned, expected.map(\.id), "Every verse remains reachable, once, in canonical order beyond the old 60-result cap")
        let both = try await engine.search(source: source, query: "faith hope", pageSize: 200)
        let independentlyMatched = all.filter { containsWord("faith", $0.text) && containsWord("hope", $0.text) }
        XCTAssertEqual(both.total, independentlyMatched.count)
        XCTAssertEqual(both.hits.map(\.id), independentlyMatched.map(\.id))
        let phrase = try await engine.search(source: source, query: "\"in the beginning\"")
        XCTAssertTrue(phrase.hits.contains { $0.id == "GEN.1.1" })
        XCTAssertTrue(phrase.hits.contains { $0.id == "JHN.1.1" })
    }

    func testPassageScopesValidateActualBSBVerseIdentifiersAndCrossChapterBoundaries() async throws {
        let source = bsbSource(), engine = BibleSearchEngine()
        // John 5 has 46 numbered verses, but verse 47 exists and verse 4 does not.
        let last = try await engine.search(source: source, query: "NOT zzznonexistent", scope: .passage(Anchor(book: "JHN", chapter: 5, verse: 47)))
        XCTAssertEqual(last.hits.map(\.id), ["JHN.5.47"])
        do {
            _ = try await engine.search(source: source, query: "faith", scope: .passage(Anchor(book: "JHN", chapter: 5, verse: 4)))
            XCTFail("Omitted endpoints must be rejected even below the manifest verse count")
        } catch { XCTAssertEqual(error as? BibleSearchError, .invalidPassage) }
        let scope = try XCTUnwrap(Anchor.parse("Romans 8:28–9:5"))
        let cross = try await engine.search(source: source, query: "NOT zzznonexistent", scope: .passage(scope), pageSize: 200)
        XCTAssertEqual(cross.total, 17)
        XCTAssertEqual(cross.hits.first?.id, "ROM.8.28")
        XCTAssertEqual(cross.hits.last?.id, "ROM.9.5")
        let chapter = try await engine.search(source: source, query: "NOT zzznonexistent", scope: .passage(Anchor(book: "JHN", chapter: 5)), pageSize: 200)
        XCTAssertEqual(chapter.total, 46)
        XCTAssertFalse(chapter.hits.contains { $0.verse == 4 })
        XCTAssertEqual(chapter.hits.last?.verse, 47)
    }

    func testLocalOnlyHandlesRescanInvalidationAndCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Lectern-empty-search-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ScriptureLibrary(bundledRoot: TestPaths.scripturePacks, userRoot: root)
        XCTAssertNil(library.searchSource(translationID: "ESV"))
        XCTAssertNil(library.searchSource(translationID: "NKJV"))
        let first = try XCTUnwrap(library.searchSource(translationID: "BSB"))
        library.rescan()
        XCTAssertNotEqual(first.revision, library.searchSource(translationID: "BSB")?.revision)
        let engine = BibleSearchEngine()
        do {
            _ = try await engine.search(source: nil, query: "love")
            XCTFail("Online caches must not become search corpora")
        } catch { XCTAssertEqual(error as? BibleSearchError, .unavailable) }
        let task = Task { () throws -> BibleSearchPage in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.search(source: first, query: "the")
        }
        do { _ = try await task.value; XCTFail("Cancelled requests must stop") }
        catch { XCTAssertTrue(error is CancellationError) }

        let (source, fixtureRoot) = try fixture()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let before = try await engine.search(source: source, query: "faith")
        XCTAssertEqual(before.total, 2)
        let changed = BookPack(code: "JHN", name: "John", chapters: [ChapterPack(n: 1, v: [1], t: ["Hope only"])])
        try JSONEncoder().encode(changed).write(to: fixtureRoot.appendingPathComponent("JHN.json"))
        let updated = BibleSearchSource(translationID: source.translationID, directory: source.directory,
                                       bookCodes: source.bookCodes, revision: UUID())
        let after = try await engine.search(source: updated, query: "faith")
        XCTAssertEqual(after.total, 0, "A reinstalled pack cannot reuse its earlier corpus or matches")
        let translated = BibleSearchSource(translationID: "OTHER", directory: source.directory,
                                          bookCodes: source.bookCodes, revision: UUID())
        let other = try await engine.search(source: translated, query: "hope")
        XCTAssertEqual(other.translationID, "OTHER")
        XCTAssertEqual(other.hits.map(\.id), ["JHN.1.1"])
    }
}
