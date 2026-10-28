import AppKit
import SwiftUI
import XCTest
@testable import StudyTable
@testable import StudyTableCore

/// Workstream J (0.8): Passage Guide — Topics (Nave's), Dictionary (Easton's), People &
/// Places (STEPBible TIPNR), Compare. Uses a fresh `ReferenceStore(directory:)` pointed at
/// the real bundled `Resources/Reference` (read-only; nothing here writes into it), never
/// `.shared`, so each test measures a genuinely cold load — same pattern as `LexiconTests`.
@MainActor
final class ReferenceTests: XCTestCase {
    private func freshStore() -> ReferenceStore {
        ReferenceStore(directory: AppResources.url("Reference"))
    }

    // MARK: Required spot checks (WORKPLAN-0.8.md § J)

    /// "John 3:16 topics plausible (Nave's)": the verse is at the heart of the gospel's own
    /// summary of salvation through God's love in Christ, so at least one topic drawn from
    /// that semantic space should be present. Not asserting an exact topic set — Nave's own
    /// wording/coverage is the source of truth, not this test's guess at it.
    func testJohn316TopicsArePlausible() {
        let store = freshStore()
        let topics = store.topics(bookCode: "JHN", chapter: 3, verse: 16)
        XCTAssertFalse(topics.isEmpty, "John 3:16 should resolve at least one Nave's topic")
        let plausible: Set<String> = ["SALVATION", "GOD", "LIFE", "FAITH", "JESUS, THE CHRIST", "LOVE", "IMMORTALITY"]
        XCTAssertFalse(plausible.isDisjoint(with: Set(topics)),
                       "expected a salvation/love/faith-related topic, got \(topics)")
        // "Topic → all verses" must actually resolve and include the seed verse back.
        guard let first = topics.first, let topic = store.topic(named: first) else {
            return XCTFail("topic \(topics.first ?? "?") did not resolve")
        }
        XCTAssertTrue(topic.refs.contains { $0.code == "JHN" && $0.chapter == 3 && $0.start <= 16 && $0.end >= 16 })
    }

    /// "Genesis 1:1 dictionary links Creation."
    func testGenesisOneOneDictionaryLinksCreation() {
        let store = freshStore()
        let headwords = store.dictionaryHeadwords(bookCode: "GEN", chapter: 1, verse: 1)
        XCTAssertTrue(headwords.contains("CREATION"), "expected CREATION, got \(headwords)")
        let article = store.article(headword: "CREATION")
        XCTAssertNotNil(article)
        XCTAssertFalse(article?.text.isEmpty ?? true)
    }

    /// Book introductions: every canon book should resolve to a real Easton article.
    func testBookIntroductionsResolveForAllCanonBooks() {
        let store = freshStore()
        var missing: [String] = []
        for code in Canon.bookCodes where store.bookIntroArticle(bookCode: code) == nil {
            missing.append(code)
        }
        XCTAssertTrue(missing.isEmpty, "missing Easton book introductions for: \(missing)")
    }

    /// "Acts 9:3 people include Saul/Paul and places include Damascus."
    func testActsNineThreePeopleAndPlaces() {
        let store = freshStore()
        let names = store.names(bookCode: "ACT", chapter: 9, verse: 3)
        let people = names.filter { $0.isPerson }.map(\.name)
        let places = names.filter { $0.isPlace }.map(\.name)
        XCTAssertTrue(people.contains("Paul") || people.contains("Saul"),
                      "expected Paul or Saul among people, got \(people)")
        XCTAssertTrue(places.contains("Damascus"), "expected Damascus among places, got \(places)")
        // Every name should carry a non-empty STEPBible description and at least one ref.
        for entry in names {
            XCTAssertFalse(entry.description.isEmpty, "\(entry.name) has no description")
            XCTAssertFalse(entry.refs.isEmpty, "\(entry.name) has no references")
        }
    }

    /// "Compare shows ≥3 offline translations for John 3:16." Exercises the exact function
    /// `CompareSection` calls, not a reimplementation of its logic.
    func testCompareShowsAtLeastThreeOfflineTranslationsForJohn316() {
        let library = ScriptureLibrary()
        let rows = compareOfflineRows(library: library, bookCode: "JHN", chapter: 3, verse: 16)
        XCTAssertGreaterThanOrEqual(rows.count, 3, "expected >=3 offline translations, got \(rows.map(\.label))")
        XCTAssertTrue(rows.contains { $0.id == "BSB" })
        for row in rows {
            XCTAssertFalse(row.text.isEmpty, "\(row.label) returned empty text")
            XCTAssertFalse(row.isCached, "an offline pack row should never be marked cached")
            XCTAssertEqual(row.attribution, library.translations.first { $0.id == row.id }?.attribution,
                           "Compare must retain the pack attribution with its text")
        }
    }

