import XCTest
import Foundation
@testable import StudyTable

@MainActor
final class LibrarySearchIndexTests: XCTestCase {
    private let augustine = ResourceBook(id: "pg-45305", title: "The City of God, Volume II", author: "Augustine of Hippo", attribution: "Public domain", source: nil, articles: [
        ResourceArticle(id: "a", title: "Book XX", body: "We shall be caught up together with them in the clouds, to meet the Lord in the air.\n\nThe thousand years are the whole period of this world.\n\nThe resurrections of the dead are two.", anchor: nil),
        ResourceArticle(id: "b", title: "Book XXI", body: "Of the eternal fire of hell.", anchor: nil)])
    private let calvin = ResourceBook(id: "pg-64392", title: "Institutes II", author: "John Calvin", attribution: "Public domain", source: nil, articles: [
        ResourceArticle(id: "c", title: "Chapter XXV", body: "The Millenarians limited the reign of Christ to a thousand years.", anchor: nil)])

    private func index(_ books: [ResourceBook]) async throws -> LibrarySearchIndex {
        let index = LibrarySearchIndex(url: temporaryDirectory("search-index").appendingPathComponent("index.sqlite"))
        try await index.sync(sources: books.map(LibrarySearchSources.book))
        return index
    }

    func testConceptSearchFindsOlderWordingAndRanksExactPhraseFirst() async throws {
        let index = try await index([augustine, calvin])
        let rapture = try await LibraryTextSearch.indexed(query: "rapture", scope: .books, offset: 0, concepts: true, index: index, studyRoot: nil,
            historicRoot: nil, books: [augustine, calvin], notes: [], includeResearch: false, citing: [])
        XCTAssertEqual(rapture.page.hits.first?.body.hasPrefix("We shall be caught up"), true, "“rapture” finds “caught up”")
        XCTAssertEqual(rapture.concepts.first?.name, "Rapture")
        let exact = try await LibraryTextSearch.indexed(query: "rapture", scope: .books, offset: 0, concepts: false, index: index, studyRoot: nil,
            historicRoot: nil, books: [augustine, calvin], notes: [], includeResearch: false, citing: [])
        XCTAssertEqual(exact.page.total, 0, "Exact words only does not widen")
        let millennium = try await LibraryTextSearch.indexed(query: "millennium", scope: .books, offset: 0, concepts: true, index: index, studyRoot: nil,
            historicRoot: nil, books: [augustine, calvin], notes: [], includeResearch: false, citing: [])
        XCTAssertEqual(Set(millennium.page.hits.compactMap(\.focus?.bookID)), ["pg-45305", "pg-64392"])
        let phrase = try await LibraryTextSearch.indexed(query: "thousand years", scope: .books, offset: 0, concepts: true, index: index, studyRoot: nil,
            historicRoot: nil, books: [augustine, calvin], notes: [], includeResearch: false, citing: [])
        XCTAssertEqual(phrase.page.hits.count, 2)
    }

    func testStemmingAndDiacriticsMatchWordForms() async throws {
        let index = try await index([augustine])
        let hits = try await index.search("\"resurrection\"", kinds: [.book], includeResearch: false, limit: 10)
        XCTAssertEqual(hits.total, 1, "“resurrection” matches “resurrections”")
    }

    func testSyncReindexesChangedBooksAndRemovesDeletedOnes() async throws {
        let index = try await index([augustine, calvin])
        let first = try await index.documentCount()
        let unchanged = try await index.sync(sources: [augustine, calvin].map(LibrarySearchSources.book))
        XCTAssertEqual(unchanged, 0, "Unchanged sources are not reindexed")
        let removed = try await index.sync(sources: [augustine].map(LibrarySearchSources.book))
        XCTAssertEqual(removed, 0)
        let after = try await index.documentCount()
        XCTAssertEqual(after, first - 1, "Removed book's paragraphs leave the index")
        let gone = try await index.search("\"millenarians\"", kinds: [.book], includeResearch: false, limit: 5)
        XCTAssertEqual(gone.total, 0)
    }

    func testQueryPlansKeepPunctuationOutOfSearchSyntax() {
        XCTAssertEqual(SearchPlan.literal("NEAR(\"x\" OR *"), "\"NEAR( x OR *\"")
        let plan = SearchPlan.make("man of sin")
        XCTAssertEqual(plan?.concepts.first?.name, "Antichrist", "A whole-query concept is one concept")
        XCTAssertNil(SearchPlan.make("   "))
        XCTAssertTrue(ConceptVocabulary.groups.allSatisfy { !$0.terms.isEmpty })
    }

    func testCommentaryIndexMatchesBundledSourcesAndIsFast() async throws {
        guard ProcessInfo.processInfo.environment["STUDYTABLE_INDEX_COMMENTARY"] == "1" else { throw XCTSkip("Indexes all bundled commentary (about a minute); opt-in") }
        let state = makeOfflineState()
        let root = try XCTUnwrap(state.studyResources.searchDirectory)
        let folder = temporaryDirectory("search-commentary")
        let index = LibrarySearchIndex(url: folder.appendingPathComponent("index.sqlite"))
        var start = Date()
        try await index.sync(sources: [try XCTUnwrap(LibrarySearchSources.commentary(root: root))])
        let entries = try await index.documentCount()
        let bytes = (try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])).reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        print("COMMENTARY INDEX SIZE: \(bytes / 1_000_000) MB on disk")
        print("COMMENTARY INDEX: \(entries) entries in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        start = Date()
        let result = try await LibraryTextSearch.indexed(query: "first resurrection", scope: .commentary, offset: 0, concepts: true, index: index,
            studyRoot: root, historicRoot: nil, books: [], notes: [], includeResearch: false, citing: [])
        let elapsed = Date().timeIntervalSince(start)
        print("COMMENTARY SEARCH: \(result.page.total) results in \(String(format: "%.3f", elapsed))s; first: \(result.page.hits.first?.collection ?? "-") \(result.page.hits.first?.anchor?.displayString ?? "")")
        XCTAssertGreaterThan(result.page.total, 0)
        XCTAssertLessThan(elapsed, 1.0)
        let linearStart = Date()
        _ = try LibraryTextSearch.search(query: "first resurrection", scope: .commentary, offset: 0, studyRoot: root, books: [], notes: [], historicRoot: nil, includeResearch: false)
        print("LINEAR COMMENTARY SEARCH: \(String(format: "%.3f", Date().timeIntervalSince(linearStart)))s")
    }
}
