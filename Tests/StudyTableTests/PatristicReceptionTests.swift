import XCTest
@testable import StudyTable

@MainActor
final class PatristicReceptionTests: XCTestCase {
    func testActualOfflineReaderIncludesFathersAndRetainsSpuriousAttributions() throws {
        let book = try PatristicReader.load()
        XCTAssertGreaterThan(book.articles.count, 100)
        XCTAssertEqual(Set(book.articles.map(\.id)).count, book.articles.count)
        let body = book.articles.map(\.body).joined(separator: "\n").lowercased()
        for name in ["clement", "polycarp", "ignatius", "hermas", "papias"] { XCTAssertTrue(body.contains(name), name) }
        XCTAssertTrue(book.articles.contains { $0.title.localizedCaseInsensitiveContains("spurious") })
        XCTAssertTrue(book.articles.contains { $0.title.localizedCaseInsensitiveContains("shorter") })
        XCTAssertTrue(book.articles.contains { $0.title.localizedCaseInsensitiveContains("longer") })
        XCTAssertTrue(body.contains("full project gutenberg"))
        XCTAssertTrue(book.attribution.contains("1870"))
        XCTAssertTrue(ResourceCatalog.resources(in: .included).contains { $0.id == "apostolic-fathers" })
    }

    func testMissingReaderReportsFailureInsteadOfAdvertisingAnEmptyLibrary() {
        XCTAssertThrowsError(try PatristicReader.load(url: nil))
    }

    func testProfilesPreserveJudgmentScopeAndContestedReception() throws {
        let store = FatherProfileStore()
        XCTAssertGreaterThanOrEqual(store.count, 74)
        for profile in store.allProfiles { XCTAssertFalse(profile.sources.isEmpty, profile.name) }
        let novatian = try XCTUnwrap(store.profile(forAuthor: "Novatian"))
        XCTAssertTrue(try XCTUnwrap(novatian.conciliarJudgment?.note).contains("not for a Trinitarian heresy"))
        let origen = try XCTUnwrap(store.profile(forAuthor: "Origen of Alexandria"))
        XCTAssertNil(origen.conciliarJudgment)
        XCTAssertTrue(try XCTUnwrap(origen.controversies).contains("disputed"))
        XCTAssertEqual(origen.receptionLabel, "Reception note — read context")
        XCTAssertNil(store.profile(forAuthor: "Valentinus")?.conciliarJudgment)
        XCTAssertTrue(ConfessionalTier.researchWarning.contains("Origen and Tertullian remain"))
    }

    func testDoctrinalConflictIsSourcedWithoutInventingAnAncientCondemnation() throws {
        let jung = try XCTUnwrap(ReceptionTopic.topics.first { $0.id == "jung" })
        XCTAssertEqual(jung.kind, .conflict)
        XCTAssertEqual(jung.period, "20th century")
        XCTAssertTrue(jung.limit.contains("No early council ruled on Jung"))
        XCTAssertTrue(jung.summary.contains("§661"))
        XCTAssertTrue(jung.summary.contains("§662"))
        XCTAssertTrue(jung.comparison.contains("1 Corinthians 15:3"))
        XCTAssertEqual(ReceptionTopic.topics.first { $0.id == "nicaea" }?.kind, .council)
        XCTAssertEqual(ReceptionTopic.topics.first { $0.id == "docetism" }?.kind, .refuted)
        for topic in ReceptionTopic.topics {
            XCTAssertFalse(topic.sources.isEmpty)
            for source in topic.sources { XCTAssertEqual(source.url?.scheme, "https") }
        }
    }
}
