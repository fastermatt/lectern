import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

@MainActor
final class PassageGuideTests: XCTestCase {
    private func library() -> ScriptureLibrary { ScriptureLibrary(userRoot: temporaryDirectory("guide-translations")) }

    private func resources(at directory: URL? = AppResources.url("Study")) -> StudyResourceStore {
        StudyResourceStore(confession: ConfessionStore(localLinksURL: nil), studyDirectory: directory)
    }

    private func service(resources store: StudyResourceStore? = nil, references: ReferenceStore? = nil,
                         study: StudyStore? = nil) -> PassageGuideService {
        PassageGuideService(library: library(), resources: store ?? resources(),
            references: references ?? ReferenceStore(), study: study ?? ephemeralStudy())
    }

    func testSelectedRangeUsesEveryVerseAndDeduplicatesRealSourceIDs() throws {
        let store = resources()
        let guide = service(resources: store)
        let anchor = try XCTUnwrap(Anchor.parse("Rom 8:28–39"))
        let result = try guide.build(anchor: anchor, traditions: Set(SourceTradition.allCases), includeResearch: false)
        XCTAssertEqual(result.verses.map(\.verse), Array(28...39))
        // Independent oracle: filter raw chapter entries by interval overlap, not per-verse lookups.
        let expected = store.entries(bookCode: "ROM").filter {
            $0.chapter == 8 && $0.startVerse <= 39 && $0.endVerse >= 28 && $0.tier != .tier3ResearchOnly
        }
        XCTAssertEqual(Set(result.sources.map(\.id)), Set(expected.map(\.id)))
        XCTAssertEqual(result.sources.count, Set(result.sources.map(\.id)).count)
        XCTAssertTrue(result.sources.contains { $0.verses.count > 1 }, "real passage-spanning entries should occur once")
        XCTAssertTrue(result.sources.contains { $0.verses.contains(PassageGuideVerse(chapter: 8, verse: 39)) })
        for item in result.sources {
            XCTAssertEqual(item.resolved.record, store.registry[item.resolved.entry.source])
            XCTAssertEqual(item.verses.count, Set(item.verses).count)
            XCTAssertTrue(item.verses.allSatisfy { item.resolved.entry.covers(verse: $0.verse) })
        }
    }

    func testCrossChapterGuideRemainsFixedWhenReaderMovesUntilFollowIsChosen() throws {
        let guide = service()
        let anchor = try guide.parse("Rom 8:39–9:5")
        let result = try guide.build(anchor: anchor, traditions: [.reformed], includeResearch: false)
        XCTAssertEqual(result.verses, [PassageGuideVerse(chapter: 8, verse: 39)] + (1...5).map { PassageGuideVerse(chapter: 9, verse: $0) })
        XCTAssertEqual(Set(result.sources.map { $0.resolved.entry.chapter }), [8, 9])
        var scope = PassageGuideScope()
        scope.pin(anchor)
        let next = Anchor(book: "JHN", chapter: 3, verse: 16)
        XCTAssertEqual(scope.anchor(selection: next), anchor)
        XCTAssertFalse(scope.followsSelection)
        scope.followSelection()
        XCTAssertEqual(scope.anchor(selection: next), next)
        XCTAssertTrue(scope.followsSelection)
    }

    func testActualVerseIdentifiersAreValidatedAndOversizeNeverTruncated() throws {
        let guide = service()
        XCTAssertThrowsError(try guide.parse("Rom 8:999"))
        XCTAssertThrowsError(try guide.parse("Romans 99:1"))
        XCTAssertThrowsError(try guide.parse("Romans 8:39–28"))
        XCTAssertThrowsError(try guide.parse("bananas"))
        XCTAssertThrowsError(try guide.parse("Romans")) { XCTAssertEqual($0 as? PassageGuideError, .tooManyChapters) }
        XCTAssertThrowsError(try guide.parse("Rom 1–6")) { XCTAssertEqual($0 as? PassageGuideError, .tooManyChapters) }
        // The BSB's omitted verse has a number below the chapter's maximum, so count-based
        // endpoint validation would accept a verse which is not actually present.
        XCTAssertThrowsError(try guide.parse("Matthew 17:21")) {
            XCTAssertEqual($0 as? PassageGuideError, .missingVerse(17, 21))
        }
        let wholeChapter = try guide.parse("Rom 8")
        XCTAssertEqual(try guide.verses(in: wholeChapter).count, 39)
        XCTAssertEqual(try guide.parse("Rom.8.28-Rom.8.39").chapterStart, 8)
    }

