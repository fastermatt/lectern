import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

@MainActor
final class AppearanceReworkTests: XCTestCase {
    func testPalettePersistsPerFinishWithoutChangingReadingPreferences() throws {
        let state = makeOfflineState()
        state.fontSize = 26; state.lineSpacing = 11
        state.palette = .preset("Sage")
        var edited = state.palette
        edited.dark.accent = 0xDDAA88
        state.palette = edited
        let loaded = WorkspacePalette.load(from: state.preferenceStore)
        XCTAssertEqual(loaded, edited)
        XCTAssertEqual(loaded.light, WorkspacePalette.preset("Sage").light)
        XCTAssertEqual(state.fontSize, 26); XCTAssertEqual(state.lineSpacing, 11)
        state.theme = .dark; XCTAssertEqual(state.colorScheme, .dark)
        state.theme = .light; XCTAssertEqual(state.colorScheme, .light)
        state.theme = .system; XCTAssertNil(state.colorScheme)
        state.palette = .standard
        XCTAssertEqual(WorkspacePalette.load(from: state.preferenceStore), .standard)
    }
    func testDamagedPaletteFallsBackWithoutOverwritingIt() {
        let defaults = ephemeralDefaults()
        let damaged = Data("broken".utf8)
        defaults.set(damaged, forKey: WorkspacePalette.preferenceKey)
        XCTAssertEqual(WorkspacePalette.load(from: defaults), .standard)
        XCTAssertEqual(defaults.data(forKey: WorkspacePalette.preferenceKey), damaged)
        defaults.set(Data(#"{"light":{"accent":999999999,"paper":1,"ink":2},"dark":{"accent":1,"paper":1,"ink":2}}"#.utf8), forKey: WorkspacePalette.preferenceKey)
        XCTAssertEqual(WorkspacePalette.load(from: defaults), .standard)
    }
    func testLiveColorChangeRepaintsExistingReaderWithoutRemounting() throws {
        let state = makeOfflineState()
        let host = NSHostingView(rootView: PaletteProbe().environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua); host.appearance = window.appearance
        window.contentView = host; window.setFrameOrigin(NSPoint(x: -20000, y: -20000)); window.orderBack(nil)
        defer { window.orderOut(nil); PaletteRuntime.shared.apply(.standard) }
        settle(host)
        let before = try pixel(host)
        var palette = state.palette; palette.light.paper = 0xCCEEDD
        state.palette = palette
        settle(host)
        let after = try pixel(host)
        XCTAssertGreaterThan(abs(after.redComponent - before.redComponent), 0.10)
        XCTAssertEqual(after.greenComponent, 238.0 / 255, accuracy: 0.04)
        XCTAssertEqual(after.blueComponent, 221.0 / 255, accuracy: 0.04)
    }
    private struct PaletteProbe: View {
        @EnvironmentObject var state: AppState
        var body: some View {
            VStack { Text(state.theme.rawValue); Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity).background(STColor.paper)
        }
    }
    private func pixel(_ host: NSView) throws -> NSColor {
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB))
    }
    private func settle(_ host: NSView) {
        for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.12)) }
    }
    private func render<V: View>(_ view: V, dark: Bool, size: CGSize, name: String) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); host.appearance = window.appearance
        window.contentView = host; window.setFrameOrigin(NSPoint(x: -20000, y: -20000)); window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(host)
        if let output = ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] {
            var lines: [String] = []
            func describe(_ view: NSView, depth: Int) {
                if view is NSSplitView { lines.append("\(String(repeating: " ", count: depth))\(type(of: view)) \(view.frame) children \(view.subviews.count) arranged \((view as? NSSplitView)?.arrangedSubviews.count ?? 0)") }
                for child in view.subviews { describe(child, depth: depth + 1) }
            }
            describe(host, depth: 0)
            try? lines.joined(separator: "\n").write(toFile: output + "/" + name + ".splits.txt", atomically: true, encoding: .utf8)
        }
        if name.hasPrefix("selected-design-"), size.width > 1000 {
            func splits(_ view: NSView) -> [NSSplitView] {
                ((view as? NSSplitView).map { [$0] } ?? []) + view.subviews.flatMap { splits($0) }
            }
            let all = splits(host)
            let reading = try XCTUnwrap(all.filter(\.isVertical).min { $0.bounds.width < $1.bounds.width })
            let first = try XCTUnwrap(reading.arrangedSubviews.first)
            XCTAssertEqual(first.frame.width / reading.bounds.width, 0.60, accuracy: 0.015,
                           "The actual SwiftUI-hosted reader must restore its split, even with decorative NSSplitView subviews")
            let notes = try XCTUnwrap(all.first { !$0.isVertical })
            XCTAssertEqual(try XCTUnwrap(notes.arrangedSubviews.first).frame.height / notes.bounds.height, 0.65, accuracy: 0.015)
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let output = ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: output); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent(name + ".png"))
        }
    }
    func testSelectedDesignAndControlsInBothFinishes() throws {
        for dark in [false, true] {
            let state = makeOfflineState()
            state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
            state.selectedTraditions = [.reformed, .exegetes, .crossReferences]
            state.rangeEndVerse = 30
            state.theme = dark ? .dark : .light
            state.fontSize = 25; state.studyFontSize = 16
            state.study.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verses: 28, to: 30)], title: "Hope and assurance",
                body: "Read verses 28–30 together. What does this passage say about God's purpose?")
            let finish = dark ? "dark" : "light"
            try render(MainView().environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                       size: CGSize(width: 1487, height: 1058), name: "selected-design-\(finish)")
            try render(AppearancePanel().environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                       size: CGSize(width: 370, height: 520), name: "appearance-\(finish)")
            try render(ReadingOptionsPanel().environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                       size: CGSize(width: 380, height: 450), name: "reading-options-\(finish)")
            state.palette = .preset("Sage")
            try render(MainView().environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                       size: CGSize(width: 980, height: 650), name: "selected-design-sage-\(finish)-small")
        }
        PaletteRuntime.shared.apply(.standard)
    }
    func testDiscoveryAndContributionOffscreen() throws {
        guard ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] != nil else { throw XCTSkip("Offscreen artifact capture is opt-in") }
        for dark in [false, true] {
            let state = makeOfflineState(); state.theme = dark ? .dark : .light
            let finish = dark ? "dark" : "light"
            let historic = PuritanLibraryService(storageDirectory: temporaryDirectory("historic-preview"))
            try render(ResourceLibraryView(books: state.resourceBooks, adding: true, historic: historic)
                .environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                size: CGSize(width: 1080, height: 800), name: "discovery-\(finish)")
            try render(ResourceLibraryView(books: state.resourceBooks, destination: .contribute, historic: historic)
                .environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                size: CGSize(width: 760, height: 650), name: "contribute-\(finish)-small")
        }
        PaletteRuntime.shared.apply(.standard)
    }

    func testPatristicLibraryOffscreen() throws {
        guard ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] != nil else { throw XCTSkip("Offscreen artifact capture is opt-in") }
        for dark in [false, true] {
            let state = makeOfflineState(); state.theme = dark ? .dark : .light
            let finish = dark ? "dark" : "light"
            for section in PatristicLibraryView.Section.allCases {
                try render(PatristicLibraryView(initialSection: section, read: { _ in })
                    .environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                    size: CGSize(width: 700, height: 650), name: "fathers-\(section)-\(finish)")
            }
            try render(ResourceLibraryView(books: state.resourceBooks, destination: .fathers,
                historic: PuritanLibraryService(storageDirectory: temporaryDirectory("historic-fathers-preview")))
                .environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                size: CGSize(width: 1060, height: 800), name: "fathers-library-\(finish)")
            try render(ResourceBookReader(book: try PatristicReader.load(), back: {})
                .environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                size: CGSize(width: 840, height: 700), name: "fathers-reader-\(finish)")
        }
        PaletteRuntime.shared.apply(.standard)
    }


    func testWindowLayoutsAndOptionalDownloadsOffscreen() throws {
        guard ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] != nil else { throw XCTSkip("Offscreen artifact capture is opt-in") }
        for dark in [false, true] {
            let state = makeOfflineState(); state.theme = dark ? .dark : .light
            let finish = dark ? "dark" : "light"
            var recipe = state.workspaceRecipe()
            recipe.windows = [DetachedWindowRecipe(panel: "bible", frame: nil, pinned: nil), DetachedWindowRecipe(panel: "notes", frame: nil, pinned: true)]
            state.layouts.save("Sermon prep · two windows", recipe: recipe)
            state.layouts.save("Docked reading", recipe: state.workspaceRecipe())
            try render(LayoutsPanel(library: state.layouts).environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                       size: CGSize(width: 490, height: 560), name: "layouts-windows-\(finish)")
            try render(PatristicLibraryView(books: state.resourceBooks, read: { _ in })
                .environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                size: CGSize(width: 720, height: 2400), name: "fathers-downloads-\(finish)")
            try render(ResourceLibraryView(books: state.resourceBooks, destination: .modern,
                historic: PuritanLibraryService(storageDirectory: temporaryDirectory("historic-modern-preview")))
                .environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                size: CGSize(width: 1060, height: 1500), name: "free-resources-\(finish)")
            try render(ScrollView { DownloadLibraryView().padding(24) }.environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                       size: CGSize(width: 640, height: 2300), name: "bible-downloads-\(finish)")
        }
        PaletteRuntime.shared.apply(.standard)
    }

    func testLinkedReaderAndLibraryCitationsOffscreen() async throws {
        guard ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] != nil else { throw XCTSkip("Offscreen artifact capture is opt-in") }
        let state = makeOfflineState()
        let library = ResourceBookLibrary(root: temporaryDirectory("linked-preview"))
        await library.load(); await library.citationsReady()
        let fathers = try XCTUnwrap(library.includedBooks.first)
        let hit = try XCTUnwrap(library.citations.citing(Anchor(book: "MAT", chapter: 5, throughChapter: nil)).first)
        for dark in [false, true] {
            state.theme = dark ? .dark : .light
            let finish = dark ? "dark" : "light"
            try render(ResourceBookReader(book: fathers, focus: LibraryFocus(bookID: fathers.id, articleID: hit.articleID, paragraph: hit.paragraph), back: {})
                .environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                size: CGSize(width: 900, height: 720), name: "linked-reader-\(finish)")
            try render(ScrollView { LibraryCitationsPanel(books: library, anchor: Anchor(book: "MAT", chapter: 5, throughChapter: nil), startsExpanded: true) }
                .environmentObject(state).preferredColorScheme(state.colorScheme).background(STColor.paper), dark: dark,
                size: CGSize(width: 460, height: 900), name: "library-citations-\(finish)")
        }
        PaletteRuntime.shared.apply(.standard)
    }

    /// PASTOR_WALKTHROUGH=1 STUDYTABLE_SNAPSHOT_DIR=… (downloads Darby into a temporary folder)
    func testPastorWalkthroughWorkspaceOffscreen() async throws {
        guard ProcessInfo.processInfo.environment["PASTOR_WALKTHROUGH"] == "1",
              ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] != nil else { throw XCTSkip("Opt-in walkthrough capture") }
        let packs = temporaryDirectory("pastor-packs")
        try await BibleInstaller(root: packs).install(try XCTUnwrap(BibleDownload.catalog.first { $0.id == "DBY" })) { _ in }
        let cache = OnlineChapterCache(directory: temporaryDirectory("cache"))
        let service = OnlineTranslationService(cache: cache, transport: { _ in throw URLError(.notConnectedToInternet) },
            idStore: BibleIDStore(defaultsKey: "test.ids.\(UUID().uuidString)"), keyReader: { _ in nil })
        let books = ResourceBookLibrary(root: temporaryDirectory("pastor-books"))
        let state = AppState(library: ScriptureLibrary(userRoot: packs), studyResources: StudyResourceStore(), online: service,
            defaults: ephemeralDefaults(), notes: ephemeralNotes(), resourceBooks: books)
        state.hasSeenIntro = true; state.applyPreset(.study); state.fontSize = 22; state.lineSpacing = 8
        await books.load(); await books.citationsReady()
        state.translationID = "DBY"
        state.navigate(bookCode: "REV", chapter: 20, verse: 4); state.rangeEndVerse = 6
        state.study.addNote(anchors: [Anchor(book: "REV", chapter: 20, verses: 1, to: 6)], title: "Was a pre-trib rapture taught before Darby?", kind: .sermonIdea,
            sections: [NoteSection(key: "points", text: "1. What Rev 20 says\n2. Didache 16; Irenaeus V.29–30; Augustine City of God XX\n3. Darby (1830s): Israel/Church, pre-tribulation")])
        for dark in [false, true] {
            state.theme = dark ? .dark : .light
            let finish = dark ? "dark" : "light"
            try render(MainView().environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                       size: CGSize(width: 1487, height: 1058), name: "pastor-workspace-\(finish)")
            try render(ScrollView { LibraryCitationsPanel(books: books, anchor: Anchor(book: "REV", chapter: 20, verses: 1, to: 6), startsExpanded: true) }
                .environmentObject(state).preferredColorScheme(state.colorScheme).background(STColor.paper), dark: dark,
                size: CGSize(width: 460, height: 800), name: "pastor-citations-rev20-\(finish)")
            if let fathers = books.includedBooks.first, let hit = books.citations.citing(Anchor(book: "REV", chapter: 20, verses: 1, to: 6)).first {
                try render(ResourceBookReader(book: fathers, focus: LibraryFocus(bookID: fathers.id, articleID: hit.articleID, paragraph: hit.paragraph), back: {})
                    .environmentObject(state).preferredColorScheme(state.colorScheme), dark: dark,
                    size: CGSize(width: 1100, height: 760), name: "pastor-reader-\(finish)")
            }
        }
        PaletteRuntime.shared.apply(.standard)
    }
}
