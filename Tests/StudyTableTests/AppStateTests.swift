import XCTest
import StudyTableCore
@testable import StudyTable

@MainActor
final class AppStateTests: XCTestCase {
    func testRomansLoadsMultipleSyncedResourceBanks() {
        let state = makeOfflineState()
        state.selectedBookCode = "ROM"; state.selectedChapter = 1; state.selectedVerse = 1
        let sources = state.sourcesForPassage()
        XCTAssertGreaterThanOrEqual(sources.count, 3)
        XCTAssertTrue(sources.allSatisfy { $0.passage == "Romans 1:1" })
        XCTAssertTrue(Set(sources.map(\.entry.tradition)).isSuperset(of: TestPaths.isPublicSource ? [.reformed, .crossReferences] : [.fathers, .reformed, .crossReferences]))
    }

    func testEveryReturnedResourceContainsSelectedVerse() {
        let state = makeOfflineState()
        state.selectedBookCode = "ROM"; state.selectedChapter = 8; state.selectedVerse = 28
        let sources = state.sourcesForPassage()
        XCTAssertFalse(sources.isEmpty)
        XCTAssertTrue(sources.allSatisfy { $0.entry.chapter == 8 && $0.entry.covers(verse: 28) })
    }

    func testSourceKeysAreIndependentFilters() {
        let state = makeOfflineState()
        state.selectedBookCode = "ROM"; state.selectedChapter = 1; state.selectedVerse = 1
        // Four independent bank toggles since E2 (0.7 wave 2) added Exegetes; turn off every
        // bank but Reformed to isolate it.
        state.toggleTradition(.fathers); state.toggleTradition(.crossReferences); state.toggleTradition(.exegetes)
        let sources = state.sourcesForPassage()
        XCTAssertFalse(sources.isEmpty)
        XCTAssertTrue(sources.allSatisfy { $0.entry.tradition == .reformed })
    }

    func testUncuratedVersesShowNothingInsteadOfAnotherPassagesCards() {
        let state = makeOfflineState()
        state.selectedBookCode = "JHN"; state.selectedChapter = 1; state.selectedVerse = 1
        let john11 = Set(state.sourcesForPassage().map(\.id))
        state.selectedBookCode = "OBA"; state.selectedChapter = 1; state.selectedVerse = 5
        XCTAssertTrue(state.sourcesForPassage().allSatisfy { !john11.contains($0.id) })
    }

    func testAllSixtySixBooksHaveAWorkingSyncedIndexAndScripture() {
        let state = makeOfflineState()
        XCTAssertEqual(state.library.books.count, 66)
        for book in state.library.books {
            let verses = state.library.chapter(translation: "BSB", bookCode: book.code, chapter: 1)
            XCTAssertFalse(verses?.isEmpty ?? true, "missing Scripture for \(book.name)")
            XCTAssertFalse(state.studyResources.sources(bookCode: book.code, bookName: book.name, chapter: 1, verse: 1).isEmpty,
                           "missing synced index for \(book.name) 1:1")
        }
    }

    func testPassageReflectsBookAndVerseSelection() {
        let state = makeOfflineState()
        state.selectedBookCode = "ROM"; state.selectedChapter = 8; state.selectedVerse = 28
        XCTAssertEqual(state.passage, "Romans 8:28")
        state.selectedBookCode = "JHN"; state.selectedChapter = 1; state.selectedVerse = 1
        XCTAssertEqual(state.passage, "John 1:1")
    }

    func testChangingBookResetsToChapterOneVerseOneAndLoadsThatBook() {
        let state = makeOfflineState()
        state.selectedBookCode = "ROM"; state.selectedChapter = 8; state.selectedVerse = 28
        state.selectedBookCode = "JUD"
        XCTAssertEqual(state.selectedChapter, 1)
        XCTAssertEqual(state.selectedVerse, 1)
        guard case .loaded(let content) = state.chapterLoad else { return XCTFail("expected Jude to load") }
        XCTAssertEqual(content.verses.last?.number, 25)
    }

    func testChapterStepsCrossBookBoundariesInBothDirections() {
        let state = makeOfflineState()
        state.selectedBookCode = "MAL"; state.selectedChapter = 4
        state.stepChapter(1)
        XCTAssertEqual(state.selectedBookCode, "MAT"); XCTAssertEqual(state.selectedChapter, 1)
        state.stepChapter(-1)
        XCTAssertEqual(state.selectedBookCode, "MAL"); XCTAssertEqual(state.selectedChapter, 4)
        state.selectedBookCode = "GEN"; state.selectedChapter = 1
        state.stepChapter(-1)
        XCTAssertEqual(state.selectedBookCode, "GEN", "there is nothing before Genesis 1")
    }