    func testBanksAndResearchOptInApplyToEveryVerseAndReferenceProvenanceSurvivesDedup() throws {
        let directory = temporaryDirectory("guide-fixture")
        let book = directory.appendingPathComponent("ROM", isDirectory: true)
        try FileManager.default.createDirectory(at: book, withIntermediateDirectories: true)
        let reference = CrossReference(code: "JHN", chapter: 3, start: 16, end: 16, label: "John 3:16")
        let exactURL = URL(string: "https://example.org/edition/chapter")!
        func entry(_ id: String, tradition: SourceTradition, tier: ConfessionalTier = .tier1Confessional) -> StudySource {
            StudySource(id: id, chapter: 8, startVerse: 28, endVerse: 30, rangeBasis: .stated,
                author: "Historic author", work: "Specific edition", era: "Historic", tradition: tradition,
                source: "fixture", excerpt: "A source quotation.", sourceURL: exactURL, isExactQuote: true,
                truncated: false, crossRefs: [reference], tier: tier)
        }
        let entries = [entry("received", tradition: .fathers), entry("research", tradition: .fathers, tier: .tier3ResearchOnly),
                       entry("reformed", tradition: .reformed)]
        struct Chapter: Encodable { let schema = 3; let code = "ROM"; let book = "Romans"; let chapter = 8; let entries: [StudySource] }
        try JSONEncoder().encode(Chapter(entries: entries)).write(to: book.appendingPathComponent("8.json"))
        let record = SourceRecord(title: "Fixture edition", short: "Fixture", publisher: "Historic publisher",
            url: URL(string: "https://example.org/database")!, license: "Fixture licence",
            review: ReviewInfo(state: .sourceAttributed, note: "Fixture provenance"))
        try JSONEncoder().encode(SourceRegistry(schema: 3, sources: ["fixture": record])).write(to: directory.appendingPathComponent("sources.json"))
        let guide = service(resources: resources(at: directory), references: ReferenceStore(directory: temporaryDirectory("guide-empty-refs")))
        let anchor = try guide.parse("Rom 8:28–30")
        let filtered = try guide.build(anchor: anchor, traditions: [.fathers], includeResearch: false)
        XCTAssertEqual(filtered.sources.map(\.id), ["received"])
        let expanded = try guide.build(anchor: anchor, traditions: [.fathers], includeResearch: true)
        XCTAssertEqual(Set(expanded.sources.map(\.id)), ["received", "research"])
        XCTAssertEqual(expanded.crossReferences.count, 1)
        XCTAssertEqual(expanded.crossReferences.first?.from.count, 3)
        XCTAssertEqual(expanded.crossReferences.first?.sources.count, 2)
        XCTAssertEqual(expanded.sources.first?.resolved.provenanceURL, exactURL)
        XCTAssertEqual(expanded.sources.first?.resolved.provenanceScope, .specificWork)
        XCTAssertEqual(expanded.sources.first?.resolved.record?.license, "Fixture licence")
        XCTAssertTrue(expanded.sources.allSatisfy { $0.resolved.confessionLinks.isEmpty }, "aggregation must not manufacture curated WCF links")
        let none = try guide.build(anchor: anchor, traditions: [], includeResearch: true)
        XCTAssertTrue(none.sources.isEmpty)
        XCTAssertTrue(none.crossReferences.isEmpty)
    }