    /// Compare never fetches — an online translation with nothing cached simply doesn't
    /// appear (no network call is made or possible from this synchronous helper at all).
    func testCompareNeverIncludesAnUncachedOnlineTranslation() {
        let library = ScriptureLibrary()
        let rows = compareOfflineRows(library: library, bookCode: "JHN", chapter: 3, verse: 16)
        XCTAssertFalse(rows.contains { $0.id == "ESV" || $0.id == "NKJV" },
                       "ESV/NKJV are online-only and must never appear from the offline-only helper")
    }

    // MARK: Specificity (0.10, workstream R2)

    /// The pastor's finding: SIN / ROME (and Easton's FELLOWSHIP) sat on every verse of Romans
    /// 8:28-39 because those topics cite "Rom. 8" as a whole chapter. They no longer attach to a verse
    /// they merely span; they remain reachable behind "more"; and the topic -> all-verses direction
    /// is untouched (SIN still lists the whole-chapter citation).
    func testWideCitationsDoNotAttachToEveryVerseOfRomans8() throws {
        let store = freshStore()
        for verse in 28...39 {
            let topics = store.topics(bookCode: "ROM", chapter: 8, verse: verse)
            XCTAssertFalse(topics.contains("SIN"), "SIN is shown at Rom 8:\(verse)")
            XCTAssertFalse(topics.contains("ROME"), "ROME is shown at Rom 8:\(verse)")
            XCTAssertFalse(store.dictionaryHeadwords(bookCode: "ROM", chapter: 8, verse: verse).contains("FELLOWSHIP"))
            XCTAssertFalse(topics.isEmpty, "Rom 8:\(verse) lost every direct topic")
        }
        let more = store.moreTopics(bookCode: "ROM", chapter: 8, verse: 28)
        XCTAssertTrue(more.contains("SIN") && more.contains("ROME"), "wide hits must stay reachable: \(more)")
        XCTAssertTrue(store.moreDictionaryHeadwords(bookCode: "ROM", chapter: 8, verse: 28).contains("FELLOWSHIP"))
        let sin = try XCTUnwrap(store.topic(named: "SIN"))
        XCTAssertTrue(sin.refs.contains { $0.code == "ROM" && $0.chapter == 8 && $0.start == 1 && $0.end == 39 },
                      "the topic's own verse list must be unchanged")
        // Real narrow hits stay: RIGHTEOUS cites Rom 8:28 itself.
        XCTAssertTrue(store.topics(bookCode: "ROM", chapter: 8, verse: 28).contains("RIGHTEOUS"))
    }

    /// GERIZIM (a bare "Gen. 22" mention in its article) and TEMPLE, SOLOMON'S (cites Gen 22:1-14) are
    /// off the Genesis 22 verses; the passage's own figures are not: ABRAHAM and ISAAC cite the story
    /// as one long span but are named in the verse text, so they stay direct where the text names them.
    func testGenesis22KeepsItsOwnFiguresAndLosesTheStrays() {
        let store = freshStore()
        for verse in 1...19 {
            let words = store.dictionaryHeadwords(bookCode: "GEN", chapter: 22, verse: verse)
            XCTAssertFalse(words.contains("GERIZIM"), "GERIZIM at Gen 22:\(verse)")
            XCTAssertFalse(words.contains("TEMPLE, SOLOMON\u{2019}S"), "TEMPLE, SOLOMON'S at Gen 22:\(verse)")
        }
        XCTAssertTrue(store.moreDictionaryHeadwords(bookCode: "GEN", chapter: 22, verse: 2).contains("GERIZIM"))
        XCTAssertTrue(store.topics(bookCode: "GEN", chapter: 22, verse: 3).contains("ABRAHAM"))
        XCTAssertTrue(store.topics(bookCode: "GEN", chapter: 22, verse: 3).contains("ISAAC"))
        // Ranking: a topic that cites the verse itself (MORIAH) leads a topic citing the story (FAITH).
        let verseTwo = store.topics(bookCode: "GEN", chapter: 22, verse: 2)
        XCTAssertLessThan(verseTwo.firstIndex(of: "MORIAH") ?? .max, verseTwo.firstIndex(of: "FAITH") ?? .max)
    }