    func testSwitchingTranslationChangesTheTextButKeepsThePassage() {
        let state = makeOfflineState()
        state.selectedBookCode = "JHN"; state.selectedChapter = 3
        guard case .loaded(let bsb) = state.chapterLoad else { return XCTFail() }
        state.translationID = "KJV"
        guard case .loaded(let kjv) = state.chapterLoad else { return XCTFail() }
        XCTAssertEqual(state.passage, "John 3:1")
        XCTAssertNotEqual(bsb.verses.first?.text, kjv.verses.first?.text)
        XCTAssertEqual(kjv.origin, .offline)
    }

    func testOnlineTranslationWithoutAKeyIsUnavailableWithGuidanceNotEmpty() async throws {
        let state = makeOfflineState()
        state.translationID = "ESV"
        try await Task.sleep(nanoseconds: 300_000_000)
        guard case .unavailable(let message) = state.chapterLoad else { return XCTFail("got \(state.chapterLoad)") }
        XCTAssertTrue(message.contains("API key"))
    }

    func testOnlineTranslationLoadsWhenAKeyIsPresentAndTheNetworkAnswers() async throws {
        let network = MockNetwork { _ in (200, Data(#"{"passages":["[1] In the beginning was the Word."]}"#.utf8)) }
        let service = OnlineTranslationService(cache: OnlineChapterCache(directory: temporaryDirectory("st")), transport: network.transport,
                                               idStore: BibleIDStore(defaultsKey: "t.\(UUID())"), keyReader: { _ in "k" })
        let state = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), online: service, defaults: ephemeralDefaults(), notes: ephemeralNotes())
        state.translationID = "ESV"
        try await Task.sleep(nanoseconds: 400_000_000)
        guard case .loaded(let content) = state.chapterLoad else { return XCTFail("got \(state.chapterLoad)") }
        XCTAssertEqual(content.origin, .onlineLive)
        XCTAssertTrue(content.attribution.contains("Crossway"))
    }

    func testLicensePackOnlyTranslationExplainsHowToInstallIt() {
        let state = makeOfflineState()
        state.translationID = "NASB"
        guard case .unavailable(let message) = state.chapterLoad else { return XCTFail() }
        XCTAssertTrue(message.contains("licensed offline pack"))
    }

    func testAStaleOnlineResponseNeverOverwritesALaterSelection() async throws {
        let slow = MockNetwork { _ in Thread.sleep(forTimeInterval: 0.3); return (200, Data(#"{"passages":["[1] slow ESV text"]}"#.utf8)) }
        let service = OnlineTranslationService(cache: OnlineChapterCache(directory: temporaryDirectory("st")), transport: slow.transport,
                                               idStore: BibleIDStore(defaultsKey: "t.\(UUID())"), keyReader: { _ in "k" })
        let state = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), online: service, defaults: ephemeralDefaults(), notes: ephemeralNotes())
        state.translationID = "ESV"
        state.translationID = "BSB"
        try await Task.sleep(nanoseconds: 700_000_000)
        guard case .loaded(let content) = state.chapterLoad else { return XCTFail() }
        XCTAssertEqual(content.origin, .offline)
        XCTAssertNotEqual(content.verses.first?.text, "slow ESV text")
    }
}

/// Measured budgets. Startup used to spend ~2.3 s parsing 66 USFM books on the main thread.
@MainActor
final class PerformanceTests: XCTestCase {
    private func milliseconds(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    func testStartupReadsOnlyManifestsAndIsFast() {
        var library: ScriptureLibrary!
        let startup = milliseconds { library = ScriptureLibrary() }
        var firstChapter: [BibleVerse]?
        let firstPaint = milliseconds { firstChapter = library.chapter(translation: "BSB", bookCode: "JHN", chapter: 1) }
        FileHandle.standardError.write(Data("PERF library_init_ms=\(String(format: "%.1f", startup)) first_chapter_ms=\(String(format: "%.1f", firstPaint))\n".utf8))
        XCTAssertNotNil(firstChapter)
        XCTAssertLessThan(startup, 250, "was ~2300 ms with startup USFM parsing")
        XCTAssertLessThan(firstPaint, 250)
    }

    func testBookSwitchLoadsScriptureAndStudyIndexQuickly() {
        let library = ScriptureLibrary()
        let study = StudyResourceStore()
        var worst = 0.0
        for code in ["PSA", "ISA", "JER", "GEN", "ROM"] {
            let ms = milliseconds {
                _ = library.chapter(translation: "BSB", bookCode: code, chapter: 1)
                _ = study.sources(bookCode: code, bookName: code, chapter: 1, verse: 1)
            }
            worst = max(worst, ms)
            FileHandle.standardError.write(Data("PERF book_switch \(code) cold_ms=\(String(format: "%.1f", ms))\n".utf8))
        }
        XCTAssertLessThan(worst, 1500)
    }
}

@MainActor
final class PreferencesIsolationTests: XCTestCase {
    func testRememberedTranslationRestoresAndNeverLeaksIntoOtherStores() {
        let defaults = ephemeralDefaults()
        let first = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), defaults: defaults, notes: ephemeralNotes())
        first.translationID = "KJV"
        let second = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), defaults: defaults, notes: ephemeralNotes())
        XCTAssertEqual(second.translationID, "KJV")
        let unrelated = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), defaults: ephemeralDefaults(), notes: ephemeralNotes())
        XCTAssertEqual(unrelated.translationID, "BSB")
    }

    func testAnUnknownRememberedTranslationFallsBackToTheBundledBSB() {
        let defaults = ephemeralDefaults()
        defaults.set("NIV2099", forKey: "translation")
        let state = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), defaults: defaults, notes: ephemeralNotes())
        XCTAssertEqual(state.translationID, "BSB")
    }
}