    func testDirectAndAdditionalTopicIndexesRemainDistinctAndPeopleAreRealRecords() throws {
        let references = ReferenceStore()
        let guide = service(references: references)
        let result = try guide.build(anchor: guide.parse("Rom 8:28–39"), traditions: [], includeResearch: false)
        let sin = try XCTUnwrap(result.topics.first { $0.name == "SIN" })
        XCTAssertTrue(sin.direct.isEmpty)
        XCTAssertEqual(sin.additional.count, 12)
        XCTAssertTrue(result.topics.contains { !$0.direct.isEmpty })
        let acts = try guide.build(anchor: guide.parse("Acts 9:3"), traditions: [], includeResearch: false)
        XCTAssertTrue(acts.people.contains { $0.name.name == "Damascus" && $0.name.isPlace })
        XCTAssertTrue(acts.people.allSatisfy { !$0.name.description.isEmpty && $0.verses == [PassageGuideVerse(chapter: 9, verse: 3)] })
    }

    func testAdditionalTopicsCanContainNarrowDirectCitationsBeyondThePrimaryDisplayCap() throws {
        let references = ReferenceStore()
        let guide = service(references: references)
        // Independent evidence from the topic's complete citation metadata: this nine-verse
        // citation qualifies as direct, although BABYLON falls beyond the primary 12 names.
        let rawTopic = try XCTUnwrap(references.topic(named: "BABYLON"))
        XCTAssertTrue(rawTopic.refs.contains {
            $0.code == "GEN" && $0.chapter == 11 && $0.start == 1 && $0.end == 9
        })
        XCTAssertFalse(references.topics(bookCode: "GEN", chapter: 11, verse: 3).contains("BABYLON"))
        let result = try guide.build(anchor: guide.parse("Gen 11:3"), traditions: [], includeResearch: false)
        let babylon = try XCTUnwrap(result.topics.first { $0.name == "BABYLON" })
        XCTAssertTrue(babylon.direct.isEmpty)
        XCTAssertEqual(babylon.additional, [PassageGuideVerse(chapter: 11, verse: 3)],
            "overflow remains reachable without claiming it is necessarily a broad citation")
    }

    func testEmptyResourcesAreHonestAndPersonalItemsUseRangeOverlap() throws {
        let study = ephemeralStudy()
        let anchor = try XCTUnwrap(Anchor.parse("Rom 8:28–39"))
        let note = study.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verse: 39)], title: "Range note", body: "An observation")
        _ = study.addNote(anchors: [Anchor(book: "ROM", chapter: 9, verse: 1)], title: "Outside", body: "Elsewhere")
        _ = study.save(Anchor(book: "ROM", chapter: 8, verses: 29, to: 31))
        let guide = service(resources: resources(at: temporaryDirectory("guide-no-sources")),
                            references: ReferenceStore(directory: temporaryDirectory("guide-no-references")), study: study)
        let result = try guide.build(anchor: anchor, traditions: Set(SourceTradition.allCases), includeResearch: false)
        XCTAssertTrue(result.sources.isEmpty)
        XCTAssertTrue(result.crossReferences.isEmpty)
        XCTAssertTrue(result.topics.isEmpty)
        XCTAssertTrue(result.people.isEmpty)
        XCTAssertEqual(result.personal.notes.map(\.id), [try XCTUnwrap(note?.id)])
        XCTAssertEqual(result.personal.saved.count, 1)
    }

    func testGuideRendersAt290PointDeskWidthInBothFinishes() throws {
        InterlinearSelection.shared.clear()
        defer { InterlinearSelection.shared.clear() }
        for dark in [false, true] {
            let online = OnlineTranslationService(cache: OnlineChapterCache(directory: temporaryDirectory("guide-cache")),
                transport: { _ in throw URLError(.notConnectedToInternet) },
                idStore: BibleIDStore(defaultsKey: "guide-tests.\(UUID().uuidString)"), keyReader: { _ in nil })
            let defaults = ephemeralDefaults()
            let state = AppState(library: library(), studyResources: resources(), online: online,
                defaults: defaults, notes: ephemeralStudy())
            state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
            state.extendRange(to: 39)
            let view = SourcesPane(references: ReferenceStore()).environmentObject(state)
                .defaultAppStorage(defaults).environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: 290, height: 800)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 290, height: 800)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderBack(nil)
            defer { window.orderOut(nil) }
            for _ in 0..<4 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
            if let output = ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent("passage-guide-290-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
