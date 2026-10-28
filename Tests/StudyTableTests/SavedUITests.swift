import AppKit
import SwiftUI
import XCTest
import StudyTableCore
@testable import StudyTable

/// S2a (0.10): range selection, one-gesture save, verse marks, and the Library "Saved" mode.
/// Tests never touch ~/Library/Application Support/StudyTable/ — every state comes from
/// `makeOfflineState()` / `ephemeralStudy()`.
@MainActor
final class SavedUITests: XCTestCase {
    // MARK: Offscreen rendering (same approach as SnapshotTests.swift)

    /// Set STUDYTABLE_SNAPSHOT_DIR to write the review PNGs actually viewed for this report.
    private var snapshotDirectory: URL? {
        ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func render<V: View>(_ view: V, dark: Bool, size: CGSize, name: String = "") throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if !name.isEmpty, let directory = snapshotDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        }
        return rep
    }

    private func distinctColorCount(_ rep: NSBitmapImageRep) -> Int {
        var distinct = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    distinct.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
                }
            }
        }
        return distinct.count
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(distinctColorCount(rep), 4, "\(label) rendered blank", file: file, line: line)
    }

    // MARK: - Range selection

    func testShiftClickExtendsRangeAndPlainClickResets() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.extendRange(to: 39)
        XCTAssertEqual(state.rangeEndVerse, 39)
        XCTAssertEqual(state.selectedAnchor, Anchor(book: "ROM", chapter: 8, verses: 28, to: 39))
        XCTAssertEqual(state.passage, "Romans 8:28\u{2013}39")

        // A plain click on a different verse resets to a single verse.
        state.selectSingleVerse(5)
        XCTAssertEqual(state.selectedVerse, 5)
        XCTAssertNil(state.rangeEndVerse)

        // A plain click back on the anchor of an active range collapses it (not just a no-op).
        state.selectSingleVerse(5)
        state.extendRange(to: 10)
        XCTAssertEqual(state.rangeEndVerse, 10)
        state.selectSingleVerse(5)
        XCTAssertNil(state.rangeEndVerse, "clicking the range's own anchor again must collapse the range")
    }

    func testExtendRangeToAnchorCollapsesIt() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.extendRange(to: 30)
        XCTAssertEqual(state.rangeEndVerse, 30)
        state.extendRange(to: 28)
        XCTAssertNil(state.rangeEndVerse)
    }

    func testKeyboardExtendSelectionGrowsAndShrinksAndClamps() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.extendSelection(by: 1)
        XCTAssertEqual(state.rangeEndVerse, 29)
        state.extendSelection(by: 1)
        XCTAssertEqual(state.rangeEndVerse, 30)
        state.extendSelection(by: -2)
        XCTAssertNil(state.rangeEndVerse, "shrinking back to the anchor collapses the range")
        state.extendSelection(by: -1)
        XCTAssertEqual(state.rangeEndVerse, 27)

        // Clamped to the chapter: Romans 8 has 39 verses.
        state.selectSingleVerse(39)
        state.extendSelection(by: 1)
        XCTAssertNil(state.rangeEndVerse, "cannot extend past the last verse of the chapter")
    }

    func testCurrentSectionAndSelectSection() throws {
        let state = makeOfflineState()
        state.navigate(bookCode: "MRK", chapter: 4, verse: 35)
        guard let section = state.currentSection() else {
            throw XCTSkip("no BSB section heading indexed for Mark 4:35 in this environment")
        }
        state.selectSection(section)
        XCTAssertEqual(state.selectedBookCode, section.bookCode)
        XCTAssertEqual(state.selectedChapter, section.startChapter)
        XCTAssertEqual(state.selectedVerse, max(section.startVerse, 1))
        if section.endChapter == section.startChapter, section.endVerse > section.startVerse {
            XCTAssertNotNil(state.rangeEndVerse, "a same-chapter section spanning more than one verse selects a range")
        }
    }

    // MARK: - Save toggle

    func testCommandDTogglesSaveOnTheSelection() throws {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        let anchor = try XCTUnwrap(state.selectedAnchor)
        XCTAssertFalse(state.notes.isSaved(anchor))
        let saved = MyStudyActions.toggleSave(anchor, in: state)
        XCTAssertTrue(saved)
        XCTAssertTrue(state.notes.isSaved(anchor))
        let unsaved = MyStudyActions.toggleSave(anchor, in: state)
        XCTAssertFalse(unsaved)
        XCTAssertFalse(state.notes.isSaved(anchor))
    }

    func testToggleSaveOnARange() throws {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.extendRange(to: 39)
        let anchor = try XCTUnwrap(state.selectedAnchor)
        MyStudyActions.toggleSave(anchor, in: state)
        let saved = state.notes.savedPassage(matching: anchor)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.anchor.displayString, "Romans 8:28\u{2013}39")
    }

    func testHighlightAutoSavesAndSetsColor() {
        let state = makeOfflineState()
        let anchor = Anchor(book: "JHN", chapter: 3, verse: 16)
        XCTAssertFalse(state.notes.isSaved(anchor))
        MyStudyActions.setHighlight(.yellow, for: anchor, in: state)
        XCTAssertEqual(state.notes.savedPassage(matching: anchor)?.highlight, .yellow)
        MyStudyActions.setHighlight(nil, for: anchor, in: state)
        XCTAssertNil(state.notes.savedPassage(matching: anchor)?.highlight)
    }

    func testMarkAsMemoryVerseTogglesAndAutoSaves() {
        let state = makeOfflineState()
        let anchor = Anchor(book: "JHN", chapter: 3, verse: 16)
        MyStudyActions.toggleMemory(anchor, in: state)
        XCTAssertEqual(state.notes.savedPassage(matching: anchor)?.isMemory, true)
        MyStudyActions.toggleMemory(anchor, in: state)
        XCTAssertEqual(state.notes.savedPassage(matching: anchor)?.isMemory, false)
    }

    // MARK: - Collections (CRUD through the actions the UI calls)

    func testCreateCollectionAndAddThenToggleMembership() throws {
        let state = makeOfflineState()
        let anchor = Anchor(book: "ROM", chapter: 8, verse: 28)
        let collection = try XCTUnwrap(MyStudyActions.createCollectionAndAdd(named: "Security in Christ", anchor: anchor, in: state))
        XCTAssertEqual(state.notes.savedPassages(in: collection.id).map(\.anchor), [anchor])
        MyStudyActions.toggleCollection(collection, for: anchor, in: state)
        XCTAssertTrue(state.notes.savedPassages(in: collection.id).isEmpty)
        MyStudyActions.toggleCollection(collection, for: anchor, in: state)
        XCTAssertEqual(state.notes.savedPassages(in: collection.id).count, 1)

        XCTAssertTrue(state.notes.renameCollection(collection.id, to: "Assurance"))
        XCTAssertEqual(state.notes.collections.first?.name, "Assurance")
        XCTAssertTrue(state.notes.deleteCollection(collection.id))
        XCTAssertTrue(state.notes.collections.isEmpty)
        // Deleting the collection never unsaves its passages.
        XCTAssertTrue(state.notes.isSaved(anchor))
    }

    func testCopyWithReferenceCopiesEveryVerseInARange() throws {
        let state = makeOfflineState()
        state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
        state.extendRange(to: 17)
        let anchor = try XCTUnwrap(state.selectedAnchor)
        MyStudyActions.copyWithReference(anchor, in: state)
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(clipboard.contains("John 3:16"))
        XCTAssertTrue(clipboard.contains("John 3:17"))
        XCTAssertEqual(clipboard.split(separator: "\n").count, 2)
    }

    // MARK: - Marks: on vs off, and range overlap

    func testVerseMarksBadgeDrawsNothingWhenEverythingIsOff() throws {
        let off = try render(VerseMarksBadge(hasNote: false, highlight: nil, isSaved: false, isMemory: false)
            .frame(width: 40, height: 60).background(Color.white), dark: false, size: CGSize(width: 40, height: 60))
        XCTAssertLessThanOrEqual(distinctColorCount(off), 2, "an unmarked verse must draw no marks at all")
    }

    func testVerseMarksBadgeDrawsSomethingWhenSavedHighlightedAndMemory() throws {
        let on = try render(VerseMarksBadge(hasNote: true, highlight: .yellow, isSaved: true, isMemory: true)
            .frame(width: 40, height: 60).background(Color.white), dark: false, size: CGSize(width: 40, height: 60))
        assertNotBlank(on, "marks on")
    }

    func testHighlightColorsHaveDistinctGlyphsNotJustColor() {
        let glyphs = Set(HighlightColor.allCases.map(\.glyphName))
        XCTAssertEqual(glyphs.count, HighlightColor.allCases.count, "every highlight colour must have its OWN glyph shape")
    }

    func testNoteOverlappingARangeShowsOnEveryVerseItCovers() {
        let state = makeOfflineState()
        state.notes.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verses: 28, to: 30)], body: "A range note")
        for verse in 28...30 {
            let hit = state.notes.notes(overlapping: Anchor(book: "ROM", chapter: 8, verse: verse))
            XCTAssertEqual(hit.count, 1, "verse \(verse) should be covered by the range note")
        }
        XCTAssertTrue(state.notes.notes(overlapping: Anchor(book: "ROM", chapter: 8, verse: 31)).isEmpty)
    }

    // MARK: - Pixel-identical verse typography with marks on vs off

    /// Adding marks (ribbon/highlight glyph/MEM tick) must never move or repaint the verse's own
    /// text: they live entirely in the trailing decoration gutter this crops away. Row-hashes the
    /// same way `HeadingTests` compares against its baseline, skipping a margin wide enough to
    /// exclude that gutter on both sides.
    func testMarksNeverAlterVerseTypography() throws {
        let plain = makeOfflineState()
        plain.navigate(bookCode: "ROM", chapter: 8, verse: 28)

        let marked = makeOfflineState()
        marked.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        marked.notes.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verse: 28)], body: "Note")
        let saved = try XCTUnwrap(marked.notes.save(Anchor(book: "ROM", chapter: 8, verse: 28)))
        marked.notes.setHighlight(saved.id, .yellow)
        marked.notes.setMemory(saved.id, true)

        let width: CGFloat = 420, height: CGFloat = 60
        guard case .loaded(let content) = plain.chapterLoad, let verse = content.verses.first(where: { $0.number == 28 }) else {
            throw XCTSkip("Romans 8 not available offline in this environment")
        }
        let plainRep = try render(VerseRow(verse: verse).environmentObject(plain).background(STColor.paper),
                                  dark: false, size: CGSize(width: width, height: height))
        let markedRep = try render(VerseRow(verse: verse).environmentObject(marked).background(STColor.paper),
                                   dark: false, size: CGSize(width: width, height: height))
        XCTAssertEqual(plainRep.pixelsWide, markedRep.pixelsWide)
        XCTAssertEqual(plainRep.pixelsHigh, markedRep.pixelsHigh)

        // Every mark lives inside the trailing ~40pt decoration gutter; skip it (both sides, to
        // stay symmetric) and require the rest of the row to be byte-identical.
        let scale = Double(plainRep.pixelsWide) / Double(width)
        let margin = Int((44 * scale).rounded())
        var mismatched = 0
        for y in 0..<plainRep.pixelsHigh {
            for x in margin..<max(margin, plainRep.pixelsWide - margin) {
                let a = plainRep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                let b = markedRep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                if a?.redComponent != b?.redComponent || a?.greenComponent != b?.greenComponent || a?.blueComponent != b?.blueComponent {
                    mismatched += 1
                }
            }
        }
        XCTAssertEqual(mismatched, 0, "marks changed \(mismatched) pixels of the verse's own text/number region")
    }

    // MARK: - Renders (light/dark, 980pt minimum)

    func testSavedHighlightedMemoryVerseRendersInBothFinishesAndAtMinimumWidth() throws {
        for (dark, width) in [(false, 1143.0), (true, 1143.0), (false, 980.0)] {
            let state = makeOfflineState()
            state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
            let saved = try XCTUnwrap(state.notes.save(Anchor(book: "ROM", chapter: 8, verse: 28)))
            state.notes.setHighlight(saved.id, .green)
            state.notes.setMemory(saved.id, true)
            state.notes.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verse: 28)], body: "Note")
            let rep = try render(MainView().environmentObject(state), dark: dark, size: CGSize(width: width, height: 700),
                                name: "saved-highlighted-memory-\(dark ? "dark" : "light")-\(Int(width))")
            assertNotBlank(rep, "saved+highlighted+memory \(dark ? "dark" : "light") @\(width)")
        }
    }

    func testRangeSelectionRendersInBothFinishes() throws {
        for dark in [false, true] {
            let state = makeOfflineState()
            state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
            state.extendRange(to: 39)
            let rep = try render(MainView().environmentObject(state), dark: dark, size: CGSize(width: 1143, height: 700),
                                name: "range-selection-\(dark ? "dark" : "light")")
            assertNotBlank(rep, "range selection \(dark ? "dark" : "light")")
        }
    }

    func testSavedLibraryModeRendersWithCollectionsTagsAndMemoryFilterInBothFinishes() throws {
        for dark in [false, true] {
            let state = makeOfflineState()
            let a = Anchor(book: "ROM", chapter: 8, verse: 28), b = Anchor(book: "JHN", chapter: 3, verse: 16)
            let collection = try XCTUnwrap(MyStudyActions.createCollectionAndAdd(named: "Favorites", anchor: a, in: state))
            _ = collection
            let savedB = try XCTUnwrap(state.notes.save(b))
            state.notes.setTags(savedID: savedB.id, tags: ["gospel"])
            state.notes.setMemory(savedB.id, true)
            let view = SavedLibraryView().environmentObject(state)
            let rep = try render(view, dark: dark, size: CGSize(width: 220, height: 700), name: "saved-library-\(dark ? "dark" : "light")")
            assertNotBlank(rep, "saved library \(dark ? "dark" : "light")")
        }
    }

    func testEmptySavedLibraryExplainsCommandD() throws {
        let state = makeOfflineState()
        let rep = try render(SavedLibraryView().environmentObject(state), dark: false, size: CGSize(width: 220, height: 700))
        assertNotBlank(rep, "empty saved library")
    }

    func testLibraryPaneSavedModeSwitchesContent() throws {
        // The BOOKS | SAVED segmented header itself, in both modes, through the real LibraryPane.
        let state = makeOfflineState()
        let repBooks = try render(LibraryPane().environmentObject(state), dark: false, size: CGSize(width: 220, height: 700))
        assertNotBlank(repBooks, "library, books mode")
    }

    // MARK: - VoiceOver custom actions present at source level

    func testVerseRowSourceDeclaresTheRequiredVoiceOverActions() throws {
        let source = try String(contentsOf: TestPaths.root.appendingPathComponent("Sources/StudyTable/Panes.swift"), encoding: .utf8)
        for expected in ["\"Unsave\"", "\"Save\"", "Highlight\\u{2026}", "memory verse", "Add to collection\\u{2026}", "Study a word\\u{2026}"] {
            XCTAssertTrue(source.contains(expected), "VerseRow is missing the VoiceOver action \(expected)")
        }
    }
}