@MainActor
final class ResourceLayoutTests: XCTestCase {
    func testResolverFindsFlatAndNestedBundleLayouts() throws {
        for nested in [false, true] {
            let resources = temporaryDirectory("res")
            let bundle = resources.appendingPathComponent("StudyTable_StudyTable.bundle")
            let content = nested ? bundle.appendingPathComponent("Contents/Resources") : bundle
            try FileManager.default.createDirectory(at: content.appendingPathComponent("Scripture/BSB"), withIntermediateDirectories: true)
            XCTAssertEqual(AppResources.resolveRoot(mainResourceURL: resources)?.standardizedFileURL.path, content.standardizedFileURL.path)
        }
        XCTAssertNil(AppResources.resolveRoot(mainResourceURL: temporaryDirectory("empty")))
    }

    /// Run after packaging: STUDYTABLE_PACKAGED_APP="/path/Study Table.app" swift test --filter ResourceLayoutTests
    func testPackagedAppContainsEverythingTheAppLoadsAndNothingItMustNot() throws {
        guard let path = ProcessInfo.processInfo.environment["STUDYTABLE_PACKAGED_APP"] else { throw XCTSkip("no packaged app supplied") }
        let resources = URL(fileURLWithPath: path).appendingPathComponent("Contents/Resources")
        let root = try XCTUnwrap(AppResources.resolveRoot(mainResourceURL: resources), "packaged resource bundle not found")
        for id in ["BSB", "KJV", "WEB"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Scripture/\(id)/manifest.json").path), id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Scripture/\(id)/JHN.json").path), id)
        }
        for name in ["sources.json", "ROM/8.json", "OBA/1.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Study/\(name)").path), name)
        }
        for name in ["wcf-chapters.json", "wcf-links.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Confession/\(name)").path), name)
        }
        // The same libraries the app builds must load from the packaged copy.
        let library = ScriptureLibrary(bundledRoot: root.appendingPathComponent("Scripture"), userRoot: temporaryDirectory("none"))
        XCTAssertEqual(library.translations.filter { $0.delivery == .bundled }.map(\.id), ["BSB", "KJV", "WEB"])
        let study = StudyResourceStore(confession: ConfessionStore(chaptersURL: root.appendingPathComponent("Confession/wcf-chapters.json"),
                                                                     bundledLinksURL: root.appendingPathComponent("Confession/wcf-links.json"), localLinksURL: nil),
                                       studyDirectory: root.appendingPathComponent("Study"))
        XCTAssertFalse(study.sources(bookCode: "ROM", bookName: "Romans", chapter: 8, verse: 28).isEmpty)
        let originals = InterlinearStore(directory: root.appendingPathComponent("Interlinear"))
        XCTAssertFalse(originals.words(bookCode: "JHN", chapter: 3, verse: 16).isEmpty)
        let references = ReferenceStore(directory: root.appendingPathComponent("Reference"))
        XCTAssertFalse(references.topics(bookCode: "JHN", chapter: 3, verse: 16).isEmpty)
        for name in ["Materials/lectern-micrograin.png", "Study/fathers-profiles.json", "Licenses/offline-downloads.txt",
                     "Lexicon/strongs-greek.json", "Confession/standards/proof-index.json"] {
            if TestPaths.isPublicSource && name.hasPrefix("Materials/") { continue }
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path), name)
        }
        let forbidden = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.lastPathComponent.lowercased() }
            .filter { $0.hasSuffix(".usfm") || $0.hasSuffix(".sqlite") || $0.contains("esv") || $0.contains("nkjv") || $0.contains("nasb") } ?? []
        XCTAssertEqual(forbidden, [])
    }
}

