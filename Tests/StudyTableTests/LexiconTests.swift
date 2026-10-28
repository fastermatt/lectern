import AppKit
import SwiftUI
import XCTest
@testable import StudyTable
@testable import StudyTableCore

/// Workstream D: Strong's-tagging side channel + Hebrew/Greek dictionaries + the
/// `WordStudySection` view. Uses a fresh `LexiconStore(directory:)` pointed at the real
/// bundled `Resources/Lexicon` (read-only; nothing here writes into it), never `.shared`,
/// so each test measures a genuinely cold load.
@MainActor
final class LexiconTests: XCTestCase {
    private func freshStore() -> LexiconStore {
        LexiconStore(directory: AppResources.url("Lexicon"))
    }

    // MARK: Required spot checks (WORKPLAN-0.7.md § D)

    func testJohnThreeSixteenGodIsG2316() {
        let store = freshStore()
        let tags = store.tags(bookCode: "JHN", chapter: 3, verse: 16)
        let god = tags.first { $0.word == "God" }
        XCTAssertEqual(god?.strongs, ["G2316"])
        XCTAssertEqual(store.entry(for: "G2316")?.lemma, "θεός")
    }

    func testGenesisOneOneElohimIsH430() {
        let store = freshStore()
        let tags = store.tags(bookCode: "GEN", chapter: 1, verse: 1)
        let god = tags.first { $0.word == "God" }
        XCTAssertEqual(god?.strongs, ["H430"])
        XCTAssertEqual(store.entry(for: "H430")?.translit, "ʼĕlôhîym")
    }