    /// Bounded per verse (12 topics / 8 headwords shown), the two lists never overlap, and nothing that
    /// is capped out disappears: it is in the "more" list.
    func testPerVerseListsAreCappedDisjointAndLoseNothing() {
        let store = freshStore()
        for (code, chapter, verse) in [("JHN", 3, 16), ("ROM", 8, 28), ("GEN", 22, 12), ("PSA", 22, 16), ("PSA", 119, 105), ("MRK", 4, 39), ("ISA", 53, 5)] {
            let topics = store.topics(bookCode: code, chapter: chapter, verse: verse)
            let more = store.moreTopics(bookCode: code, chapter: chapter, verse: verse)
            XCTAssertLessThanOrEqual(topics.count, 12, "\(code) \(chapter):\(verse)")
            XCTAssertTrue(Set(topics).isDisjoint(with: more), "\(code) \(chapter):\(verse) lists overlap")
            XCTAssertEqual(Set(topics).count, topics.count)
            let words = store.dictionaryHeadwords(bookCode: code, chapter: chapter, verse: verse)
            let moreWords = store.moreDictionaryHeadwords(bookCode: code, chapter: chapter, verse: verse)
            XCTAssertLessThanOrEqual(words.count, 8)
            XCTAssertTrue(Set(words).isDisjoint(with: moreWords))
        }
        XCTAssertTrue(store.diagnostics.isEmpty, "\(store.diagnostics)")
    }

    /// Cold-load budget still holds with the extra "more" indexes (they are only read when asked for).
    func testMoreIndexesDoNotSlowTheColdPath() {
        let store = freshStore()
        let start = Date()
        _ = store.topics(bookCode: "ROM", chapter: 8, verse: 28)
        _ = store.moreTopics(bookCode: "ROM", chapter: 8, verse: 28)
        _ = store.dictionaryHeadwords(bookCode: "ROM", chapter: 8, verse: 28)
        _ = store.moreDictionaryHeadwords(bookCode: "ROM", chapter: 8, verse: 28)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
    }

    func testWiderPassagesRowRendersInLightAndDark() throws {
        try withExpandedSections {
            for (dark, finish) in [(false, "light"), (true, "dark")] {
                let state = stateAt("ROM", 8, 28)
                let topics = try render(onDesk(TopicsSection().environmentObject(state)),
                                         dark: dark, size: CGSize(width: 380, height: 520), name: "reference-topics-wider-\(finish)")
                assertNotBlank(topics, "topics-wider-\(finish)")
                let dictionary = try render(onDesk(DictionarySection().environmentObject(state)),
                                             dark: dark, size: CGSize(width: 380, height: 520), name: "reference-dictionary-wider-\(finish)")
                assertNotBlank(dictionary, "dictionary-wider-\(finish)")
            }
        }
    }

    // MARK: Performance budget