@MainActor
final class NavigationTests: XCTestCase {
    func testCrossBookNavigateFetchesOnlineTranslationExactlyOnce() async throws {
        let network = MockNetwork { _ in (200, Data(#"{"passages":["[1] text"]}"#.utf8)) }
        let service = OnlineTranslationService(cache: OnlineChapterCache(directory: temporaryDirectory("nav")), transport: network.transport,
                                               idStore: BibleIDStore(defaultsKey: "t.\(UUID())"), keyReader: { _ in "k" })
        let state = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), online: service, defaults: ephemeralDefaults(), notes: ephemeralNotes())
        state.translationID = "ESV"
        try await Task.sleep(nanoseconds: 300_000_000)
        let before = network.requests.count
        // A cross-reference jump: different book AND different chapter in one call.
        state.navigate(bookCode: "PSA", chapter: 23, verse: 1)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(network.requests.count, before + 1, "one navigate() call must fetch exactly once, not once per property it changes")
        XCTAssertEqual(state.selectedBookCode, "PSA")
        XCTAssertEqual(state.selectedChapter, 23)
        XCTAssertEqual(state.selectedVerse, 1)
    }

    func testStepChapterAcrossABookBoundaryFetchesOnlineTranslationExactlyOnce() async throws {
        let network = MockNetwork { _ in (200, Data(#"{"passages":["[1] text"]}"#.utf8)) }
        let service = OnlineTranslationService(cache: OnlineChapterCache(directory: temporaryDirectory("nav2")), transport: network.transport,
                                               idStore: BibleIDStore(defaultsKey: "t.\(UUID())"), keyReader: { _ in "k" })
        let state = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), online: service, defaults: ephemeralDefaults(), notes: ephemeralNotes())
        state.translationID = "ESV"
        state.selectedBookCode = "MAL"
        state.selectedChapter = 4   // Malachi's last chapter, so the next step crosses into Matthew.
        try await Task.sleep(nanoseconds: 300_000_000)
        let before = network.requests.count
        state.stepChapter(1)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(network.requests.count, before + 1)
        XCTAssertEqual(state.selectedBookCode, "MAT")
    }

    func testNavigateToStoredPassageParsesBookChapterAndVerse() {
        let state = makeOfflineState()
        state.navigate(toStoredPassage: "Romans 8:28")
        XCTAssertEqual(state.selectedBookCode, "ROM"); XCTAssertEqual(state.selectedChapter, 8); XCTAssertEqual(state.selectedVerse, 28)
        // The BSB's own \toc1 title for Song of Solomon is the short form "Song" — the parser
        // must match on the book's *real* name, not an assumed canonical title.
        state.navigate(toStoredPassage: "Song 2:1")
        XCTAssertEqual(state.selectedBookCode, "SNG"); XCTAssertEqual(state.selectedChapter, 2); XCTAssertEqual(state.selectedVerse, 1)
        state.navigate(toStoredPassage: "1 Corinthians 13:4")
        XCTAssertEqual(state.selectedBookCode, "1CO"); XCTAssertEqual(state.selectedChapter, 13); XCTAssertEqual(state.selectedVerse, 4)
    }

    func testNavigateToStoredPassageWithoutAVerseDefaultsToVerseOne() {
        let state = makeOfflineState()
        state.navigate(toStoredPassage: "Jude 1")
        XCTAssertEqual(state.selectedBookCode, "JUD"); XCTAssertEqual(state.selectedChapter, 1); XCTAssertEqual(state.selectedVerse, 1)
    }

    func testNavigateToAnUnrecognizedStoredPassageDoesNothing() {
        let state = makeOfflineState()
        state.selectedBookCode = "ROM"; state.selectedChapter = 8; state.selectedVerse = 28
        state.navigate(toStoredPassage: "Not A Real Book 1:1")
        XCTAssertEqual(state.selectedBookCode, "ROM"); XCTAssertEqual(state.selectedChapter, 8); XCTAssertEqual(state.selectedVerse, 28)
    }

    func testCrossReferenceChipNavigatesToTheReferencedPassage() {
        let state = makeOfflineState()
        state.selectedBookCode = "GEN"; state.selectedChapter = 1; state.selectedVerse = 1
        let xref = state.sourcesForPassage().first { $0.entry.tradition == .crossReferences }
        guard let ref = xref?.entry.crossRefs.first else { return XCTFail("expected a parsed cross-reference on Genesis 1:1") }
        state.navigate(bookCode: ref.code, chapter: ref.chapter, verse: ref.start)
        XCTAssertEqual(state.selectedBookCode, ref.code)
        XCTAssertEqual(state.selectedChapter, ref.chapter)
        XCTAssertEqual(state.selectedVerse, ref.start)
    }
}

@MainActor
final class ConfessionalTierTests: XCTestCase {
    func testTier3ResearchSourcesAreExcludedByDefault() throws {
        try XCTSkipIf(TestPaths.isPublicSource, "This corpus visibility audit requires withheld HCF excerpts; profile and alignment logic remain tested.")
        let state = makeOfflineState()
        XCTAssertFalse(state.showResearchTier, "research tier must default to off")
        // Find a passage where a Tier 3 author (Origen, Tertullian, ...) has material.
        guard let tier3Entry = Corpus.all.first(where: { $0.tier == .tier3ResearchOnly }) else {
            return XCTFail("expected at least one Tier 3 entry in the corpus")
        }
        let code = String(tier3Entry.id.prefix(while: { $0 != "." }))
        state.selectedBookCode = code
        state.selectedChapter = tier3Entry.chapter
        state.selectedVerse = tier3Entry.startVerse
        XCTAssertFalse(state.sourcesForPassage().contains { $0.id == tier3Entry.id }, "Tier 3 source leaked in without opt-in")

        state.showResearchTier = true
        XCTAssertTrue(state.sourcesForPassage().contains { $0.id == tier3Entry.id }, "Tier 3 source should appear once opted in")
    }

    func testTier3NeverBleedsIntoTheDefaultCoverageMap() throws {
        try XCTSkipIf(TestPaths.isPublicSource, "This corpus visibility audit requires withheld HCF excerpts; profile and alignment logic remain tested.")
        // The chapter-map coverage (LCD) is unfiltered by tier today — confirm this deliberately:
        // it's a map of "anything in the index," not "anything currently visible," so this test
        // documents the boundary rather than asserting a stricter behavior that would need a
        // second, tier-aware coverage call.
        let store = StudyResourceStore()
        guard let tier3Entry = Corpus.all.first(where: { $0.tier == .tier3ResearchOnly }) else {
            return XCTFail("expected at least one Tier 3 entry in the corpus")
        }
        let code = String(tier3Entry.id.prefix(while: { $0 != "." }))
        let coverage = store.coverage(bookCode: code, chapter: tier3Entry.chapter)
        XCTAssertTrue(coverage[.fathers]?.contains(tier3Entry.startVerse) ?? false)
    }
}

@MainActor
final class NotesStoreIsolationTests: XCTestCase {
    /// A QA pass (2026-09-21) found that every `swift test` run was silently writing fake notes
    /// into the developer's real ~/Library/Application Support/StudyTable/notes.json, because
    /// NotesStore had no injectable storage path. This locks in the fix.
    func testNotesStoreWritesOnlyToItsInjectedDirectoryNeverTheRealOne() {
        let realFile = AppResources.supportDirectory.appendingPathComponent("notes.json")
        let before = try? Data(contentsOf: realFile)

        let scratch = temporaryDirectory("isolation")
        let store = NotesStore(directory: scratch)
        store.update(passage: "Test 1:1", title: "Should not leak", body: "into the real notes file")

        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("study.json").path),
                      "the injected directory should receive the write")
        let after = try? Data(contentsOf: realFile)
        XCTAssertEqual(before, after, "the real notes file must be untouched by a test-scoped NotesStore")
    }

    func testMakeOfflineStateNeverTouchesTheRealNotesFile() {
        let realFile = AppResources.supportDirectory.appendingPathComponent("notes.json")
        let before = try? Data(contentsOf: realFile)
        let state = makeOfflineState()
        state.notes.update(passage: "Test 2:2", title: "leak check", body: "body")
        let after = try? Data(contentsOf: realFile)
        XCTAssertEqual(before, after, "makeOfflineState() must never write to the real notes file")
    }
}
