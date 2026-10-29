import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

/// Renders the real interface offscreen (no screen access needed) so both finishes can be
/// inspected. Set STUDYTABLE_SNAPSHOT_DIR to write PNGs; otherwise these tests only assert
/// that rendering produces a non-blank image.
@MainActor
final class SnapshotTests: XCTestCase {
    func testGuidedStudyInBothAppearances() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("PHP", 4, 4)
            state.preferenceStore.set(true, forKey: "learning.showEmphasis")
            for step in GuidedStudyStep.allCases {
                let view = ScrollView {
                    GuidedStudyView(study: state.study, initialStep: step, initialWordIndex: 0)
                }.environmentObject(state).defaultAppStorage(state.preferenceStore).background(STColor.paper)
                let rep = try render(view, dark: dark, size: CGSize(width: 330, height: 850),
                                     name: "guided-\(step.title.lowercased())-\(name)")
                assertNotBlank(rep, "guided \(step) \(name)")
            }
        }
    }

    func testLocalModelChooserBothAppearances() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let manager = LocalAIManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            let rep = try render(LocalAISetupView(manager: manager), dark: dark, size: CGSize(width: 620, height: 690), name: "local-models-" + name)
            assertNotBlank(rep, name)
        }
    }
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

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
        defer { window.contentView = nil; window.orderOut(nil) }
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        let rep = try snapshotBitmap(of: host)
        if let directory = outputDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        }
        return rep
    }

    private func stateAt(_ code: String, _ chapter: Int, _ verse: Int, translation: String = "BSB") -> AppState {
        let state = makeOfflineState()
        state.translationID = translation
        state.selectedBookCode = code
        state.selectedChapter = chapter
        state.selectedVerse = verse
        return state
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
        XCTAssertGreaterThan(distinct.count, 12, "\(label) rendered blank")
    }

    func testWorkspaceLibraryAndLayouts() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("ROM", 8, 28)
            let books = ResourceBookLibrary(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            let resources = try render(ResourceLibraryView(books: books, adding: true).environmentObject(state), dark: dark,
                size: CGSize(width: 980, height: 740), name: "library-add-\(name)")
            assertNotBlank(resources, name)
            state.layouts.save("Sunday passage study", recipe: state.workspaceRecipe())
            let layout = try render(LayoutsPanel(library: state.layouts).environmentObject(state), dark: dark,
                size: CGSize(width: 540, height: 580), name: "layouts-\(name)")
            assertNotBlank(layout, name)
            let search = try render(SearchWorkspace(session: BibleSearchSession()).environmentObject(state).background(STColor.paper), dark: dark,
                size: CGSize(width: 790, height: 690), name: "search-workspace-\(name)")
            assertNotBlank(search, name)
        }
    }

    func testStudyLayoutRendersInLightAndDark() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("ROM", 8, 28)
            let rep = try render(MainView().environmentObject(state), dark: dark, size: CGSize(width: 1143, height: 797), name: "study-romans-\(name)")
            assertNotBlank(rep, name)
        }
    }

    func testMinimumWindowSizeRenders() throws {
        let state = stateAt("PSA", 23, 1)
        let rep = try render(MainView().environmentObject(state), dark: false, size: CGSize(width: 980, height: 650), name: "min-psalm-light")
        assertNotBlank(rep, "minimum size")
    }

    func testOwnAIPanelInBothFinishes() async throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("ROM", 8, 28)
            let session = AIChatSession()
            let empty = try render(AIAssistantView(session: session).environmentObject(state), dark: dark,
                                   size: CGSize(width: 700, height: 600), name: "own-ai-setup-\(name)")
            assertNotBlank(empty, "AI setup \(name)")
            session.connection.model = "example-local-model"
            session.draft = "How does Romans 8:28 relate to the surrounding passage?"
            let body = Data(#"{"choices":[{"message":{"content":"Read Romans 8:28 alongside verses 29–30. The surrounding passage connects this assurance to God’s purpose. This is an example AI response for a UI fixture, not a sourced commentary quotation."},"finish_reason":"stop"}]}"#.utf8)
            let mock = MockNetwork { _ in (200, body) }
            session.send(key: "", client: AIChatClient(transport: mock.transport))
            for _ in 0..<100 where session.isSending { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(session.messages.count, 2)
            let filled = try render(AIAssistantView(session: session).environmentObject(state), dark: dark,
                                    size: CGSize(width: 760, height: 740), name: "own-ai-chat-\(name)")
            assertNotBlank(filled, "AI chat \(name)")
        }
    }

    func testReworkSearchAndResourceCenterInBothFinishes() throws {
        let original = SettingsOpener.shared.destination
        defer { SettingsOpener.shared.destination = original }
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("ROM", 8, 28)
            let session = BibleSearchSession(query: "faith OR hope", translationID: "BSB")
            let search = try render(BibleSearchView(session: session).environmentObject(state),
                                    dark: dark, size: CGSize(width: 760, height: 620),
                                    name: "rework-search-\(name)")
            assertNotBlank(search, "Search \(name)")
            SettingsOpener.shared.destination = .resources
            let resources = try render(SettingsView().environmentObject(state), dark: dark,
                                       size: CGSize(width: 620, height: 660),
                                       name: "rework-resources-\(name)")
            assertNotBlank(resources, "Resources \(name)")
        }
    }

    /// Optional release acceptance against the actual staged app, with no user packs/keys/notes.
    func testPackagedReworkWithFreshOfflineProfile() async throws {
        guard let path = ProcessInfo.processInfo.environment["LECTERN_CANDIDATE_APP"] else {
            throw XCTSkip("Set LECTERN_CANDIDATE_APP to verify an actual packaged candidate")
        }
        let app = URL(fileURLWithPath: path)
        let root = try XCTUnwrap(AppResources.resolveRoot(mainResourceURL: app.appendingPathComponent("Contents/Resources")))
        let confession = ConfessionStore(chaptersURL: root.appendingPathComponent("Confession/wcf-chapters.json"),
            bundledLinksURL: root.appendingPathComponent("Confession/wcf-links.json"), localLinksURL: nil,
            creedsURL: root.appendingPathComponent("Confession/creeds.json"))
        let resources = StudyResourceStore(confession: confession, studyDirectory: root.appendingPathComponent("Study"))
        XCTAssertNil(resources.registry["hcf"])
        let library = ScriptureLibrary(bundledRoot: root.appendingPathComponent("Scripture"), userRoot: temporaryDirectory("empty-packs"))
        let online = OnlineTranslationService(cache: OnlineChapterCache(directory: temporaryDirectory("empty-cache")),
            transport: { _ in XCTFail("Core study attempted network access"); throw URLError(.notConnectedToInternet) },
            idStore: BibleIDStore(defaultsKey: "test.ids.\(UUID().uuidString)"), keyReader: { _ in nil })
        let state = AppState(library: library, studyResources: resources, online: online,
                             defaults: ephemeralDefaults(), notes: ephemeralNotes())
        state.hasSeenIntro = true
        state.applyPreset(.study)
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.rangeEndVerse = 39
        let search = try await BibleSearchEngine().search(source: library.searchSource(translationID: "BSB"), query: "faith OR hope")
        XCTAssertEqual(search.total, 388)
        let guide = PassageGuideService(library: library, resources: resources,
            references: ReferenceStore(directory: root.appendingPathComponent("Reference")), study: state.study)
        let result = try guide.build(anchor: XCTUnwrap(Anchor.parse("Rom 8:28–39")),
                                    traditions: Set(SourceTradition.allCases), includeResearch: false)
        XCTAssertEqual(result.verses.count, 12)
        XCTAssertFalse(result.sources.isEmpty)
        XCTAssertFalse(result.sources.contains { $0.resolved.entry.source == "hcf" })
        XCTAssertFalse(result.crossReferences.isEmpty)
        XCTAssertTrue(resources.diagnostics.isEmpty)
        let original = SettingsOpener.shared.destination
        defer { SettingsOpener.shared.destination = original }
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let desk = try render(MainView().environmentObject(state), dark: dark,
                                 size: CGSize(width: 1143, height: 797), name: "candidate-study-\(name)")
            assertNotBlank(desk, "Candidate \(name)")
            SettingsOpener.shared.destination = .resources
            let resourceView = try render(SettingsView().environmentObject(state), dark: dark,
                size: CGSize(width: 620, height: 660), name: "candidate-resources-\(name)")
            assertNotBlank(resourceView, "Candidate resources \(name)")
        }
    }

    func testStudyPaneCanExpandBeyondFormerWidthCap() throws {
        let state = stateAt("ROM", 8, 28)
        let host = NSHostingView(rootView: MainView().environmentObject(state)
            .frame(width: 1600, height: 900))
        host.frame = NSRect(x: 0, y: 0, width: 1600, height: 900)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        defer { window.orderOut(nil) }
        func splits(in view: NSView) -> [NSSplitView] {
            ((view as? NSSplitView).map { [$0] } ?? [])
                + view.subviews.flatMap { splits(in: $0) }
        }
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        }
        // The smaller of the two vertical splits owns Scripture | Study Desk.
        let split = try XCTUnwrap(splits(in: host)
            .filter { $0.isVertical && $0.arrangedSubviews.count == 2 && $0.bounds.width > 1000 }
            .min { $0.bounds.width < $1.bounds.width })
        let savedName = split.autosaveName
        split.autosaveName = nil // Do not save a test divider position to the user's workspace.
        defer { split.autosaveName = savedName }
        split.setPosition(410, ofDividerAt: 0)
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        }
        XCTAssertGreaterThan(split.arrangedSubviews[1].frame.width, 700,
                             "Study Desk must expand well beyond the previous 480pt cap")
    }

    func testMaterialControlsInBothFinishes() throws {
        for (dark, finish) in [(false, "light"), (true, "dark")] {
            let controls = HStack(spacing: 12) {
                KeyTile(title: "FOCUS", glyph: .symbol("arrow.up.left.and.arrow.down.right"), size: 32) {}
                KeyTile(title: "FATHERS", glyph: .symbol("scroll"), selected: true, size: 32) {}
                KnobTile(value: .constant(15), range: 15...30, step: 1, label: "TYPE", unit: "PT", cap: STColor.navy)
                    .frame(width: 106)
                KnobTile(value: .constant(16), range: 2...16, step: 1, label: "LEADING", unit: "PT", cap: STColor.orange)
                    .frame(width: 106)
            }.padding(16).background(STColor.chassisTop)
            let rep = try render(controls, dark: dark, size: CGSize(width: 420, height: 112), name: "material-controls-\(finish)")
            assertNotBlank(rep, finish)
        }
    }

    func testSavedNoteRibbonInBothFinishes() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("ROM", 8, 28)
            state.notes.update(passage: "Romans 8:28", title: "Providence", body: "A saved study note.")
            _ = try render(MainView().environmentObject(state), dark: dark,
                size: CGSize(width: 1143, height: 797), name: "ivory-note-\(name)")
        }
    }

    func testChapterFaderExtremesAndLCD() throws {
        for (dark, finish) in [(false, "light"), (true, "dark")] {
            for (book, chapter) in [("PSA", 150), ("OBA", 1)] {
                let state = stateAt(book, chapter, 1)
                _ = try render(MainView().environmentObject(state), dark: dark,
                    size: CGSize(width: 980, height: 650), name: "fader-\(book)-\(finish)")
            }
        }
    }

    /// 0.7 fix-batch verification sweep: Psalm 23:1 and Isaiah 53:5 (the two required-verification
    /// passages not otherwise rendered as the *full* `MainView`, at *both* the 980pt minimum and
    /// the default window size, in *both* finishes -- Romans 8:28 already gets this combination via
    /// `testDeckAt980ptDoesNotBleedIntoNeighboringTiles`/`testStudyLayoutRendersInLightAndDark`,
    /// and Isaiah 53:5's own `exegetes-isaiah-53-5-*` renders are the Study Desk alone, not the
    /// full window).
    func testPsalm23AndIsaiah53RenderAtMinimumAndDefaultSizeInBothFinishes() throws {
        for (code, chapter, verse, label) in [("PSA", 23, 1, "psalm23"), ("ISA", 53, 5, "isaiah53")] {
            for size: (CGSize, String) in [(CGSize(width: 980, height: 650), "980"), (CGSize(width: 1143, height: 797), "default")] {
                for (dark, name) in [(false, "light"), (true, "dark")] {
                    let state = stateAt(code, chapter, verse)
                    let rep = try render(MainView().environmentObject(state), dark: dark, size: size.0, name: "\(label)-\(size.1)-\(name)")
                    assertNotBlank(rep, "\(label) \(size.1) \(name)")
                }
            }
        }
    }

    func testKJVAndReadingLayoutsRender() throws {
        let state = stateAt("JHN", 3, 16, translation: "KJV")
        state.applyPreset(.reading)
        assertNotBlank(try render(MainView().environmentObject(state), dark: true, size: CGSize(width: 1143, height: 797), name: "reading-kjv-dark"), "reading")
    }

    /// Study is covered by `testStudyLayoutRendersInLightAndDark` (it's `makeOfflineState()`'s
    /// default) and Reading by the test above; Research — Library + Scripture + Study Desk, no
    /// notebook — wasn't rendered anywhere in this file before this pass.
    func testResearchLayoutRenders() throws {
        let state = stateAt("ROM", 8, 28)
        state.applyPreset(.research)
        for (dark, name) in [(false, "light"), (true, "dark")] {
            assertNotBlank(try render(MainView().environmentObject(state), dark: dark, size: CGSize(width: 1143, height: 797), name: "research-\(name)"), "research")
        }
    }

    func testUnavailableOnlineTranslationRenders() throws {
        let state = stateAt("JHN", 1, 1, translation: "ESV")
        assertNotBlank(try render(MainView().environmentObject(state), dark: false, size: CGSize(width: 1143, height: 797), name: "esv-nokey-light"), "unavailable")
    }

    /// An expanded card with a *fixture* reviewed WCF link (never shipped) beside an anchored Calvin card.
    func testSourceCardsShowRangeProvenanceAndReviewedLinksInBothFinishes() throws {
        let store0 = StudyResourceStore(confession: ConfessionStore(localLinksURL: nil))
        let calvin = try XCTUnwrap(store0.sources(bookCode: "ROM", bookName: "Romans", chapter: 8, verse: 28).first { $0.entry.author == "John Calvin" })
        let links = temporaryDirectory("snap").appendingPathComponent("links.json")
        try #"{"schema":1,"links":[{"entryID":"\#(calvin.id)","wcf":{"chapter":3,"section":1},"relation":"discusses","state":"curated","reviewer":"FIXTURE REVIEWER","reviewedOn":"2026-09-21","note":"Test fixture only."}]}"#
            .write(to: links, atomically: true, encoding: .utf8)
        let resources = StudyResourceStore(confession: ConfessionStore(bundledLinksURL: links, localLinksURL: nil))
        let linked = try XCTUnwrap(resources.sources(bookCode: "ROM", bookName: "Romans", chapter: 8, verse: 28).first { $0.id == calvin.id })
        XCTAssertEqual(linked.confessionLinks.count, 1)
        let anchored = try XCTUnwrap(resources.sources(bookCode: "1CO", bookName: "1 Corinthians", chapter: 6, verse: 1).first { $0.entry.rangeBasis == .anchored })
        let block = try XCTUnwrap(resources.sources(bookCode: "1TI", bookName: "1 Timothy", chapter: 3, verse: 4).first { $0.entry.rangeBasis == .block })
        let crossRef = try XCTUnwrap(resources.sources(bookCode: "GEN", bookName: "Genesis", chapter: 1, verse: 1).first { $0.entry.tradition == .crossReferences })
        let state = makeOfflineState()
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let view = VStack(spacing: 0) {
                SourceCard(resolved: linked, bookName: "Romans", startExpanded: true)
                Rectangle().fill(STColor.hairline).frame(height: 1)
                SourceCard(resolved: crossRef, bookName: "Genesis") { _ in }
                Rectangle().fill(STColor.hairline).frame(height: 1)
                SourceCard(resolved: anchored, bookName: "1 Corinthians")
                Rectangle().fill(STColor.hairline).frame(height: 1)
                SourceCard(resolved: block, bookName: "1 Timothy")
                Spacer(minLength: 0)
            }
            .tileFace().environmentObject(state)
            assertNotBlank(try render(view, dark: dark, size: CGSize(width: 430, height: 1150), name: "cards-\(name)"), name)
        }
    }

    func testNotesBrowserAndWelcomeSheetRenderInBothFinishes() throws {
        let state = makeOfflineState()
        state.notes.update(passage: "Romans 8:28", title: "Providence", body: "Everything works together for good.")
        state.notes.update(passage: "John 1:1", title: "The Word", body: "Pre-existence of Christ.")
        for (dark, name) in [(false, "light"), (true, "dark")] {
            assertNotBlank(try render(NotesBrowser().environmentObject(state), dark: dark, size: CGSize(width: 340, height: 420), name: "notes-\(name)"), name)
            assertNotBlank(try render(WelcomeSheet(), dark: dark, size: CGSize(width: 420, height: 480), name: "welcome-\(name)"), name)
        }
    }

    func testLibrarySearchShowsVerseMatchesInBothFinishes() throws {
        let state = makeOfflineState()
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let view = LibraryPane().environmentObject(state).frame(width: 260)
            assertNotBlank(try render(view, dark: dark, size: CGSize(width: 260, height: 700), name: "library-\(name)"), name)
        }
    }

    /// The LCD must degrade by dropping content (`ViewThatFits`, `LCD.swift`), never by wrapping
    /// a line. Renders the display alone — not the whole window — at three widths spanning the
    /// full/medium/compact candidates: 400pt (full row fits), 260pt (medium: bank counts drop),
    /// and 170pt (compact: book code + no origin word), which is roughly what the LCD actually
    /// gets inside a real 980×650 window once Library/Scripture/Desk take their minimums and the
    /// fixed-width keys take theirs (see `testMinimumWindowSizeRenders` for the full-window case).
    /// An offscreen bitmap can't assert "no wrap" directly, so this pairs with a manual look at
    /// the written PNGs — recorded in the workstream report, not re-asserted here.
    func testLCDAt980ptDoesNotWrap() throws {
        for width: CGFloat in [400, 260, 170] {
            for (dark, name) in [(false, "light"), (true, "dark")] {
                let state = stateAt("ROM", 8, 28)
                let rep = try render(LCDDisplay().environmentObject(state), dark: dark,
                                      size: CGSize(width: width, height: 46), name: "lcd-\(Int(width))-\(name)")
                // The shared `assertNotBlank` samples every 17px and expects >12 distinct colors,
                // tuned for full-window renders; a lone 46pt-tall LCD tile is mostly its own flat
                // black background, so a smaller, still-meaningful floor applies here instead —
                // this only needs to prove the row actually drew content, not measure richness.
                var distinct = Set<UInt32>()
                for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                    for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
                        if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                            distinct.insert(UInt32(c.redComponent * 63) << 12 | UInt32(c.greenComponent * 63) << 6 | UInt32(c.blueComponent * 63))
                        }
                    }
                }
                XCTAssertGreaterThan(distinct.count, 4, "LCD at \(width)pt, \(name) rendered blank")
            }
        }
    }

    /// Reformed commentary is about to carry Calvin, Matthew Henry's *Complete* Commentary and
    /// John Gill together (workstream C) — entries thousands of words long, multiple authors per
    /// bank. Builds a synthetic fixture (a real entry would need the not-yet-landed data) and
    /// renders the collapsed default and the expanded state, checking the collapse/author-grouping
    /// machinery doesn't break on real-scale text rather than the short excerpts every other
    /// fixture in this file happens to use.
    func testLongCommentaryCardCollapsesAndGroupsByAuthorInBothFinishes() throws {
        let longExcerpt = Array(repeating: "the mercy and providence of God toward those who are called according to his purpose", count: 220)
            .joined(separator: ", ") + "."
        func source(id: String, author: String, work: String) -> ResolvedSource {
            let entry = StudySource(id: id, chapter: 8, startVerse: 28, endVerse: 28, rangeBasis: .stated,
                                     author: author, work: work, era: "16th c.", tradition: .reformed,
                                     source: "Fixture", excerpt: longExcerpt, sourceURL: nil,
                                     isExactQuote: true, truncated: false, tier: .tier1Confessional,
                                     contentKind: .verseCommentary)
            return ResolvedSource(entry: entry, record: nil, confessionLinks: [], passage: "Romans 8:28")
        }
        let calvin = source(id: "fixture.calvin", author: "John Calvin", work: "Commentary on Romans")
        let henry = source(id: "fixture.henry", author: "Matthew Henry", work: "Commentary on the Whole Bible")
        let state = makeOfflineState()
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let collapsed = VStack(spacing: 0) {
                DeskSectionHeader(title: "Reformed", color: STColor.reformed, count: 2)
                DeskAuthorGroupHeader(text: calvin.entry.author)
                SourceCard(resolved: calvin, bookName: "Romans", bankTier: .tier1Confessional, expectedClassLabel: "REFORMED SOURCE")
                Rectangle().fill(STColor.hairline).frame(height: 1)
                DeskAuthorGroupHeader(text: henry.entry.author)
                SourceCard(resolved: henry, bookName: "Romans", bankTier: .tier1Confessional, expectedClassLabel: "REFORMED SOURCE")
                Spacer(minLength: 0)
            }.tileFace().environmentObject(state)
            assertNotBlank(try render(collapsed, dark: dark, size: CGSize(width: 420, height: 520), name: "long-collapsed-\(name)"), name)

            let expanded = VStack(spacing: 0) {
                SourceCard(resolved: calvin, bookName: "Romans", startExpanded: true, bankTier: .tier1Confessional, expectedClassLabel: "REFORMED SOURCE")
                Spacer(minLength: 0)
            }.tileFace().environmentObject(state)
            assertNotBlank(try render(expanded, dark: dark, size: CGSize(width: 420, height: 900), name: "long-expanded-\(name)"), name)
        }
    }

    /// Alignment badge integration (0.9.5, Claude wiring N's `AlignmentStore` onto `SourceCard`):
    /// no chrome change at all with no lens selected, and exactly one small badge appended when a
    /// lens is active and there's a real, sourced claim to show. `.noMapping` (the common case
    /// once a lens is on) is deliberately suppressed at the card level — see the comment at the
    /// call site in `Panes.swift` — so this also confirms a `.noMapping` source (Keil & Delitzsch,
    /// which has no sourced Westminster-lens claim) shows no badge even with a lens selected.
    func testAlignmentBadgeOnlyAppearsWithASelectedLensAndARealClaim() throws {
        let resources = StudyResourceStore()
        let calvin = try XCTUnwrap(resources.sources(bookCode: "ROM", bookName: "Romans", chapter: 8, verse: 28)
            .first { $0.entry.author == "John Calvin" })
        let state = makeOfflineState()
        for (dark, name) in [(false, "light"), (true, "dark")] {
            state.alignmentStandard = .none
            let noLens = SourceCard(resolved: calvin, bookName: "Romans").tileFace().environmentObject(state)
            assertNotBlank(try render(noLens, dark: dark, size: CGSize(width: 420, height: 220), name: "alignment-none-\(name)"), name)

            state.alignmentStandard = .westminsterStandards
            let withLens = SourceCard(resolved: calvin, bookName: "Romans").tileFace().environmentObject(state)
            assertNotBlank(try render(withLens, dark: dark, size: CGSize(width: 420, height: 220), name: "alignment-wcf-\(name)"), name)
        }
        let wcfResult = state.alignment.alignment(for: calvin.entry, against: .westminsterStandards)
        guard case .documentedAgreement = wcfResult else {
            return XCTFail("expected Calvin to show documented agreement under the Westminster lens, got \(String(describing: wcfResult))")
        }
        XCTAssertNil(state.alignment.alignment(for: calvin.entry, against: .none))
    }

    func testTierDisclaimersAndConfessionalLibraryRenderInBothFinishes() throws {
        let resources = StudyResourceStore()
        let tier2 = try XCTUnwrap(resources.sources(bookCode: "ROM", bookName: "Romans", chapter: 8, verse: 28).first { $0.entry.tier == .tier2HistoricWitness })
        let synthetic = StudySource(id: "ROM.8.28-28.fixture.00000000", chapter: 8, startVerse: 28, endVerse: 28,
            rangeBasis: .stated, author: "Theodore of Mopsuestia", work: "Synthetic UI fixture", era: "test",
            tradition: .fathers, source: "fixture", excerpt: "Synthetic text for testing a research-only source card. Not a historical quotation.",
            sourceURL: nil, isExactQuote: false, truncated: false, tier: .tier3ResearchOnly)
        let tier3 = try XCTUnwrap(TestPaths.isPublicSource ? synthetic : Corpus.all.first { $0.tier == .tier3ResearchOnly })
        let tier3Resolved = ResolvedSource(entry: tier3, record: resources.registry[tier3.source], confessionLinks: [], passage: "sample")
        let state = makeOfflineState()
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let view = VStack(spacing: 0) {
                SourceCard(resolved: tier2, bookName: "Romans")
                Rectangle().fill(STColor.hairline).frame(height: 1)
                SourceCard(resolved: tier3Resolved, bookName: "Sample")
            }
            .tileFace().environmentObject(state)
            assertNotBlank(try render(view, dark: dark, size: CGSize(width: 420, height: 520), name: "tiers-\(name)"), name)
            assertNotBlank(try render(ConfessionalLibrarySheet().environmentObject(state), dark: dark, size: CGSize(width: 460, height: 560), name: "library-\(name)"), name)
        }
    }

    /// E6 (0.7 wave 2): the Study Desk's source stack (not the whole window, so the new Exegetes
    /// bank is never pushed below the fold by Word Study) for the three verses the workstream
    /// brief names as the visual proof of E1-E3 — Isaiah 53:5 (Keil & Delitzsch should appear,
    /// labelled Lutheran), Matthew 26:26 (inside the Complete Commentary's documented 19-28 gap,
    /// so the Concise Commentary gap-fill should appear instead, labelled "Concise Commentary"),
    /// John 3:16 (Gill should appear, labelled Particular Baptist, alongside Calvin and Matthew
    /// Henry). Also confirms every Exegetes card actually prints its own tradition label and
    /// that the bank header carries the historic-witness disclaimer once, not per card.
    func testExegetesBankAndHenryBackfillRenderForKeyVersesInBothFinishes() throws {
        let isaiah = stateAt("ISA", 53, 5)
        let isaiahSources = isaiah.studyResources.sources(bookCode: "ISA", bookName: "Isaiah", chapter: 53, verse: 5)
        XCTAssertTrue(isaiahSources.contains { $0.entry.source == "keil-delitzsch" && $0.entry.authorTradition == "Lutheran" },
                      "expected a Lutheran-labelled Keil & Delitzsch entry at Isaiah 53:5")

        let matthew = stateAt("MAT", 26, 26)
        let matthewSources = matthew.studyResources.sources(bookCode: "MAT", bookName: "Matthew", chapter: 26, verse: 26)
        XCTAssertTrue(matthewSources.contains { $0.entry.source == "mhcc" && $0.entry.work == "Concise Commentary" },
                      "expected the Concise Commentary gap-fill at Matthew 26:26 (inside the Complete's documented 19-28 gap)")
        XCTAssertFalse(matthewSources.contains { $0.entry.source == "matthew-henry" },
                       "Matthew 26 is a documented Complete-commentary gap; a real Complete entry here would mean the gap list is stale")

        let john = stateAt("JHN", 3, 16)
        let johnSources = john.studyResources.sources(bookCode: "JHN", bookName: "John", chapter: 3, verse: 16)
        XCTAssertTrue(johnSources.contains { $0.entry.source == "john-gill" && $0.entry.authorTradition == "Particular Baptist" },
                      "expected a Particular Baptist-labelled Gill entry at John 3:16")
        XCTAssertTrue(johnSources.contains { $0.entry.source == "calvin" } && johnSources.contains { $0.entry.source == "matthew-henry" },
                      "John 3:16 should still carry Calvin and Matthew Henry in the Reformed bank")

        for (code, chapter, verse, label) in [("ISA", 53, 5, "isaiah-53-5"), ("MAT", 26, 26, "matthew-26-26"), ("JHN", 3, 16, "john-3-16")] {
            for (dark, name) in [(false, "light"), (true, "dark")] {
                let state = stateAt(code, chapter, verse)
                // `SourcesPane` is always hosted inside `StudyDesk`'s `.tileFace()` in the real
                // app (`Panes.swift`'s `StudyDesk.body`) -- rendering it bare here (as this test
                // did before) left dark-mode text painted against the system default window
                // background instead of the warm/graphite tile gradient it was designed against,
                // so the Exegetes bank had genuinely never been visually verified in dark mode.
                let view = SourcesPane().environmentObject(state).tileFace()
                assertNotBlank(try render(view, dark: dark, size: CGSize(width: 400, height: 3400), name: "exegetes-\(label)-\(name)"), name)
            }
        }
    }

    /// E2's own non-negotiable: the deck (all four bank keys plus everything else) must still
    /// fit at the true 980pt minimum window width, in both finishes, with nothing clipped or
    /// wrapped -- verified here by rendering the whole window, not just the LCD in isolation
    /// (`testLCDAt980ptDoesNotWrap` already covers the LCD component alone).
    func testDeckWithFourBankKeysFitsAt980ptInBothFinishes() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("ROM", 8, 28)
            let rep = try render(MainView().environmentObject(state), dark: dark, size: CGSize(width: 980, height: 650), name: "deck-four-keys-980-\(name)")
            assertNotBlank(rep, name)
        }
    }

    /// INTEGRATION regression guard (item 1, 0.7 fix batch): `testDeckWithFourBankKeysFitsAt980ptInBothFinishes`
    /// above only proved the window renders *something* non-blank -- it did not catch the real bug,
    /// where the chapter numeral painted outside the LCD's own clip onto the PASSAGE key, and the
    /// gear icon was hidden under the TYPE knob tile drawn after it. Two independent, pixel-based
    /// checks against the real `MainView`, not the isolated `LCDDisplay` (which passed in isolation
    /// at 170pt and is exactly why this slipped before):
    ///
    /// 1. Left edge: the Grille and PASSAGE key sit to the LCD's *left* with window-size-independent
    ///    fixed widths, so for the same AppState their pixels must be identical whether the window
    ///    is the true 980pt minimum (LCD's tightest allocation) or a comfortably wide 1143pt (LCD
    ///    never needs to compress). Any divergence in that region is LCD content bleeding outside
    ///    its own bounds -- exactly how the numeral escaped onto the PASSAGE key.
    /// 2. Right edge: the gear icon's color (`STColor.lcdDim`, a mid-grey distinct from the LCD's
    ///    black background, its white ink text, and every warm off-white neighboring tile) must
    ///    actually appear near the LCD's own measured right edge at 980pt -- if it's been painted
    ///    over by the TYPE knob tile, it won't be there.
    func testCompactReadingHeaderFitsNarrowPaneAndLongReference() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("1CO", 13, 4)
            let rep = try render(ReadingNavigation().environmentObject(state), dark: dark,
                                 size: CGSize(width: 420, height: 85), name: "reading-header-\(name)")
            XCTAssertEqual(rep.pixelsWide, 840)
            _ = try render(PassageJumpPanel {}.environmentObject(state), dark: dark,
                           size: CGSize(width: 370, height: 240), name: "passage-jump-\(name)")
        }
    }

    /// 0.8 (workstream G): the Settings scene itself, offscreen — the gear icon/menu items call
    /// `openSettings()`, but that function's *effect* (opening a real `NSWindow` via
    /// `OpenSettingsAction`) can't be exercised by an offscreen unit test at all (there is no live
    /// app/scene lifecycle here to open a window into) — what this test verifies is the other half
    /// of the fix: that `SettingsView`, the content the fixed `openSettings()` now actually
    /// succeeds in showing, renders correctly on its own, including the new About tab's STEPBible
    /// attribution. See the workstream report for how the fix itself was verified (reading the
    /// call sites + a live-app smoke check is the honest answer; a headless test cannot open a
    /// real window).
    func testSettingsViewRendersInBothFinishes() throws {
        let original = SettingsOpener.shared.destination
        defer { SettingsOpener.shared.destination = original }
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = makeOfflineState()
            for (destination, tab) in [(SettingsDestination.workspace, "workspace"), (.translations, "translations"), (.about, "about")] {
                SettingsOpener.shared.destination = destination
                let rep = try render(SettingsView().environmentObject(state), dark: dark, size: CGSize(width: 620, height: 660), name: "settings-\(tab)-\(name)")
                assertNotBlank(rep, name)
            }
        }
    }

    /// 0.8 (workstream G): Matt's direct feedback on a wide window screenshot — "this area takes
    /// up a ton of space for no reason" — was about the LCD's dead space once the window is wider
    /// than the default. Proves the redesigned LCD actually *uses* that width for the selected
    /// verse's original-language interlinear strip at a genuinely wide window (1600pt, well past
    /// default), for both a Hebrew verse (Genesis 1:1, right-to-left) and a Greek one (John 3:16),
    /// in both finishes — the visual proof the workplan asked for, not just "renders something."
    func testLCDInterlinearStripAppearsAtWideWindowForHebrewAndGreekVersesInBothFinishes() throws {
        for (code, chapter, verse, label) in [("GEN", 1, 1, "gen1-1-hebrew"), ("JHN", 3, 16, "jhn3-16-greek")] {
            for (dark, name) in [(false, "light"), (true, "dark")] {
                let state = stateAt(code, chapter, verse)
                let rep = try render(MainView().environmentObject(state), dark: dark, size: CGSize(width: 1600, height: 900),
                                      name: "lcd-wide-1600-\(label)-\(name)")
                assertNotBlank(rep, "\(label) \(name)")
            }
        }
    }

    /// Companion to the 1600pt render above at the *default* window size (1143pt) — confirms the
    /// strip is already doing useful work well before an unusually wide window, not only at an
    /// extreme.
    func testLCDInterlinearStripAppearsAtDefaultWindowSizeInBothFinishes() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("ROM", 8, 28)
            let rep = try render(MainView().environmentObject(state), dark: dark, size: CGSize(width: 1143, height: 797),
                                  name: "lcd-default-romans-\(name)")
            assertNotBlank(rep, name)
        }
    }

    /// The 980pt minimum-width invariant, re-verified specifically with a Hebrew verse selected
    /// (every other 980pt render in this file happens to use Romans/Psalms/Isaiah — all Greek or
    /// already-covered OT passages) so the interlinear strip's own width computation is exercised
    /// at the true floor with right-to-left content, not just left-to-right Greek.
    func testDeckAt980ptWithHebrewVerseSelectedInBothFinishes() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("GEN", 1, 1)
            let rep = try render(MainView().environmentObject(state), dark: dark, size: CGSize(width: 980, height: 650),
                                  name: "deck-980-genesis-hebrew-\(name)")
            assertNotBlank(rep, name)
        }
    }

    /// Longest contiguous horizontal run at row `y` whose pixels satisfy `isBlack` (near-`STColor.lcd`,
    /// r/g/b all below 0.16 -- the LCD's black background in both finishes; distinct from every
    /// warm off-white tile and, at this threshold, from the thin 1.5pt inter-tile gutter gaps too
    /// short to compete with the LCD rect's own width).
    private func longestRun(_ rep: NSBitmapImageRep, y: Int, isBlack: Bool) -> (Int, Int)? {
        guard y >= 0, y < rep.pixelsHigh else { return nil }
        var best: (Int, Int)?
        var start: Int?
        for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let matches = c.redComponent < 0.16 && c.greenComponent < 0.16 && c.blueComponent < 0.16
            if matches {
                if start == nil { start = x }
            } else if let s = start {
                if best == nil || (x - s) > (best!.1 - best!.0) { best = (s, x) }
                start = nil
            }
        }
        if let s = start, best == nil || (rep.pixelsWide - s) > (best!.1 - best!.0) { best = (s, rep.pixelsWide) }
        return best
    }
}
