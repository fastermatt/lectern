import XCTest
import StudyTableCore
@testable import StudyTable

@MainActor
final class ScriptureTests: XCTestCase {
    func testBundledLibraryHoldsThreePublicDomainTranslationsAndListsTheLockedOnes() {
        let library = ScriptureLibrary()
        let bundled = library.translations.filter { $0.delivery == .bundled }.map(\.id)
        XCTAssertEqual(bundled, ["BSB", "KJV", "WEB"])
        XCTAssertEqual(library.books.count, 66)
        XCTAssertEqual(library.translation(id: "ESV")?.delivery, .online(.esv))
        XCTAssertEqual(library.translation(id: "NKJV")?.delivery, .online(.apiBible))
        XCTAssertEqual(library.translation(id: "NASB")?.delivery, .licensePackRequired)
        // Copyrighted text must never be offline in the bundle.
        for id in ["ESV", "NKJV", "NASB"] { XCTAssertFalse(library.translation(id: id)?.isOffline ?? true, id) }
        for name in ["ESV", "NKJV", "NASB"] {
            XCTAssertNil(AppResources.url("Scripture/\(name)"), "\(name) must not ship in the app bundle")
        }
    }

    func testKnownVersesReadCorrectlyInEachBundledTranslation() throws {
        let library = ScriptureLibrary()
        func text(_ id: String, _ code: String, _ chapter: Int, _ verse: Int) throws -> String {
            try XCTUnwrap(library.chapter(translation: id, bookCode: code, chapter: chapter)?.first { $0.number == verse }?.text)
        }
        XCTAssertTrue(try text("KJV", "JHN", 3, 16).hasPrefix("For God so loved the world"))
        XCTAssertTrue(try text("BSB", "JHN", 1, 1).hasPrefix("In the beginning was the Word"))
        XCTAssertTrue(try text("WEB", "GEN", 1, 1).contains("God created the heavens and the earth"))
        XCTAssertEqual(try text("KJV", "JHN", 3, 16), "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.")
    }

    func testKJVHasExactlyTheProtestantCanonVerseCount() {
        let library = ScriptureLibrary()
        let total = library.books.reduce(0) { sum, book in
            sum + book.chapterNumbers.reduce(0) { $0 + (library.chapter(translation: "KJV", bookCode: book.code, chapter: $1) ?? []).filter { $0.number > 0 }.count }
        }
        XCTAssertEqual(total, 31_102, "the Protestant canon has 31,102 verses")
    }