    /// Cold load ≤50ms: a fresh store's first lookup for each of the three datasets on one
    /// verse, measured together (each touches only its own small per-book verse-index file,
    /// never a multi-hundred-KB detail shard).
    func testColdLoadIsFast() {
        let start = Date()
        let store = freshStore()
        _ = store.topics(bookCode: "JHN", chapter: 3, verse: 16)
        _ = store.dictionaryHeadwords(bookCode: "JHN", chapter: 3, verse: 16)
        _ = store.names(bookCode: "JHN", chapter: 3, verse: 16)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.05, "cold load took \(elapsed * 1000) ms, budget is 50ms")
    }

    /// Loading a topic's/article's/name's full detail (a shard decode) should also stay fast
    /// even though shards are much larger than the per-book indexes.
    func testDetailShardLoadIsFast() {
        let store = freshStore()
        let start = Date()
        _ = store.topic(named: "LOVE")
        _ = store.article(headword: "CREATION")
        _ = store.name(id: "Paul@Act.7.58-2Pe")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.1, "detail shard load took \(elapsed * 1000) ms")
    }

    // MARK: Coverage / attribution

    func testAttributionMentionsEachSourceByName() {
        let store = freshStore()
        let attribution = store.attribution
        XCTAssertTrue(attribution.nave.localizedCaseInsensitiveContains("Nave"))
        XCTAssertTrue(attribution.easton.localizedCaseInsensitiveContains("Easton"))
        XCTAssertTrue(attribution.tipnr.localizedCaseInsensitiveContains("STEPBible"))
        XCTAssertTrue(attribution.tipnr.localizedCaseInsensitiveContains("CC BY"))
    }

    func testStoreLoadsWithNoDiagnostics() {
        let store = freshStore()
        _ = store.topics(bookCode: "JHN", chapter: 3, verse: 16)
        _ = store.dictionaryHeadwords(bookCode: "GEN", chapter: 1, verse: 1)
        _ = store.names(bookCode: "ACT", chapter: 9, verse: 3)
        _ = store.attribution
        XCTAssertTrue(store.diagnostics.isEmpty, "unexpected diagnostics: \(store.diagnostics)")
    }

    // MARK: Offscreen renders (light + dark) — no computer-use, per project standing decision.

    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Copied verbatim from `SnapshotTests.swift`'s render helper (workstream A/G convention)
    /// so this file's renders use the exact same offscreen technique.
    private func render<V: View>(_ view: V, dark: Bool, size: CGSize, name: String) throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))   // offscreen; never shown to the user
        window.orderBack(nil)
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let directory = outputDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
        return rep
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep, _ label: String) {
        var distinct = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 17) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 17) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    distinct.insert(UInt32(c.redComponent * 63) << 12 | UInt32(c.greenComponent * 63) << 6 | UInt32(c.blueComponent * 63))
                }
            }
        }
        XCTAssertGreaterThan(distinct.count, 4, "\(label) rendered blank")
    }

    private func stateAt(_ code: String, _ chapter: Int, _ verse: Int) -> AppState {
        let state = makeOfflineState()
        state.selectedBookCode = code
        state.selectedChapter = chapter
        state.selectedVerse = verse
        return state
    }

    /// Renders each section on the same `tileWell`-tinted background `SourcesPane` actually
    /// places these sections on (`Panes.swift`), not the bare white host background, so the
    /// PNGs are representative of how K (wave 2) will actually present them. The opaque
    /// `tileTop` base underneath matters: `SourcesPane`'s real tint is a semi-transparent
    /// `tileWell.opacity(0.5)` layered over the desk's own opaque chassis, but this test's
    /// `NSHostingView` has no such backing of its own — without an opaque layer first, the
    /// 0.5-opacity tint blends against the render host's default white canvas instead and
    /// washes out to a flat mid-gray in dark mode, which isn't what the real window shows.
    private func onDesk<V: View>(_ view: V) -> some View {
        ZStack {
            STColor.tileTop
            view.frame(maxWidth: .infinity, alignment: .top).background(STColor.tileWell.opacity(0.5))
        }
    }

    /// The four `@AppStorage` "section expanded" flags these views use (same pattern as
    /// `ProofTextsSection`/`WordStudySection` before them) are real `UserDefaults.standard`
    /// keys, so this test saves and restores them around the one render pass that needs the
    /// expanded look, rather than permanently flipping Matt's real app's remembered desk
    /// state the way the pre-0.6.1 `NotesStore` bug once did to his real notes file.
    private func withExpandedSections(_ body: () throws -> Void) rethrows {
        let keys = ["desk.topicsExpanded", "desk.dictionaryExpanded", "desk.peoplePlacesExpanded", "desk.compareExpanded"]
        let originals = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, original) in zip(keys, originals) {
                if let original { UserDefaults.standard.set(original, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        for key in keys { UserDefaults.standard.set(true, forKey: key) }
        try body()
    }

    func testDeskSectionsRenderInLightAndDark() throws {
        try withExpandedSections {
            for (dark, finish) in [(false, "light"), (true, "dark")] {
                let johnState = stateAt("JHN", 3, 16)
                let actsState = stateAt("ACT", 9, 3)

                let topics = try render(onDesk(TopicsSection().environmentObject(johnState)),
                                         dark: dark, size: CGSize(width: 380, height: 520), name: "reference-topics-\(finish)")
                assertNotBlank(topics, "topics-\(finish)")

                let dictionary = try render(onDesk(DictionarySection().environmentObject(johnState)),
                                             dark: dark, size: CGSize(width: 380, height: 520), name: "reference-dictionary-\(finish)")
                assertNotBlank(dictionary, "dictionary-\(finish)")

                let peoplePlaces = try render(onDesk(PeoplePlacesSection().environmentObject(actsState)),
                                               dark: dark, size: CGSize(width: 380, height: 520), name: "reference-people-places-\(finish)")
                assertNotBlank(peoplePlaces, "people-places-\(finish)")

                let compare = try render(onDesk(CompareSection().environmentObject(johnState)),
                                          dark: dark, size: CGSize(width: 380, height: 520), name: "reference-compare-\(finish)")
                assertNotBlank(compare, "compare-\(finish)")
            }
        }
    }
}