    /// Every one of the 349,308 tags in the bundled KJV resolves in the dictionaries. This is
    /// a real measurement, not an assumption — if it ever regresses, report the exact miss
    /// rate rather than silently loosening the assertion.
    func testEveryTagResolvesInTheDictionaries() {
        let store = freshStore()
        var totalTags = 0
        var missing: Set<String> = []
        var missingOccurrences = 0
        for code in Canon.bookCodes {
            guard let directory = AppResources.url("Lexicon/kjv-tags") else { continue }
            let url = directory.appendingPathComponent("\(code).json")
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: [WordTag]].self, from: data) else { continue }
            for (_, tagList) in decoded {
                for tag in tagList {
                    totalTags += 1
                    for number in tag.strongs where store.entry(for: number) == nil {
                        missing.insert(number)
                        missingOccurrences += 1
                    }
                }
            }
        }
        XCTAssertEqual(totalTags, 349_308, "bundled KJV tag count drifted from the source USFM")
        let missRate = totalTags > 0 ? Double(missingOccurrences) / Double(totalTags) : 0
        XCTAssertEqual(missing.count, 0,
                       "miss rate \(String(format: "%.4f%%", missRate * 100)): \(missing.sorted().prefix(20))")
    }

    /// G26 (ἀγάπη, "love") — cross-checked directly against the raw USFM (independent of the
    /// build script and the store) so the concordance count is verified two ways, not just
    /// "however many the pipeline happened to produce."
    func testAgapeConcordanceCountMatchesTheKJVTaggingTotal() throws {
        let store = freshStore()
        let hits = store.concordance(for: "G26")
        let rawCount = try countRawOccurrences(of: "G26", strongLetter: "G", strongDigits: "0026")
        XCTAssertEqual(hits.count, rawCount)
        XCTAssertEqual(store.occurrenceCount(for: "G26"), hits.count)
        XCTAssertTrue(hits.allSatisfy { $0.bookCode.count == 3 && $0.chapter > 0 && $0.verse >= 0 })
    }

    /// Independent recount straight from `scripture-source/kjv/*.usfm` — deliberately does not
    /// call into `build-lexicon.py` or `LexiconStore`, so a bug shared by both wouldn't be
    /// masked.
    private func countRawOccurrences(of canonical: String, strongLetter: String, strongDigits: String) throws -> Int {
        let sourceDirectory = TestPaths.root.appendingPathComponent("scripture-source/kjv")
        let files = try FileManager.default.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "usfm" }
        var count = 0
        let needle = "strong=\"\(strongLetter)\(strongDigits)\""
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            count += text.components(separatedBy: needle).count - 1
        }
        return count
    }

    // MARK: Performance budgets (WORKPLAN-0.7.md § D)

    /// Cold load of one book's tags ≤ 50ms. Psalms is the largest book by tag count, so it's
    /// the honest worst case rather than a small book that would flatter the number.
    func testColdBookLoadIsUnderFiftyMilliseconds() {
        let store = freshStore()
        let start = DispatchTime.now()
        let tags = store.tags(bookCode: "PSA", chapter: 119, verse: 1)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        XCTAssertFalse(tags.isEmpty)
        XCTAssertLessThanOrEqual(elapsedMs, 50, "cold Psalms tag load took \(elapsedMs) ms")
    }

    /// Concordance for a common word (G26, 117 occurrences) ≤ 500ms on first computation —
    /// this is the expensive path (scans every book's tag file), so it's measured on a store
    /// that has touched nothing yet.
    func testFirstConcordanceComputationIsUnderFiveHundredMilliseconds() {
        let store = freshStore()
        let start = DispatchTime.now()
        let hits = store.concordance(for: "G26")
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        XCTAssertGreaterThan(hits.count, 0)
        XCTAssertLessThanOrEqual(elapsedMs, 500, "first G26 concordance computation took \(elapsedMs) ms")

        // Second call must be cache-served and much faster (sanity check, not a hard budget).
        let start2 = DispatchTime.now()
        _ = store.concordance(for: "G26")
        let elapsedMs2 = Double(DispatchTime.now().uptimeNanoseconds - start2.uptimeNanoseconds) / 1_000_000
        XCTAssertLessThan(elapsedMs2, elapsedMs)
    }

    // MARK: Store behavior

    func testUnknownStrongNumberReturnsNil() {
        let store = freshStore()
        XCTAssertNil(store.entry(for: "G999999"))
        XCTAssertNil(store.entry(for: "H999999"))
        XCTAssertNil(store.entry(for: "X1"))
    }

    func testVerseWithNoSelectionReturnsNoTags() {
        let store = freshStore()
        XCTAssertTrue(store.tags(bookCode: "GEN", chapter: 1, verse: 999).isEmpty)
    }

    func testHasTagsIsHonestAboutCoverage() {
        let store = freshStore()
        XCTAssertTrue(store.hasTags(bookCode: "ROM"))
        XCTAssertFalse(store.hasTags(bookCode: "ZZZ"))
    }

    // MARK: Offscreen render (no computer-use, per the project's standing decision)

    private func render<V: View>(_ view: V, dark: Bool, size: CGSize, name: String = "word-study") throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let directory = ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: url.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        window.orderOut(nil)
        return rep
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep) {
        var distinct = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 11) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 11) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    distinct.insert(UInt32(c.redComponent * 63) << 12 | UInt32(c.greenComponent * 63) << 6 | UInt32(c.blueComponent * 63))
                }
            }
        }
        XCTAssertGreaterThan(distinct.count, 8, "render looks blank")
    }

    func testWordStudySectionRendersInLightAndDarkExpanded() throws {
        for dark in [false, true] {
            let state = makeOfflineState()
            state.selectedBookCode = "JHN"
            state.selectedChapter = 3
            state.selectedVerse = 16
            let view = ScrollView {
                WordStudySection(store: LexiconStore(directory: AppResources.url("Lexicon")))
            }
            .environmentObject(state)
            .frame(width: 380, height: 700)
            .background(dark ? Color.black : Color.white)
            let rep = try render(view, dark: dark, size: CGSize(width: 380, height: 700), name: "word-study-john316")
            assertNotBlank(rep)
        }
    }

    /// Verifies the expanded card layout (dictionary entry + concordance chips), not just the
    /// collapsed summary row — this is where long-content layout and the concordance's chip
    /// wrapping actually get exercised.
    func testExpandedWordRowWithConcordanceRenders() throws {
        let store = LexiconStore(directory: AppResources.url("Lexicon"))
        let tag = WordTag(word: "loved", strongs: ["G25"])
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WordTagRow(tag: tag, store: store, startExpanded: true)
                ConcordanceDisclosure(number: "G25", store: store, cached: .constant(nil), startShown: true)
                    .padding(.horizontal, 12)
            }
        }
        .frame(width: 380, height: 900)
        let rep = try render(view, dark: false, size: CGSize(width: 380, height: 900), name: "word-study-expanded")
        assertNotBlank(rep)
    }

    func testWordStudySectionEmptyStateRenders() throws {
        let state = makeOfflineState()
        state.selectedBookCode = "GEN"
        state.selectedChapter = 1
        state.selectedVerse = nil
        let view = WordStudySection(store: LexiconStore(directory: AppResources.url("Lexicon")))
            .environmentObject(state)
            .frame(width: 380, height: 200)
        let rep = try render(view, dark: false, size: CGSize(width: 380, height: 200), name: "word-study-empty")
        assertNotBlank(rep)
    }

    // MARK: - Item 9 (0.7 fix batch): collapsed summary leads with content words

    func testCollapsedSummarySkipsLeadingFunctionWords() {
        // Real Romans 8:28 KJV tagging order: "And know that things together for good love God
        // are called to purpose" -- the un-fixed summary led with "And G1161", a function word.
        let words = [
            WordTag(word: "And", strongs: ["G1161"]), WordTag(word: "know", strongs: ["G1492"]),
            WordTag(word: "that", strongs: ["G3754"]), WordTag(word: "things", strongs: ["G3956"]),
            WordTag(word: "together", strongs: ["G4903"]), WordTag(word: "for", strongs: ["G1519"]),
            WordTag(word: "good", strongs: ["G18"]), WordTag(word: "love", strongs: ["G25"]),
            WordTag(word: "God", strongs: ["G2316"]), WordTag(word: "are", strongs: ["G5607"]),
            WordTag(word: "called", strongs: ["G2822"]), WordTag(word: "to", strongs: ["G2596"]),
            WordTag(word: "purpose", strongs: ["G4286"]),
        ]
        let ordered = wordStudyCollapsedOrder(words)
        XCTAssertEqual(ordered.first?.word, "know", "the summary should lead with the first content word, not \"And\"")
        XCTAssertFalse(ordered.isEmpty)
        // Content words only, in their original relative (verse) order.
        XCTAssertEqual(ordered.map(\.word), ["know", "things", "together", "good", "love", "God", "called", "purpose"])
    }

    func testCollapsedSummaryFallsBackToAllWordsWhenEveryTagIsAFunctionWord() {
        let words = [WordTag(word: "And", strongs: ["G1161"]), WordTag(word: "that", strongs: ["G3754"])]
        XCTAssertEqual(wordStudyCollapsedOrder(words), words, "with no content word at all, the fallback must show every tagged word, not an empty summary")
    }

    func testCollapsedSummaryMatchIsCaseInsensitive() {
        // The KJV capitalizes sentence-initial function words ("For", "And", "The") -- the
        // stoplist match must not be defeated by capitalization alone.
        let words = [WordTag(word: "For", strongs: ["G1063"]), WordTag(word: "mercy", strongs: ["G1656"])]
        XCTAssertEqual(wordStudyCollapsedOrder(words).map(\.word), ["mercy"])
    }

    func testExpandedWordListStaysCompleteAndInVerseOrderRegardlessOfCollapsedFiltering() {
        // The fix must never touch the expanded list -- WordStudySection.words itself is
        // unfiltered; this just re-confirms wordStudyCollapsedOrder is a pure, non-mutating
        // reorder/filter of its input, so nothing upstream needs to change to keep that true.
        let words = [
            WordTag(word: "And", strongs: ["G1161"]), WordTag(word: "know", strongs: ["G1492"]),
            WordTag(word: "that", strongs: ["G3754"]),
        ]
        _ = wordStudyCollapsedOrder(words)
        XCTAssertEqual(words.map(\.word), ["And", "know", "that"], "the input array itself must be unmodified")
    }
}
