import XCTest
@testable import StudyTable

/// The Westminster link model: only human-reviewed links are ever shown, and being a
/// Reformed source never creates one.
@MainActor
final class ConfessionTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = temporaryDirectory("wcf")
    }

    private func linkFile(_ links: [String]) throws -> URL {
        let url = directory.appendingPathComponent("links-\(UUID().uuidString).json")
        try #"{"schema":1,"links":[\#(links.joined(separator: ","))]}"#.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func link(_ id: String, chapter: Int = 8, section: Int? = 5, state: String = "curated",
                      reviewer: String? = "Reviewer One", date: String? = "2026-09-21", relation: String = "affirms") -> String {
        var fields = [#""entryID":"\#(id)""#, #""wcf":{"chapter":\#(chapter),"section":\#(section.map(String.init) ?? "null")}"#,
                      #""relation":"\#(relation)""#, #""state":"\#(state)""#]
        if let reviewer { fields.append(#""reviewer":"\#(reviewer)""#) }
        if let date { fields.append(#""reviewedOn":"\#(date)""#) }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func store(_ links: [String], local: [String] = []) throws -> ConfessionStore {
        ConfessionStore(chaptersURL: AppResources.url("Confession/wcf-chapters.json"),
                        bundledLinksURL: try linkFile(links),
                        localLinksURL: local.isEmpty ? nil : try linkFile(local))
    }

    private var romans828: [StudySource] { (Corpus.byBook["ROM"] ?? []).filter { $0.chapter == 8 && $0.covers(verse: 28) } }

    func testShippedConfessionStructureMatchesTheDocument() throws {
        let confession = ConfessionStore()
        XCTAssertEqual(confession.chapters.count, 33)
        XCTAssertEqual(confession.chapters.values.reduce(0) { $0 + $1.sections }, 171)
        XCTAssertEqual(confession.chapters[31]?.sections, 4)
        XCTAssertEqual(confession.chapters[8]?.title, "Of Christ the Mediator")
    }

    func testShippedStoreHasNoLinksThatAreNotHumanReviewed() {
        let confession = ConfessionStore(localLinksURL: nil)
        for record in confession.allRecords where confession.isValid(record) {
            XCTAssertEqual(record.state, .curated)
            XCTAssertFalse((record.reviewer ?? "").isEmpty)
            XCTAssertFalse((record.reviewedOn ?? "").isEmpty)
        }
        let ids = Set(Corpus.all.map(\.id))
        XCTAssertEqual(confession.problems(knownEntryIDs: ids), [], "shipped links must all resolve to real entries")
    }

    func testBeingAReformedSourceNeverProducesAWestminsterLink() throws {
        let empty = StudyResourceStore(confession: try store([]))
        let sources = empty.sources(bookCode: "ROM", bookName: "Romans", chapter: 8, verse: 28)
        XCTAssertTrue(sources.contains { $0.entry.tradition == .reformed })
        XCTAssertTrue(sources.allSatisfy { $0.confessionLinks.isEmpty })
    }

    func testOnlyACuratedReviewedLinkIsDisplayedAndOnlyOnItsOwnEntry() throws {
        let calvin = try XCTUnwrap(romans828.first { $0.author == "John Calvin" })
        let henry = try XCTUnwrap(romans828.first { $0.author == "Matthew Henry" })
        let resources = StudyResourceStore(confession: try store([link(calvin.id)]))
        let sources = resources.sources(bookCode: "ROM", bookName: "Romans", chapter: 8, verse: 28)
        XCTAssertEqual(sources.first { $0.id == calvin.id }?.confessionLinks.map(\.wcf.label), ["WCF 8.5"])
        XCTAssertEqual(sources.first { $0.id == henry.id }?.confessionLinks.count, 0, "another Reformed source must not inherit the link")
        XCTAssertEqual(sources.first { $0.id == calvin.id }?.entry.sourceClass, .reformedSource, "the source class stays Reformed")
    }

    func testCandidateRejectedAndUnattributedLinksAreNeverShown() throws {
        let id = try XCTUnwrap(romans828.first).id
        let confession = try store([
            link(id, chapter: 1, section: 1, state: "candidate"),
            link(id, chapter: 2, section: 1, state: "rejected"),
            link(id, chapter: 3, section: 1, reviewer: nil),
            link(id, chapter: 4, section: 1, reviewer: "  "),
            link(id, chapter: 5, section: 1, date: nil)
        ])
        XCTAssertTrue(confession.links(forEntryID: id).isEmpty)
        XCTAssertEqual(confession.displayableCount, 0)
        XCTAssertTrue(confession.problems(knownEntryIDs: [id]).contains { $0.contains("curated link without reviewer or date") })
    }

    func testInvalidChapterOrSectionIsNotShownAndIsReported() throws {
        let id = try XCTUnwrap(romans828.first).id
        let confession = try store([link(id, chapter: 4, section: 9), link(id, chapter: 40, section: 1)])
        XCTAssertTrue(confession.links(forEntryID: id).isEmpty)
        let problems = confession.problems(knownEntryIDs: [id])
        XCTAssertTrue(problems.contains { $0.contains("no section 9") })
        XCTAssertTrue(problems.contains { $0.contains("unknown WCF chapter") })
    }

    func testOrphanedLinksAreReported() throws {
        let confession = try store([link("ROM.8.28-28.calvin.deadbeef")])
        XCTAssertEqual(confession.problems(knownEntryIDs: Set(Corpus.all.map(\.id))).count, 1)
    }

    func testLocalReviewFileOverridesTheShippedRecordAndCanWithdrawALink() throws {
        let id = try XCTUnwrap(romans828.first).id
        let shipped = link(id)
        XCTAssertEqual(try store([shipped]).links(forEntryID: id).count, 1)
        let withdrawn = try store([shipped], local: [link(id, state: "rejected")])
        XCTAssertTrue(withdrawn.links(forEntryID: id).isEmpty)
        let added = try store([], local: [link(id, chapter: 3, section: 1)])
        XCTAssertEqual(added.links(forEntryID: id).map(\.wcf.label), ["WCF 3.1"])
    }

    func testChapterLevelLinkLabelsWithoutASection() throws {
        let id = try XCTUnwrap(romans828.first).id
        XCTAssertEqual(try store([link(id, chapter: 8, section: nil)]).links(forEntryID: id).first?.wcf.label, "WCF 8")
    }
}

@MainActor
final class CreedsTests: XCTestCase {
    func testShippedCreedsLoadAllThreeWithFullText() {
        let confession = ConfessionStore()
        XCTAssertEqual(Set(confession.creeds.map(\.id)), ["apostles", "nicene", "chalcedon"])
        for creed in confession.creeds {
            XCTAssertGreaterThan(creed.text.count, 100, creed.id)
            XCTAssertFalse(creed.note.isEmpty, creed.id)
            XCTAssertFalse(creed.era.isEmpty, creed.id)
        }
    }

    func testApostlesCreedTextIsComplete() {
        let confession = ConfessionStore()
        let apostles = confession.creeds.first { $0.id == "apostles" }
        XCTAssertTrue(apostles?.text.contains("Maker of heaven and earth") ?? false)
        XCTAssertTrue(apostles?.text.contains("the resurrection of the body") ?? false)
        XCTAssertTrue(apostles?.text.hasSuffix("Amen.") ?? false)
    }

    func testConfessionChapterListIsExposedForBrowsing() {
        let confession = ConfessionStore()
        XCTAssertEqual(confession.chapterList.count, 33)
        XCTAssertEqual(confession.chapterList.map(\.n), Array(1...33), "chapter list should be sorted")
    }
}