    func testNoBundledTranslationContainsLeftoverMarkup() throws {
        let library = ScriptureLibrary()
        let leftovers = try NSRegularExpression(pattern: #"\\|\||strong=|\+w|\\w|¶|\\add|\bx-"#)
        for id in ["BSB", "KJV", "WEB"] {
            for book in library.books {
                for chapter in book.chapterNumbers {
                    for verse in library.chapter(translation: id, bookCode: book.code, chapter: chapter) ?? [] {
                        let range = NSRange(verse.text.startIndex..., in: verse.text)
                        XCTAssertNil(leftovers.firstMatch(in: verse.text, range: range), "\(id) \(book.code) \(chapter):\(verse.number) has markup: \(verse.text.prefix(80))")
                        XCTAssertFalse(verse.text.isEmpty)
                    }
                }
            }
        }
    }

    func testClosingMarkersKeepTheSpaceAfterThem() {
        XCTAssertEqual(USFMParser.cleanUSFM(#"and \+add of\+add* \+w the Spirit|strong="G4151"\+w*, he"#), "and of the Spirit, he")
        XCTAssertEqual(USFMParser.cleanUSFM(#"\wj \+w Verily|strong="G1"\+w*, \+w verily|strong="G1"\+w*\wj* said"#), "Verily, verily said")
    }

    /// No two ordinary English function words may be run together ("ofthe", "andthe"…). The vocabulary
    /// comes from the BSB, which is clean, so a legitimate word is never flagged.
    func testNoWordsAreGluedTogetherInAnyBundledTranslation() throws {
        let library = ScriptureLibrary()
        let glue = try NSRegularExpression(pattern: #"\b(of|and|to|in|for|but|that|with|from|unto|upon|by|as|is|be|was|he|she|it|not)(the|thy|his|her|them|him|you|thee|thou|my|our|their|a|an|i)\b"#, options: .caseInsensitive)
        var vocabulary = Set<String>()
        for book in library.books {
            for chapter in book.chapterNumbers {
                for verse in library.chapter(translation: "BSB", bookCode: book.code, chapter: chapter) ?? [] {
                    vocabulary.formUnion(verse.text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }).map(String.init))
                }
            }
        }
        for id in ["BSB", "KJV", "WEB"] {
            for book in library.books {
                for chapter in book.chapterNumbers {
                    for verse in library.chapter(translation: id, bookCode: book.code, chapter: chapter) ?? [] {
                        let range = NSRange(verse.text.startIndex..., in: verse.text)
                        for match in glue.matches(in: verse.text, range: range) {
                            let word = (verse.text as NSString).substring(with: match.range).lowercased()
                            XCTAssertTrue(vocabulary.contains(word), "\(id) \(book.code) \(chapter):\(verse.number) has run-together “\(word)”")
                        }
                    }
                }
            }
        }
    }

    func testVerseCountFollowsTheSelectedTranslationNotTheReferenceBook() {
        let state = makeOfflineState()
        state.selectedBookCode = "MRK"; state.selectedChapter = 16
        let bsbCount = state.verseCount
        state.translationID = "KJV"
        XCTAssertEqual(state.verseCount, 20, "KJV Mark 16 has 20 verses")
        XCTAssertGreaterThanOrEqual(state.verseCount, bsbCount)
    }

    func testPsalmSuperscriptionsAreKeptAsUnnumberedScripture() throws {
        let library = ScriptureLibrary()
        let psalm3 = try XCTUnwrap(library.chapter(translation: "BSB", bookCode: "PSA", chapter: 3))
        let title = try XCTUnwrap(psalm3.first)
        XCTAssertEqual(title.number, 0)
        XCTAssertTrue(title.text.contains("David"))
        XCTAssertEqual(psalm3.dropFirst().first?.number, 1)
    }

    func testParserStripsMarkupAndKeepsVerseOrder() throws {
        let usfm = """
        \\id JHN Test
        \\toc1 John
        \\c 1
        \\p
        \\v 1 In the \\w beginning|strong="G0746"\\w* was the Word\\f + \\ft a footnote\\f*, and God.
        \\q1 second line
        \\v 2 He was with \\add God\\add*, \\wj \\+w said|strong="G1"\\+w* ¶ more\\wj*.
        \\c 2
        \\d A Psalm of David.
        \\v 1 Next.
        """
        let book = try XCTUnwrap(USFMParser.parseBook(usfm))
        XCTAssertEqual(book.chapters[1]?.map(\.number), [1, 2])
        XCTAssertEqual(book.chapters[1]?.first?.text, "In the beginning was the Word, and God. second line")
        XCTAssertEqual(book.chapters[1]?.last?.text, "He was with God, said more.")
        XCTAssertEqual(book.chapters[2]?.map(\.number), [0, 1])
    }

    func testCommittedPacksAreByteIdenticalToAFreshBuildFromSource() throws {
        for (folder, id) in [("bsb", "BSB"), ("kjv", "KJV"), ("web", "WEB")] {
            let pack = try ScripturePackBuilder.build(sourceDirectory: TestPaths.scriptureSource.appendingPathComponent(folder))
            XCTAssertEqual(pack.manifest.id, id)
            XCTAssertEqual(ScripturePackBuilder.drift(of: pack, in: TestPaths.scripturePacks.appendingPathComponent(id)), [], "\(id) pack is stale")
        }
    }

    func testPackBuilderRefusesAnIncompleteSource() throws {
        let directory = temporaryDirectory("usfm")
        try #"{"id":"X","abbreviation":"X","name":"X","language":"eng","license":{"summary":"s","attribution":"a"}}"#
            .write(to: directory.appendingPathComponent("translation.json"), atomically: true, encoding: .utf8)
        try "\\id JHN\n\\toc1 John\n\\c 1\n\\v 1 x".write(to: directory.appendingPathComponent("a.usfm"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ScripturePackBuilder.build(sourceDirectory: directory))
    }

    func testUserInstalledPackAppearsAsAnOfflineTranslationAndCannotShadowBundledOnes() throws {
        let userRoot = temporaryDirectory("translations")
        let source = TestPaths.scripturePacks.appendingPathComponent("KJV")
        // A "licensed" pack installed under a different id.
        let installed = userRoot.appendingPathComponent("ESV")
        try FileManager.default.copyItem(at: source, to: installed)
        let manifestURL = installed.appendingPathComponent("manifest.json")
        let renamed = try String(contentsOf: manifestURL, encoding: .utf8)
            .replacingOccurrences(of: #""id":"KJV""#, with: #""id":"ESV""#)
            .replacingOccurrences(of: #""abbreviation":"KJV""#, with: #""abbreviation":"ESV""#)
        try renamed.write(to: manifestURL, atomically: true, encoding: .utf8)
        // A folder that tries to replace bundled BSB.
        try FileManager.default.copyItem(at: TestPaths.scripturePacks.appendingPathComponent("KJV"), to: userRoot.appendingPathComponent("BSBx"))
        let spoof = userRoot.appendingPathComponent("BSBx/manifest.json")
        try String(contentsOf: spoof, encoding: .utf8).replacingOccurrences(of: #""id":"KJV""#, with: #""id":"BSB""#)
            .write(to: spoof, atomically: true, encoding: .utf8)

        let library = ScriptureLibrary(userRoot: userRoot)
        XCTAssertEqual(library.translation(id: "ESV")?.delivery, .installedPack)
        XCTAssertTrue(library.translation(id: "ESV")?.isOffline ?? false)
        XCTAssertEqual(library.translation(id: "BSB")?.delivery, .bundled)
        XCTAssertTrue(try XCTUnwrap(library.chapter(translation: "BSB", bookCode: "JHN", chapter: 1)?.first?.text).hasPrefix("In the beginning was the Word"))
    }
}

@MainActor
extension ScriptureTests {
    func testFullTextSearchFindsAVerseByPhraseAcrossTheWholeBible() {
        let library = ScriptureLibrary()
        let hits = library.search(translationID: "KJV", query: "God so loved the world")
        XCTAssertTrue(hits.contains { $0.bookCode == "JHN" && $0.chapter == 3 && $0.verse == 16 })
        XCTAssertTrue(hits.allSatisfy { $0.text.localizedCaseInsensitiveContains("God so loved the world") })
    }

    func testSearchIsCaseInsensitiveAndIgnoresShortQueries() {
        let library = ScriptureLibrary()
        XCTAssertEqual(library.search(translationID: "KJV", query: "jesus wept").map(\.reference), ["John 11:35"])
        XCTAssertTrue(library.search(translationID: "KJV", query: "ab").isEmpty, "queries under 3 characters should not search")
    }

    func testSearchRespectsTheLimitAndStaysPerTranslation() {
        let library = ScriptureLibrary()
        let capped = library.search(translationID: "KJV", query: "the LORD", limit: 5)
        XCTAssertEqual(capped.count, 5)
        let kjv = library.search(translationID: "KJV", query: "shall not want")
        let web = library.search(translationID: "WEB", query: "shall not want")
        XCTAssertFalse(kjv.isEmpty)
        // WEB uses different wording in places; the two translations are not required to agree,
        // but both must only ever return hits that actually contain the query.
        XCTAssertTrue(web.allSatisfy { $0.text.localizedCaseInsensitiveContains("shall not want") })
        XCTAssertTrue(kjv.allSatisfy { $0.text.localizedCaseInsensitiveContains("shall not want") })
    }

    func testUnknownTranslationSearchesReturnNothing() {
        let library = ScriptureLibrary()
        XCTAssertTrue(library.search(translationID: "ESV", query: "beginning was the Word").isEmpty)
    }
}
